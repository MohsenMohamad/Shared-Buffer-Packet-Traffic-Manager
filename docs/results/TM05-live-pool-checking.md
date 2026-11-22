# Live UVM pool checking

The replay monitor delivers each sampled edge to an independent UVM
scoreboard. It checks old-state legality, accepted events and registered
counts from one ownership model. It samples native crosses from checked
edges and enforces the directed witnesses, named faults, seed replay,
mandatory bins and exact drain in the simulator. The historical pool
preparation used the same public ABI and records its original scope and
results. [Original pool preparation](TM05-pool-dv-preparation.md)

## Pool replay results

| Check | Primary 4×4 | Small 2×2 |
| --- | ---: | ---: |
| Required descriptor bins | 125/125 | 51/51 |
| Required cell bins | 62/62 | 38/38 |
| Random-only descriptor and cell bins | 30 and 26 | 39 and 26 |
| Activity edges per seed | 10,441–10,493 | 4,108–4,145 |
| Directed, reset, and exact drain | PASS | PASS |
| Seed 17 exact replay | PASS | PASS |
| Named seeded faults | 11 detected | 11 detected |
| Unqualified fatal probes | 5 rejected | 5 rejected |

The campaign used seeds 17, 31, 53, 67, 89, 113, 149 and 197, with
a floor of 2,048 checked activity edges per seed. Each profile's seed-17
trace matched its replay byte for byte. The fixture now owns its random
stream within each sequence. The historical seed fingerprints remain
attached to their original runs.

The directed input files and episode order match the archived preparation
byte for byte. The archived checker matched the directed transition
signatures, reset and drain, and first divergences on the replayed inputs.
The required cross coordinates and exclusions match the executed preparation
plan. The simulator writes checked-bin counts, including the random subset,
to `bins.txt` and records native covergroup counters in `coverage.dat`.
[Executed coverage plan](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/b67c593a94aa2c577e8af25c64ee3855abadfaf3/dv/multi_egress_pools/coverage_plan.py)

| Fault | Detector | First edge, primary / small |
| --- | --- | ---: |
| Descriptor return bypass | `DESC_PRE_FREE` | 772 / 28 |
| Cell return bypass | `CELL_PRE_FREE` | 1,116 / 32 |
| Repeated prefix descriptor | `DESC_PRE_FREE` | 766 / 22 |
| Returned credit bypass | `CREDIT_PREFIX` | 1,116 / 32 |
| Physical exhaustion | `PHYSICAL_EXHAUSTION` | 1,116 / 32 |
| Repeated cell return | `DUPLICATE_CELL_RETURN` | 27 / 19 |
| Missing highest-lane return | `TX_CELL_EVENT` | 27 / 19 |
| Early abort credit | `EARLY_CLEANUP_CREDIT` | 8 / 8 |
| Stale owner across reset | `STALE_OWNER` | 19 / 19 |
| Missing final descriptor return | `TX_DESC_EVENT` | 12 / 12 |
| Missing final cleanup | `DRAIN_OWNERSHIP` | 4 / 4 |

The local runs used Verilator 5.054 and Accellera UVM 2020.3.2 with
the migration diff on `b5e82af3ff84fd77c994458eb576d9dcf9c917b2`. Their
summary and case manifests retain the owned source digests, binary digest
and exact simulator invocations. The directories under `.build/runs` are
`multi-egress-pools-preparation-primary-2026-11-22T155036.340645+0000-1b5d5a41`
and `multi-egress-pools-preparation-small-2026-11-22T155024.230946+0000-a637300f`.

## Other executed checks

The UVM capability fixture passed with default seeds 17 and 19 and with
seeds 23 and 29. It checked 64 transfers and 12 queue/length crosses per
seed, reproduced the first seed, and detected the held-output assertion
mutation. The native report recorded all 19 covergroup bins across the
campaign. [Toolchain commands](../implementation/toolchain.md)

The small admission, metadata and connected-control fixtures passed. The
connected run used read latency 2. The retained STA command measured the
small balanced-admission map after its mapping inputs were restored
byte-for-byte from the retired allocator study at
`4634d5a4dacb00304635ddb64a3f83747d8b03e8`. The mapper takes geometry
from the extracted configuration.

```sh
python3 tools/queue_control_sta.py --profile small --point admission-balanced \
  --short-abc --output .build/migration/sta-after
make test-uvm-smoke JOBS=2 RUN_ARGS='--seed 23 --seed 29'
```

## Verdict inventory

