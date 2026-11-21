#!/usr/bin/env python3
"""Check mapped queue/control repairs, focused paths and reset arrival sensitivity."""
from argparse import ArgumentParser
import json
import os
from pathlib import Path
import re

from evidence import sha
from queue_control_sta import EXP, LIBERTY, path_record, run, timing

GROUPS = {
    "admission-balanced-rx": {
        "first_service": (("held", "credit"),
                          ("minimum*", "alpha*", "route*", "length*", "first_keep*", "first_last*",
                           "receive_space*", "dynamic_mode", "wait_mode"),
                          ("rx_grant", "rx_reject", "rx_abort")),
        "credit_return": ((), ("desc_return*", "return_id*", "credit_release*", "release_qid*",
                               "release_count*"), ("held", "credit", "free_desc")),
    },
    "head-token-feedback": {
        "token_binding": (("balance",), (), ("bound", "bound_desc", "bound_info")),
        "cached_refill": (("head", "next_link", "metadata"), ("publish*",), ("cached",)),
        "token_debit": (("cached",), (), ("balance",)),
    },
    "cell-cleanup-feedback": {
        "cleanup_pool": (("reclaim_cell",), (), ("free_cell", "abort_successor")),
        "tx_link": (("links",), ("read_cell*", "read_eligible*", "read_more*"), ("tx_successor",)),
        "tx_return": ((), ("tx_return*",), ("free_cell",)),
    },
    "connected": {
        "first_service": (("held", "credit", "rx_owned"), ("header_valid*", "first_keep*", "length*"),
                          ("rx_owned", "rx_cleaning", "rx_owner")),
        "credit_return": (("frame_live", "beats_left", "ready", "reclaim_cell", "rx_reservation"),
                          ("sink_ready*",), ("held", "credit", "free_desc")),
        "cached_refill": (("unpublished_info", "publish_queue", "next_link"), (), ("cached",)),
        "token_binding": (("cached", "balance", "beats_left"), (), ("bound", "frame_live", "frame_desc")),
        "token_debit": (("cached",), (), ("balance",)),
        "tx_link": (("links", "next_read"), (), ("next_read",)),
        "cleanup_pool": (("reclaim_cell",), (), ("free_cell", "reclaim_cell")),
        "response_credit": (("pending", "slot_address", "slot_owner"),
                            ("response*",), ("ready", "pending")),
    },
}
RESET_REQUIRES_WRITE = {"cell-cleanup-feedback", "connected"}
RESET_ARRIVALS = (0.20, 5.00, 9.99)


def read_map(path, top):
    return json.loads((path / "mapped.json").read_text())["modules"][top]


def buffer_types():
    """Use the locked library's actual noninverting one-input function."""
    library = LIBERTY.read_text()
    types = set()
    for section in re.split(r"(?m)^\s*cell\s*\(", library)[1:]:
        name = section.split(")", 1)[0].strip()
        functions = re.findall(r'\bfunction\s*:\s*"([^"]+)"', section)
        if name in {"BUF_X1", "BUF_X4"} and functions == ["A"]:
            types.add(name)
    if types != {"BUF_X1", "BUF_X4"}:
        raise ValueError("Locked Liberty lacks the expected identity buffer functions")
    return types


