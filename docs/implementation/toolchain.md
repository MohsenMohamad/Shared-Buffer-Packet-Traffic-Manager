# Running the P00 capability gates

Install prerequisites on Linux x86-64: Python 3.11+, glibc 2.39+, a C++20
compiler with working `std::format` (GCC 14 is tested), Make, Bash, Perl, Git,
curl, pkg-config and dpkg-deb. CI transfer additionally uses zstd. Then run:

```sh
make setup JOBS=2
make doctor
make repo-check
make test-unit
make lint
make test-uvm-smoke JOBS=2
make uvm-dpi JOBS=2
make formal-smoke
make synth-smoke
make frontends
make bridge
make representation-formal
make ci JOBS=2
```

The selected locks are Yosys 0.70 with its integrated slang frontend and
ABC gitlinks, Verilator 5.054, UVM 2020.3.2, SBY 0.71, Z3 5.4.1 and authoritative
OpenSTA 3.2.0 source. CMake 4.4.5, SWIG 4.5.1, Eigen 5.0.1, CUDD 3.0.0 and Click
8.5.1 are explicit dependencies. See the [inventory and source identities](modern-toolchain-plan.md)
and [current qualification status](../results/modern-toolchain.md); active pins do
not imply all required qualification has completed.

`setup` verifies every cached/downloaded archive, extracts the audited build and
Tcl/zlib packages into `.tools/sysroot`, builds to `.tools/install`, and retains
external source/licenses under `.deps`. It does not depend on an old toolchain
installation, a container, system package installation or mutable upstream
branches. The upstream Z3 binary requires glibc 2.39; C++ language/runtime
compatibility is tested by compilation/execution, rather than rejecting every
compiler patch different from 14.2.0.

A cold source build can take substantial time on two cores. Yosys/ABC builds are
bounded to two hours; other setup steps to one hour. Logs are under `.build/setup`.
The completion stamp is written only after every install succeeds. Repeated setup
verifies archives and reuses a complete matching recipe. Changed source archives
invalidate their CMake objects; CI cold preparation discards all owned tool/source
and CMake build trees, preventing an ABI/lock miss from reusing stale objects.

Autoconf/Automake/Bison/Flex/M4 and the Flex C++ header come from exact package
locks. CMake uses its checksum-locked official distribution; SWIG is source-built.
Local alternatives and Autotools metadata/executables are relocated explicitly.
Help2man, old packaged tools, Boost Python/filesystem/system, readline and ffi are
not required by the chosen recipes. Eigen is header-only here; optional BLAS,
LAPACK, demos, tests and documentation are disabled. Tcl 8.6 matches the selected
OpenSTA finder/runtime ABI. No implicit fmt fetch occurs because the compiler's
`std::format` probe must succeed.

The runner loads `.tools/environment.json`; for direct native commands use
`source .tools/activate.sh`. The compatibility UVM entry point delegates to
the common runner; `--uvm-home` must identify the locked repository install.
No external credential, GUI or container daemon is needed.

`make ci` runs doctor, repository contracts, runner tests, fixture lint and
compiler-error rejection, UVM, formal and mapping/STA in sequence, continuing
independent gates after failures. GitHub Actions runs UVM/formal/synthesis/frontend/bridge/representation checks
in dependent consumer jobs after one shared preparation, each with its doctor and orchestration checks. Routine
artifacts are retained for 14 days. Hosted execution status belongs in the
PR; adding a workflow is not evidence that it executed successfully.

P00 capability commands use the `toolchain` profile. UVM defaults to seeds 17 and 19,
plus an identical seed-17 replay and a held-data mutation. For example:

```sh
make test-uvm-smoke RUN_ARGS='--profile toolchain --seed 23 --seed 29 --timeout 120 --build-timeout 1200'
python3 tools/run.py ci --test formal --test synth --jobs 2
```

