#!/usr/bin/env python3
"""Map production pools with live same-edge ID consumers under Decision 0010."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from uuid import uuid4

from pool_sources import INCLUDE, LOCKS, PROFILES, PUBLIC, RTL

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from evidence import Case, Run, execute, output, sha
from frontend import read_sources
from queue_control_composition import buffer_types, check_preserved, read_map
from queue_control_electrical import repair
from queue_control_sta import DIAGNOSTIC, LIBERTY, mapped_measurements, path_record, timing

EXPERIMENT = Path("experiments/multi-egress-pools")
REFERENCE = Path("experiments/queue-control")
TOP = "tm_pools_timing"
WRAPPER = EXPERIMENT / f"{TOP}.sv"
CONSTRAINTS = REFERENCE / "reference.sdc"
SOURCES = [*RTL, str(WRAPPER)]
RETURN_INPUTS = ("tx_present*", "tx_final*", "tx_cell*", "tx_desc*", "tx_qid*", "cleanup_*")


def mapping_script(base, profile):
    read = read_sources(SOURCES, TOP, includes=[INCLUDE], params={"PROFILE": PROFILES[profile]})
    return read + f"""
synth -top {TOP} -flatten -noabc
dffunmap
dfflibmap -liberty {LIBERTY}
abc -liberty {LIBERTY} -constr {EXPERIMENT / 'abc.constr'}
clean
rename -enumerate
read_liberty -lib {LIBERTY}
check -assert
write_verilog -noattr {base / 'mapped.v'}
write_json {base / 'mapped.json'}
tee -o {base / 'stats.json'} stat -json -liberty {LIBERTY}
"""


def pin_groups(base):
    design = json.loads((base / "mapped.json").read_text())["modules"][TOP]
    netnames = design["netnames"]

    def bits(*names):
        return {bit for name in names for bit in netnames[name]["bits"]}

    def flops(*names):
        targets = bits(*names)
        registers = {}
        for name, cell in design["cells"].items():
            if cell["type"].startswith("DFF"):
                for port in ("Q", "QN"):
                    for bit in cell["connections"].get(port, []):
                        if bit in targets:
                            registers[bit] = name
        if registers.keys() != targets:
            raise ValueError(f"Incomplete mapped register endpoints for {names}")
        return sorted(set(registers.values()))

    def pins(*names, port):
        instances = flops(*names)
        return " ".join(f"{name}/{port}" for name in instances)

    def from_pins(*names):
        return f"[endpoints launch {{{pins(*names, port='CK')}}}]"

    def to_pins(*names):
        return f"[endpoints capture {{{pins(*names, port='D')}}}]"

    def ports(*names):
        return "[get_ports {" + " ".join(names) + "}]"

    cell_state = "dut.cells.free_bits"
    desc_state = "dut.descriptors.free_bits"
    returns = ports(*RETURN_INPUTS)
    return {
        "CELL_ID": (from_pins(cell_state), ports("write_id*")),
        "DESC_RANK": (from_pins(desc_state), to_pins("captured_rank_id", "captured_rank_valid")),
        "DESC_ID": (from_pins(desc_state), ports("grant_desc*")),
        "CELL_CONSUMER": (from_pins(cell_state), to_pins("captured_write_id")),
        "DESC_CONSUMER": (from_pins(desc_state), to_pins("captured_grant_desc")),
        "CELL_RETURN": (returns, to_pins(cell_state, "free_cells")),
        "DESC_RETURN": (returns, to_pins(desc_state, "free_desc")),
        "CREDIT_RETURN": (returns, to_pins("unreserved", "held")),
    }


def measurements(log, groups):
    data = timing(log)
    for name in groups:
        for delay in ("max", "min"):
            marker = f"TM_{name}_{delay}"
            section = log.split(marker + "_BEGIN", 1)[1].split(marker + "_END", 1)[0]
            item = path_record(section)
            # Count mapped timing arcs represented by the reported max-slack path.
            # Exclude the launch flop and BUF/INV stages are included.
            arcs = re.findall(r"(?m)^\s*[\d. -]+[v^]\s+\S+\s+\(([A-Z][A-Z0-9]+_X\d+)\)", section)
            item["logic_levels"] = sum(not cell.startswith("DFF") for cell in arcs)
            data[f"{name.lower()}_{delay}"] = item
    return data


def analyze(case, base):
    mapped = mapped_measurements(base, TOP)
    groups = pin_groups(base)
    focus = base / "focus.tcl"
    lines = [f"    {name} {start} {end}" for name, (start, end) in groups.items()]
    focus.write_text("set tm_focus [list " + " ".join(lines) + "]\n")

    # Reuse all reference checks and append the candidate-specific path groups.
    sta_script = base / "timing.tcl"
    reference = (ROOT / REFERENCE / "timing.tcl").read_text()
    sta_script.write_text(reference.replace(
        "puts TM_STA_DONE\nexit\n",
        f"source {ROOT / EXPERIMENT / 'paths.tcl'}\nputs TM_STA_DONE\nexit\n",
    ))
    env = dict(os.environ, TM_LIBERTY=str(LIBERTY), TM_TOP=TOP,
               TM_SDC=str(ROOT / CONSTRAINTS), TM_NETLIST=str(base / "mapped.v"),
               TM_FOCUS_TCL=str(focus))
    argv = ["sta", "-no_init", "-exit", str(sta_script)]
    step = execute(argv, base, "focused-sta", 300, env=env)
    case.data["steps"].append(step)
    if step["result"] != "PASS":
        raise ValueError(step["first_failure"])
    log = output(step)
    if DIAGNOSTIC.search(log):
        raise ValueError("OpenSTA reported diagnostics")
    data = measurements(log, groups)
    if data["registers"] != mapped["flops"] or data["outputs"] != sum(mapped["outputs"].values()):
        raise ValueError("Mapping and timing endpoint counts differ")
    return dict(mapping=mapped, timing=data, netlist_sha256=sha(base / "mapped.v"),
                sta_script_sha256=sha(sta_script), focus_sha256=sha(focus),
                analysis_env={key: env[key] for key in (
                    "TM_LIBERTY", "TM_TOP", "TM_SDC", "TM_NETLIST", "TM_FOCUS_TCL",
                )})


def point(run, profile):
    case = Case(run, "mapped")
    base = case.path
    script = base / "mapping.ys"
    script.write_text(mapping_script(base, profile))
    case.data["mapping_script_sha256"] = sha(script)
    step = case.execute(["yosys", "-Q", "-T", "-s", script], timeout=1200)
    if step["result"] != "PASS":
        return case.finish(step["result"], step["first_failure"])
    try:
        baseline = analyze(case, base)
        case.data["unbuffered"] = baseline
        final = baseline
        if not baseline["timing"]["electrical"]["max capacitance"]["met"]:
            (base / "result.json").write_text(json.dumps(dict(baseline, result="MEASURED")) + "\n")
            repair_dir = base / "buffer-repair"
            repair(base, repair_dir, rounds=4, repair_hold=False)
            repaired = sorted(repair_dir.glob("round-*"))[-1]
            case.data["connectivity"] = check_preserved(read_map(base, TOP), read_map(repaired, TOP),
                                                       buffer_types())
            final = analyze(case, repaired)
        data = final["timing"]
        cap_and_slew = all(data["electrical"][name]["met"] for name in ("max capacitance", "max slew"))
        data_timing = all(data[f"data_{delay}"]["slack_ns"] >= 0 for delay in ("max", "min"))
        result = "PASS" if cap_and_slew and data_timing else "FAIL"
        return case.finish(result, None if result == "PASS" else "Reference data timing or electrical violation",
                           **final, max_fanout="UNSUPPORTED",
                           reference_reset="PASS" if data["reset_min"]["slack_ns"] >= 0 and
                           data["reset_max"]["slack_ns"] >= 0 else "FAIL")
    except subprocess.TimeoutExpired as error:
        return case.finish("TIMEOUT", str(error))
    except (KeyError, IndexError, OSError, ValueError) as error:
        return case.finish("TOOL_ERROR", str(error))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=PROFILES, required=True)
    args = parser.parse_args()
    for tool in ("yosys", "sta"):
        found = shutil.which(tool)
        if not found or not Path(found).is_relative_to(ROOT / ".tools/install"):
            parser.error(f"activate the pinned {tool} installation")
    lock = json.loads((ROOT / LOCKS[0]).read_text())
    if sha(LIBERTY) != lock["liberty"]["sha256"]:
        parser.error("locked Liberty checksum mismatch")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
    base = ROOT / ".build/runs" / f"pools-sta-{args.profile}-{stamp}-{uuid4().hex[:8]}"
    run = Run(base, args.profile, sorted(set(PUBLIC + SOURCES + LOCKS + [
        str(CONSTRAINTS), str(REFERENCE / "timing.tcl"), str(EXPERIMENT / "paths.tcl"),
        str(EXPERIMENT / "abc.constr"), "dv/designer/multi_egress_pools_sta.py",
        "dv/designer/pool_sources.py", "tools/frontend.py", "tools/queue_control_sta.py",
        "tools/queue_control_electrical.py", "tools/queue_control_composition.py",
    ])))
    run.scope = "Isolated production resource pools with same-edge consumer registers"
    run.versions.update({tool: subprocess.check_output([tool, "--version" if tool == "yosys" else "-version"],
                                                       text=True).strip()
                         for tool in ("yosys", "sta")})
    run.provenance["liberty_sha256"] = sha(LIBERTY)
    point(run, args.profile)
    return run.finish()


if __name__ == "__main__":
    sys.exit(main())
