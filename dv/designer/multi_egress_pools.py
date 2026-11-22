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
from evidence import IGNORED, Case, Run, completed, output, sha
from frontend import read_sources

HERE = "dv/designer"
BENCH = [f"{HERE}/{name}" for name in (
    "tm_pool_smoke_types.sv", "tm_pool_smoke_pkg.sv", "tm_pool_smoke_tb.sv",
)]
HEADERS = [f"{HERE}/{name}" for name in ("tm_pool_smoke_scoreboard.svh", "tm_pool_smoke_sequences.svh")]
WAIVERS = f"{HERE}/multi_egress_pools.vlt"
TOP = "tm_resource_pools"
SMOKE_TOP = "tm_pool_smoke_tb"
UVM = ROOT / ".deps/src/uvm/src"
RTL_PROBES = ("rtl-duplicate-cell", "rtl-free-cell", "rtl-duplicate-descriptor", "rtl-free-descriptor",
              "rtl-overcommit-d", "rtl-overcommit-u", "rtl-zero-count", "rtl-oversize-count")
CASES = ("descriptor", "cell", "peak", "abort", "identity", "reset", "producer", "random", *RTL_PROBES)
SEEDS = (17, 31, 53)


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
        "verilator", "--binary", "--timing", "--assert", "--coverage-user", "--timescale", "1ns/1ps",
        "+define+UVM_NO_DPI", "-DTM_POOL_ASSERTIONS", f"-DTM_POOL_SMOKE_PROFILE={geometry}",
        "--top-module", SMOKE_TOP, f"-I{INCLUDE}", f"-I{HERE}", f"-I{UVM}",
        "--build-jobs", str(jobs), "--output-groups", "4", "--output-split", "20000",
        "--output-split-cfuncs", "500", "-CFLAGS", "-O0", "--Mdir", obj,
        UVM / "uvm_pkg.sv", *RTL, *BENCH,
    ], timeout=900, stem="compile")
    binary = obj / f"V{SMOKE_TOP}"
    status, reason = compile_case["result"], compile_case["first_failure"]
    if IGNORED.search(output(compile_case)):
        status, reason = "UNSUPPORTED", "Simulator ignored a required construct"
    if status == "PASS" and not binary.is_file():
        status, reason = "TOOL_ERROR", "Missing compiled UVM executable"
    build.finish(status, reason)
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


def simulate(run, binary, scenario, seed, trace=None, replay=False):
    name = f"{scenario}-{seed}" + ("-replay" if replay else "")
    case = Case(run, name, seed)
    if binary is None:
        return case.finish("NOT_RUN", "Verilator build did not produce a usable executable")
    argv = [binary, f"+case={scenario}", f"+seed={seed}", "+UVM_NO_RELNOTES"]
    if trace is not None:
        argv.append(f"+trace_{'in' if replay else 'out'}={trace}")
        case.data["artifacts"]["edge_trace"] = str(trace)
    step = case.execute(argv, cwd=case.path, stem="simulate")
    if scenario in RTL_PROBES and step["returncode"] is not None and step["result"] != "TIMEOUT":
        # The fatal probe and its UVM verdict run in separate processes.
        step = case.execute([
            *argv, "+review_fault", f"+fault_exit={step['returncode']}",
            f"+fault_stdout={step['stdout']}", f"+fault_stderr={step['stderr']}",
        ], cwd=case.path, stem="fault-review")
    status, reason = completed(step, "POOL_UVM_COMPLETE")
    return case.finish(status, reason)


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
    source_paths = sorted(set(PUBLIC + RTL + LOCKS + BENCH + HEADERS + [WAIVERS, __file__,
                                                        f"{HERE}/pool_sources.py", "tools/frontend.py"]))
    source_paths = [str(Path(path).relative_to(ROOT)) if Path(path).is_absolute() else path
                    for path in source_paths]
    results = []
    for profile in profiles:
        run = Run(ROOT / ".build/runs" / f"pools-designer-{profile}-{run_id}", profile, source_paths)
        run.scope = "Production resource pool SV/UVM designer smoke"
        run.versions.update(versions)
        run.versions["uvm_pkg_sha256"] = sha(UVM / "uvm_pkg.sv")
        binary = frontend_checks(run, PROFILES[profile], args.jobs)
        slang_check(run, PROFILES[profile])
        for scenario in cases:
            selected_seeds = seeds if scenario == "random" or args.seed is not None else (17,)
            for seed in selected_seeds:
                trace = run.path / "random-17" / "edges.hex" if scenario == "random" and seed == 17 else None
                passed = simulate(run, binary, scenario, seed, trace)
                if trace is not None:
                    if passed:
                        simulate(run, binary, scenario, seed, trace, replay=True)
                    else:
                        Case(run, "random-17-replay", seed).finish("NOT_RUN", "Original seed 17 failed")
        results.append(run.finish())
    return int(any(results))


if __name__ == "__main__":
    sys.exit(main())