def check_preserved(before, after, identity_types):
    """Contract added identity cells and compare every original pin and port."""
    if before["ports"] != after["ports"]:
        raise ValueError("Buffer repair changed mapped ports")
    previous = before["cells"]
    repaired = after["cells"]
    if not previous.keys() <= repaired.keys():
        raise ValueError("Buffer repair removed an original cell")
    inserted = {}
    for name in repaired.keys() - previous.keys():
        cell = repaired[name]
        if (cell["type"] not in identity_types or cell["parameters"] or
                cell["port_directions"] != {"A": "input", "Z": "output"}):
            raise ValueError(f"Repair inserted a nonidentity cell at {name}")
        [source] = cell["connections"]["A"]
        [destination] = cell["connections"]["Z"]
        if destination in inserted:
            raise ValueError(f"Multiple added buffer drivers at {destination}")
        inserted[destination] = source

    original_bits = {bit for net in before["netnames"].values() for bit in net["bits"]}
    if inserted.keys() & original_bits:
        raise ValueError("An added buffer drives an original net")
    roots = {}
    for bit in inserted:
        root = bit
        seen = set()
        while root in inserted:
            if root in seen:
                raise ValueError("Inserted buffer cycle")
            seen.add(root)
            root = inserted[root]
        if root not in original_bits:
            raise ValueError("Inserted buffer has no original driver")
        roots[bit] = root

    compared_pins = 0
    for name, original in previous.items():
        final = repaired[name]
        for key in ("type", "parameters", "port_directions"):
            if final[key] != original[key]:
                raise ValueError(f"Buffer repair changed {name} {key}")
        contracted = {}
        for pin, bits in final["connections"].items():
            if final["port_directions"][pin] == "input":
                contracted[pin] = [roots.get(bit, bit) for bit in bits]
            else:
                contracted[pin] = bits
        if contracted != original["connections"]:
            raise ValueError(f"Buffer repair changed logical connection at {name}")
        compared_pins += sum(len(bits) for bits in contracted.values())
    return dict(result="PASS", inserted_buffers=len(inserted),
                compared_cells=len(previous), compared_pins=compared_pins)


def qualify_buffer_checker(before, after, identity_types):
    name, pin, index = next(
        (name, pin, index)
        for name, cell in before["cells"].items()
        for pin, bits in cell["connections"].items() if cell["port_directions"][pin] == "input"
        for index, bit in enumerate(bits)
        if isinstance(bit, int) and bit != after["cells"][name]["connections"][pin][index]
    )
    bits = after["cells"][name]["connections"][pin]
    saved = bits[index]
    try:
        bits[index] = "0"
        check_preserved(before, after, identity_types)
    except ValueError as error:
        if str(error) == f"Buffer repair changed logical connection at {name}":
            return dict(result="DETECTED", pin=f"{name}/{pin}", diagnostic=str(error))
        raise
    finally:
        bits[index] = saved
    raise ValueError("Expected wrong-buffer-input detector did not fire")


def register_pins(design, aliases, pin):
    if not aliases:
        return []
    pattern = re.compile(r"(?:^|\.)(?:" + "|".join(map(re.escape, aliases)) + r")(?=$|\[)")
    bits = {bit for name, value in design["netnames"].items() if pattern.search(name)
            for bit in value["bits"] if isinstance(bit, int)}
    pins = [f"{name}/{pin}" for name, cell in design["cells"].items()
            if cell["type"].startswith("DFF")
            and any(bit in bits for bit in cell["connections"]["Q"])]
    if not pins:
        raise ValueError(f"Missing mapped {pin} for {', '.join(aliases)}")
    return sorted(pins)


def group_paths(raw, groups):
    if raw.count("TM_COMPOSED_DONE") != 1:
        raise ValueError("Missing composed STA completion")
    records = {}
    for group in groups:
        records[group] = {}
        for delay in ("max", "min"):
            token = f"TM_GROUP_{group}_{delay}"
            if raw.count(token + "_BEGIN") != 1 or raw.count(token + "_END") != 1:
                raise ValueError(f"Missing or duplicate {group} {delay} endpoint report")
            report = raw.split(token + "_BEGIN", 1)[1].split(token + "_END", 1)[0]
            if report.count("Startpoint: ") != 1:
                raise ValueError(f"Expected one constrained path in {group} {delay}")
            records[group][delay] = path_record(report)
    return records


def sta(path, top, stem, sdc, extra=None):
    env = dict(os.environ, TM_LIBERTY=str(LIBERTY), TM_TOP=top, TM_SDC=str(sdc),
               TM_NETLIST=str(path / "mapped.v"))
    env.update(extra or {})
    raw = run(["sta", "-no_init", "-exit", str(EXP / "composed_checks.tcl")], path, stem, 900, env)
    observed = timing(raw)
    if raw.count("TM_COMPOSED_DONE") != 1:
        raise ValueError("Missing composed STA completion")
    return raw, observed