Jobs are limited to 1–8, with default 2. Run subprocesses default to 120
seconds, UVM compilation to 1200; both are configurable up to 3600 seconds.
Timeout kills the process group, including compiler and solver children.
Unknown/empty selections, duplicate selections, incompatible versions,
failed compilation, missing completion evidence and zero unit tests fail.
`coverage`, `benchmark`, `synthesis` and `sta` remain
`NOT_IMPLEMENTED`, exiting nonzero until their hardware tasks land.

Each invocation creates a unique directory under `.build/runs` (`--output`
changes the parent). `summary.json` links per-case manifests. Manifests include
UTC start/end, source revision/dirty state, owned-source/dependency/constraint
digests, versions, profile/seed, exact argv/cwd, return codes, result and first
failure, and artifact paths. Stdout and stderr have separate files. Results
retain `TOOL_ERROR`, `TIMEOUT`, `UNSUPPORTED`, `NOT_RUN` and
`NOT_IMPLEMENTED`; they cannot become empty PASS. Expected assertion failures
and formal counterexamples retain their nonzero raw tool status and an
explicit expected outcome, while the capability check passes only after
inspecting the assertion/trace evidence.

Inspect UVM `coverage.dat`, the coverage tool's report, and the manifest's
`coverage` object. The runner requires nonzero owned line coverage and 19 named
functional bins (4 queues, 3 length ranges, 12 crosses), including hit cross
bins. Unhit bins stay visible. Tool percentages are not substituted for raw
counts. Positive failures are rerun with tracing using the same executable,
seed and profile. The negative assertion run always saves `wave.vcd`.

Verilator is two-state: X/Z propagation is unsupported. The separate current-stack reproducer retains its actual execution status in the refresh report. UVM DPI/backdoor
services are available for separately qualified uses; the default frontdoor path retains `UVM_NO_DPI`. No
production RTL, full-system proof, physical timing signoff or silicon result
is implied. See [the decision record](../decisions/0001-native-toolchain.md)
and [executed results](../results/P00-toolchain.md).

`python3 tools/run.py four-state` compiles and executes the portable
`tests/toolchain/four_state.sv` reproducer. A simulator retaining X values
should print `TM_FOUR_STATE_PASS`; Verilator instead reaches
`TM_FOUR_STATE_UNSUPPORTED`. That executed case has `UNSUPPORTED` status
and exits nonzero. It is kept outside the required two-state capability
suite, with its limitation retained in the results.

P01 adds `regression --profile E0 --test contracts --seed 17` (all six
production profiles supported). This selects declaration elaboration and batching
examples only. See [module contracts](../spec/module-contracts.md) for source
ownership, seed rules and verification limits.

P02 adds the `pools` component suite under all six production profiles. It runs
both FIFO depths and cell/descriptor exhaustion/recovery, invalid requests and
reset collisions with independent models. An extra ID encoding bit exercises
out-of-range requests. Example:

```sh
make regression RUN_ARGS='--profile I0 --test pools --seed 19'
make formal-rtl RUN_ARGS='--timeout 240'
make formal-rtl RUN_ARGS='--test descriptor --test fifo4 --timeout 240'
```

The production formal route defaults to E0 with a 240-second per-task timeout
and rejects other profiles, empty,
duplicate or unknown family selections and seeds. It runs prove/cover tasks and
the pool wrong-delta qualifications. See [proof scope](../../formal/pools/README.md).
`formal-smoke` remains the P00 counter fixture. Component tests and local pool
proofs do not establish integrated traffic-manager ownership or payload behavior.

P07 adds `regression --profile E0 --test uvm-foundation --seed 17`. The suite
executes real UVM agents, frontdoor RAL, independent observed-transaction models,
saved coverage and exact seeded-defect detections on a declared behavioral
fixture. I0 also qualifies simultaneous descriptor returns in the model probe.
This route is separate from production TM requirements and the P00 tool fixture.
See [P07 results](../results/P07-verification-foundation.md).

