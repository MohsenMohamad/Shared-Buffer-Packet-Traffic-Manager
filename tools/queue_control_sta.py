#!/usr/bin/env python3
"""Map isolated queue-control cones with the pinned allocator and R01 reference flow."""
from argparse import ArgumentParser
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess

from evidence import ROOT, sha
from frontend import read_sources
from queue_control_geometry import PROFILES

EXP = ROOT / "experiments/queue-control"
LIBERTY = ROOT / ".deps/liberty.lib"
POINTS = {"head-direct": ("queue_head", {"CACHED": 0}),
          "head-cached": ("queue_head", {"CACHED": 1}),
          "head-token-feedback": ("queue_head", {"CACHED": 1, "TOKEN_FEEDBACK": 1}),
          "admission": ("admission", {"LOOKAHEAD": 0}),
          "admission-lookahead": ("admission", {"LOOKAHEAD": 1}),
          "admission-factored": ("admission", {"LOOKAHEAD": 2}),
          "admission-staged": ("admission", {"LOOKAHEAD": 3}),
          "admission-balanced": ("admission", {"LOOKAHEAD": 4}),
          "admission-rx": ("admission", {"LOOKAHEAD": 2, "RX_FRAMING": 1}),
          "admission-balanced-rx": ("admission", {"LOOKAHEAD": 4, "RX_FRAMING": 1}),
          "cell": ("cell_control", {}),
          "cell-cleanup-feedback": ("cell_control", {"ABORT_FEEDBACK": 1}),
          "connected": ("connected_control", {})}
DIAGNOSTIC = re.compile(r"(?im)^\s*(?:Error|Warning)(?:\s+\d+)?\s*:")


def run(argv, path, stem, timeout, env=None):
    with (path / (stem + ".stdout")).open("w") as stdout, (path / (stem + ".stderr")).open("w") as stderr:
        with subprocess.Popen(argv, cwd=ROOT, env=env, stdout=stdout, stderr=stderr,
                              start_new_session=True) as process:
            try:
                status = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                raise
    if status != 0:
        raise ValueError(f"{stem} exited {status}")
    return (path / (stem + ".stdout")).read_text() + (path / (stem + ".stderr")).read_text()


def path_record(section):
    required = {
        "start": r"^Startpoint: (.+)",
        "end": r"^Endpoint: (.+)",
        "arrival_ns": r"([-+]?\d+\.\d+)\s+data arrival time",
        "slack_ns": r"([-+]?\d+\.\d+)\s+slack",
    }
    values = {}
    for name, pattern in required.items():
        match = re.search(pattern, section, re.M)
        if match is None:
            raise ValueError(f"Missing {name} in constrained timing path")
        values[name] = float(match[1]) if name.endswith("_ns") else match[1]
    data = section.split("data arrival time", 1)[0]
    pins = re.findall(r"(?m)^\s*[\d. -]+[\^v]?\s+([\\\w.\[\]/]+) \((?:[A-Z][A-Z0-9]+_X\d+|in|out)\)", data)
    if pins:
        # Register paths often list the clock pin immediately before the Q arc.
        start_pin = pins[1] if len(pins) > 1 and pins[0].endswith("/CK") else pins[0]
        values["path_pins"] = [start_pin, pins[-1]]

    return values


def timing(text):
    if text.count("TM_STA_DONE") != 1 or DIAGNOSTIC.search(text):
        raise ValueError("STA diagnostics or missing completion")
    measurements = {}
    for kind in ("DATA", "RESET", "RESET_CONTROL"):
        for delay in ("max", "min"):
            token = f"TM_{kind}_{delay}"
            if text.count(token + "_BEGIN") != 1 or text.count(token + "_END") != 1:
                raise ValueError(f"Missing or duplicate {token}")
            report = text.split(token + "_BEGIN", 1)[1].split(token + "_END", 1)[0]
            paths = [path_record("Startpoint: " + p) for p in report.split("Startpoint: ")[1:]]
            if not paths and kind != "RESET_CONTROL":
                raise ValueError(f"No constrained paths in {token}")
            measurements[kind.lower() + "_" + delay] = min(
                paths, key=lambda p: p["slack_ns"], default=None)
    for delay, check in (("max", "recovery"), ("min", "removal")):
        path = measurements["reset_" + delay]
        if not path["start"].startswith("rst_n ") or f"({check} check" not in path["end"]:
            raise ValueError(f"Missing explicit {check} path")
    if ("(recovery check" in measurements["data_max"]["end"] or
            "(removal check" in measurements["data_min"]["end"]):
        raise ValueError("Reset path included in data timing")
    release_slack = {
        delay: min(measurements[name]["slack_ns"]
                   for name in ("reset_" + delay, "reset_control_" + delay) if measurements[name])
        for delay in ("min", "max")
    }
    measurements["reset_release_required_ns"] = {
        "earliest": round(0.2 - release_slack["min"], 5),
        "latest": round(2.0 + release_slack["max"], 5),
    }
    reports = text.split("TM_CHECK_TYPES_BEGIN", 1)[1].split("TM_CHECK_TYPES_END", 1)[0]
    checks = {}
    for heading in ("max slew", "max capacitance", "max fanout"):
        match = re.search(r"(?m)^" + heading + r"\s*$", reports)
        if match is None:
            checks[heading] = None
            continue
        row = next((line for line in reports[match.end():].splitlines()
                    if line.endswith(("(MET)", "(VIOLATED)"))), "")
        if not row:
            raise ValueError(f"Missing values for {heading}")
        pin, limit, observed, slack, verdict = row.split()
        checks[heading] = dict(pin=pin, limit=float(limit), observed=float(observed),
                               slack=float(slack), met=verdict == "(MET)")
    measurements["electrical"] = checks
    measurements["registers"] = int(re.search(r"TM_REGISTERS (\d+)", text)[1])
    measurements["outputs"] = int(re.search(r"TM_OUTPUTS (\d+)", text)[1])
    return measurements