def focused(path, top, groups, design, mapping, sample=False, require_write=False):
    counts = {}
    pin_lists = []
    for name, (starts, inputs, ends) in groups.items():
        start_pins = register_pins(design, starts, "CK")
        end_pins = register_pins(design, ends, "D")
        pin_lists.append("|".join((name, " ".join(start_pins), " ".join(inputs), " ".join(end_pins))))
        counts[name] = dict(start_registers=len(start_pins), end_registers=len(end_pins), input_patterns=inputs)
    pin_file = path / "composed-endpoints.txt"
    pin_file.write_text("\n".join(pin_lists) + "\n")
    extra = {"TM_COMPOSED_GROUPS": str(pin_file)}
    if sample:
        extra["TM_RESET_SAMPLES"] = " ".join(f"{arrival:.2f}" for arrival in RESET_ARRIVALS)
        if require_write:
            write_file = path / "reset-write-endpoints.txt"
            write_file.write_text(" ".join(register_pins(design, ("links", "owners"), "D")) + "\n")
            extra["TM_RESET_WRITE_PINS"] = str(write_file)
    raw, result = sta(path, top, "composed", EXP / "reference.sdc", extra)
    focused_paths = group_paths(raw, groups)
    if result["registers"] != mapping["flops"] or result["outputs"] != sum(mapping["outputs"].values()):
        raise ValueError("OpenSTA and mapping endpoint counts differ")
    return raw, result, dict(paths=focused_paths, counts=counts)


def qualify_endpoint_checker(raw, groups):
    group = next(iter(groups))
    missing = raw.replace(f"TM_GROUP_{group}_min_BEGIN", "OMITTED", 1)
    try:
        group_paths(missing, groups)
    except ValueError as error:
        if str(error) == f"Missing or duplicate {group} min endpoint report":
            return dict(result="DETECTED", diagnostic=str(error))
        raise
    raise ValueError("Expected missing-endpoint detector did not fire")


def reset_record(raw, arrival, check, delay, required=True):
    token = f"TM_SAMPLE_{arrival}_{check}_{delay}"
    if raw.count(token + "_BEGIN") != 1 or raw.count(token + "_END") != 1:
        raise ValueError(f"Missing or duplicate {token}")
    report = raw.split(token + "_BEGIN", 1)[1].split(token + "_END", 1)[0]
    if not required and report.count("Startpoint: ") == 0:
        return None
    if report.count("Startpoint: ") != 1:
        raise ValueError(f"Expected one constrained path at {token}")
    record = path_record(report)
    if not record["start"].startswith("rst_n "):
        raise ValueError(f"Unexpected reset startpoint at {token}")
    if check == "reset":
        check_type = "recovery" if delay == "max" else "removal"
        if f"({check_type} check" not in record["end"]:
            raise ValueError(f"Missing {check_type} endpoint at {token}")
    return record


def reset_samples(raw, require_write):
    samples = []
    reference_write = {
        f"reset_write_{delay}": reset_record(raw, "reference", "reset_write", delay)
        for delay in ("min", "max")
    } if require_write else {}
    for arrival in RESET_ARRIVALS:
        checks = {
            f"{check}_{delay}": reset_record(raw, f"{arrival:.2f}", check, delay, check == "reset")
            for check in ("reset", "reset_control") for delay in ("min", "max")
        }
        if require_write:
            checks.update({f"reset_write_{delay}": reset_record(raw, f"{arrival:.2f}", "reset_write", delay)
                           for delay in ("min", "max")})
        failed = [name for name, record in checks.items() if record and record["slack_ns"] < 0]
        if arrival == 0.20:
            valid = "reset_min" in failed
        elif arrival == 5.00:
            valid = not failed
        else:
            valid = bool(set(failed) & {"reset_max", "reset_control_max"})
        samples.append(dict(arrival_ns=arrival, checks=checks,
                            negative_slack=failed, result="EXPECTED" if valid else "UNEXPECTED"))
    return reference_write, samples


