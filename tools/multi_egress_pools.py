"""Run the independent multi-egress pool preparation or candidate gate."""

import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import subprocess
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
CANDIDATE_SET = "verification/sources/multi-egress-pools-candidate.json"
PRODUCTION_SOURCES = tuple("rtl/multi_egress/tm_" + name + ".sv" for name in (
    "pool_first_free", "cell_pool", "descriptor_pool", "reservation_accounting", "resource_pools"))
PRODUCTION_HEADERS = tuple("rtl/include/multi_egress/tm_multi_" + name + ".svh" for name in (
    "parameters", "types", "validate"))
PRODUCTION = (SV_SOURCES[0], *PRODUCTION_SOURCES, *PRODUCTION_HEADERS)
CANDIDATE_DV = (DV + "pool_candidate_top.sv", DV + "pool_candidate.svh",
                DV + "pool_candidate_checks.svh")
FORMAL_DV = ("formal/multi_egress_pools/pool_obligations.sv",
             "formal/multi_egress_pools/pool_candidate_formal.sv")
CANDIDATE_MARKER = "POOL_CANDIDATE_PASS"
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
        allowed = {f'"{name}"' for name in (*DV_HEADERS, "tm_multi_types.svh", "uvm_macros.svh",
                                              "pool_candidate.svh", "pool_candidate_checks.svh")}
        if any(name.strip() not in allowed for name in includes):
            raise ValueError(f"Unexpected transitive include in {filename}: {includes}")
    return manifest


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, timeout=30)


def verify_candidate(revision):
    if not revision or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Candidate requires a full lowercase 40-character commit SHA")
    if git("cat-file", "-t", revision).strip() != b"commit":
        raise ValueError("Candidate SHA must identify a commit")

    registry = json.loads((ROOT / CANDIDATE_SET).read_text())
    expected = {
        "production_sources": (SV_SOURCES[0], *PRODUCTION_SOURCES),
        "production_headers": PRODUCTION_HEADERS,
        "verification_sources": (*SV_SOURCES[1:], CANDIDATE_DV[0]),
        "verification_headers": (*(DV + name for name in DV_HEADERS), *CANDIDATE_DV[1:]),
        "include_dirs": INCLUDE_DIRS,
        "formal_sources": FORMAL_DV,
    }
    for key, paths in expected.items():
        if tuple(registry.get(key, [])) != paths:
            raise ValueError(f"Unexpected candidate {key}")
    files = (*PRODUCTION, *CANDIDATE_DV)
    for name in files:
        path = ROOT / name
        if path.resolve() != path or not path.is_file():
            raise ValueError(f"Missing or indirect candidate source path {name}")
    expected_digests = {}
    for name in (*PRODUCTION, "tools/dependencies.json", "tools/packages.lock.json"):
        content = git("show", f"{revision}:{name}")
        if (ROOT / name).read_bytes() != content:
            raise ValueError(f"Candidate source differs from {revision}: {name}")
        expected_digests[name] = hashlib.sha256(content).hexdigest()
    for name in files:
        includes = re.findall(r'(?m)^\s*`include\s+(.+)$', (ROOT / name).read_text())
        allowed = {f'"{Path(header).name}"' for header in PRODUCTION_HEADERS}
        if any(include.strip() not in allowed for include in includes):
            raise ValueError(f"Unregistered transitive include in {name}: {includes}")
    selected_sources()
    return registry, expected_digests


def case(run, name):
    result = Case(run, name)
    result.data["source_capture_paths"] = list(run.provenance["source_identity_paths"])
    return result


def classify(result, step, marker):
    status, reason = completed(step, marker)
    if status != "PASS":
        result.finish(status, reason)
    return status == "PASS"


