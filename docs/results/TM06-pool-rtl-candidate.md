# Multi-egress resource pools RTL candidate

The production component grants cell credit and a distinct descriptor on the
reservation edge. Materialization uses a pre-edge-free cell. The TX and
cleanup lanes apply their returns to the next state. Both profiles pass
designer smoke and meet the isolated 10 ns data target after mapped load
repair. Independent binding, physical reset and composed timing remain open.

## Tested identities

| Role | Revision |
| --- | --- |
| Fetched `origin/main` baseline | `b5e82af3ff84fd77c994458eb576d9dcf9c917b2` |
| Integrated preparation merge, PR #34 | `4634d5a4dacb00304635ddb64a3f83747d8b03e8` |
| Preparation head | `42b6eec32597e85967db4c09d09cdf6e7d231312` |
| Clean RTL, designer and timing sources used for the runs below | `0507a74d6efb839e820aa0371eeb56e5e8413d9e` |

Preparation is an ancestor of the baseline. Required main CI and local
`make doctor` passed at the baseline. [Main CI run](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/45015054949)

The [source manifest](../../dv/designer/pool_sources.py) identifies the
compilation order, include root, profile IDs and public files at the tested
revision. The production top is [tm_resource_pools](../../rtl/multi_egress/tm_resource_pools.sv).
The Verilator and Slang runs compile only the listed package and pool sources.
The timing run adds [same-edge consumers](../../experiments/multi-egress-pools/tm_pools_timing.sv).
The public types, port declaration and CSR package match the baseline.
Candidate manifests in run storage give the complete source and dependency
SHA-256s. Both geometries encode every possible cell, descriptor and queue
index in their published widths.

## Binding the component

Sample offers, grants, ownership and the staged-write handshake immediately
before the rising edge. Sample the updated counts after that edge. Sample
the offer slots in the caller's rotating order. For queue policy, the caller
can evaluate earlier successful reservations using pre-edge `U`, `D`
and `H`. Supply eligible offers for that prefix, with holes for entries
blocked by policy or other caller resources. The component independently
checks the old descriptor count and remaining credit. Each successful offer
takes the next old descriptor rank and commits that ID and its full
reservation on the same edge. A failed or absent offer consumes no rank.
The caller can observe the actual ID only where `grant` is set.

| Observation | Component boundary | Caller supplies or checks |
| --- | --- | --- |
| Admission | `reserve_offer`, `reserve_cells`, `reserve_qid`, `grant`, `grant_desc` | Rotated order, ingress/frame identity, one eligible header per ingress, valid queue and full-frame count. New grants may mark a first-beat abort without a write. |
| Write | `write_offer`, `write_accept`, `write_id` | An old staged cell with an unused credit for that frame. Payload memory, links, owner, index and final flag use the same accepted ID and edge. |
| TX return | `tx_present[p]`, `tx_cell[p]`, `tx_qid[p]`, `tx_final[p]`, `tx_desc[p]` | Accepted cell-last beat on physical egress `p`, with `tx_final` only for the real final frame retirement. Descriptor ID is relevant on a final. |
| Abort cleanup | `cleanup_present`, `cleanup_has_cell`, `cleanup_cell`, `cleanup_done`, `cleanup_qid`, `cleanup_desc`, `cleanup_released` | The dedicated cleanup grant selects one old abort. Supply the physical cell when present. On done, supply the residual credit and descriptor. The cleaning ingress remains ineligible on that edge. |
| State | `free_cells` (F), `unreserved` (U), `reserved_free` (R), `free_desc` (D), `held[q]` (H) | Current live owner maps can cross-check assigned cells, live descriptors and credits at each edge. Gate CSR and packet activity with the system initialization and RUN controls. |
| Reset | `rst_n`, `ready` | Assert common reset asynchronously across two rising edges and release synchronously. Ready and handshakes are low during reset and through sampling of the first released edge. Counts are initialized in reset and ready rises after that first released edge. |

Each ID-only return names a distinct current owner in the correct TX or
cleanup lane. Caller state excludes stale epochs, duplicates, already-free
IDs, wrong-queue releases and work from a completed cleanup. Repeated opaque
tags have no bearing on pool ownership. Probe wider malformed IDs before
narrowing at an upstream boundary. An out-of-range ID cannot be encoded
at these component ports. Absent lanes and unqualified payload fields carry
no information. Keep caller ownership assertions live when adapting the
public tagged events.

