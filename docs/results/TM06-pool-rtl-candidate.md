# Multi-egress resource pools RTL candidate

Admission owns one ordered prefix decision. The pool publishes old credit,
queue occupancy and descriptor ranks. It applies the committed
reservations, writes and returns to state on the same edge. The
[reviewed candidate report](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/5db09905e19e458044e2ec895b722215706601d3/docs/results/TM06-pool-rtl-candidate.md)
records the original implementation and evidence.

## Tested identities

| Scope | Revision |
| --- | --- |
| Main baseline | `b5e82af3ff84fd77c994458eb576d9dcf9c917b2` |
| Integrated preparation merge, PR #34 | `4634d5a4dacb00304635ddb64a3f83747d8b03e8` |
| PR #36 before this change, doctor and remapped comparison baseline | `5db09905e19e458044e2ec895b722215706601d3` |
| PR #36 revised RTL, designer and mapped sources | `9f5f96405f99cff0e9a963254ae05c4095d59cbc` |

The [source manifest](../../dv/designer/pool_sources.py) gives the compilation
order, include root, profile IDs and public declarations. Both pool profiles
use the published packet and software ABI types. The checked-in report is a
documentation-only follow-up to the tested source revision.

## Binding the component

Before the rising edge, admission reads `unreserved` (U), `held[q]` (H),
`free_desc` (D), `rank_valid` and `rank_id`. The rank outputs depend on the
old descriptor bitmap. A valid rank can be read before the commit mask
is available. Admission walks the rotated header prefix and accounts for
each earlier success when deciding the next lane's header legality, queue
policy and shared credit. It drives successful lanes on `reserve_commit`
with `reserve_cells` and `reserve_qid` in the same rotated order. An absent
or denied lane consumes neither credit nor a rank. Each asserted bit
commits its full count and consumes the next old descriptor rank. Where
a commit bit is set, `grant_desc` is the corresponding rank ID projected
into that lane. The producer samples the commit and projected ID on the
same active edge. New credit, IDs and queue occupancy are visible to the
following edge.

| Observation | Component boundary | Caller supplies or checks |
| --- | --- | --- |
| Admission | `ready`, `unreserved`, `held`, `free_desc`, `rank_valid`, `rank_id`, `reserve_commit`, `reserve_cells`, `reserve_qid`, `grant_desc` | Valid headers, correct rotation and policy, one eligible header per ingress, and valid full-frame reservation count and queue. A first-beat abort may coincide with its reservation. |
| Write | `write_offer`, `write_accept`, `write_id` | An old staged cell with a reserved credit for that owner. The accepted payload and link write use the same ID and edge. |
| TX return | `tx_present[p]`, `tx_cell[p]`, `tx_qid[p]`, `tx_final[p]`, `tx_desc[p]` | Cell-last handshake on physical egress `p`. Final descriptor validity comes from the real frame-last handshake. Descriptor bits are irrelevant for nonfinal cells. |
| Cleanup | `cleanup_present`, `cleanup_has_cell`, `cleanup_cell`, `cleanup_done`, `cleanup_qid`, `cleanup_desc`, `cleanup_released` | One old abort in the dedicated cleanup lane. Only completion supplies the descriptor and residual credit. A cleaning ingress stays ineligible on that edge. |
| State and reset | `free_cells` (F), `reserved_free` (R), `rst_n`, `ready` | Sample transactions with ready high. Assert reset asynchronously across two rising edges and release synchronously. Ready rises after the first released edge. Gate packet and CSR activity in the system initialization and RUN logic. |

Before reducing a return to IDs, validate the current reset epoch, owner,
queue, accepted handshake and cleanup residual in the corresponding
producer. A live descriptor ID alone cannot authenticate a frame-final
claim. The pool can check pre-edge allocation and distinct return IDs
across all lane pairs. Absent fields are irrelevant. All encoded cell,
descriptor and queue indices are in range on the supported geometries.
Illegal committed inputs violate the contract.

The grouped cell selector uses only old free membership and reserved
capacity. The descriptor stages remove each selected rank from the old
bitmap for the next rank. Commit and return masks merge once per edge.
The widened ledger applies the following deltas.

| Event | F | U | R | H for the owner | D |
| --- | ---: | ---: | ---: | ---: | ---: |
| Reserve n | 0 | −n | +n | +n | −1 |
| Materialize | −1 | 0 | −1 | 0 | 0 |
| Accepted TX cell retirement | +1 | +1 | 0 | −1 | +1 on a final |
| Physical abort reclaim | +1 | 0 | +1 | 0 | 0 |
| Finish abort with n residual credits | 0 | +n | −n | −n | +1 |

A completion may coincide with the last physical reclaim or run alone
for a zero-cell abort. The resulting invariants are `F = U + R`,
`N_CELL = assigned + F = U + sum(H[q])` and
`N_DESC = D + live_descriptors`.

## Designer validation