| Entry point | Before | After |
| --- | --- | --- |
| `make multi-egress-pools-preparation` | Python decoded traces, reconstructed ownership, matched injected defects and replay digests, then fed coordinates to a separate coverage simulation. | The SV scoreboard checks the monitored edge and emits checked counts, fault locations and mandatory-bin results. One UVM campaign per profile checks seed replay. The runner propagates completion and named fatal outcomes. |
| `make test-uvm-smoke` and `tools/run_uvm_capabilities.py` | SV compared held data. Python compared seed digests and gated on saved functional counters. | The SV monitor and scoreboard check completed transfers, all 12 queue/length crosses per seed and exact replay. The saved database remains a native coverage report. The hold negative uses the existing SVA. |
| `tools/queue_control.py`, `tools/queue_control_directed.py`, `tools/multi_egress_feasibility.py` | Standalone model and model-to-model feasibility verdicts. | Original commands and source revisions are archived in the timing and feasibility reports. STA imports geometry from `tools/queue_control_geometry.py`. |
| TM03 declarations, frontends, DPI, four-state and formal entry points | HDL, assertion, elaboration or formal-tool outcomes, with Python structure checks and process status. | The ABI and netlist audits remain Python. HDL and formal checks retain their own verdict and scope. |
| `experiments/queue-control` and STA helpers | Live admission, metadata and connected-control HDL fixtures, map structure, constraints and timing reports. | The HDL fixtures and timing commands remain available. The composition detector checks mapped connectivity through inserted buffers. |
| Designer smoke in open PR #36 | `dv/designer/multi_egress_pools.cpp` and `dv/designer/multi_egress_pools.py` in the RTL-owner branch. | Separate RTL-owner task. The harness, wrapper, vectors and oracle are outside this branch. |
| Repository, light and hosted workflows | Syntax, tool availability, failure capture, registration and CI orchestration. | The light suite also tests simulator failure and noncompletion propagation and rejects the retired verdict modules on the migrated routes. |

The deleted pool verdict paths are `dv/multi_egress_pools/check.py`,
`oracle.py` and `coverage_plan.py`. The runner's file-fed covergroup sampler,
trace parser and Python coverage gate are retired. `stimulus.py` and
`abi.py` construct and encode fixture input, including intentionally
corrupt records. `bins.txt` and monitor traces are simulator outputs.
[Archived checker](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/tree/b67c593a94aa2c577e8af25c64ee3855abadfaf3/dv/multi_egress_pools) · [Archived runner](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/b67c593a94aa2c577e8af25c64ee3855abadfaf3/tools/multi_egress_pools.py)

The datapath model commands run at `96508d4d05f38ee73430d811b166fe93800dc371`.
The original queue-control study ran at `a5a3f6533295f2c02f2cc26c116a3e9f8e8f3f5e`.
The timing follow-up replay model ran at `05c1dbb90e787ab1d62a71d1323245355018f8a7`,
and the composed replays at `10b85fb9a394937d4dd0717d7a85afead7d39246`.
These are historical model results. [Datapath feasibility](multi-egress-datapath-feasibility.md) · [Queue and control](TM04-queue-control.md) · [Control timing](TM04-control-timing.md) · [Composed timing](TM04-composed-timing.md)

## Reproduction

```sh
export CXX=g++-14
source .tools/activate.sh
make doctor
make multi-egress-pools-preparation
make multi-egress-pools-preparation RUN_ARGS='--profile small --case stale-owner'
make test-uvm-smoke
python3 tools/check_repository.py
python3 tools/check_light.py
PYTHONPATH=tools python3 -m unittest discover -s tests/runner -v
```

The full pool gate also launches the duplicate-edge, lost-edge, same-edge
return bypass, stale owner and missing final cleanup cases with expected-fault
qualification disabled. Each must stop at its assigned simulator detector
before completion. The corresponding legal witnesses run in the positive
campaign. `--timeout` applies to the complete simulator invocation. The
default is 1,200 seconds.

Run `make multi-egress-pools-candidate RUN_ARGS='--profile small'` to verify
the missing-binding status. Production qualification requires an exact
candidate revision and a production observation adapter. Candidate simulation, cover and proof remain **NOT_RUN**.
[Production binding and reachability](TM05-pool-dv-preparation.md#production-binding)

## Captured migration failures

| Symptom | Disposition and retest |
| --- | --- |
| Initial pool build rejected the witness function name and queue argument syntax. | Verification defect. Renamed the reserved identifier and corrected the declaration. Both profiles built. |
| Directed fixture encoding used the old cleanup-source labels after switching to numeric coordinates. | Verification defect. Corrected the generator and compared every directed input with the archive. |
| Cell trigger names were padded when a conditional expression was formatted as a string. | Verification defect. Assigned the resource name before formatting. Both profiles reached every planned cross. |
| The former 240-second per-run limit expired in the combined small campaign. | Verification defect. Increased the campaign default to 1,200 seconds. Both full campaigns completed. |
| The first small seed-17 replay diverged at edge 3 in the selected frame length. | Verification defect. A sequence-local random stream replaced simulator-wide draws. The rebuilt seed-17 traces matched byte for byte in both profiles. |
| The STA wrapper could not open the retired allocator's mapping template. | Tool-environment dependency. Restored the shared inputs in the live experiment. The small balanced-admission smoke measured successfully. |
