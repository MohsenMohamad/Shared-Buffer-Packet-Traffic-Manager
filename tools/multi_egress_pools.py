"""Run the independent multi-egress pool preparation or candidate gate."""

import argparse
import json
import os
from pathlib import Path
import re
import resource
import sys
from uuid import uuid4

from evidence import Case, ROOT, Run, completed, output, sha, utc

DV = "dv/multi_egress_pools/"
SOURCE_SET = "verification/sources/multi-egress-pools-preparation.json"
SV_SOURCES = (
    "rtl/include/multi_egress/tm_multi_fixed.sv",
    DV + "pool_types.sv",
    DV + "pool_bench.sv",
)
DV_HEADERS = ("pool_random.svh", "pool_scoreboard.svh", "pool_model.svh",
              "pool_coverage.svh", "pool_witnesses.svh")
SV_HEADERS = ("rtl/include/multi_egress/tm_multi_types.svh", *(DV + name for name in DV_HEADERS))
INCLUDE_DIRS = ("rtl/include/multi_egress", DV.rstrip("/"))
SOURCES = [
    SOURCE_SET, *SV_SOURCES, *SV_HEADERS,
    *(DV + path for path in ("abi.py", "replay_types.py", "stimulus.py")),
    "tools/evidence.py", "tools/failure_capture.py", "tools/run.py", "tools/multi_egress_pools.py",
    "tools/dependencies.json", "tools/packages.lock.json", "Makefile",
    "docs/spec/multi-egress-traffic-manager.md", "docs/spec/multi-egress-interfaces.md",
    "verification/multi-egress-pools/baseline-allowlist.txt",
]
TOP = "multi_egress_pool_replay"
MARKER = "POOL_REPLAY_PASS"


def selected_sources():
    manifest = json.loads((ROOT / SOURCE_SET).read_text())
    if "extends" in manifest:
        raise ValueError("Pool preparation may not inherit a source set")
    for name, expected in (("sources", SV_SOURCES), ("headers", SV_HEADERS),
                           ("include_dirs", INCLUDE_DIRS)):
        if tuple(manifest[name]) != expected:
            raise ValueError(f"Unexpected pool {name}: {manifest[name]}")
        for filename in expected:
            path = ROOT / filename
            if path.resolve() != path or not path.exists():
                raise ValueError(f"Missing or indirect pool source path {filename}")
    for filename in (*SV_SOURCES, *SV_HEADERS):
        text = (ROOT / filename).read_text()
        includes = re.findall(r'(?m)^\s*`include\s+(.+)$', text)
        allowed = {f'"{name}"' for name in (*DV_HEADERS, "tm_multi_types.svh", "uvm_macros.svh")}
        if any(name.strip() not in allowed for name in includes):
            raise ValueError(f"Unexpected transitive include in {filename}: {includes}")
    return manifest


def case(run, name):
    result = Case(run, name)
    result.data["source_capture_paths"] = list(SOURCES)
    return result


def classify(result, step, marker):
    status, reason = completed(step, marker)
    if status != "PASS":
        result.finish(status, reason)
    return status == "PASS"


def compile_bench(run, args, profile):
    result = case(run, "build")
    data = selected_sources()
    uvm = Path(os.environ["UVM_HOME"]) / "src"
    top = result.path / "obj"
    command = ["verilator", "--binary", "--timing", "--assert", "--coverage-user",
               "--timescale", "1ns/1ps", "+define+UVM_NO_DPI",
               f"+define+POOL_PORTS={profile.ports}", "--build-jobs", str(args.jobs),
               "--output-groups", "4", "--output-split", "20000", "--output-split-cfuncs", "500",
               "-CFLAGS", "-O0", "+incdir+" + str(uvm),
               *("+incdir+" + str(ROOT / name) for name in data["include_dirs"]),
               str(uvm / "uvm_pkg.sv"), *(str(ROOT / name) for name in data["sources"]),
               "--top-module", TOP, "--Mdir", str(top)]
    version = result.execute(["verilator", "--version"])
    if not classify(result, version, "Verilator 5.054"):
        return None
    run.versions.update(verilator=output(version).strip(),
                        uvm=f"Accellera 2020.3.2, uvm_pkg.sv SHA-256 {sha(uvm / 'uvm_pkg.sv')}")
    step = result.execute(command, timeout=args.build_timeout, stem="compile")
    binary = top / f"V{TOP}"
    if not classify(result, step, "Verilator:"):
        return None
    if not binary.is_file():
        result.finish("TOOL_ERROR", "Compiler did not write the expected replay binary")
        return None
    result.finish("PASS", parameters=vars(profile), source_set=data, binary_sha256=sha(binary))
    return binary