def compile_bench(run, args, profile, registry=None, overrides=None):
    result = case(run, "build-mutations" if overrides else "build")
    data = selected_sources() if registry is None else registry
    sources = data["sources"] if registry is None else (
        *data["production_sources"], *data["verification_sources"])
    module = TOP if registry is None else "multi_egress_pool_candidate"
    mode = [] if registry is None else ["+define+POOL_CANDIDATE", "--coverage-line"]
    uvm = Path(os.environ["UVM_HOME"]) / "src"
    top = result.path / "obj"
    command = ["verilator", "--binary", "--timing", "--assert", "--coverage-user",
               "--timescale", "1ns/1ps", "+define+UVM_NO_DPI", *mode,
               f"+define+POOL_PORTS={profile.ports}", "--build-jobs", str(args.jobs),
               "--output-groups", "4", "--output-split", "20000", "--output-split-cfuncs", "500",
               "-CFLAGS", "-O0", "+incdir+" + str(uvm),
               *("+incdir+" + str(ROOT / name) for name in data["include_dirs"]),
               str(uvm / "uvm_pkg.sv"), *(str(ROOT / name) for name in sources),
               "--top-module", module, "--Mdir", str(top)]
    if overrides:
        command = [overrides.get(argument, argument) for argument in command]
    version = result.execute(["verilator", "--version"])
    if not classify(result, version, "Verilator 5.054"):
        return None
    run.versions.update(verilator=output(version).strip(),
                        uvm=f"Accellera 2020.3.2, uvm_pkg.sv SHA-256 {sha(uvm / 'uvm_pkg.sv')}")
    step = result.execute(command, timeout=args.build_timeout, stem="compile")
    binary = top / f"V{module}"
    if not classify(result, step, "Verilator:"):
        return None
    if not binary.is_file():
        result.finish("TOOL_ERROR", "Compiler did not write the expected replay binary")
        return None
    result.finish("PASS", parameters=vars(profile), source_set=data, binary_sha256=sha(binary),
                  mutation_source_digests={name: sha(path) for name, path in (overrides or {}).items()})
    return binary


def replay_status(step, marker=MARKER):
    status, reason = completed(step, marker)
    log = output(step)
    if status == "TOOL_ERROR" and re.search(r"Assertion failed .*POOL_CHECK_FAILED ", log):
        return "FAIL", next(line for line in log.splitlines() if "POOL_CHECK_FAILED " in line)
    if status == "PASS" and log.splitlines().count(marker) != 1:
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


def production_line_report(database):
    """Render native line points for the five production modules."""
    allowed = {Path(name).name for name in PRODUCTION_SOURCES}
    files = {}
    for line in database.read_text().splitlines():
        match = re.fullmatch(r"C '(.*)' (\d+)", line)
        if not match:
            continue
        fields = dict(field.split("\x02", 1) for field in match[1].split("\x01") if "\x02" in field)
        source = Path(fields.get("f", "")).name
        if source not in allowed or fields.get("t") not in ("line", "branch"):
            continue
        counts = files.setdefault(source, {}).setdefault(fields["t"], {"hit": 0, "total": 0})
        counts["total"] += 1
        counts["hit"] += int(int(match[2]) > 0)
    return files


def bench_case(run, args, binary, fixtures, name, selection=None, rejection=None, *, marker=MARKER, mutation=None):
    result = case(run, name)
    database = result.path / "coverage.dat"
    argv = ["stdbuf", "-oL", binary, f"+FIXTURES={fixtures}", f"+EVIDENCE_DIR={result.path}",
            f"+verilator+coverage+file+{database}", "+UVM_NO_RELNOTES"]
    if selection is not None:
        argv.append(f"+POOL_CASE={selection}")
        result.data["selection"] = selection
    if args.seed is not None:
        argv.append(f"+POOL_SEED={args.seed}")
    if args.replay:
        argv.append("+POOL_REPLAY")
    if mutation:
        argv.append(f"+POOL_MUTATION={mutation}")
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
        status, reason = replay_status(step, marker)
        if marker == CANDIDATE_MARKER and status == "PASS":
            if not database.is_file() or database.stat().st_size == 0:
                result.finish("TOOL_ERROR", "Simulator did not write its native coverage database")
                return
            report_path = result.path / "production-code-coverage.json"
            report_path.write_text(json.dumps(production_line_report(database), indent=2) + "\n")
            result.data["artifacts"]["production_code_coverage"] = str(report_path)
        result.finish(status, reason, mutation=mutation)


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


