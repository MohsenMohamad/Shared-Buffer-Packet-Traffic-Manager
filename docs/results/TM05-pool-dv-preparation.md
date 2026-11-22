# Multi-egress pool DV preparation

The replay bench checks old-state allocations, distinct ownership and merged
reservation accounting for the 4×4 primary and 2×2 small profiles. It samples
the public multi-egress edge records through a passive UVM monitor. The
scoreboard reconstructs state from the captured records and checks reported
counts as observations. Preparation establishes replay and checker behavior.

## Results

Both profile campaigns passed at clean commit `b67c593a94aa2c577e8af25c64ee3855abadfaf3`.
The evidence preserves source hashes, pre- and post-edge accounting, return
masks, seed fingerprints, exclusion rules and observed bin counts.
[Machine-readable results](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/4634d5a4dacb00304635ddb64a3f83747d8b03e8/verification/multi-egress-pools/results.json)

| Check | Primary | Small |
| --- | --- | --- |
| Required descriptor cross | 125/125 | 51/51 |
| Required cell cross | 62/62 | 38/38 |
| Intended detector failures | 11 detected | 11 detected |
| Random campaign | 8 seeds, 10,454–10,491 activity edges each | 8 seeds, 4,107–4,143 activity edges each |
| Seed 17 event and result fingerprints | Match | Match |
| Independent scoreboards and exact drain | PASS | PASS |

The randomized subset observed both occupancy boundaries, same- and
different-queue merges, concurrent allocations and returns, mixed
normal/abort returns, active reset and next-edge reuse in both profiles.
The dedicated cross cases close the remaining count, source and occupancy
combinations. The legal neighbor for each negative case passed.

Slang elaborated the formal observer at both public geometries.
Production proofs remain pending. The candidate command returned
`NOT_RUN` with a nonzero exit when the production binding was absent.

## Reproduction

The prepared toolchain supplies Verilator 5.054 and the locked Accellera
UVM 2020.3.2 library. Use the registered sources and their scoped runner. To reproduce the
original preparation projection, use its archived baseline and exact allowlist.
[Source registry](../../verification/sources/multi-egress-pools-preparation.json) ·
[Baseline allowlist](../../verification/multi-egress-pools/baseline-allowlist.txt)

```sh
make multi-egress-pools-preparation
make multi-egress-pools-preparation RUN_ARGS='--profile small --case stale-owner'
make multi-egress-pools-candidate RUN_ARGS='--profile small'
```

The first command runs both profiles and saves per-case manifests, stimuli,
monitor traces and native covergroup databases under `.build/runs/`. A
single-case replay checks the named witness or expected detector. The
candidate command exits nonzero and records `NOT_RUN` until the production
binding exists.

## Campaign design

Directed episodes construct old ownership through legal reservations, writes,
publication and dispatch. The sampled pool boundary can align a staged write,
TX final acceptances and abort service without modeling payload timing. The
cross cases construct each required count, source and occupancy combination.
The frozen plan specifies count, occupancy and source bins. A cleanup cell
has an unused abort reservation until completion. A concurrent writer consumes
another reservation, which excludes a write and cleanup at one free cell.
[Coverage plan](../../dv/multi_egress_pools/coverage_plan.py)

The UVM sequence shuffles and translates occupancy episodes, varying legal
IDs, queue classes, port coordinates, byte lengths, and selected abort-service
delays. The separate traffic ledger generates fresh constrained traffic, with
variable reservation cell budgets, completion masks, mixed ownership phases
and active reset. Each seed includes at least 2,048 generated activity edges
before its final drain. The coverage sampler receives only batches that pass
the passive scoreboard and uses the oracle's pre-edge occupancy. Primary and
small keep separate covergroup databases.

## Production binding