Verilator enables the named RTL assertions with `--assert -DTM_POOL_ASSERTIONS`.
The assertion code and its sampled reference state are omitted from the
Slang synthesis and timing runs. The checks sample active edges and verify
legal old credit, distinct old-free ranks, write eligibility, allocated and
distinct return IDs, bounded widened sums, bitmap populations, conservation
and exact per-queue updates. The C++ checker also verifies the public old
counts and projected IDs before each edge and the resulting state immediately
after it.

| Check | Both profiles |
| --- | --- |
| Legal directed scenarios | Descriptor and cell scarcity with coincident returns and following-edge reuse. Maximal commits overlap a staged write and TX returns. Five primary or three small returns include cleanup. Partial and zero-cell aborts, a withheld final, holes, live reset and complete drain pass. |
| Producer boundary | From U=8 and H=0 on both target queues, length 65 commits and leaves U=6, H=2. The second length 65 to that queue would put H=4 above threshold 2 and is denied. Length 60 to another queue consumes the second old rank. One retirement to a third queue gives next U=6 and H=2/1/0 for the three queues. Small splits the witness across two two-lane edges and verifies the retained second rank. |
| RTL negatives | Eight probes run a legal neighbor, then present the malformed input at RTL sampling. Duplicate and already-free cell or descriptor returns fail at the named allocated/distinct checks. Old D and U overcommits fail with returns present. Zero and oversized commits fail the reservation-count check. Each probe requires a nonzero simulator exit and its exact assertion. |
| Caller negatives | The caller check detects a forged final flag, stale tokens after reuse or reset and incorrect cleanup residual. The monitor detects planted old-ID and combined-credit observations. An old-empty cell pool blocks a write offer. |
| Random and replay | Seeds 17, 31 and 53 each run 1,024 active edges per profile, then drain. The seed-17 replay matches exactly in each profile. |

| Profile / seed | Sparse TX | Simultaneous returns | Partial / completed cleanup | Grants with returns | Release at U=0 | Before drain F/U/R/D |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Primary / 17 | 425 | 61 | 150 / 51 | 48 | 14 | 98 / 61 / 37 / 191 |
| Primary / 31 | 428 | 85 | 87 / 56 | 40 | 36 | 52 / 28 / 24 / 185 |
| Primary / 53 | 423 | 57 | 94 / 56 | 48 | 40 | 57 / 51 / 6 / 174 |
| Small / 17 | 443 | 36 | 2 / 43 | 67 | 43 | 4 / 2 / 2 / 0 |
| Small / 31 | 437 | 37 | 10 / 53 | 54 | 35 | 8 / 5 / 3 / 3 |
| Small / 53 | 443 | 21 | 9 / 50 | 46 | 29 | 7 / 2 / 5 / 0 |

The first assertion run was retained before repair as a `verification-defect`.
The concurrent `queue_update` comparison fired on legal traffic before
negative probes reached their injection edges. The monitor now explicitly
samples expected values in reset-aware simulation-only state and checks the
stored values at the next active edge. All legal and intended negative cases
passed with the revised monitor.

## Matched 10 ns mapping

The old and new source revisions were mapped with identical
[Decision 0010 reference constraints](../../experiments/queue-control/reference.sdc)
and [ABC constraints](../../experiments/multi-egress-pools/abc.constr).
The library is Nangate45 typical at 1.10 V and 25 °C. The reference uses a
10 ns ideal clock, 0.10 ns uncertainty, 0.20/2.00 ns I/O and reset release
delays, 0.05 ns slew and 10 fF output load.

The before map includes resource-prefix decision logic inside the pool.
The after map starts at the commit inputs and includes separate same-edge
rank observer registers. The projected descriptor ID and staged-write
capture paths use the same observer role in both maps. The new rank
endpoint measures bitmap-to-rank arrival at its observer register.
Selection depth counts mapped combinational cells on the reported late path.
Return feedback starts at the return inputs and ends at the relevant
bitmap, count or credit registers. The STA manifests give the exact paths.

| Measure | Primary before | Primary after | Small before | Small after |
| --- | ---: | ---: | ---: | ---: |
| Worst data setup / hold (ns) | +3.37490 / +0.01092 | +3.47879 / +0.00626 | +5.21581 / +0.00730 | +5.69787 / +0.01271 |
| Cell ID arrival (ns) / levels | 1.66014 / 43 | 1.85795 / 42 | 0.45194 / 8 | 0.45185 / 8 |
| Projected descriptor ID arrival (ns) / levels | 4.22725 / 94 | 4.42121 / 105 | 0.65959 / 11 | 0.55459 / 10 |
| New raw rank consumer arrival (ns) / levels | — | 4.27236 / 96 | — | 0.49965 / 9 |
| Cell ID consumer setup / hold (ns) | +8.16303 / +0.11787 | +7.98672 / +0.08254 | +9.35387 / +0.08557 | +9.35396 / +0.08557 |
| Projected ID consumer setup / hold (ns) | +5.59211 / +0.11481 | +5.49136 / +0.14157 | +9.13631 / +0.08210 | +9.25990 / +0.06849 |
| Raw rank consumer setup / hold (ns) | — | +5.58773 / +0.05855 | — | +9.35782 / +0.01735 |
| Cell return setup / hold (ns) | +6.92799 / +0.19438 | +6.93211 / +0.20111 | +7.34923 / +0.14691 | +7.35764 / +0.16249 |
| Descriptor return setup / hold (ns) | +7.05720 / +0.19648 | +7.09182 / +0.18549 | +7.36276 / +0.14715 | +7.41352 / +0.15375 |
| Credit return setup / hold (ns) | +6.58341 / +0.24157 | +6.60537 / +0.21113 | +7.11743 / +0.20800 | +7.26478 / +0.23409 |
| Reset recovery / removal (ns) | +7.93947 / -0.14368 | +7.93947 / -0.14368 | +7.93947 / -0.14368 | +7.93947 / -0.14368 |
| Mapped area (µm²) | 32,503.604 | 34,562.178 | 1,889.132 | 2,225.888 |
| Max clock / reset / data fanout | 1,530 / 1,488 / 10 | 1,566 / 1,488 / 10 | 89 / 79 / 10 | 97 / 79 / 10 |
| Worst capacitance slack (fF) | +0.66554 | +0.98070 | +0.91958 | +0.91958 |
| Worst slew slack (ns) | +0.07560 | +0.07961 | +0.07740 | +0.07740 |