def record_candidate(run, revision, digests):
    parents = git("rev-list", "--parents", "-n1", "HEAD").decode().split()[1:]
    dv_revision = parents[1] if len(parents) == 2 and parents[0] == revision else None
    run.provenance.update(candidate_revision=revision, candidate_digests=digests,
                          dv_revision=dv_revision,
                          candidate_base=git("merge-base", dv_revision or "HEAD", revision).decode().strip(),
                          effective_tree=git("rev-parse", "HEAD^{tree}").decode().strip(),
                          effective_parents=parents)


def mutation_sources(run):
    directory = run.path / "mutated-rtl"
    directory.mkdir()
    replacements = {
        "tm_cell_pool.sv": (
            ".selected(write_id)", ".selected(old_write_id)",
            """    assign write_accept =""",
            """    cell_id_t old_write_id;
    assign write_id = $test$plusargs("POOL_MUTATION=return-bypass") &&
                      return_present[N_TX-1] ? return_cell[N_TX-1] : old_write_id;
    assign write_accept =""",
        ),
        "tm_resource_pools.sv": (
            "assign cell_present[lane] = tx_present[lane];",
            """assign cell_present[lane] = tx_present[lane] &&
            !($test$plusargs("POOL_MUTATION=drop-high-lane") &&
              lane == N_TX-1 && $countones(tx_present) == 1 && !cleanup_present);""",
        ),
        "tm_reservation_accounting.sv": (
            "unreserved_next = delta_t'(unreserved) + released_sum - reserved_sum;",
            """unreserved_next = delta_t'(unreserved) + released_sum - reserved_sum
            + delta_t'($test$plusargs("POOL_MUTATION=credit-delta") && released_sum != 0);""",
        ),
    }
    overrides = {}
    patches = []
    for name, edits in replacements.items():
        original = ROOT / "rtl/multi_egress" / name
        before = original.read_text()
        after = before
        for anchor, replacement in zip(edits[::2], edits[1::2], strict=True):
            if after.count(anchor) != 1:
                raise ValueError(f"Mutation anchor changed in {name}: {anchor}")
            after = after.replace(anchor, replacement)
        path = directory / name
        path.write_text(after)
        overrides[str(original)] = str(path)
        relative = str(original.relative_to(ROOT))
        patches.extend(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                                           f"a/{relative}", f"b/{relative}"))
    (directory / "mutations.patch").write_text("".join(patches))
    return overrides


def candidate_campaign(run, args, profile):
    from stimulus import generate_candidate

    registry, digests = verify_candidate(args.candidate_revision)
    record_candidate(run, args.candidate_revision, digests)
    fixtures = run.path / "stimulus"
    generate_candidate(fixtures, profile)
    if args.mutations:
        binary = compile_bench(run, args, profile, registry, mutation_sources(run))
        if binary is None:
            return
        for mutation, neighbor in (("return-bypass", "cell-exchange"),
                                   ("drop-high-lane", "return-lanes"),
                                   ("credit-delta", "final-cleanup")):
            bench_case(run, args, binary, fixtures, f"legal-{mutation}", neighbor,
                       marker=CANDIDATE_MARKER)
            bench_case(run, args, binary, fixtures, mutation, neighbor,
                       marker=f"POOL_MUTATION_DETECTED {mutation}", mutation=mutation)
        return
    binary = compile_bench(run, args, profile, registry)
    if binary is not None:
        bench_case(run, args, binary, fixtures, "candidate", args.case, marker=CANDIDATE_MARKER)


