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
SV_HEADERS = ("rtl/include/multi_egress/tm_multi_types.svh", DV + "pool_random.svh")
INCLUDE_DIRS = ("rtl/include/multi_egress", DV.rstrip("/"))
SOURCES = [
    SOURCE_SET, *SV_SOURCES, *SV_HEADERS,
    *(DV + path for path in ("abi.py", "check.py", "coverage_plan.py", "oracle.py", "stimulus.py")),
    "tools/evidence.py", "tools/failure_capture.py", "tools/run.py", "tools/multi_egress_pools.py",
    "tools/dependencies.json", "tools/packages.lock.json", "Makefile",
    "docs/spec/multi-egress-traffic-manager.md", "docs/spec/multi-egress-interfaces.md",
    "verification/multi-egress-pools/baseline-allowlist.txt",
]
TOP = "multi_egress_pool_replay"
MARKER = re.compile(r"(?m)^POOL_REPLAY_PASS edges=(\d+) activity=(\d+)$")


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
        if any(name.strip() not in ('"tm_multi_types.svh"', '"uvm_macros.svh"', '"pool_random.svh"') for name in includes):
            raise ValueError(f"Unexpected transitive include in {filename}: {includes}")
    return manifest


def case(run, name, seed=None):
    result = Case(run, name, seed)
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


def bench_case(run, args, profile, binary, name, stimulus, triggers=None,
               detector=None, coverage=None, seed=None):
    from check import check_trace

    result = case(run, name, seed)
    trace = result.path / "monitor.edges"
    argv = [binary, f"+MONITOR_OUT={trace}", "+UVM_NO_RELNOTES"]
    if seed is not None:
        argv += [f"+verilator+seed+{seed}", f"+POOL_SEED={seed}", f"+TEMPLATES={stimulus}"]
    else:
        argv += [f"+REPLAY={stimulus}"]
    result.data["artifacts"].update(stimulus=str(stimulus), monitor_trace=str(trace))
    step = result.execute(argv, timeout=args.timeout, cwd=result.path, stem="simulate")
    if not classify(result, step, "POOL_REPLAY_PASS"):
        return None
    found = MARKER.findall(output(step))
    if len(found) != 1:
        result.finish("FAIL", "Missing or duplicate replay completion marker")
        return None
    try:
        summary = check_trace(trace, profile, triggers=triggers, detector=detector, coverage=coverage,
                              expected_edges=int(found[0][0]))
        if seed is not None and summary["random_activity_edges"] != int(found[0][1]):
            raise ValueError("Passive accepted activity count differs from stimulus count")
    except (OSError, ValueError, AssertionError) as error:
        result.finish("FAIL", str(error))
        return None
    if detector:
        result.finish("PASS", expected="SEEDED_DEFECT_DETECTION", observations=summary)
    else:
        result.finish("PASS", observations=summary)
    return summary


def native_coverage(run, args, profile, binary, samples, sampled_edges, name):
    from check import coverage_counts
    from coverage_plan import matrix

    result = case(run, name)
    database = result.path / "coverage.dat"
    argv = [binary, f"+COVER_ROWS={samples}", f"+verilator+coverage+file+{database}", "+UVM_NO_RELNOTES"]
    result.data["artifacts"].update(coverage_input=str(samples), native_database=str(database))
    step = result.execute(argv, timeout=args.timeout, cwd=result.path, stem="sample")
    if not classify(result, step, f"POOL_COVERAGE_PASS samples={sampled_edges}"):
        return None
    try:
        hits = coverage_counts(database)
        summary = {}
        for kind, counts in hits.items():
            planned = matrix(kind, profile)
            if set(planned) != set(counts):
                raise ValueError(f"{kind} database differs from frozen bin coordinates")
            if sum(counts.values()) != sampled_edges:
                raise ValueError(f"{kind} cross accounts for {sum(counts.values())} of {sampled_edges} edges")
            bins = [{"bin": key, "hits": counts[key], "exclusion": reason}
                    for key, reason in planned.items()]
            required = [entry for entry in bins if entry["exclusion"] is None]
            holes = [entry["bin"] for entry in required if not entry["hits"]]
            excluded_hits = [entry["bin"] for entry in bins if entry["exclusion"] and entry["hits"]]
            summary[kind] = dict(required=len(required), hit=len(required) - len(holes),
                                 holes=holes, excluded_hits=excluded_hits, bins=bins)
        failed = any(item["excluded_hits"] or (name == "required-coverage" and item["holes"])
                     for item in summary.values())
        result.finish("FAIL" if failed else "PASS",
                      "Required cross has holes or witnessed excluded bins" if failed else None,
                      coverage=summary, checked_edges=sampled_edges)
        return summary
    except (OSError, ValueError, AssertionError) as error:
        result.finish("FAIL", str(error))
        return None