The grouped cell selector and grouped descriptor selection at each successive
rank follow Decision 0010. Bitmaps apply the allocation clear and distinct
return set once. A descriptor rank's mask removes its pre-edge candidate
from the next rank. The valid grant count determines how many ranks the
pool consumes. The credit ledger uses widened grant and release sums before
storing U and each H. R is derived as F − U, and assigned cells as N_CELL − F.

| Edge event | F | U | R | H for the owner | D |
| --- | ---: | ---: | ---: | ---: | ---: |
| Reserve n | 0 | −n | +n | +n | −1 |
| Materialize | −1 | 0 | −1 | 0 | 0 |
| Accepted TX retirement | +1 | +1 | 0 | −1 | +1 on a final |
| Physical abort reclaim | +1 | 0 | +1 | 0 | 0 |
| Finish abort with n residual credits | 0 | +n | −n | −n | +1 |

A final physical reclaim can coincide with cleanup completion, including
its descriptor return. For zero-cell abort only the completion row applies.
These deltas preserve `F = U + R`, `N_CELL = assigned + F = U + sum(H[q])`
and `N_DESC = D + live_descriptors`. Qualification of the caller, memory
ports and top-level observation wiring belongs to later integration.

## Designer validation

Each profile ran six directed cases, three deterministic sequences and an
identical log replay of seed 17. The driver reconstructs resource state from
its frame tokens and returns. It verifies the actual grant and write IDs
against old ownership and checks every queue credit after every edge.

| Directed case | Observed trigger and result |
| --- | --- |
| Descriptor scarcity | With a legal final return, D=0 gave no grant and D=1 gave one grant. D=2 gave two distinct grants when all slots offered. At D=0 the sole returned ID granted on the following edge. Saturation exercised descriptor IDs zero and 255 or seven. |
| Cell and credit scarcity | Primary and small each reached `(F,U,R)=(1,0,1)`. The old cell was selected while a different cell retired, restoring `(1,1,0)`. An oversized-for-credit prefix offer consumed neither credit nor rank, and the later one-cell request grabbed the returned credit on the next edge. Full occupancy reached F=U=R=0 after passing through both cell index extremes. |
| Concurrent and sparse lanes | The first overlap accepted all four or two grants, one old staged write and all TX finals. Starting at `F=N_CELL-N_TX`, the edge ended at `F=N_CELL-1` with the same U and `R=N_TX`. The separate return peak accepted all five or three physical and descriptor returns, one write, and all non-cleaning ingress grants. The highest TX lane operated alone. |
| Abort and withheld final | A three-cell reservation with two writes reclaimed one cell, changing R from one to two while H stayed at three and D stayed depleted by one. Completion with the last reclaim restored three credits and one descriptor. A separate zero-cell abort released its reservation and descriptor together. Withholding a TX final kept the owner live. |
| Identity and invalid events | Repeated tags and recycled IDs kept distinct ownership. A corrupt offer at F=0 was held through an edge and rejected by the module without state changes. The caller's assertions detected disposable duplicate/free cell and descriptor IDs, a forged final flag and a stale token. Corrupt old-ID and merged-credit observations hit their specific checks. Legal neighboring edges passed. |
| Reset and drain | Reset dropped fully assigned state and a separate mixture of assigned, staged reserved and aborting state. Offers remained blocked at reset and initialization sampling. The caller rejected a stale token for a reused physical ID. Current-owner return passed. Every case ended with empty owner maps, full F/U/D and zero R and H. |

Each randomized interval had 1,024 active edges after legal full-credit
setup. An active edge has a grant, materialization, retirement or cleanup.
Sparse counts below refer to TX activity with fewer than all TX lanes
present. Simultaneous counts include concurrent TX and cleanup. Ending
values are before drain and ordered F/U/R/D.

| Profile / seed | Sparse TX | Simultaneous returns | Nonfinal / completed cleanups | Grants with returns | Release at U=0 | Before drain |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Primary / 17 | 425 | 61 | 150 / 51 | 48 | 14 | 98 / 61 / 37 / 191 |
| Primary / 31 | 428 | 85 | 87 / 56 | 40 | 36 | 52 / 28 / 24 / 185 |
| Primary / 53 | 423 | 57 | 94 / 56 | 48 | 40 | 57 / 51 / 6 / 174 |
| Small / 17 | 443 | 36 | 2 / 43 | 67 | 43 | 4 / 2 / 2 / 0 |
| Small / 31 | 437 | 37 | 10 / 53 | 54 | 35 | 8 / 5 / 3 / 3 |
| Small / 53 | 443 | 21 | 9 / 50 | 46 | 29 | 7 / 2 / 5 / 0 |

