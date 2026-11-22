#!/usr/bin/env python3
"""Run the multi-egress pool designer smoke on production RTL."""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import re
import shutil
import subprocess
import sys
from uuid import uuid4

from pool_sources import INCLUDE, LOCKS, PROFILES, PUBLIC, RTL

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from evidence import Case, Run, completed, output
from frontend import read_sources

HERE = "dv/designer"
DRIVER = f"{HERE}/multi_egress_pools.cpp"
WAIVERS = f"{HERE}/multi_egress_pools.vlt"
TOP = "tm_resource_pools"
RTL_NEGATIVES = {
    "rtl-duplicate-cell": "cell_return_distinct",
    "rtl-free-cell": "cell_return_allocated",
    "rtl-duplicate-descriptor": "descriptor_return_distinct",
    "rtl-free-descriptor": "descriptor_return_allocated",
    "rtl-overcommit-d": "old_descriptor_credit",
    "rtl-overcommit-u": "old_credit",
    "rtl-zero-count": "reservation_count",
    "rtl-oversize-count": "reservation_count",
}
CASES = ("descriptor", "cell", "peak", "abort", "identity", "reset", "producer", "random", *RTL_NEGATIVES)
SEEDS = (17, 31, 53)
DETECTIONS = {
    "cell": ["old_free_cell", "empty_cell_pool_rejected_write"],
    "peak": ["merged_queue_delta"],
    "abort": ["cleanup_delta"],
    "identity": ["real_final_retirement", "current_owner"],
    "reset": ["current_owner"],
}


def frontend_checks(run, geometry, jobs):
    build = Case(run, "verilator")
    common = ["verilator", "-Wall", "--assert", "-DTM_POOL_ASSERTIONS", "--top-module", TOP, f"-GPROFILE={geometry}",
              f"-I{INCLUDE}", WAIVERS, *RTL]
    lint = build.execute([*common, "--lint-only"], stem="lint")
    if lint["result"] != "PASS":
        build.finish(lint["result"], lint["first_failure"])
        return None
    obj = build.path / "obj"
    compile_case = build.execute([
        *common, "--cc", "--exe", "--build", "-j", str(jobs), "--Mdir", obj,
        "-CFLAGS", f"-std=c++20 -DPOOL_PROFILE={geometry}", ROOT / DRIVER,
    ], timeout=600, stem="compile")
    binary = obj / f"V{TOP}"
    status = compile_case["result"]
    if status == "PASS" and not binary.is_file():
        build.finish("TOOL_ERROR", "Missing compiled driver")
        return None
    build.finish(status, compile_case["first_failure"])
    return binary if status == "PASS" else None


def slang_check(run, geometry):
    case = Case(run, "slang")
    read = read_sources(RTL, TOP, includes=[INCLUDE], params={"PROFILE": geometry})
    script = case.path / "elaborate.ys"
    script.write_text(read + "hierarchy -check\nproc\ncheck -assert\n")
    step = case.execute(["yosys", "-Q", "-T", "-s", script], stem="elaborate")
    status, reason = completed(step, "Found and reported 0 problems.")
    if status == "PASS" and re.search(r"(?im)^\s*(?:Warning|Error)\s*:", output(step)):
        status, reason = "TOOL_ERROR", "Slang/Yosys diagnostic"
    case.finish(status, reason)