def replay_status(step):
    status, reason = completed(step, MARKER)
    if status == "PASS" and output(step).splitlines().count(MARKER) != 1:
        return "FAIL", "Expected exactly one UVM completion record"
    return status, reason


def rejection_status(step, detector):
    if step["returncode"] is None or step["result"] == "TIMEOUT":
        return step["result"], step["first_failure"]
    log = output(step)
    fatal = re.search(rf"(?m)^.*Assertion failed .*POOL_CHECK_FAILED {re.escape(detector)} ", log)
    if step["returncode"] == 0 or not fatal or MARKER in log:
        return "FAIL", f"Expected a nonzero simulator exit from {detector} without completion"
    return "PASS", None


def bench_case(run, args, binary, fixtures, name, selection=None, rejection=None):
    result = case(run, name)
    database = result.path / "coverage.dat"
    argv = [binary, f"+FIXTURES={fixtures}", f"+EVIDENCE_DIR={result.path}",
            f"+verilator+coverage+file+{database}", "+UVM_NO_RELNOTES"]
    if selection is not None:
        argv.append(f"+POOL_CASE={selection}")
        result.data["selection"] = selection
    if rejection:
        argv.append("+UNQUALIFIED")
    result.data["artifacts"].update(
        stimulus=str(fixtures), monitor_traces=str(result.path),
        witnesses=str(result.path / "witnesses.txt"), checked_bins=str(result.path / "bins.txt"),
        native_database=str(database))
    step = result.execute(argv, timeout=args.timeout, cwd=result.path, stem="simulate")
    if rejection:
        result.finish(*rejection_status(step, rejection), expected="SIMULATOR_FATAL", detector=rejection)
    else:
        result.finish(*replay_status(step))


def campaign(run, args, profile):
    from stimulus import generate

    binary = compile_bench(run, args, profile)
    if binary is None:
        return
    fixtures = run.path / "stimulus"
    generate(fixtures, profile)
    if args.case is not None:
        bench_case(run, args, binary, fixtures, "replay", args.case)
        return
    bench_case(run, args, binary, fixtures, "campaign")
    for name, detector in (
        ("duplicate-edge", "EDGE_SEQUENCE"), ("lost-edge", "EDGE_SEQUENCE"),
        ("desc-return-bypass", "DESC_PRE_FREE"), ("stale-owner", "STALE_OWNER"),
        ("omit-final-cleanup", "DRAIN_OWNERSHIP"),
    ):
        bench_case(run, args, binary, fixtures, f"reject-{name}", name, detector)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("multi-egress-pools-preparation", "multi-egress-pools-candidate"))
    parser.add_argument("--profile", choices=("primary", "small", "all"), default="all")
    parser.add_argument("--candidate-revision")
    parser.add_argument("--case", help="Run one named replay case for diagnosis")
    parser.add_argument("--output", type=Path, default=ROOT / ".build/runs")
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--timeout", type=float, default=1200, help="Simulator timeout in seconds")
    parser.add_argument("--build-timeout", type=float, default=1200)
    args = parser.parse_args(argv)
    if not 1 <= args.jobs <= 8 or not 0 < args.timeout <= 3600 or not 0 < args.build_timeout <= 3600:
        parser.error("jobs must be 1..8; timeouts must be >0 and <=3600 seconds")
    if args.action == "multi-egress-pools-preparation" and args.candidate_revision is not None:
        parser.error("Preparation does not accept a candidate revision")

    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    env_file = ROOT / ".tools/environment.json"
    if env_file.is_file():
        os.environ.update(json.loads(env_file.read_text()))
    sys.path.insert(0, str(ROOT / DV))
    from replay_types import PROFILES

    failed = False
    profiles = list(PROFILES) if args.profile == "all" else [args.profile]
    stamp = utc().replace(":", "") + "-" + uuid4().hex[:8]
    for profile in profiles:
        run = Run(args.output / (args.action + "-" + profile + "-" + stamp),
                  profile, source_paths=list(SOURCES))
        if args.action == "multi-egress-pools-candidate":
            run.scope = "Production candidate binding"
            reason = ("Production pool adapter has not been bound" if args.candidate_revision
                      else "An exact candidate revision and a production pool adapter are required")
            case(run, "candidate").finish("NOT_RUN", reason, candidate_revision=args.candidate_revision)
        else:
            run.scope = ("One scoped replay case" if args.case else
                         "Independent UVM replay and pool-accounting preparation")
            try:
                campaign(run, args, PROFILES[profile])
            except (OSError, ValueError, KeyError, AssertionError) as error:
                case(run, "preparation-error").finish("TOOL_ERROR", str(error))
        failed |= run.finish() != 0
    return int(failed)