Expected detector failures are recorded separately from unexpected failures.
The earliest-lint capture preserved the exact diagnostics for the 12
unused public package constants in this pool-only build
(`tool-environment`). The [lint configuration](../../dv/designer/multi_egress_pools.vlt)
waives only those constants. The first directed and random simulations
also retained failures (`verification-defect`). The directed driver
offered a new frame before the modeled abort ingress had cleared drain.
The random driver could mark an old frame while offering another header
on that ingress. Independent follow-up counts exposed missing primary
credit-exhaustion and small multi-cell reclaim triggers. The repair blocks
those illegal ingress schedules and deliberately reaches those triggers.
Reproduction uses the captured revision and patch with the original profile,
case and seed. The clean candidate passes the affected cases. These captures
found no production RTL defect.

## Reference mapping

Pinned Slang/Yosys/ABC and OpenSTA map the actual production modules with
grant outputs, IDs, counters and all return lanes live. The synthesis wrapper
also captures each accepted ID into a same-edge observer register. The
[shared Decision 0010 constraints](../../experiments/queue-control/reference.sdc)
use Nangate45 typical at 1.10 V and 25 °C, an ideal 10 ns clock, 0.10 ns
uncertainty, 0.20/2.00 ns min/max I/O and reset deassertion delays,
0.05 ns slew and 10 fF output load. ABC uses the [BUF_X1 drive and
10 fF load](../../experiments/multi-egress-pools/abc.constr) of the reference
default mapping flow.

| Mapped measure | Primary | Small |
| --- | ---: | ---: |
| Worst data setup / hold (ns) | +3.37490 / +0.01092 | +5.21581 / +0.00730 |
| Cell selection arrival (ns) / levels | 1.66014 / 43 | 0.45194 / 8 |
| Descriptor selection arrival (ns) / levels | 4.22725 / 94 | 0.65959 / 11 |
| Cell ID consumer setup / hold (ns) | +8.16303 / +0.11787 | +9.35387 / +0.08557 |
| Descriptor ID consumer setup / hold (ns) | +5.59211 / +0.11481 | +9.13631 / +0.08210 |
| Cell return feedback setup / hold (ns) | +6.92799 / +0.19438 | +7.34923 / +0.14691 |
| Descriptor return feedback setup / hold (ns) | +7.05720 / +0.19648 | +7.36276 / +0.14715 |
| Credit return feedback setup / hold (ns) | +6.58341 / +0.24157 | +7.11743 / +0.20800 |
| Mapped area (µm²) | 32,503.604 | 1,889.132 |
| Clock / reset / max data fanout | 1,530 / 1,488 / 10 | 89 / 79 / 10 |
| Worst capacitance slack before → after (fF) | −0.33198 → +0.66554 | −0.85554 → +0.91958 |
| Inserted identity buffers | 3 | 2 |

| Max path | Primary launch → endpoint | Small launch → endpoint |
| --- | --- | --- |
| Cell ID | `_45488_/Q` → `write_id[1]` | `_2604_/Q` → `write_id[1]` |
| Descriptor ID | `_46610_/Q` → `grant_desc[24]` | `_2634_/Q` → `grant_desc[3]` |
| Cell consumer | `_45488_/Q` → `_46914_/D` | `_2604_/Q` → `_2623_/D` |
| Descriptor consumer | `_46610_/Q` → `_46941_/D` | `_2634_/Q` → `_2628_/D` |
| Cell return feedback | `tx_present[1]` → `_46979_/D` | `tx_present[1]` → `_2673_/D` |
| Descriptor return feedback | `tx_present[1]` → `_46977_/D` | `tx_present[1]` → `_2669_/D` |
| Credit return feedback | `tx_qid[2]` → `_46962_/D` | `tx_present[1]` → `_2672_/D` |

