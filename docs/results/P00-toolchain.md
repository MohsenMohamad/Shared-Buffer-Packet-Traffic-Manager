# P00 toolchain evidence

Base: `e3d40edf942e00fb5c0e5d9a86a480e8931c3ac7`, fetched integrated `main`.
The specification seed, relevant contracts, implementation plan, dependency
pins and supplied UVM fixture were present. No predecessor implementation
task is required by P00.

G0 capability result: **PASS in the native cloud workspace**. The clean
executed source revision is `6e1365a47eb11bd5caa72e92a0016ef019c6e8e4`.
The later CI retention correction and this results/status update do not
change the executable fixtures or runner. See the
[machine-readable evidence](P00-toolchain.json) for dependency/constraint/
fixture digests, exact versions, return codes, counters and UTC run times.

## Executed commands

| Command | Actual result |
|---|---|
| `bash tools/setup.sh --jobs 2` | PASS: source build and local package installation; repeat verifies downloads and reuses installation |
| `make setup JOBS=2` | PASS: repeat/idempotence path |
| `make doctor` | PASS: locked versions, archive/UVM/Liberty integrity, C++20 execution and Z3 SAT/UNSAT |
| `make repo-check` | PASS: 52 repository requirements; no hardware evaluated |
| `make test-unit` | PASS: 14 runner contract tests, including timeout/child termination and empty selection/discovery rejection |
| `make lint` | PASS: fixture lint and expected real compiler syntax-error rejection |
| `make test-uvm-smoke JOBS=2` | PASS: two seeds, replay, saved code/functional coverage and expected held-data assertion failure |
| `make formal-smoke` | PASS: unbounded k-induction, reached wrap cover and expected mutation counterexample |
| `make synth-smoke` | PASS: Liberty/ABC mapping and OpenSTA max/min constrained paths |
| `make ci JOBS=2` | PASS: all 18 capability cases at the clean revision above |
| `python3 tools/run.py four-state --jobs 2` | UNSUPPORTED, exit 1: executed portable X/Z assertion at the same revision |
| `python3 tools/run.py regression` | NOT_IMPLEMENTED, exit 1; no empty PASS |
| `python3 tools/run.py ci --jobs invalid` | TOOL_ERROR, exit 1; malformed input manifest saved |

The final combined run is retained under
`.build/runs/ci-2026-11-10T232033.801563+0000-8882afad/`. Each case has
`manifest.json`, separate stdout/stderr and relevant raw artifacts. Earlier
failed attempts retain their own statuses in separate run directories.
Hosted execution and retained artifacts are tracked by
[PR #1 checks](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/1/checks).
Adding the workflow alone is not counted as successful hosted execution.

## Inspected evidence and scope

Seeds 17 and 19 each execute 64 transactions. Digests are `6f53ba93` and
`fe8b80f9`; the independent seed-17 replay again gives `6f53ba93`. Successful
and deliberately unsatisfiable randomization both execute. The held-data
mutation exits 1 at `TM_CAP_STABILITY_FAIL` and saves a nonempty VCD.

Each positive `coverage.dat` has 17/26 hit owned line points, 8/11 expression
points, 11/32 branch points, 141/142 toggle points and **17/19 hit functional
bins**. The saved queue, length and cross counters each account for 64 samples.
Seed 17 misses queue-0/short and queue-1/short crosses; seed 19 misses
queue-0/short and queue-2/short. The coverage tool reports a weighted 94.4%;
the gate inspects raw counters rather than treating that percentage as
closure. This qualifies collection, not traffic-manager coverage completeness.

Formal proves the three-bit enabled counter's step/hold properties by
k-induction without environment assumptions, reaches wrap at step 9 within
bound 20, and finds an assertion counterexample for increment-by-two.
Cover and mutation VCDs are saved. These properties do not prove the UVM
pipe or any production module.

The mapped fixture contains one `DFF_X1` and one `XOR2_X1`, with library
area 6.118. OpenSTA reports max slack 8.89 ns and min slack 0.22 ns at the
10 ns clock, using the pinned Nangate45 typical Liberty, explicit min/max
I/O delays, transition and load constraints. This tiny synthetic, pre-layout
analysis is not traffic-manager timing or physical signoff.

Verilator is two-state; the four-state reproducer remains UNSUPPORTED.
DPI/backdoor services are NOT_RUN outside the `UVM_NO_DPI` baseline.
Production hardware gates and later hardware commands remain unimplemented.
See [reproduction commands](../implementation/toolchain.md) and the
[compatibility decision](../decisions/0001-native-toolchain.md).