Bind the observed pool events to accepted ABI v1 actions. Preserve the
ordered admission prefix, original TX indices and dedicated cleanup index.
Bind the write to its selected physical address and prior staged owner.
Cross-check TX returns with independent output handshakes and cleanup completion
with the abort-service acceptance. Capture initialization, epoch and event
records on the rising edge. Pair them with registered F, U, R, A, D and H
sampled after that edge's state updates. Cross-check an ID-only return at its
nearest epoch-aware caller before narrowing the ID.
[ABI v1 edge observation](../spec/multi-egress-interfaces.md#edge-observation)

Composed reachability requires the following production witnesses.

- Align descriptor and credit scarcity with acceptance on real TX ports.
- Align one old free cell with a prior staged write and a legal retirement.
- Align all TX finals with cleanup, and align the grant prefix with writes
  and retirements at full lane occupancy.
- Reach zero-cell and partial aborts from malformed ingress traffic. Confirm
  exact drain, stalled ownership, and active-reset reuse at epoch-aware ports.

The candidate needs an exact RTL revision, a linked production observation
adapter and independent run manifests. Run read latencies 1 and 2 when the
binding exercises the memory interface.

Production RTL qualification, production functional and code coverage, and
formal results are **NOT_RUN**. The observer records the ownership and
conservation targets, covers and caller assumptions.
[F01-compatible observer](../../formal/multi_egress_pools/README.md)

## Source isolation and failures

The preparation worktree contains allowlisted baseline files and the new DV
sources. The build registry enumerates each HDL input and rejects inherited
lists and unexpected includes. The runner scopes both identity digests and
failure snapshots. The primary file-access audit limited original checkout
opens to Git metadata. Production and feasibility worktree files stayed
outside the projection.

The baseline `make doctor` passed version and archive checks, OpenSTA source
identity, C++20, and solver SAT/UNSAT in a 45-file public projection. The
repository-wide document and Python discovery routes were deferred to hosted
CI because they read outside that projection.

### Pre-freeze metadata exposure

**Maintainer disposition pending.** The oracle and coverage plan froze in
commit `8ce266e97a80702c6248e635cde91ae1dca916e6` on 22 November 2026 at
08:21:55 Jerusalem time (06:21:55 UTC). The original tool-call history
establishes that both responses below surfaced before that commit and before
the DV branch was created. The retained records do not establish precise
access timestamps for the individual lookups.

| Lookup | Material surfaced in the original response | Order relative to the freeze |
| --- | --- | --- |
| GitHub PR metadata for #13, #32 and #33 | Full PR descriptions. #13 included F01 symbolic-input proof, cover and mutation results. #32 included isolated admission timing and area, cached-head throughput, functional tests and reset removal. #33 included composed setup and hold values, electrical repairs, reset-release limits, directed and planted-fault results, and throughput. #13 and #32 were requested as PR style examples. #33 was queried to identify the baseline merge. | Initial preflight, before the source projection and main CI gate check. |
| Baseline `verification/requirements.json` | The tool printed nine complete records and exposed their embedded evidence fields. These included P02 FIFO and pool results, P07 fixture results, P03 queue and dispatch-guard results, P05 candidate and merged-source confirmation results, P06 reset results, and P01 parameter and interface coverage. | After the projected doctor run, while the main CI gate was still pending. The same tool batch showed scheduler F0 complete and E0 uploading evidence. |

The requirements lookup used commit
`4d6940fda61e44b3c73cd4962a0c4d1857889e61` and selected `IF-02`,
`ADM-02`, `MEM-01`, `MEM-02`, `MEM-06`, `FMT-06`, `RST-01`, `RST-02`
and `PAR-01`. The original responses identify PR #13
(`068e2c64cbf43f0bece51ff9065ab470407b4efa`), PR #32
(`523f1a025aa37c60b813408ee0884ef3d5a406dd`) and PR #33
(`4d6940fda61e44b3c73cd4962a0c4d1857889e61`) by merge SHA.

The public metadata and requirement text were relevant to the task. The
embedded author result summaries exceeded the preparation allowlist. The
doctor and primary build traces cover their own processes. They cannot
establish the scope of the GitHub responses or the separate requirements
lookup. The original history records no opening of the linked result
artifacts or retained checker bodies during those lookups. It establishes
the exposure and its order. Its effect on oracle independence requires
maintainer review.

The original preparation results and tested revision remain recorded.
PR #34 remains draft pending the maintainer's provenance disposition.

| First unexpected failure | Disposition and correction |
| --- | --- |
| Credit-bypass mutation took `DESC_PRE_FREE` at primary edge 1,116 | Verification defect. The probe now selects an old free descriptor and isolates `CREDIT_PREFIX`. |
| Verilator rejected a packed member as a `ref` argument and later lost a packed member written by `$fscanf` | Tool environment. The replay reads and translates local packed values and copies them into the sampled record. |
| The random generator's read-only lane inherited a `ref` direction | Verification defect. Explicit input arguments preserve the intended call boundary. |
| The coverage importer missed all native scoped group names | Verification defect. The importer matches the saved group names and reconciles every cross's sample count. |
| Slang reported a duplicate assertion cell while unrolling a procedural loop | Tool environment. Generated lane instances provide unique property identities. Both geometry elaborations pass. |

The retained raw build and replay captures record the first command, source,
stimulus and diagnostic. The results record separately identifies the intended
seeded-defect detections.

The formal observer elaboration used these commands with the locked Slang
frontend. They check source and property elaboration.

```sh
yosys -Q -T -p 'read_slang --top multi_egress_pool_obligations -D FORMAL formal/multi_egress_pools/pool_obligations.sv; hierarchy -check'
yosys -Q -T -p 'read_slang --top multi_egress_pool_obligations -D FORMAL -GN_RX=4 -GN_CELL=1024 -GN_DESC=256 formal/multi_egress_pools/pool_obligations.sv; hierarchy -check'
```
