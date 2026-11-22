# Independent multi-egress pool qualification

The production pool is bound to the live UVM ownership checker. The
scoreboard checks grant projection, accepted cell and descriptor IDs,
physical return and credit lanes, free bitmaps and all reported counts.
It samples functional coverage after the entire edge passes. The candidate
is the admission-owned commit interface in [PR #36](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/36).

## Source identity

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
[Hosted frozen replay](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/45070330455)

The first small production campaign passed the 51 descriptor and 38 cell
crosses, all eight random seeds and the seed-17 replay. It also reached
41 descriptor and 25 cell bins in the random subset. Observed activity
was 4,106–4,149 edges per seed. The native code report covered 59/59
instrumented line points across the five pool modules. Code points
exclude UVM, caller and scoreboard code, public declarations, and the
designer assertions disabled for independent detector qualification.
The candidate was unchanged for the retest after the caller-probe repair.

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

| Formal run | Result | DV revision | Effective tree |
| --- | --- | --- | --- |
| Small general covers, depth 12 | 14 reached | `4d1197cac54d3ecf484b338c307912d72c4c432e` | `e9f06e8b145ae8f558be57159a9cef2adb4f2839` |
| Small full cell-exhaustion cover, depth 22 | Reached at step 21 | `eca1b4959a4506a0a6e9580f9bfde4dca05d4663` | `b55c5d140c62a2b888ca9a9223e21cfb99850524` |
| Small aggregate BMC, depth 6 | PASS | `ef1a0cd2744b547872972a2c7906df4ee946c3e6` | `2136c86c28e34f1cb7465dc692b41c0130b2605f` |
| Small aggregate induction, depth 4 and 600 seconds | TIMEOUT after passing base case | `ef1a0cd2744b547872972a2c7906df4ee946c3e6` | `2136c86c28e34f1cb7465dc692b41c0130b2605f` |
| Small aggregate ABC/PDR, 420 seconds | TIMEOUT | `eca1b4959a4506a0a6e9580f9bfde4dca05d4663` | `b55c5d140c62a2b888ca9a9223e21cfb99850524` |
| Primary aggregate BMC, depth 5 and 600 seconds | TIMEOUT | `ef1a0cd2744b547872972a2c7906df4ee946c3e6` | `2136c86c28e34f1cb7465dc692b41c0130b2605f` |

The initial small ABC/PDR job using the frame ledger timed out at
240 seconds. The initial all-in-one depth-15 cover reached 14/15 covers.
One subsequent aggregate-caller elaboration rejected the packed
declaration of the queue totals before execution. The declaration now uses
a packed logic vector. The first logs and input source fingerprints were
captured before each retest.

## Captured verification failures

| First finding | Disposition |
| --- | --- |
| `caller-guards` edge 15 first reported `CALLER_DESCRIPTOR` before checking the guard. | Verification defect. Directed replay had cleared the probe marker. The marker now survives translation and returns update the caller mapping from observed physical lanes. |
| The local frozen primary replay hit its 1,200-second limit while other jobs were running. The small job then read a source edited after its driver had loaded. | Tool contention and verification workspace error. The hosted frozen regression ran from an immutable checkout and passed both profiles. |

## Reproduction

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
dv_revision=$(git rev-parse HEAD)
git fetch origin pull/36/head
git worktree add --detach work/pool-qualification "$candidate"
git -C work/pool-qualification merge --no-edit --no-ff "$dv_revision"
cd work/pool-qualification
make multi-egress-pools-candidate RUN_ARGS="--profile all --candidate-revision $candidate"
make multi-egress-pools-candidate RUN_ARGS="--profile small --mutations --candidate-revision $candidate"
make multi-egress-pools-formal RUN_ARGS="--profile all --candidate-revision $candidate"
```

The PR remains a pre-merge review. Exact confirmation after an RTL merge
must use the actual merged production revision as the candidate input.