## Registered frontend and representation checks

The formal and synthesis source registries select `slang`. `read_slang` is built
into the pinned Yosys executable; no plugin from a global installation is loaded.
`--frontend verilog` explicitly selects the same Yosys binary's native diagnostic
path. The old reference flow uses a separately prepared installation/check-out
at the historical pins; never put both installations on PATH or share runtimes.

```sh
make frontends
make bridge
make representation-formal
python3 tools/run.py formal-rtl --frontend verilog --test fifo2
python3 tools/run.py frontends --frontend verilog
python3 tools/run.py uvm-dpi
```

The native frontend comparison deliberately returns nonzero for unsupported
representations; inspect each phase/result, rather than interpreting a syntax
rejection as completed synthesis. `frontends` compares disposable production
FIFO/CSR/statistics copies, six-profile and invalid elaborations for the selected
recipes, heterogeneous instances, and independent memory/signed/unpacked/interface
examples. Source paths passed to slang use checkout-relative names; whitespace
inside source-relative paths is explicitly rejected until separately qualified.

`bridge` audits actual symbolic cells, initialization, `$past`, asynchronous
reset conversion, source labels/property counts, intended counterexamples and
cover reachability. Complete harness assumption predicates are proved equivalent
by mutual inclusion with shared arbitrary inputs; CSR state correspondence is
proved as additional invariants. The miter re-encodes every assumption predicate as an output and proves mutual
inclusion separately; production prove/cover/mutation runs retain all original
assumptions, assertions and covers. Slang's unsupported symbolic attributes/functions retain their executed
negative diagnostics; ordinary arbitrary top-level inputs are the accepted bridge.

`representation-formal` applies richer ANSI/type-parameter declarations and a
packed-record FIFO array only to generated copies of the real production modules.
It reuses their unchanged formal harnesses/properties at both FIFO depths and the
CSR proof/cover/coupling mutation. Production conversion belongs to the
[P01 follow-up](tasks/P01-followup-representation.md). Interface acceptance does
not itself justify changing the published packed-lane ABI or design algorithms.

The optional `uvm-dpi` command exercises actual regex and HDL path/read/deposit
services with the unmodified UVM DPI sources and explicit VPI visibility. Its
result does not replace frontdoor/RAL behavior, which remains qualified with the
existing no-DPI configuration. Review each service's executed status before use.

Mapping uses explicit Liberty flop mapping and ABC after `synth -noabc`. The fixed
Nangate45 typical library has ns/fF units, 1.10 V and 25 C. The capability fixture
uses a 10 ns ideal clock, 0.05 ns uncertainty, min/max IO delays, 10 fF output load,
and explicit input slew plus a separate driving-cell case. Error/warning checks,
missing constrained paths and deliberately malformed inputs remain required even
when Tcl prints a completion marker. These are pre-layout/reference-library
checks; one typical Liberty without parasitics/variation data cannot establish
physical, multi-corner, variation or noise closure.

## One CI preparation producer

[CI](../../.github/workflows/toolchain.yml) owns PR, integrated-main push and manual triggers. It calls the existing repository and component workflows through `workflow_call`; those files no longer launch independent preparations. The repository check can run immediately. The capability matrix and every heavy component workflow have a real `needs: prepare` edge in the caller. A dependency orders jobs but does not share their files: each consumer downloads the producer's same-run installation archive, extracts it with preserved permissions (`tar --zstd -xpf`) in its checkout, and runs strict validation. Consumers never build on a missing or rejected payload.

The producer computes an exact installation key, restores a matching Actions cache when available, then runs `tools/toolchain_cache.py prepare`. A valid installation passes inventory/checksum checks and the current doctor (version, C++20 and solver execution). A miss or rejected installation is discarded and built once from the locks, then doctored and sealed. Only successful preparation is cached and uploaded. A job step records the validated `cold`/`cache` outcome and `miss`/`accepted`/`rejected` status as well as the preparation artifact. No partial installation is accepted.

