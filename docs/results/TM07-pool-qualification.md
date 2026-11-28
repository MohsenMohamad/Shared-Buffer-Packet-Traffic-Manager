# Independent multi-egress pool qualification

The production pool is bound to the live UVM ownership checker. The
scoreboard checks grant projection, accepted cell and descriptor IDs,
physical return and credit lanes, free bitmaps and all reported counts.
It samples functional coverage after the entire edge passes. The candidate
is the admission-owned commit interface in [PR #36](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/36).

## Component qualification at `4ff4105`

The pre-merge pool component gate passed on the pinned candidate.
The small 2×2 profile closed unbounded safety by composition. The
primary gate passed its live campaign and full-capacity cover.

### Revisions and tools

| Role | Revision |
| --- | --- |
| Pinned PR #36 RTL | `4ff41054ce80cf5a59b053efdd610b982c297a43` |
| PR #38 head at the start of the split | `0a1364135824de83b82ee28813f350a9fa7b4877` |
| DV tested for the split | `76bbb75c87db1af0f85d01f4433c4826bef800c4` |
| Combined proof checkout | `626cbec0e94ae2782830cd63d3bfb53f33581ac8` |
| Effective proof tree | `0a307769e567b76197db49f2b9bda05985d41bcc` |
| DV tested for live simulation and mutation qualification | `70814913affb3b28a5e433d751f4fdd771c7a9bd` |
| Combined live and mutation tree | `fbd1ab20ea3f1ce37c369f1fa68d83673d8053bc` |

Both disposable checkouts merged DV into the pinned candidate without
conflicts. The component runner verifies the RTL and dependency lock
bytes. The late DV changes affect formal sources and formal runner
selection. The live bench, stimulus, checker and mutation definitions
match the earlier tested DV revision.

The locked toolchain passed `make doctor` at main
`836aca88fc02e8184a61db317693962a0d44f9dc`. The runs used Yosys
0.70+post (`28ba3cb926fe376fa05ebfc1b921747d011d4557`), Slang
`545f88b2ed3a2d20325fbd17413af177a6bca72f`, the sv-elab frontend
`9dcee13ea3862347e1715dc51f63e9f845cdd222`, SBY v0.71, Z3 5.4.1,
ABC 1.01, Verilator 5.054, GCC 14.2.0 and Accellera UVM 2020.3.2.

### Unbounded small-profile safety

The 2×2 proofs use 16 cells, eight descriptors and eight queues. Each
job elaborates the actual pool RTL with only the assertions for its
property group. Caller inputs can change each sample. Each physical
bitmap proof uses its own independent ownership mask. The
reset and lane proof checks physical wiring and the pre-ready hold as
well as the reset values. The component proof allows arbitrary later
sampled resets and arbitrary traffic stalls.

| Original obligation | Proof job | Premises and scope | Result |
| --- | --- | --- | --- |
| FP-ALLOC and FP-DESC pre-edge selection, no duplicate rank, committed-lane projection, holes and no same-edge return bypass | `selection` | Rank availability is checked for every encoding. The old-free grant implication uses the admission commit population bound. | Proved, k=1 |
| FP-ALLOC physical lanes, allocation clear and distinct return sets, free population, assigned count and free/owned partition | `cell-bitmap`, `reset-and-lanes` | Every presented return identifies a distinct old owned cell. The allocated ID is the actual accepted write ID. The component proves ownership-mask complement and exact count update. | Proved, k=2 |
| FP-DESC grant clear and distinct return sets, count bounds, free population and free/owned partition | `descriptor-bitmap`, `selection`, `reset-and-lanes` | Admission commits no more than the old free slots. Each descriptor return identifies a distinct old owner. | Proved, k=2 |
| FP-CREDIT ordered old-U reservation budget and exact widened U and H deltas | `credit-deltas`, `reset-and-lanes` | Admission supplies a committed prefix within old U. Release spends old queue credit as discharged by `caller-budget`. Nonnegative reservation amounts make every prefix fit when the full sum fits. | Proved, k=2 |
| FP-CREDIT queue and global bounds and U + sum(H) = N_CELL | `credit-conservation`, `credit-deltas`, `reset-and-lanes` | RTL routes all terms to exactly one queue and implements the widened deltas. The integer step uses the old invariant and the old-U and old-queue budgets. The RTL reset supplies the base and the pre-ready hold preserves it. | Proved, partition k=1 and integer step UNSAT |
| FP-CREDIT old staged write, exact R transition, F = U + R and U ≤ F | `reserved-credit`, `cell-bitmap`, `caller-budget` | The cell population is imported from `cell-bitmap`. Distinct old cell returns and the old reservation prefix are component contracts. The caller lemma supplies old staged capacity and the joint write/cleanup budget. | Proved, k=2 |
| Old per-queue release, final cleanup residual, and write plus cleanup spending | `caller-budget` | Distinct current-epoch owner groups partition old physical cells and held credit. A write owner has unstaged credit. Final cleanup releases its exact old credit and reclaims its last materialized cell when present. Each TX return spends one cell credit from a distinct live frame. | Proved, k=1 |
| Initial and later reset, first release, no updates before ready, TX and cleanup lane fidelity | `reset-and-lanes`, bitmap jobs | Reset is sampled asserted initially. The proof checks the advertised physical lanes and counts directly. | Proved, k=2 |
| Frame ownership, per-frame materialization, no stale references, H[q] as a sum of live reservations | Bitmap and credit transition jobs, `caller-budget` | Initial projections are empty. A caller that updates ownership and reservations using the proved event deltas preserves the projections. RX/TX/cleanup must establish owner, frame, epoch and lane fidelity at the integrated boundary. | Component transitions proved under the caller contract |

The credit lane partition proves that the queue terms sum to the global
reservation and release amounts. The integer check derives `U'` and
each `H'[q]` from those terms, checks that the old premises are
satisfiable, and proves the negation of next-edge conservation and
bounds unsatisfiable. Those bounds justify storing the widened RTL
deltas in the public count width.

The physical and global credit deltas cancel the TX return term in
`R' = F' - U'`, leaving

```text
R' = R + reserved_now - write + cleanup_cell_return - cleanup_credit_release
```

The caller groups and the capacities imply that old R equals the sum of
their unstaged units. The write contributes one debit against its own
unstaged units. Final cleanup contributes its old credit minus its
reclaimed cell against a different owner. A partial cleanup releases no
credit. The queue proof sums one unit per distinct TX owner and the
exact final cleanup credit, then compares that sum with the old queue
partition. It permits concurrent reservations to the same queue.

The integrated admission block must still establish legal frame lengths,
static or dynamic eligibility and the ordered old-credit prefix. RX must
establish old staged ownership and tie an accepted ID to the memory
write. TX must establish an accepted cell-final beat, current frame and
epoch, and last-cell semantics for descriptor release. Cleanup must
establish exclusive abort ownership and one residual release. Reset
coordination and epoch retirement must prevent stale ownership at the
real caller ports. These are explicit component input contracts and
separate integration obligations.

### Live, covers and fault detection

| Check | Result |
| --- | --- |
| Primary live 4×4 | PASS. Descriptor 125/125 and cell 62/62 crosses, 413,706 checked edges. |
| Small live 2×2 | PASS. Descriptor 51/51 and cell 38/38 crosses, 46,680 checked edges. |
| Seeds and replay | Both profiles passed seeds 17, 31, 53, 67, 89, 113, 149 and 197, exact seed-17 replay and complete drain. |
| Small full-ledger covers | All 15 general covers reached at steps 5–8. The grant, write, TX final and cell-bearing final cleanup reached step 7. TX and cleanup used the same queue. |
| Small directed full-cell exhaustion | Reached at step 21. |
| Primary capacity cover | Reached at step 6. |
| Planted RTL faults | All three reached their named detector and each legal neighbor passed. Return bypass hit `CELL_PRE_FREE` at edge 32, dropped high TX return hit `TX_CELL_EVENT` at edge 19, and extra release credit hit `REPORTED_COUNTS` at edge 4. |

### Symbolic inputs and earlier proof limits

Each completed focused job has zero generated `$anyseq` cells in the prepared
RTLIL. The final SMT2 models also contain zero generated `$anyseq`
or `$anyconst` symbols.
The exact jobs use the registered independent SV properties and the
byte-exact production candidate with its optional RTL diagnostics disabled.

The separate assertion-enabled config A diagnostic at `4ff4105` retained
46 generated cells and 325 per-cycle bits, from inactive DUT
assertion mux arms. Accounting contributes 269 bits, the cell pool 32,
and the descriptor pool 24. The two sized and defaulted harness sums contribute
zero. The `tm_resource_pools.check_conservation.accounted` assertion
cone has 83 live AIG input bits and zero generated sequence bits. The
diagnostic repeated the Slang duplicate-loop-label failure before
removing eight labels in a scratch source copy. This preserved the
assertion predicates and fatal bodies. The profiling model completed step
6 in 541.28 s of wall time under shared CPU load and timed out in step 7.
The earlier 274.31 s and 77.61 s figures below came from `d25566d`.

| Earlier attempt on `4ff4105` | Scope and engine | Last result |
| --- | --- | --- |
| Unrestricted depth-22 BMC | Full ledger and F01, ABC `bmc3`, 1,800 s | Completed step 6 and timed out in step 7. |
| Monolithic k-induction | Full ledger and F01, Z3, depth 4, 1,800 s | Base passed. Timed out in induction. |
| Monolithic PDR | Full ledger and F01, ABC PDR, 1,800 s | Timed out before the full proof. |
| First combined credit-preservation attempt | All eight RTL queue states plus U, Z3 k-induction, DV `6b66df0`, 180 s | Base completed through step 1. Induction timed out in the two-transition query. The successful rerun split lane partition and integer preservation. |
| Cell bitmap PDR comparison | 16-cell bitmap, ownership complement, population and count updates, ABC PDR, DV `6b66df0`, 90 s | Last reported frame 16 with unresolved outputs. Z3 k-induction closed the same obligation. |

The earlier directed depth-22 safety run through exhaustion remains a
bounded result for the initial candidate and directed schedule.

### Reproducing the split

Activate the locked toolchain from the repository root and run the
qualification in a detached merge.

```sh
export CXX=g++-14
source .tools/activate.sh
candidate=4ff41054ce80cf5a59b053efdd610b982c297a43
dv_revision=76bbb75c87db1af0f85d01f4433c4826bef800c4
git fetch origin pull/36/head pull/38/head
git worktree add --detach work/pool-component-replay "$candidate"
git -C work/pool-component-replay merge --no-edit --no-ff "$dv_revision"
cd work/pool-component-replay
make multi-egress-pools-formal RUN_ARGS="--profile all --candidate-revision $candidate --timeout 420"
make multi-egress-pools-formal RUN_ARGS="--profile small --formal-mode lemmas --lemma credit-conservation --candidate-revision $candidate --timeout 120"
make multi-egress-pools-candidate RUN_ARGS="--profile all --candidate-revision $candidate --timeout 1800 --build-timeout 1800"
make multi-egress-pools-candidate RUN_ARGS="--profile small --mutations --candidate-revision $candidate --timeout 1200 --build-timeout 1200"
```

The stored case manifests contain the exact SymbiYosys and Z3 commands,
generated configurations, source digests and outcome. The workspace
retains the current runs under `work/pool-split` and the earlier
candidate live campaign and assertion-enabled profile under
`work/pool-requal`.

## Initial candidate source identity

| Input | Revision |
| --- | --- |
| DV base and PR #37 merge | `836aca88fc02e8184a61db317693962a0d44f9dc` |
| RTL candidate | `d25566d0bed038bf28d73110c0bda6fad0d4ab5d` |

The candidate runner verifies byte identity for all five pool modules,
the fixed package, public types, parameters and elaboration guards, and
both dependency locks. Case manifests retain the component source digests,
full candidate and DV commits, combined tree, build inputs, tool versions
and command line. Qualification uses detached merges with the candidate
as first parent. The DV branch carries the binding, checker, formal
harness and runners. The common history of the tested RTL and DV was
`b5e82af3ff84fd77c994458eb576d9dcf9c917b2`. The detached merges
required no conflict resolutions.

| Lock | SHA-256 |
| --- | --- |
| `tools/dependencies.json` | `4bc7cf21fed06e8ba7e3a2196c45e5aa5e58897d0164c4c0af55d9d1ea3fdc38` |
| `tools/packages.lock.json` | `13ce46997fccbd49662be8140443e7321e4c8a8d29a1efc54fd56dd11d797996` |

The frozen replay checker and coverage plan retain their original scope,
including the pre-freeze metadata exposure disposition.
[Preparation provenance](TM05-pool-dv-preparation.md#pre-freeze-metadata-exposure)
· [SV migration parity](TM05-live-pool-checking.md#pool-replay-results)

## Observation boundary

The UVM driver stimulates the committed reservation, staged-write and
return inputs at the falling edge. A passive monitor reads accepted actions
at the rising edge and the state one time unit later, after nonblocking
updates. Fixture descriptors and cells are symbolic. The caller maps them
from observed acceptance and preserves the physical TX and cleanup lanes
on return. Byte lengths, publication, dispatch, abort phase, epoch and
the accepted beat shape come from the caller fixture. Independent model
checks reconcile that context against observed actions, owner history
and unchanged state on a rejected modeled-caller probe.

The production pool has a synchronized reset input but no memory response
interface. Simulated epoch rejection and forged finals exercise the
modeled caller. Admission, RX, TX and cleanup integration must establish
the same constraints before IDs are narrowed.
[Composition bindings](../../formal/multi_egress_pools/README.md#composition)

## Replay and live simulation

The hosted frozen replay passed both profiles, including the 11 named
checker faults and five raw rejection probes per profile. The local
resource and source checks passed on 76 Python tests and independently
rejected missing, mismatched and modified transitive candidate inputs.
[Hosted replay and qualification logs](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/45071399539/job/137359122376)
· [Replay traces, coverage and formal artifacts](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/45071399539/artifacts/14775032770)

Both corrected production campaigns passed. Each ran eight seeds and
matched its seed-17 replay edge for edge in the scoreboard. Both
reached the stale-epoch guard at edge 15, the forged-final guard at
edge 16, and exact drain at edge 18 in the directed caller case.

| Live result | Primary 4×4 | Small 2×2 |
| --- | ---: | ---: |
| Checked edges across all cases | 413,706 | 46,680 |
| Descriptor crosses | 125/125 | 51/51 |
| Cell crosses | 62/62 | 38/38 |
| Random descriptor and cell subsets | 32 and 28 | 41 and 25 |
| Activity edges per seed | 13,243–13,318 | 4,106–4,149 |
| Seed-17 replay | Exact match | Exact match |
| Complete drain at the end of every case | PASS | PASS |

The corrected local simulation uses DV
`2675f38f51320fc5e1bc711e05962227dcb8c8cd`, combined commit
`8ea97d46a3820048e42b79e123080ad54e34d56e`, and effective tree
`0b40ecb0cd732a783c238d2be597d41eff5afbb0`. The small full run reused
the byte-identical binary from the scoped `caller-guards` build.

The native code report covered 59/59 instrumented line points in each profile
across the five pool modules. These points exclude UVM, caller and
scoreboard code, public declarations, and the designer assertions
disabled for independent detector qualification.

| Live cross | Required primary | Required small | Excluded primary / small |
| --- | ---: | ---: | ---: |
| Descriptor count × old occupancy × return source | 125 | 51 | 475 / 189 |
| Cell count × old occupancy × return source | 62 | 38 | 178 / 122 |

The exclusions come from the plan's lane counts, old ownership and
distinct reservation requirements. Each seed is checked in SV with at
least 2,048 newly generated activity edges. The fixed seeds are 17, 31,
53, 67, 89, 113, 149 and 197. Seed 17 is compared edge for edge in the
simulator.

## Detector qualification

All three planted RTL defects reached the intended detector at a checked
small-profile edge. The three legal neighbors passed with the mutation
switches idle. The runner applies the patch in a disposable source directory
and records each copied source digest. The normal candidate stays byte-exact.

| Fault | Case and first edge | Observed detector |
| --- | --- | --- |
| Return bypass | `cell-exchange`, 32 | `CELL_PRE_FREE`. The write selected the physical ID returned on that edge. |
| Dropped high TX cell return | `return-lanes`, 19 | `TX_CELL_EVENT`. The modeled accepted beat reached the pool input and the highest physical cell lane was absent at the cell state owner. |
| Extra unreserved credit on release | `final-cleanup`, 4 | `REPORTED_COUNTS`. U was 17 instead of 16 and R was 31 instead of 0. |

The first mutation run used DV `8f336fba0a57e7e0f2e798bd6faf545828e94001`
and tree `b989a2483894ee941633c7dd53bb71071274ddb8`. The patch SHA-256
was `6bfa7924ac1c1bab223d07d3db0c976767da61a610af404a5ef1a664f4e86ba7`.
The raw manifests retain the command for each mutant and each legal case.

## Reachability and proof runs

The small ledger reached the 14 general covers at steps 5–8. They include
descriptor exhaustion, subsequent cell and descriptor reuse, write and
grant with returns, all return lanes, distinct highest and cleanup lanes,
partial and final cleanup, zero-cell completion and active reset.
The directed full-capacity ledger reached the cell-exhaustion cover at
step 21. This closes all 15 small component covers across the two runs.
The primary directed capacity witness reached step 6 after four one-cell
grants and a staged write. It saw 1,023 free cells, 1,020 unreserved
credits, three reserved free cells and 252 free descriptors. This run
checks directed reachability at full primary geometry.

| Formal run | Result | DV revision | Effective tree |
| --- | --- | --- | --- |
| Small general covers, depth 12 | 14 reached | `4d1197cac54d3ecf484b338c307912d72c4c432e` | `e9f06e8b145ae8f558be57159a9cef2adb4f2839` |
| Small full cell-exhaustion cover, depth 22 | Reached at step 21 | `eca1b4959a4506a0a6e9580f9bfde4dca05d4663` | `b55c5d140c62a2b888ca9a9223e21cfb99850524` |
| Small strengthened ledger BMC, depth 6 | PASS | `e17397f50414027435e9ccb54adbe8300941e5cd` | `c474d267329b0fca95fb8b750d738616050e46bd` |
| Small directed exhaustion BMC, depth 22 | PASS through step 21 | `e17397f50414027435e9ccb54adbe8300941e5cd` | `c474d267329b0fca95fb8b750d738616050e46bd` |
| Small unrestricted ABC/BMC, depth 22 and 1,200 seconds | TIMEOUT after checking step 6 | `9784bc4d0fe16cacc9bf8e436c123062c15c832f` | `c5a67b30e21e6c4f20dd3d6e2d82ea7a57758493` |
| Small strengthened k-induction, depth 4 and 900 seconds | TIMEOUT in the induction step after passing the base case | `e17397f50414027435e9ccb54adbe8300941e5cd` | `c474d267329b0fca95fb8b750d738616050e46bd` |
| Small strengthened ABC/PDR, 480 seconds | TIMEOUT | `e17397f50414027435e9ccb54adbe8300941e5cd` | `c474d267329b0fca95fb8b750d738616050e46bd` |
| Small unrestricted Z3 bit-vector BMC, depth 22 and 1,200 seconds | TIMEOUT while checking step 6 | `b6e0fd0c324fb6913095f283d88c61ae8ebc6836` | `3e44104bee828b27d573067b795b97940cc38647` |
| Small aggregate induction, depth 4 and 600 seconds | TIMEOUT after passing base case | `ef1a0cd2744b547872972a2c7906df4ee946c3e6` | `2136c86c28e34f1cb7465dc692b41c0130b2605f` |
| Small aggregate ABC/PDR, 420 seconds | TIMEOUT | `eca1b4959a4506a0a6e9580f9bfde4dca05d4663` | `b55c5d140c62a2b888ca9a9223e21cfb99850524` |
| Primary aggregate BMC, depth 5 and 600 seconds | TIMEOUT, known tool limit | `ef1a0cd2744b547872972a2c7906df4ee946c3e6` | `2136c86c28e34f1cb7465dc692b41c0130b2605f` |
| Primary capacity cover, depth 7 | Reached at step 6 | `edce268b7f6546c77efd44f4cc9fa11a6dae300e` | `9e8dd47114eb5943f59a2b1ba58f43a529a11372` |

The strengthened harness asserts both free populations, ownership
exclusion, descriptor and cell capacities, total credit, each descriptor's
materialized count, and each queue's sum of live reservation credit. It
also asserts empty ownership on the first release edge. The unrestricted
depth-6 run evaluated the helpers from reset with the small frame ledger
and arbitrary legal stalls.

The directed depth-22 run checks all assertions through the step-21
full-cell exhaustion and return. It schedules two reset edges, four
full reservation batches, sixteen staged writes and one TX cell return.
The normal frame ledger determines input legality and the DUT selects the
allocated IDs. This run covers safety for that fill-and-return schedule.
For reproduction, use the depth-22 BMC configuration, add
`-DPOOL_EXHAUSTION_COVER` to `read_slang`, and use the engine
`smtbmc --stbv --nopresat z3`.

The initial small ABC/PDR job using the frame ledger timed out at
240 seconds. The initial all-in-one depth-15 cover reached 14/15 covers.
One subsequent aggregate-caller elaboration rejected the packed
declaration of the queue totals before execution. The declaration now uses
a packed logic vector. The first logs and input source fingerprints were
captured before each retest.

## Small BMC profile

The step-6 slowdown is already present in the RTL-only baseline. The
caller ledger reduced step 6 from 274.31 to 77.61 seconds. Adding the F01
observer moved it to 80.08 seconds while adding 214 ABC state bits.
The step-6 conflict counts were 1,411,286, 435,795 and 481,027 respectively.
The sweep measures each layer as a whole. The caller ledger adds both
checks and tighter ownership constraints.

The profile used the small 2×2 configuration with 16 cells and eight
descriptors, the locked ABC engine
`bmc3 -F 8 -v`, and a 600-second SBY cap per run. Candidate
`d25566d0bed038bf28d73110c0bda6fad0d4ab5d` and DV
`aed084b24ddfbd8d8314d093124c94228fb0b7c2` were merged in a disposable
checkout at `f8f2d6de26a450b4c31ffb844a7192cbd91182e3`, with effective
tree `567cbe2bd3ab7295577bbd3d2a7d99c2f3527667`. The merge required no
conflict resolution.

| Configuration | ABC state bits | AIGER latches before folding | Live top-level bits per cycle | Generated symbolic bits per cycle | Held witness bits | Initialization-only bits |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| A. DUT and RTL-internal assertions | 206 | 205 | 62 | 2,200 | 0 | 134 |
| B. A plus caller ledger and its checks | 487 | 486 | 65 | 2,464 | 0 | 277 |
| C. B plus F01 observer | 701 | 700 | 65 | 2,464 | 7 | 448 |

State bits are the registers reported by ABC after `fold; strash`. ABC
counted 57, 160 and 193 assertion outputs and 36, 55 and 57 constraints.
The input columns use the live fan-in of the AIGER properties and
constraints, which retained the same input support after folding. They
separate the top-level inputs from Yosys-generated `anyseq` sources,
initialization inputs, and the modeled clock. C uses three symbolic
descriptor bits and four cell bits as witnesses. F01 holds them stable
after their first sample. The legality constraints restrict which
combinations of the reported bits are admissible.

| BMC step, zero-based | A | B | C |
| --- | ---: | ---: | ---: |
| 0 | 0.05 | 0.06 | 0.07 |
| 1 | 0.00 | 0.01 | 0.00 |
| 2 | 0.01 | 0.01 | 0.02 |
| 3 | 0.02 | 0.04 | 0.06 |
| 4 | 0.05 | 0.12 | 0.16 |
| 5 | 0.45 | 0.72 | 1.10 |
| 6 | 274.31 | 77.61 | 80.08 |
| 7 | Timeout after about 324 s wall | Timeout after about 515 s wall | Timeout after about 511 s wall |

Completed-step timings are differences between ABC's cumulative wall
timestamps, rounded to 0.01 seconds. Step 0 includes BMC initialization.
Timeout intervals use SBY wall timestamps. All three runs completed
step 6 and timed out in step 7.

All three profiles enabled `TM_POOL_ASSERTIONS`. They shared the same
reset assumptions and DUT-derived legality checks for old bitmap
membership, distinct returns, committed reservations, staged writes
and old queue credit. B retained the PR's frame ledger assumptions and
local checks, with the `check_pool` instance absent. C restored that
instance. Slang rejected colliding names on eight assertions in RTL
procedural loops. The disposable source copies removed those labels and
preserved the predicates and fatal bodies. The label-only patch SHA-256
is `974634c8a4aba1d919f1e8c80931d1b41940f98b989a0c696430378a2fec27dc`.

The workspace retains the three SBY configurations, the generated tops,
RTL label patch, file hashes, ABC logs and AIGER witness maps under
`work/bmc-profile`. The run logs are `a/probe2.stdout`,
`b/run.stdout` and `c/run.stdout`. With the locked toolchain active,
run the saved configurations from the repository root.

```sh
sby -f -d work/bmc-profile/a/probe2 work/bmc-profile/a/pool.sby
sby -f -d work/bmc-profile/b/run work/bmc-profile/b/pool.sby
sby -f -d work/bmc-profile/c/run work/bmc-profile/c/pool.sby
```

## Captured verification failures

| First finding | Disposition |
| --- | --- |
| `caller-guards` edge 15 first reported `CALLER_DESCRIPTOR` before checking the guard. | Verification defect. Directed replay had cleared the probe marker. The marker now survives translation and returns update the caller mapping from observed physical lanes. |
| The local frozen primary replay hit its 1,200-second limit while other jobs were running. The small job then read a source edited after its driver had loaded. | Tool contention and verification workspace error. The hosted frozen regression ran from an immutable checkout and passed both profiles. |

## Initial candidate reproduction

Use the prepared repository toolchain and start from the tested DV commit.
The report retains identities of the executed DV and combined trees.
The candidate runner accepts a single profile, a named `--case`, or
`--seed 17 --replay` for the exact seed-17 comparison.

```sh
export CXX=g++-14
source .tools/activate.sh
make doctor
make multi-egress-pools-preparation
candidate=d25566d0bed038bf28d73110c0bda6fad0d4ab5d
dv_revision=0a1364135824de83b82ee28813f350a9fa7b4877
git fetch origin pull/36/head
git worktree add --detach work/pool-qualification "$candidate"
git -C work/pool-qualification merge --no-edit --no-ff "$dv_revision"
cd work/pool-qualification
make multi-egress-pools-candidate RUN_ARGS="--profile all --candidate-revision $candidate"
make multi-egress-pools-candidate RUN_ARGS="--profile small --mutations --candidate-revision $candidate"
make multi-egress-pools-formal RUN_ARGS="--profile all --candidate-revision $candidate"
make multi-egress-pools-formal RUN_ARGS="--profile small --formal-mode prove --depth 4 --timeout 900 --candidate-revision $candidate"
make multi-egress-pools-formal RUN_ARGS="--profile small --formal-mode prove --proof-engine pdr --timeout 480 --candidate-revision $candidate"
make multi-egress-pools-formal RUN_ARGS="--profile small --formal-mode bmc --bmc-engine abc --depth 22 --timeout 1200 --candidate-revision $candidate"
```

Unbounded safety is a small-profile gate. The primary gate uses the
passing live campaign and full-capacity cover. The primary BMC timeout is
a known tool limit. Hosted CI at DV
`b3387464858cd14a268da1a74addb53603584346` passed both live campaigns,
the three RTL mutations and their neighbors, both frozen profiles and
the small covers. Its aggregate job failed on formal timeouts under the
earlier gate configuration. The optimized local primary capacity cover
supplies the full-width primary witness.
[Qualification workflow](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/45071399539)

Exact confirmation after an RTL merge
must use the actual merged production revision as the candidate input.