def campaign(run, args, profile):
    from coverage_plan import ACTIVITY_EDGES, RANDOM_REQUIREMENTS, REQUIRED_DETECTORS, REQUIRED_WITNESSES, SEEDS
    from stimulus import generate

    binary = compile_bench(run, args, profile)
    if binary is None:
        return
    fixtures = run.path / "stimulus"
    generate(fixtures, profile)
    mapping = json.loads((fixtures / "cases.json").read_text())
    cases = {name: triggers for name, triggers in mapping.items() if not name.startswith(("descriptor:", "cell:"))}
    observed = {}
    if args.case:
        if args.case in (*cases, *REQUIRED_DETECTORS, "crosses"):
            triggers = ({k: edge for v in mapping.values() for k, edge in v.items() if ":" in k}
                        if args.case == "crosses" else cases.get(args.case))
            bench_case(run, args, profile, binary, args.case, fixtures / (args.case + ".edges"),
                       triggers=triggers, detector=REQUIRED_DETECTORS.get(args.case))
        else:
            case(run, "selection").finish("TOOL_ERROR", f"Unknown case {args.case}")
        return

    with (run.path / "checked-coverage.txt").open("w") as all_samples, \
         (run.path / "random-coverage.txt").open("w") as random_samples:
        for name, triggers in cases.items():
            summary = bench_case(run, args, profile, binary, name, fixtures / (name + ".edges"),
                                 triggers=triggers, coverage=all_samples)
            if summary:
                observed[name] = summary
        targeted = {k: edge for value in mapping.values() for k, edge in value.items() if ":" in k}
        crosses = bench_case(run, args, profile, binary, "crosses", fixtures / "crosses.edges",
                             triggers=targeted, coverage=all_samples)
        if crosses:
            observed["crosses"] = crosses
        for name, detector in REQUIRED_DETECTORS.items():
            bench_case(run, args, profile, binary, name, fixtures / (name + ".edges"), detector=detector)

        randomized = {}
        for seed in SEEDS:
            summary = bench_case(run, args, profile, binary, f"seed-{seed}", fixtures,
                                 coverage=random_samples, seed=seed)
            if summary:
                randomized[seed] = summary
        replay = bench_case(run, args, profile, binary, f"replay-{SEEDS[0]}", fixtures, seed=SEEDS[0])

    random_edges = sum(item["samples"] for item in randomized.values())
    if random_edges:
        all_text = run.path / "checked-coverage.txt"
        with all_text.open("a") as target, (run.path / "random-coverage.txt").open() as source:
            for line in source:
                target.write(line)
        native_coverage(run, args, profile, binary, run.path / "random-coverage.txt",
                        random_edges, "random-coverage")
    total_samples = sum(value["samples"] for value in observed.values()) + random_edges
    if total_samples:
        native_coverage(run, args, profile, binary, run.path / "checked-coverage.txt",
                        total_samples, "required-coverage")

    missing_triggers = set(REQUIRED_WITNESSES) - {
        label for value in observed.values() for label in value["triggers"]}
    features = {name for value in randomized.values() for name in value["features"]}
    missing_random = set(RANDOM_REQUIREMENTS) - features
    fingerprints = ("accepted_sha256", "result_sha256")
    replay_matches = bool(replay and SEEDS[0] in randomized and
                          all(replay[key] == randomized[SEEDS[0]][key] for key in fingerprints))
    activity = {seed: value["random_activity_edges"] for seed, value in randomized.items()}
    seed_pass = (set(activity) == set(SEEDS) and all(n >= ACTIVITY_EDGES for n in activity.values()) and
                 len({info["accepted_sha256"] for info in randomized.values()}) == len(SEEDS))
    ok = not (missing_triggers or missing_random) and replay_matches and seed_pass and crosses
    case(run, "campaign").finish("PASS" if ok else "FAIL", None if ok else "Missing campaign evidence",
                                 missing_triggers=sorted(missing_triggers),
                                 missing_random=sorted(missing_random), activity_edges=activity,
                                 replay_matches=replay_matches, seed_pass=seed_pass)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("multi-egress-pools-preparation", "multi-egress-pools-candidate"))
    parser.add_argument("--profile", choices=("primary", "small", "all"), default="all")
    parser.add_argument("--candidate-revision")
    parser.add_argument("--case", help="Run one named replay case for diagnosis")
    parser.add_argument("--output", type=Path, default=ROOT / ".build/runs")
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--timeout", type=float, default=240)
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
    from oracle import PROFILES

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