def simulate(run, binary, scenario, seed, replay_of=None):
    name = f"{scenario}-{seed}" + ("-replay" if replay_of is not None else "")
    case = Case(run, name, seed)
    if binary is None:
        case.finish("NOT_RUN", "Verilator build did not produce a usable executable")
        return None
    step = case.execute([binary, scenario, str(seed)], stem="simulate")
    log = output(step)
    if scenario in RTL_NEGATIVES:
        expected = RTL_NEGATIVES[scenario]
        detector = re.findall(r"(?m)^.*Assertion failed .*: POOL_ASSERT (\w+)$", log)
        reached = re.search(rf"(?m)^RTL_PROBE {re.escape(scenario)} edge=\d+$", log)
        neighbor = f"RTL_NEIGHBOR {scenario} passed" in log.splitlines()
        if step["returncode"] and step["result"] != "TIMEOUT" and neighbor and reached and detector == [expected]:
            case.finish("PASS", intended_detection=expected, legal_neighbor=True, sampled_edge=reached[0])
        else:
            status = "TIMEOUT" if step["result"] == "TIMEOUT" else "FAIL"
            case.finish(status, f"Expected RTL assertion {expected}, observed {detector}")
        return None
    status, reason = completed(step, f"POOLS_PASS {scenario} seed={seed}")
    if step["returncode"] == 1 and "POOLS_FAIL " in log:
        status, reason = "FAIL", next(line for line in log.splitlines() if line.startswith("POOLS_FAIL "))
    if step["returncode"] and "Assertion failed " in log:
        status, reason = "FAIL", next(line for line in log.splitlines() if "Assertion failed " in line)
    detections = re.findall(r"(?m)^EXPECTED (\S+)$", log)
    samples = re.findall(r"(?m)^STATE (.+)$", log)
    totals = re.search(r"(?m)^TOTAL (.+)$", log)
    active = re.search(r"(?m)^RANDOM_ACTIVE (\d+)$", log)
    triggers = re.search(r"(?m)^RANDOM_TRIGGERS (.+)$", log)
    if status == "PASS" and (detections != DETECTIONS.get(scenario, []) or not totals or not samples):
        status, reason = "FAIL", "Missing or incorrect detector, state or drain evidence"
    if status == "PASS" and scenario == "random" and (not active or int(active[1]) < 1024):
        status, reason = "FAIL", "Fewer than 1024 observed active edges"
    if status == "PASS" and replay_of is not None and log != replay_of:
        status, reason = "FAIL", "Replay differs from the original seed-17 log"
    case.finish(status, reason, intended_detections=detections, observed_states=samples,
                totals=dict(re.findall(r"(\w+)=(\d+)", totals[1])) if totals else {},
                random_active_edges=int(active[1]) if active else None,
                random_triggers=dict(re.findall(r"(\w+)=(\d+)", triggers[1])) if triggers else {})
    return log if status == "PASS" else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=PROFILES, action="append")
    parser.add_argument("--case", choices=CASES, action="append")
    parser.add_argument("--seed", type=int, action="append")
    parser.add_argument("--jobs", type=int, choices=range(1, 9), default=2)
    args = parser.parse_args()
    profiles = args.profile or list(PROFILES)
    cases = args.case or CASES
    seeds = args.seed or SEEDS
    if any(len(set(selection)) != len(selection) for selection in (profiles, cases, seeds)):
        parser.error("duplicate selection")
    if any(not 1 <= seed <= 2**32 - 1 for seed in seeds):
        parser.error("seed must be a nonzero 32-bit unsigned integer")

    versions = {}
    for tool in ("verilator", "yosys"):
        selected = shutil.which(tool)
        if not selected or not Path(selected).is_relative_to(ROOT / ".tools/install"):
            parser.error(f"activate the pinned {tool} installation")
        versions[tool] = subprocess.check_output([tool, "--version"], text=True).strip()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
    run_id = f"{stamp}-{uuid4().hex[:8]}"
    source_paths = sorted(set(PUBLIC + RTL + LOCKS + [DRIVER, WAIVERS, __file__,
                                                        f"{HERE}/pool_sources.py", "tools/frontend.py"]))
    source_paths = [str(Path(path).relative_to(ROOT)) if Path(path).is_absolute() else path
                    for path in source_paths]
    results = []
    for profile in profiles:
        run = Run(ROOT / ".build/runs" / f"pools-designer-{profile}-{run_id}", profile, source_paths)
        run.scope = "Production resource pool designer smoke"
        run.versions.update(versions)
        binary = frontend_checks(run, PROFILES[profile], args.jobs)
        slang_check(run, PROFILES[profile])
        for scenario in cases:
            selected_seeds = seeds if scenario == "random" or args.seed is not None else (17,)
            for seed in selected_seeds:
                log = simulate(run, binary, scenario, seed)
                if scenario == "random" and seed == 17:
                    if log is None:
                        Case(run, "random-17-replay", seed).finish("NOT_RUN", "Original seed 17 failed")
                    else:
                        simulate(run, binary, scenario, seed, replay_of=log)
        results.append(run.finish())
    return int(any(results))


if __name__ == "__main__":
    sys.exit(main())