def formal_campaign(run, args, profile):
    registry, digests = verify_candidate(args.candidate_revision)
    record_candidate(run, args.candidate_revision, digests)
    jobs = (args.formal_mode,) if args.formal_mode else (
        ("bmc", "prove", "cover", "exhaustion") if profile.ports == 2 else ("primary-prefix",))
    for mode in jobs:
        result = case(run, mode)
        if mode == "exhaustion" and profile.ports != 2:
            result.finish("NOT_RUN", "Full cell-exhaustion cover is registered for the small profile")
            continue
        if mode == "primary-prefix" and profile.ports != 4:
            result.finish("NOT_RUN", "The primary prefix cover requires the primary profile")
            continue
        directed_covers = {
            "exhaustion": ("-DPOOL_EXHAUSTION_COVER", "c_full_cell_exhaustion"),
            "primary-prefix": ("-DPOOL_PRIMARY_PREFIX_COVER", "c_primary_capacity"),
        }
        is_cover = mode == "cover" or mode in directed_covers
        depth = args.depth or {"prove": 4, "bmc": 6, "cover": 12, "exhaustion": 22, "primary-prefix": 7}[mode]
        caller = args.formal_caller or ("ledger" if profile.ports == 2 else "aggregate")
        if mode == "exhaustion" and caller != "ledger":
            result.finish("NOT_RUN", "Directed capacity covers use the frame ledger")
            continue
        inputs = (*registry["production_sources"], *registry["formal_sources"])
        profile_id = int(profile.ports == 2)
        definitions = ["-DPOOL_ABSTRACT_CALLER"] if caller == "aggregate" else []
        if mode in directed_covers:
            definitions.append(directed_covers[mode][0])
        script = (f"read_slang --top pool_candidate_formal -GPROFILE={profile_id} "
                  f"{' '.join(definitions)} -I. {' '.join(Path(path).name for path in inputs)}\n"
                  "prep -top pool_candidate_formal")
        if mode == "cover":
            script += "\nchformal -cover -remove pool_candidate_formal/c:check_pool.c_cell_exhaustion"
        elif mode in directed_covers:
            selected = directed_covers[mode][1]
            script += ("\nchformal -cover -remove pool_candidate_formal/c:c_* "
                       f"pool_candidate_formal/c:check_pool.c_* %u pool_candidate_formal/c:{selected} %d")
            if mode == "primary-prefix":
                script += "\nchformal -assert -remove\nopt_clean"
        files = "\n".join(str(ROOT / name) for name in (*inputs, *registry["production_headers"]))
        config = result.path / "pool.sby"
        engine = "smtbmc z3"
        if mode == "prove":
            engine = "abc pdr" if args.proof_engine == "pdr" else "smtbmc --unroll z3"
        elif mode == "bmc" and args.bmc_engine == "abc":
            engine = "abc bmc3"
        sby_mode = "cover" if is_cover else mode
        config.write_text(f"[options]\nmode {sby_mode}\ndepth {depth}\n"
                          f"[engines]\n{engine}\n[script]\n{script}\n[files]\n{files}\n")
        result.data["artifacts"].update(formal_config=str(config), traces=str(result.path / "work"))
        step = result.execute(["sby", "-f", "-d", result.path / "work", config], timeout=args.timeout)
        status, reason = completed(step, "DONE (PASS")
        transcript = output(step)
        reached = [{"step": int(edge), "name": name} for edge, name in re.findall(
            r"Reached cover statement in step (\d+) at pool_candidate_formal: (\S+)", transcript)]
        if status == "PASS" and is_cover and not reached:
            status, reason = "TOOL_ERROR", "Formal tool reported no executed cover"
        if status == "TOOL_ERROR" and "DONE (UNKNOWN" in transcript:
            status, reason = "INCONCLUSIVE", "Engine did not establish the induction step"
        if status == "TOOL_ERROR" and "DONE (FAIL" in transcript:
            status = "INCONCLUSIVE" if sby_mode == "cover" else "FAIL"
            reason = "Required cover not reached within depth" if sby_mode == "cover" else "Formal counterexample"
        result.finish(status, reason, mode=sby_mode, depth=depth, engine=engine,
                      caller=caller, parameters=vars(profile), reached_covers=reached)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("multi-egress-pools-preparation", "multi-egress-pools-candidate",
                                           "multi-egress-pools-formal"))
    parser.add_argument("--profile", choices=("primary", "small", "all"), default="all")
    parser.add_argument("--candidate-revision")
    parser.add_argument("--mutations", action="store_true")
    parser.add_argument("--formal-mode", choices=("prove", "bmc", "cover", "exhaustion", "primary-prefix"))
    parser.add_argument("--proof-engine", choices=("pdr", "induction"))
    parser.add_argument("--bmc-engine", choices=("abc", "z3"), default="z3")
    parser.add_argument("--formal-caller", choices=("aggregate", "ledger"))
    parser.add_argument("--depth", type=int, choices=range(2, 65), metavar="2..64")
    parser.add_argument("--case", help="Run one named replay case for diagnosis")
    parser.add_argument("--seed", type=int, choices=(17, 31, 53, 67, 89, 113, 149, 197))
    parser.add_argument("--replay", action="store_true", help="Check an identical replay of seed 17")
    parser.add_argument("--output", type=Path, default=ROOT / ".build/runs")
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--timeout", type=float, default=1200, help="Simulator timeout in seconds")
    parser.add_argument("--build-timeout", type=float, default=1200)
    args = parser.parse_args(argv)
    if not 1 <= args.jobs <= 8 or not 0 < args.timeout <= 3600 or not 0 < args.build_timeout <= 3600:
        parser.error("jobs must be 1..8; timeouts must be >0 and <=3600 seconds")
    if args.action == "multi-egress-pools-preparation" and args.candidate_revision is not None:
        parser.error("Preparation does not accept a candidate revision")

    if args.case is not None and args.seed is not None:
        parser.error("--case and --seed select different runs")
    if args.replay and args.seed != 17:
        parser.error("--replay requires --seed 17")
    formal = args.action == "multi-egress-pools-formal"
    candidate = args.action == "multi-egress-pools-candidate"
    if args.mutations and (not candidate or args.profile != "small" or args.seed or args.case):
        parser.error("--mutations requires the full small candidate selection")
    if formal and (args.seed or args.case):
        parser.error("Formal selection uses --formal-mode and --depth")
    if args.proof_engine and (not formal or args.formal_mode != "prove"):
        parser.error("--proof-engine requires --formal-mode prove")
    if args.bmc_engine == "abc" and (not formal or args.formal_mode != "bmc"):
        parser.error("--bmc-engine abc requires --formal-mode bmc")
    if not formal and (args.formal_mode or args.formal_caller or args.depth):
        parser.error("Formal options require the formal target")
    source_paths = [*SOURCES, CANDIDATE_SET, *PRODUCTION, *CANDIDATE_DV] if candidate or formal else SOURCES
    if formal:
        source_paths += list(FORMAL_DV)

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
                  profile, source_paths=list(dict.fromkeys(source_paths)))
        run.scope = ("Production pool component formal" if formal else
                     "Production pool component" if candidate else "Independent UVM pool preparation")
        try:
            if formal:
                formal_campaign(run, args, PROFILES[profile])
            elif candidate:
                candidate_campaign(run, args, PROFILES[profile])
            else:
                campaign(run, args, PROFILES[profile])
        except (OSError, ValueError, KeyError, AssertionError, subprocess.SubprocessError) as error:
            case(run, "selection-or-build-error").finish("TOOL_ERROR", str(error))
        failed |= run.finish() != 0
    return int(failed)