The first new primary fixture exposed raw ranks and projected IDs as
separate ports. Shared rank drivers carried the duplicated output
load, then a rank node with one 10 fF port and internal sinks still
exceeded its Liberty budget after four buffer splits. Both maps and
the failures were retained before repair. The fixture now measures
rank use at a separate same-edge consumer while keeping projected IDs
at the I/O boundary. The rank observer is measurement logic. Admission
composition still needs its own timing measurement.

With the revised fixture, targeted identity buffers clear cap and slew
checks on both maps. The repair validates every original cell pin and port
after contracting the added buffers. Area includes the new 36 primary or
eight small rank observation bits. The worst data path now begins at the
old descriptor bitmap in primary and at `reserve_commit[0]` in small.
The primary projected ID is slower from the bitmap even as worst overall
setup improves under the changed boundary.

The reference reset release still misses removal by 0.14368 ns in both
profiles. The isolated required arrival window is 0.34368–9.93947 ns at
0.05 ns slew. Max fanout acceptance remains `UNSUPPORTED` because the
reference provides no limit. These are single-corner pre-layout measurements.

## Reproduction and handoff

Use the prepared toolchain at the tested source revisions.

```sh
export CXX=g++-14
source .tools/activate.sh
make doctor
python3 dv/designer/multi_egress_pools.py --jobs 2
python3 dv/designer/multi_egress_pools.py --profile small --case rtl-overcommit-u
python3 dv/designer/multi_egress_pools_sta.py --profile primary
python3 dv/designer/multi_egress_pools_sta.py --profile small
make multi-egress-declarations
make repo-check
python3 tools/check_light.py
PYTHONPATH=tools python3 -m unittest discover -s tests/runner -v
git diff --check origin/main...HEAD
make multi-egress-pools-candidate RUN_ARGS="--profile all --candidate-revision $(git rev-parse HEAD)"
```

Run the two mapping commands at both recorded revisions to reproduce the
comparison. Raw logs, manifests and failure snapshots live under
`.build/runs/` and the hosted designer evidence artifact.

| Scope | Local run directory under `.build/runs/` |
| --- | --- |
| Doctor at reviewed head | `doctor-2026-11-22T120938.322678+0000-27d8eada` |
| Before timing | `pools-sta-primary-20261122T121013-9df5b0a6`, `pools-sta-small-20261122T121013-132d0afc` |
| After timing | `pools-sta-primary-20261122T121714-3ac791bb`, `pools-sta-small-20261122T121714-e1c3485f` |
| Both designer profiles | `pools-designer-{primary,small}-20261122T121714-5381635a` |
| Public declaration gate | `multi-egress-declarations-2026-11-22T121714.202948+0000-fd19036f` |
| Candidate adapter check | `multi-egress-pools-candidate-{primary,small}-2026-11-22T121714.380380+0000-e44baf92` |
| First assertion and timing failures | `pools-designer-{primary,small}-20261122T121341-a8c12817`, `pools-sta-primary-20261122T121217-8bf8cedb`, `pools-sta-primary-20261122T121502-5b2708ec` |

The simulator is Verilator 5.054. The mapping uses Yosys
`28ba3cb926fe376fa05ebfc1b921747d011d4557` with integrated Slang
`545f88b2ed3a2d20325fbd17413af177a6bca72f` and OpenSTA 3.2.0. The locked
Liberty SHA-256 is `8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1`.
The manifests include the exact netlist hashes, endpoint reports and
source digests for all four maps.

The public declaration gate passed both profiles at both read latencies.
Repository, lightweight and failure-capture checks passed. The published
candidate command reported `NOT_RUN` in both profiles and exited nonzero
because the production adapter is unbound. Independent qualification and
proofs remain pending at named RTL and DV sources. Use both read latencies
when the integrated binding exercises the memory interface. Keep
[Decision 0010](../decisions/0010-multi-egress-queue-control.md) open for
physical reset and composed timing.