def mapped_measurements(path, top):
    design = json.loads((path / "mapped.json").read_text())["modules"][top]
    stats = json.loads((path / "stats.json").read_text())["modules"]["\\" + top]
    histogram = Counter(c["type"] for c in design["cells"].values())
    if any(c.startswith("$") or c.startswith("DLAT") for c in histogram):
        raise ValueError("Unmapped cell or unexpected latch")
    flops = sum(n for c, n in histogram.items() if c.startswith("DFF"))
    if not flops:
        raise ValueError("No mapped sequential logic")
    names, sinks, drivers = defaultdict(list), Counter(), {}
    for n, net in design["netnames"].items():
        for i, bit in enumerate(net["bits"]):
            names[bit].append(n if len(net["bits"]) == 1 else f"{n}[{i}]")
    for n, cell in design["cells"].items():
        for pin, bits in cell["connections"].items():
            for bit in bits:
                if cell["port_directions"][pin] == "input":
                    sinks[bit] += 1
                else:
                    drivers[bit] = f"{n}/{pin}"
    outputs = {n: len(p["bits"]) for n, p in design["ports"].items() if p["direction"] == "output"}
    if any(b not in drivers for p in design["ports"].values() if p["direction"] == "output" for b in p["bits"]):
        raise ValueError("Constant or undriven consumer bit")
    roots = {design["ports"][p]["bits"][0]: kind for p, kind in (("clk", "clock"), ("rst_n", "reset"))}
    buffers = [c for c in design["cells"].values() if c["type"].startswith(("BUF_X", "INV_X"))]
    while True:
        old_size = len(roots)
        for cell in buffers:
            source = cell["connections"]["A"][0]
            if source in roots:
                dest = next(bits[0] for p, bits in cell["connections"].items() if p != "A")
                roots[dest] = roots[source]
        if old_size == len(roots):
            break
    fanout = {}
    for kind in ("clock", "reset", "data"):
        ranked = ((n, b) for b, n in sinks.items() if isinstance(b, int) and roots.get(b, "data") == kind)
        fanout[kind] = [dict(sinks=n, driver=drivers.get(b, names[b][0] if names[b] else "?"),
                             aliases=sorted(names[b])[:6])
                        for n, b in sorted(ranked, reverse=True)[:3]]
    sequential = stats.get("sequential_area")
    if sequential is None:
        library = LIBERTY.read_text()
        areas = {cell: float(area) for cell, area in re.findall(
            r"cell\s*\(\s*(\w+)\s*\)\s*\{[^}]*?\barea\s*:\s*([.\d]+)", library, re.S)}
        sequential = sum(areas[c] * n for c, n in histogram.items() if c.startswith("DFF"))
    return dict(area_um2=stats["area"], sequential_um2=sequential,
                combinational_um2=round(stats["area"] - sequential, 5), flops=flops,
                outputs=outputs, fanout=fanout, histogram=histogram)


def expected_flops(top, params):
    if top == "connected_control":
        # The connected representation shares state and observability across
        # boundaries. Its repair check compares every original mapped cell.
        return None
    ports, cells, desc = (params[key] for key in ("P", "N_CELL", "N_DESC"))
    queues = 4 * ports
    b, c, d = ((size - 1).bit_length() for size in (ports, cells, desc))
    q = b + 2
    k = cells.bit_length()
    if top == "queue_head":
        metadata = c + 5 + b + 64 + 16 + 2 + 1 + 16
        queue_state = queues * (1 + 2 * d)
        binding = ports * (1 + 2 + 2 + d + metadata)
        head_cache = queues * metadata if params["CACHED"] else 0
        token_state = 32 * (queues + ports) if params.get("TOKEN_FEEDBACK") else 0
        return desc * (metadata + d) + queue_state + binding + head_cache + token_state + 1
    if top == "cell_control":
        cleanup_state = ports * (1 + 5 + c + d) if params.get("ABORT_FEEDBACK") else 0
        return cells * (1 + c + d) + 6 * b + 4 * c + d + 5 + 1 + cleanup_state
    admission = desc + k * (queues + 1) + b + ports * (4 + 3 + d + q + k) + 1
    if params["LOOKAHEAD"] == 3:
        # Sampled header count is at most ceil(65535/64) truncated to the
        # fixture width. Header errors occupy two bits and alpha is per lane.
        sample_fields = ports * (q + min(k + 1, 11) + 1 + 2 + d + 1 + 1 + 13)
        sample_subsets = ((1 << ports) - 1) * (4 + 2 * (k + 1))
        return admission + 1 + sample_fields + sample_subsets
    return admission


