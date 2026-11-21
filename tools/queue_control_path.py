#!/usr/bin/env python3
"""Annotate a mapped admission path with actual pins and transitive root inputs."""
from argparse import ArgumentParser
from collections import defaultdict
from functools import cache
import json
from pathlib import Path
import re

POINT = re.compile(r"([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+[\^v]\s+(\S+) \((\w+)\)$")


def explain(path, report):
    design = json.loads((path / "mapped.json").read_text())["modules"]["admission"]
    cells, aliases, drivers = design["cells"], defaultdict(list), {}
    for name, net in design["netnames"].items():
        if not name.startswith("$") and not re.fullmatch(r"_\d+_", name):
            for index, bit in enumerate(net["bits"]):
                aliases[bit].append(f"{name}[{index}]" if len(net["bits"]) > 1 else name)
    for name, cell in cells.items():
        for pin, bits in cell["connections"].items():
            if cell["port_directions"][pin] == "output":
                for bit in bits:
                    drivers[bit] = (name, pin)
    port_bits = {b: name for name, port in design["ports"].items()
                 if port["direction"] == "input" for b in port["bits"]}
    by_signal = {n: {b: i for i, b in enumerate(design["netnames"][n]["bits"])}
                 for n in ("credit", "held", "free_desc", "cursor")}
    k = len(design["ports"]["credit"]["bits"])
    primary_inputs = {n: {b: i for i, b in enumerate(design["ports"][n]["bits"])}
                      for n in ("minimum", "alpha")}

    @cache
    def roots(bit):
        if bit in port_bits:
            name = port_bits[bit]
            if name == "minimum":
                name += f":{primary_inputs['minimum'][bit] // k}"
            if name == "alpha":
                name += f":{primary_inputs['alpha'][bit] // 13}"
            return frozenset([name])
        if bit not in drivers:
            return frozenset()
        name, _ = drivers[bit]
        cell = cells[name]
        if cell["type"].startswith("DFF"):
            q, = cell["connections"]["Q"]
            return frozenset([next((n for n, vector in by_signal.items() if q in vector),
                                   f"state:{name}")])
        return frozenset().union(*(roots(b) for pin, bits in cell["connections"].items()
                                  if cell["port_directions"][pin] == "input" for b in bits))

    text = (path / report).read_text().split("TM_DATA_max_BEGIN", 1)[1].split("TM_DATA_max_END", 1)[0]
    data = text.split("data arrival time", 1)[0]
    points = []
    previous = frozenset()
    for row in data.splitlines():
        match = POINT.search(row)
        if not match:
            continue
        slew, delay, arrival, pin, cell_type = match.groups()
        if "/" in pin:
            instance, port = pin.rsplit("/", 1)
            cell = cells[instance]
            if port == "CK":
                continue
            bit, = cell["connections"][port]
            consumer = aliases[cell["connections"]["Q"][0]] if port == "D" and "Q" in cell["connections"] else []
        else:
            bit = next((b for b, names in aliases.items() if pin in names), None)
            consumer = []
        support = roots(bit)
        new = sorted(support - previous)
        fields = row.split()
        points.append(dict(pin=pin, cell=cell_type, fanout=int(fields[0]) if len(fields) == 8 else None,
                           slew_ns=float(slew), delay_ns=float(delay), arrival_ns=float(arrival),
                           aliases=aliases[bit], consumer=consumer, new_roots=new))
        previous = support
    if len(points) < 2:
        raise ValueError("No complete mapped timing path")
    return points


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("point", type=Path)
    parser.add_argument("report")
    args = parser.parse_args()
    print(json.dumps(explain(args.point, args.report), indent=2))


if __name__ == "__main__":
    main()