def compare(source, repair, output, qualify=False):
    original = json.loads((source / "result.json").read_text())
    edits = json.loads((repair / "summary.json").read_text())
    if original["result"] != "MEASURED" or edits["netlist_sha256"] != sha(source / "mapped.v"):
        raise ValueError("Repair input differs from the measured baseline")
    point = original["point"]
    groups = GROUPS[point]
    rounds = len(edits["edits"])
    candidate = repair / f"round-{rounds}" if rounds else source
    top, = (name for name, module in json.loads((source / "mapped.json").read_text())["modules"].items()
            if module["attributes"].get("top", "").endswith("1"))
    before = read_map(source, top)
    require_write = point in RESET_REQUIRES_WRITE
    before_raw, before_timing, before_paths = focused(source, top, groups, before, original["mapping"],
                                                     sample=not rounds, require_write=require_write)
    candidate_result = json.loads((candidate / "result.json").read_text())
    after = read_map(candidate, top) if rounds else before
    identity_types = buffer_types()
    proof = check_preserved(before, after, identity_types)
    detectors = {}
    if qualify:
        if not rounds:
            raise ValueError("Expected an actual repair for buffer detector qualification")
        detectors["wrong_buffer_input"] = qualify_buffer_checker(before, after, identity_types)
        detectors["missing_endpoint"] = qualify_endpoint_checker(before_raw, groups)
    if rounds:
        after_raw, after_timing, after_paths = focused(candidate, top, groups, after, candidate_result["mapping"],
                                                       sample=True, require_write=require_write)
    else:
        after_raw, after_timing, after_paths = before_raw, before_timing, before_paths
    reset_write, samples = reset_samples(after_raw, require_write)
    calculated = after_timing["reset_release_required_ns"]
    for sample in samples:
        start = sample["arrival_ns"]
        inside = calculated["earliest"] <= start <= calculated["latest"]
        if inside == bool(sample["negative_slack"]):
            raise ValueError("Observed release sample disagrees with the calculated window")
    checks = after_timing["electrical"]
    if edits["remaining"] or any(row and not row["met"] for row in checks.values()):
        electrical = "FAIL"
    else:
        electrical = "UNSUPPORTED" if any(row is None for row in checks.values()) else "PASS"
    slack = [after_timing["data_max"]["slack_ns"], after_timing["data_min"]["slack_ns"]]
    slack.extend(record["slack_ns"] for delays in after_paths["paths"].values() for record in delays.values())
    result = dict(profile=original["profile"], point=point, repair_rounds=rounds,
                  data_result="PASS" if min(slack) >= 0 else "FAIL", electrical_result=electrical,
                  supported_electrical_result=("PASS" if all(checks.get(key) and checks[key]["met"]
                                           for key in ("max slew", "max capacitance")) else "FAIL"),
                  proof=proof, intended_detections=detectors, reset_samples=samples,
                  reset_write_reference=reset_write, reference_sdc_sha256=sha(EXP / "reference.sdc"),
                  baseline=dict(path=str(source.relative_to(Path.cwd())), timing=before_timing,
                                mapping=original["mapping"], focused=before_paths,
                                netlist_sha256=sha(source / "mapped.v")),
                  repaired=dict(path=str(candidate.relative_to(Path.cwd())), timing=after_timing,
                                mapping=candidate_result["mapping"], focused=after_paths,
                                netlist_sha256=sha(candidate / "mapped.v")))
    output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"{original['profile']}/{point} data={result['data_result']} electrical={electrical}", flush=True)
    return result


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("repair", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--qualify-detectors", action="store_true")
    args = parser.parse_args()
    result = compare(args.source.resolve(), args.repair.resolve(), args.output, args.qualify_detectors)
    if (result["data_result"] != "PASS" or result["electrical_result"] != "PASS"
            or any(case["result"] != "EXPECTED" for case in result["reset_samples"])):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
