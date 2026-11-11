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
in independent jobs, each with its doctor and orchestration checks. Routine
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