def point(name, profile_name, output, sta_only, short_abc, sta_timeout):
    profile = PROFILES[profile_name]
    top, extra = POINTS[name]
    path = output / f"{profile_name}-{name}"
    path.mkdir(parents=True, exist_ok=True)
    params = dict(P=profile.ports, N_CELL=profile.cells, N_DESC=profile.descriptors, **extra)
    if top in ("admission", "connected_control"):
        params["MAX_BYTES"] = profile.maximum
    script = (EXP / "mapping.ys.in").read_text()
    if short_abc:
        script = script.replace("abc -liberty", f"abc -script {EXP / 'abc-short.script'} -liberty")
    files = [EXP / (top + ".sv")]
    defines = ()
    if top == "connected_control":
        files.extend(EXP / (name + ".sv") for name in ("admission", "queue_head", "cell_control"))
        defines = ("QUEUE_CONTROL_CONNECTED",)
    substitutions = dict(READ=read_sources(files, top, defines=defines, params=params),
                         TOP=top, LIBERTY=LIBERTY, ABC_CONSTR=EXP / "abc.constr",
                         NETLIST=path / "mapped.v", JSON=path / "mapped.json", STATS=path / "stats.json")
    for key, value in substitutions.items():
        script = script.replace("@" + key + "@", str(value))
    script_path = path / "mapping.ys"
    if sta_only and (not script_path.is_file() or script_path.read_text() != script):
        raise ValueError(f"Existing map was produced with a different recipe: {script_path}")
    script_path.write_text(script)
    env = dict(os.environ, TM_LIBERTY=str(LIBERTY), TM_TOP=top, TM_SDC=str(EXP / "reference.sdc"),
               TM_NETLIST=str(substitutions["NETLIST"]))
    result = dict(profile=profile_name, point=name, parameters=params,
                  abc="short" if short_abc else "default", mapping_script_sha256=sha(script_path))
    try:
        if not sta_only:
            run(["yosys", "-Q", "-T", "-s", str(script_path)], path, "yosys", 1800)
        result["mapping"] = mapped_measurements(path, top)
        expected = expected_flops(top, params)
        if expected is not None and result["mapping"]["flops"] != expected:
            raise ValueError("Mapped storage or consumer state count differs from design")
        result["netlist_sha256"] = sha(substitutions["NETLIST"])
        data = timing(run(["sta", "-no_init", "-exit", str(EXP / "timing.tcl")], path, "sta", sta_timeout, env))
        if data["registers"] != result["mapping"]["flops"] or data["outputs"] != sum(result["mapping"]["outputs"].values()):
            raise ValueError("OpenSTA and mapping endpoint counts differ")
        result.update(timing=data, result="MEASURED")
        result["data_closure"] = all(data["data_" + d]["slack_ns"] >= 0 for d in ("max", "min"))
    except subprocess.TimeoutExpired as exc:
        result.update(result="TIMEOUT", error=str(exc))
    except (OSError, ValueError, KeyError) as exc:
        result.update(result="ERROR", error=str(exc))
    (path / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"{profile_name}/{name}: {result['result']} {result.get('error', '')}", flush=True)
    return result


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--profile", choices=("all", *PROFILES), default="all")
    parser.add_argument("--point", choices=("all", *POINTS), default="all")
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--sta-only", action="store_true")
    parser.add_argument("--short-abc", action="store_true")
    parser.add_argument("--sta-timeout", type=int, default=300)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    if not 1 <= args.sta_timeout <= 1800:
        parser.error("--sta-timeout must be between 1 and 1800 seconds")
    if not all(Path(shutil.which(t) or "/").is_relative_to(ROOT / ".tools/install") for t in ("yosys", "sta")):
        parser.error("activate the validated repository toolchain")
    lock = ROOT / "tools/dependencies.json"
    if sha(LIBERTY) != json.loads(lock.read_text())["liberty"]["sha256"]:
        parser.error("Liberty differs from the validated lock")
    destination = args.output.resolve()
    scope = [(name, profile) for profile in PROFILES for name in POINTS
             if args.profile in ("all", profile) and args.point in ("all", name)]
    files = [*EXP.glob("*"), lock, ROOT / "tools/packages.lock.json",
             ROOT / "tools/queue_control_geometry.py", Path(__file__).resolve()]
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True))
    manifest = dict(source_revision=revision, dirty=dirty, liberty_sha256=sha(LIBERTY),
                    definition_sha256={str(p.relative_to(ROOT)): sha(p) for p in files if p.is_file()})
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        manifest["results"] = list(pool.map(lambda item: point(*item, destination, args.sta_only, args.short_abc, args.sta_timeout), scope))
    (destination / "summary.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if any(p["result"] != "MEASURED" for p in manifest["results"]):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