Installation identity includes both dependency locks, setup scripts, setup-imported `evidence.py`, the cache-format helper, Linux OS release, architecture, glibc, Python ABI, compiler version/target, inherited compiler/linker/Make flags and the C++ runtime digest. It excludes `tools/run.py`, `tools/doctor.py` and repository HEAD. Suite registration and non-rejecting validator-only edits therefore reuse identical tools. Every restore and every consumer still executes the current validator; neither a matching key nor an old seal is acceptance.

If a validator change rejects previously compatible installations, bump `CACHE_PREFIX` in `tools/toolchain_cache.py` in the same PR. The versioned generation (currently `tm-tools-v3-`) provides a new immutable key under which a successful rebuild can be saved, even when the tool binaries are unchanged. The changed validator must pass before sealing/saving; a prefix bump cannot turn a failed validation into success.

Setup embeds absolute paths, so the checkout root remains part of identity and consumers must use the same layout. Standard hosted jobs for this repository provide that layout; a custom runner must reproduce it or prepare its own compatible installation. The current doctor compiles/executes the required C++20 features; a changed compiler/runtime invalidates cache compatibility without imposing one compiler patch as a universal requirement.

Hosted bootstrap checks use installed compiler/Make/Perl/curl/Git/dpkg/Python/zstd and install packages only when missing. Autoconf, Automake, Bison, Flex and the scanner header come from the checksum-locked sysroot, so a warm run does not require an unnecessary apt mirror refresh.

Caches are an optimization. Cache service restore/save failures do not remove the cold build path. Rejection emits a workflow warning naming the actual restored key and reason. `.build/setup-cache/preparation.json` retains `rejected_key`, `restore_rejected`, `cache_status: rejected` and `source: cold`; an Actions exact hit followed by rebuilding is not healthy cache reuse. An immutable rejected entry cannot be overwritten: bump the existing `CACHE_PREFIX` generation and commit/push the change before expecting a replacement entry. Failed setup or current validation never produces a complete seal or a cache save.

PR-created caches are scoped to the PR merge ref and are **not available to main**. Main may need its own cold build unless a compatible default-branch cache exists. PR jobs may restore a compatible default-branch cache according to Actions scope rules.

Only superseded pull-request runs share a cancellation group. Every main push and manual run/attempt has its own group, so both active and older pending runs can complete independently. Setting only `cancel-in-progress: false` on a shared main group would still allow GitHub to replace an older pending run; unique groups avoid that loss.

### Ephemeral handoff cleanup

The per-run installation handoff has one-day retention. After all heavy consumers settle, including failed/skipped consumers, an `always()` cleanup job verifies the producer's exact artifact ID, name, run ID and attempt before deleting that handoff alone. Only this job has job-level `actions: write`; the workflow default remains `contents: read`. Diagnostic/result artifacts retain their 14-day policy and are never selected for deletion. Raw transfer tarballs remain excluded from consumer evidence uploads.

Cleanup is best effort. A missing/restricted token, API failure or metadata mismatch emits a warning and records `retention-fallback` in the job output and summary. Cancellation may prevent cleanup from executing; the producer announces the one-day fallback before upload. Previously uploaded historical handoffs keep their original retention and are not swept. Rerun the whole workflow, including preparation, when a new handoff is needed; rerunning a consumer alone cannot recover a deleted or expired archive.

### Local preparation and transfer checks

The preparation command owns and may replace ignored `.tools` and `.deps` directories. Do not run it against an installation you need to preserve without a backup. Ordinary developer `make setup` remains available.

```sh
CXX=g++-14 python3 tools/toolchain_cache.py key
CXX=g++-14 python3 tools/toolchain_cache.py prepare --jobs 2
CXX=g++-14 python3 tools/toolchain_cache.py prepare --jobs 2
mkdir -p .build/toolchain-transfer
tar --zstd -cf .build/toolchain-transfer/toolchain.tar.zst .tools .deps/downloads .deps/src/uvm .deps/liberty.lib
CXX=g++-14 python3 tools/toolchain_cache.py validate
python3 -m unittest discover -s tests/toolchain -p test_toolchain_cache.py -v
```

