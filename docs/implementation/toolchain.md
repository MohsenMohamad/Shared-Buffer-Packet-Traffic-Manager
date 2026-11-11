# Running the P00 capability gates

Install prerequisites on Linux x86-64: Python 3.11+, glibc 2.38+, GCC 14
(C++20), Make, Bash, Perl, Git, curl, and dpkg-deb. Then run:

```sh
make setup JOBS=2
make doctor
make repo-check
make test-unit
make lint
make test-uvm-smoke JOBS=2
make formal-smoke
make synth-smoke
make ci JOBS=2
```

`setup` verifies all cached/downloaded bytes before use, extracts pinned
packages into `.tools/sysroot`, installs tools into `.tools/install` and
places dependency sources in `.deps`. It writes `.tools/setup.json` only
after successful installation. Repeating the same recipe verifies downloads
and reuses the prepared installation. Delete `.tools/setup.json` to rerun
installation, or delete `.deps/src/verilator` for a clean simulator rebuild.
Installation logs are under `.build/setup`. Builds are bounded to 30 minutes
per setup step. Source checks are never implicitly installed by tests.

The runner loads `.tools/environment.json`; for direct native commands use
`source .tools/activate.sh`. The compatibility UVM entry point delegates to
the common runner; `--uvm-home` must identify the locked repository install.
No external credential, GUI or container daemon is needed.

`make ci` runs doctor, repository contracts, runner tests, fixture lint and
compiler-error rejection, UVM, formal and mapping/STA in sequence, continuing
independent gates after failures. GitHub Actions runs UVM/formal/synthesis
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

Verilator is two-state: X/Z propagation is unsupported. UVM DPI/backdoor
services are deliberately outside the qualified `UVM_NO_DPI` baseline. No
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

## One CI preparation producer

[CI](../../.github/workflows/toolchain.yml) owns PR, integrated-main push and manual triggers. It calls the existing repository and component workflows through `workflow_call`; those files no longer launch independent preparations. The repository check can run immediately. The capability matrix and every heavy component workflow have a real `needs: prepare` edge in the caller. A dependency orders jobs but does not share their files: each consumer downloads the producer's same-run installation archive, extracts it in its checkout, and runs strict validation. Consumers never build on a missing or rejected payload.

The producer computes an exact compatibility key, restores a matching Actions cache when available, then runs `tools/toolchain_cache.py prepare`. A valid installation passes inventory/checksum checks and the real doctor (version, C++20 and solver execution). A miss or rejected installation is discarded and built once from the locks, then doctored and sealed. Only successful preparation is cached and uploaded. No partial installation is accepted. The installation transfer is retained for two days; diagnostic/test artifacts for 14 days. Raw transfer tarballs are excluded from consumer evidence uploads.

Compatibility includes both dependency locks, setup/activation/evidence/doctor/runner/cache-helper inputs, Linux OS release, architecture, glibc, Python ABI, compiler version/target and the C++ runtime digest. It does not include the repository HEAD; unrelated RTL/docs commits reuse compatible tools. Setup embeds absolute paths, so the checkout root is also included and consumers must use the same checkout layout. Standard hosted jobs for this repository provide that layout; a custom runner must reproduce it or prepare its own compatible installation. Preserve the pinned qualified versions even if a newer runner compiler causes doctor to reject them.

Caches are an optimization. Cache service restore/save failures do not remove the cold build path. A corrupt immutable cache entry can be rejected and rebuilt, but cannot be overwritten under the same key; delete that specific bad entry administratively before expecting reuse. PR-created caches are scoped to the PR merge ref and are **not available to main**. Integrated main may require its own cold build unless a compatible main/default-branch cache already exists. PR jobs may restore a compatible default-branch cache according to Actions cache scope rules. Superseded runs for a PR or ref are canceled by the caller's concurrency group; completed integrated-main checks remain separately observable.

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
3. Dispatch again on the same compatible branch/environment. Verify the same key, an exact cache hit and `source: cache`, a successful restore-doctor and no setup invocation. Record both run IDs/URLs and tested SHAs in a compact results report.
4. On a disposable branch, change a relevant setup input or lock without changing qualified versions. Verify the key changes and the producer cold path executes once. Keep criteria/source modifications separate from measured results. Unit tests cover corruption/ABI invalidation; a hosted corruption exercise, if needed, must use a disposable cache key, never damage shared main entries.
5. Verify a main push after integration independently: PR cache availability is not evidence of main reuse. Do not merge merely to test this task. If Actions cannot run or be inspected, record the precise limitation and leave these hosted outcomes unverified.

The supporting [review-preparation results](../results/review-preparation.md) distinguish executed local checks from observed hosted runs.
