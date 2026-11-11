# P01 G1 contract evidence

G1 passes for production declarations, module API ownership/timing, source/profile
registration and the independent event-batching example. **No functional TM
datapath, component correctness, TM proof or mapped TM implementation is claimed.**
The production top and component APIs have no behavior.

## Tested sources and environment

The checkout was fast-forwarded from the seed to integrated P00 base
`56abc747f1b86aa7a5f6631e5bb4f4e24613a218` before implementation. Tests executed
on that base plus the uncommitted P01 worktree. The curated
[P01-contracts.json](P01-contracts.json) records each run's base revision, dirty
state, tested behavioral source/dependency hashes, exact positive frontend argv,
per-case result/expected outcome, raw-manifest location/hash and separate
stdout/stderr hashes. All eight final contracts runs used identical final
behavioral sources, verified against the worktree before curating this report.
Later report/status edits do not imply additional hardware execution.

The repository's `make setup JOBS=4` installed the locked toolchain, followed by
actual doctor checks. Qualified versions were Verilator 5.054, Yosys 0.52 at
`fee39a3284c90249e1d9684cf6944ffbbcbb8f90`, SBY v0.71, Z3 4.13.3, OpenSTA
2.0.17 and GCC 14.2.0; Python was 3.12.14. Exact version strings and lock digests
are in the JSON. No dependency pins or upstream UVM sources were changed.

## Executed results

| Check | Result | Boundary |
| --- | --- | --- |
| Production declarations, F0/F1/I0/I1/E0/E1 | PASS | Actual production type/port declarations elaborated under Verilator and Yosys, including all 14 component APIs plus tm_top. No behavioral assignments. |
| Monitor records, all six profiles | PASS | Verilator elaborates the independent packed batch; verification records excluded from synthesis source lists. |
| Positive options, both frontends, all profiles | PASS | RX depth 4, TX depth 8, packet RR, maximum quantum 4096, trace disabled; baseline profiles cover DRR, latency 1/2 and guarded endpoint widths. |
| Invalid elaborations | PASS, expected rejection | 25 configurations × two frontends × six profiles = 300 intended configuration rejections. A timeout, missing tool or unrelated syntax failure cannot qualify a rejection. |
| Independent batch interface | PASS | Ten Python tests per suite, including four scenarios with all 720 callback orders each. This is a bounded interface example, not the P07 UVM/model environment. |
| Single-seed replay | PASS | E0 seed 17 twice has identical permutation digest; seed 19 changes traversal order while preserving state expectations. No functional TM traffic is generated. |
| Existing P00 CI selectors | PASS | Repository check, 14 runner unit tests, lint/compile rejection, counter prove/cover/expected mutation, mapped fixture synthesis and max/min STA. All remain fixture-only. |
| Existing P00 UVM replay qualification | PASS | Seeds 17/19 plus seed-17 replay, nonzero saved coverage, unsatisfiable randomization and expected held-data assertion failure with waveform. Fixture only. |
| Hosted contracts workflow | NOT_RUN | Added workflow invokes these same local commands; no hosted execution is asserted. |

Each production profile run contains 59 passing checks: three doctor capability
checks, five positive declaration/monitor/option checks, fifty expected invalid
elaboration checks and one ten-test batching/registration suite. There were no
unresolved failures in these final runs. Initial portability probes are not
counted as final evidence.

The invalid cases isolate unsupported data width, RX/queue counts, cell size,
non-power-of-two/minimum/maximum cell and descriptor capacities, packet length
bounds and total capacity, RX depth, read latency, TX read-credit depth,
scheduler mode, quantum bounds, trace setting, undersized cell/descriptor index
and count widths, and undersized deficit width. The intended rejection must name
`TM_INVALID_CONFIGURATION`. Negative manifests preserve each nonzero raw tool
status and `expected=INVALID_ELABORATION`.

The callback examples check simultaneous reservation/materialization, TX cell
release and two descriptor returns; conservative rejection despite a same-cycle
release; last-pop plus push with duplicate tags; and refusal to dispatch a
concurrent commit into an empty queue. Additional tests reject incomplete,
duplicate, stale, mixed-cycle and unknown monitor callbacks, check reset flush,
ensure failed updates are atomic, verify source ownership and reject invalid
runner selections. CLI qualification confirms a single functional seed reaches
the selected suite, while P00 UVM still rejects a single qualification seed.

E0 permutation digests:

| Seed/run | SHA256 |
| --- | --- |
| 17 | `474c983d5ef19cf509b03e6fefb7800f8b649d9b0ba56e740527d63ae5688daa` |
| 17 replay | `474c983d5ef19cf509b03e6fefb7800f8b649d9b0ba56e740527d63ae5688daa` |
| 19 | `b68ba5359e665bf38f3cd0115fb8b8275294ae41f86baedf5e9a5924c7901120` |

P00 transaction digests were `6f53ba93`, `fe8b80f9`, `6f53ba93` for seed 17,
seed 19 and replay. UVM ran before the final empty-profile rejection/layout-check
edit; its fixture and UVM execution path were unchanged. The later P00 selector
run includes the final runner and all runner tests. Per-run source hashes retain
this distinction.

## Reproduction and raw artifacts

Run from the repository root with the prerequisites in
[the toolchain guide](../implementation/toolchain.md):

```sh
make setup JOBS=4
make doctor
for profile in F0 F1 I0 I1 E0 E1; do
  make regression RUN_ARGS="--profile $profile --test contracts --seed 17"
done
make regression RUN_ARGS='--profile E0 --test contracts --seed 17'
make regression RUN_ARGS='--profile E0 --test contracts --seed 19'
python3 tools/run.py ci --test repo --test unit --test lint --test formal --test synth --jobs 2
make test-uvm-smoke JOBS=2
make repo-check
git diff --check
```

The loop's E0 run is the first seed-17 execution; the following seed-17 command
is its replay. Installation and execution are separate. Contracts compilation
uses the normal 120-second per-tool bound; P00 UVM uses the 1200-second build
bound and two compilation jobs. All final runs completed within those bounds.

Raw files are under ignored `.build/runs/`; exact unique summary/manifest paths
are preserved in the curated JSON. Every manifest retains argv/cwd, UTC times,
source/dependency/constraint hashes, tool versions, result, first failure and
separate logs. Each expected negative preserves the tool's actual error output.
UVM coverage/waves and formal/mapping/STA artifacts remain at their recorded
paths. Setup logs are under `.build/setup/`. Reproduction regenerates these
artifacts if the workspace expires; the hosted workflow retains them for 14 days
when it is executed.

The only declaration-harness lint waiver is Verilator PINMISSING for intentionally
open declaration ports. There is no synthesis of an undriven module masquerading
as a datapath, and no claim from empty test selection. Four-state semantics,
functional requirement closure, component implementations and all G2–G7 work
remain outside this gate. PAR-01 retains NOT_IMPLEMENTED for functional parameter
regression, with the G1 contracts evidence mapped separately.
