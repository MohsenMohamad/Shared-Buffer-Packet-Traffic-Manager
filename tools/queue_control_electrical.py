#!/usr/bin/env python3
"""Measure an unchanged map and a targeted buffer split under the same SDC."""
from argparse import ArgumentParser
from collections import defaultdict
from copy import deepcopy
import json
import os
from pathlib import Path

from evidence import sha
from queue_control_sta import EXP, LIBERTY, mapped_measurements, run, timing


def measure(path, top, stem):
    env = dict(os.environ, TM_LIBERTY=str(LIBERTY), TM_TOP=top,
               TM_SDC=str(EXP / "reference.sdc"), TM_NETLIST=str(path / "mapped.v"),
               TM_DETAIL="1")
    raw = run(["sta", "-no_init", "-exit", str(EXP / "timing.tcl")], path, stem, 300, env)
    details = raw.split("TM_CAP_VIOLATIONS_BEGIN", 1)[1].split("TM_CAP_VIOLATIONS_END", 1)[0]
    violations = []
    for line in details.splitlines():
        if line.endswith("(VIOLATED)"):
            pin, limit, observed, slack, _ = line.split()
            violations.append(dict(pin=pin, limit_ff=float(limit), observed_ff=float(observed),
                                   slack_ff=float(slack)))
    return timing(raw), violations


def insert_buffers(design, violations):
    cells = design["cells"]
    sinks = defaultdict(list)
    for name, cell in cells.items():
        for pin, bits in cell["connections"].items():
            if cell["port_directions"][pin] == "input":
                for index, bit in enumerate(bits):
                    sinks[bit].append((name, pin, index))
    free_bit = 1 + max(bit for net in design["netnames"].values()
                       for bit in net["bits"] if isinstance(bit, int))
    for violation in violations:
        instance, pin = violation["pin"].rsplit("/", 1)
        source = cells[instance]
        [net] = source["connections"][pin]
        attached = sorted(sinks[net])
        if not attached:
            raise ValueError(f"No internal loads to split at {instance}/{pin}")
        moved = attached[len(attached) // 2:]
        index = free_bit
        while f"repair_buf_{index}" in cells:
            index += 1
        name = f"repair_buf_{index}"
        design["netnames"][name + "_z"] = dict(hide_name=0, bits=[free_bit], attributes={})
        cells[name] = dict(hide_name=0, type="BUF_X4", parameters={}, attributes={},
                           port_directions=dict(A="input", Z="output"),
                           connections=dict(A=[net], Z=[free_bit]))
        for load, load_pin, bit in moved:
            cells[load]["connections"][load_pin][bit] = free_bit
        free_bit += 1
        violation.update(cell=source["type"], sink_count=len(attached), inserted=name,
                         moved_sinks=[f"{load}/{load_pin}" for load, load_pin, _ in moved])


def repair(source, destination, rounds):
    original = json.loads((source / "result.json").read_text())
    if original["result"] != "MEASURED":
        raise ValueError(f"Expected a measured baseline at {source}")
    design = json.loads((source / "mapped.json").read_text())
    top, = (name for name, module in design["modules"].items()
            if module["attributes"].get("top", "").endswith("1"))
    base, violations = measure(source, top, "electrical")
    edits = []
    for turn in range(rounds):
        if not violations:
            break
        edits.append(deepcopy(violations))
        insert_buffers(design["modules"][top], edits[-1])
        path = destination / f"round-{turn + 1}"
        path.mkdir(parents=True, exist_ok=True)
        (path / "mapped.json").write_text(json.dumps(design) + "\n")
        script = path / "rebuffer.ys"
        script.write_text(f"read_json {path / 'mapped.json'}\n"
                          f"hierarchy -top {top}\ncheck -assert {top}\n"
                          f"write_verilog -noattr {path / 'mapped.v'}\n"
                          f"tee -o {path / 'stats.json'} stat -json -liberty {LIBERTY}\n")
        run(["yosys", "-Q", "-T", "-s", str(script)], path, "yosys", 180)
        mapping = mapped_measurements(path, top)
        if any(mapping[key] != original["mapping"][key] for key in ("flops", "outputs")):
            raise ValueError("Buffer split changed mapped state or output width")
        revised, violations = measure(path, top, "sta")
        (path / "result.json").write_text(json.dumps(dict(mapping=mapping, timing=revised,
                                                         remaining=violations), indent=2) + "\n")
        print(f"{source.name} round {turn + 1}: {len(violations)} capacitance violators", flush=True)
    destination.mkdir(parents=True, exist_ok=True)
    evidence = dict(source=str(source), netlist_sha256=sha(source / "mapped.v"), original=base,
                    edits=edits, remaining=violations)
    (destination / "summary.json").write_text(json.dumps(evidence, indent=2) + "\n")


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--rounds", type=int, choices=range(1, 5), default=2)
    args = parser.parse_args()
    repair(args.source.resolve(), args.destination.resolve(), args.rounds)


if __name__ == "__main__":
    main()