The first command on an empty installation must report `cold`, the second `cache`. Preserve `.build/setup-cache/preparation.json` after each invocation if comparing them: the latest preparation replaces that summary. Each validation records the real doctor's case manifests under `.build/runs`. A local tar transfer should be extracted into an emptied installation at the same absolute checkout path and validated before executing a consumer command. Local checks establish implementation behavior, not hosted cache scope or Actions orchestration.

### Hosted verification procedure

1. Open/update the PR and inspect the CI run for its actual head/merge revision, or dispatch CI explicitly with `gh workflow run toolchain.yml --ref chore/review-preparation`. Locate its real run ID with `gh run list --workflow toolchain.yml --branch chore/review-preparation`; inspect it with `gh run view RUN_ID --json headSha,event,status,conclusion,jobs,url`.
2. For a fresh compatibility key, confirm exactly one `prepare-toolchain` job records a miss and `source: cold`, successful setup/doctor, cache save and transfer upload. All heavy consumers must start only after preparation succeeds and must download and validate the same named artifact in their own workspaces. Inspect every suite's actual result, including intended negative qualifications; merely scheduled or skipped jobs do not pass.
3. Use a second run: push an unrelated documentation commit on the same PR to test PR-cache reuse, or dispatch twice on the same branch for branch-scoped reuse. Do not expect a branch dispatch to see a PR-merge-ref cache. Verify the same key, an exact hit, `source: cache`, `cache_status: accepted`, a successful current restore-doctor and no setup invocation. Record cold and reuse run IDs/URLs and tested SHAs separately; one run cannot demonstrate both paths.
4. On a disposable branch, change a relevant setup input or lock without changing qualified versions. Verify the key changes and the producer cold path executes once. Keep criteria/source modifications separate from measured results. Unit tests cover corruption/ABI invalidation; a hosted corruption exercise, if needed, must use a disposable cache key, never damage shared main entries.
5. Verify a main push after integration independently: PR cache availability is not evidence of main reuse. Do not merge merely to test this task. If Actions cannot run or be inspected, record the precise limitation and leave these hosted outcomes unverified.
6. After consumers settle, inspect `cleanup-handoff`. Confirm the selected handoff ID is absent after `deleted`, while preparation and test artifacts remain. A reported permission/API failure or cancellation leaves the one-day fallback; record it as a fallback, not successful deletion. Check concurrency with distinct main/manual run IDs and shared same-PR groups; do not claim hosted main execution from a local policy test.

The supporting [review-preparation results](../results/review-preparation.md) distinguish executed local checks from observed hosted runs.

The synthesis gate also checks current OpenSTA API availability (`define_scene`,
`read_spef`, `set_timing_derate`, `annotate_noise_delays`) and default POCV mode.
This does not run multi-scene, statistical variation or coupled-noise analysis.
Those studies need characterized corner/variation libraries and annotated routed
parasitics, including coupling data for noise. `define_corners` is deprecated
upstream in favor of `define_scene`. FIFO mapping records path groups and
`timing_closure` independently of successful analysis; see the refresh report
for the retained reset-removal violation.

The executed DPI service probe passes positive/negative regex matching and
HDL path/read/deposit using unmodified UVM C++ sources. Only its target variable
is marked `public_flat_rw`; globally exposing the entire UVM implementation is
unnecessary. Integer API results are compared with zero and deposit values are
cast to `uvm_hdl_data_t`, keeping owned width diagnostics enabled. This does not
qualify force/release, polling or X/Z semantics.

DPI services have their own shared-installation CI consumer; production frontdoor
regressions continue to use their tested no-DPI configuration.
