#!/usr/bin/env python3
"""Select the actual register endpoints of each composed timing boundary."""
from argparse import ArgumentParser
import json
import os
from pathlib import Path

from queue_control_sta import EXP, LIBERTY, path_record, run, timing


def pins(design, names, endpoint):
    bits = {bit for name in names for bit in design["netnames"][name]["bits"]
            if isinstance(bit, int)}
    selected = [f"{name}/{endpoint}" for name, cell in design["cells"].items()
                if cell["type"].startswith("DFF") and cell["connections"]["Q"][0] in bits]
    if not selected:
        raise ValueError(f"Missing mapped {endpoint} for {names}")
    return selected


def measure(path, boundary):
    top, source, inputs, destination = {
        "token-dispatch": ("queue_head", "balance", [], ("bound", "bound_desc", "bound_info")),
        "admission-service": ("admission", "held", ["minimum*", "alpha*", "route*", "length*",
                              "first_keep*", "first_last*", "receive_space*"], ("rx_abort",)),
        "cleanup-pool": ("cell_control", "reclaim_cell", [], ("free_cell", "abort_successor")),
    }[boundary]
    design = json.loads((path / "mapped.json").read_text())["modules"][top]
    source_nets = [n for n in design["netnames"] if n == source or n.endswith("." + source)]
    env = dict(os.environ, TM_LIBERTY=str(LIBERTY), TM_TOP=top,
               TM_SDC=str(EXP / "reference.sdc"), TM_NETLIST=str(path / "mapped.v"),
               TM_FOCUS_PORTS=" ".join(inputs), TM_FOCUS_FLOPS=" ".join(pins(design, source_nets, "CK")),
               TM_FOCUS_TO=" ".join(pins(design, destination, "D")))
    raw = run(["sta", "-no_init", "-exit", str(EXP / "timing.tcl")], path, boundary, 900, env)
    timing(raw)
    block = raw.split("TM_FOCUS_BEGIN", 1)[1].split("TM_FOCUS_END", 1)[0]
    result = path_record(block)
    names = {}
    for role, pin in zip(("start", "end"), result["path_pins"]):
        if "/" in pin:
            instance = pin.rsplit("/", 1)[0]
            bit, = design["cells"][instance]["connections"]["Q"]
            names[role] = [f"{name}[{index}]" if len(net["bits"]) != 1 else name
                           for name, net in design["netnames"].items()
                           if not name.startswith("$") and not name.startswith("_")
                           for index, b in enumerate(net["bits"]) if b == bit]
    result["register_aliases"] = names
    (path / f"{boundary}.json").write_text(json.dumps(result, indent=2) + "\n")


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("point", type=Path)
    parser.add_argument("boundary", choices=("token-dispatch", "admission-service", "cleanup-pool"))
    args = parser.parse_args()
    measure(args.point.resolve(), args.boundary)


if __name__ == "__main__":
    main()