Selection depth counts combinational cells on the reported latest-arrival
bitmap-to-ID path, including buffers. Focused consumer paths end at the
wrapper's capture registers. Return paths launch at the physical return
inputs and end in the free bitmap/count, or U/H state. The focused script
lists every matched mapped pin in the generated Tcl. The overall
setup path ends at a descriptor ID and launches at a reservation-count
input in both geometries. The measures are for one post-mapping typical
corner with ideal clock and reset distribution.

The initial Liberty capacitance violations came from heavily loaded mapped
drivers. Buffer splits repaired the affected nets without modifying any
original cell, port or logical connection. The repair reuses the earlier
composition check to contract only added noninverting Liberty buffers and
compare every original cell pin. Arrival and slack were remeasured after
the split.

The reference reset check still fails removal by 0.14368 ns at the
0.20 ns release assumption. Recovery passes by 7.93947 ns. The resulting
ideal-root window is 0.34368–9.93947 ns after the reference launch at
0.05 ns slew, subject to actual reset distribution and integration
endpoints. Slew and capacitance pass after buffering. Max fanout acceptance
is `UNSUPPORTED` because the library and SDC give no limit. Fanout counts
remain available. Keep the architecture freeze open under
[Decision 0010](../decisions/0010-multi-egress-queue-control.md).

## Reproduction and remaining qualification

Use the prepared toolchain at the recorded revision.

```sh
export CXX=g++-14
source .tools/activate.sh
make doctor
python3 dv/designer/multi_egress_pools.py --jobs 2
python3 dv/designer/multi_egress_pools.py --profile small --case random --seed 17
python3 dv/designer/multi_egress_pools_sta.py --profile primary
python3 dv/designer/multi_egress_pools_sta.py --profile small
make multi-egress-declarations
make repo-check
python3 tools/check_light.py
git diff --check origin/main...HEAD
make multi-egress-pools-candidate RUN_ARGS="--profile all --candidate-revision $(git rev-parse HEAD)"
```

The public declaration gate passed both geometries at both read latencies
with layout, malformed geometry and intended-fault checks. Repository
contracts, 73 lightweight unit tests, syntax and Git whitespace checks passed.

The candidate command reported `NOT_RUN` in both profiles and exited
nonzero because the production adapter has not been bound. Designer smoke,
the declaration gate and the existing preparation replay retain their
distinct scopes. Independent production checks and proofs remain pending
at named RTL and DV revisions. The isolated DUT has no memory response
interface. Use both read latencies when an integrated binding exercises it.

Generated scripts, netlists, reports and failure captures are in ignored
`.build/runs/` storage. Hosted full CI uploads fresh designer and timing
outputs through the multi-egress declaration job's existing run artifact.

| Scope | Local run directory below `.build/runs/` |
| --- | --- |
| Baseline doctor | `doctor-2026-11-22T112537.449347+0000-18452e4b` |
| Both designer profiles | `pools-designer-{primary,small}-20261122T113829-9c1fc6c5` |
| Primary mapping | `pools-sta-primary-20261122T113829-712b9f36` |
| Small mapping | `pools-sta-small-20261122T113829-a0cfe810` |
| Public declaration gate | `multi-egress-declarations-2026-11-22T113829.369751+0000-47b9d9b4` |
| Missing production binding | `multi-egress-pools-candidate-primary-2026-11-22T113829.300970+0000-bd417da0` and `multi-egress-pools-candidate-small-2026-11-22T113829.300970+0000-bd417da0` |
| Initial lint and smoke failures | `manual-failure-pools-entry`, `pools-designer-{primary,small}-20261122T113400-91e7d093` and `pools-designer-{primary,small}-20261122T113500-d1d06d9f` |

Verilator is 5.054. The mapping uses Yosys
`28ba3cb926fe376fa05ebfc1b921747d011d4557` with integrated Slang
`545f88b2ed3a2d20325fbd17413af177a6bca72f` and OpenSTA 3.2.0.
The locked Liberty SHA-256 is
`8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1`.
The reference SDC SHA-256 is
`4ab8a2d789d76c1258a4183a64bc727c856da2ff2781a9e2294c7d9902af3924`.
The mapped Verilog after repair has SHA-256
`41e9e2f9ae9b539a361a57f034b485443eab2cc6c045cdd1ce4825339bd4e144`
for primary and
`aee28b7f1ced3b673f5b63da88219fe35699025c0af9e24d36ce6a0d1272922a`
for small.
