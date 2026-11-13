# P03 independent queue qualification

Independent local queue DV passes on `verify/p03-queues`. This report is separate
from the unchanged [P03 designer evidence](P03-queues.md). No independent scope
is verified until the passing DV PR merges. Production RTL and embedded designer
assertions are outside this PR's edit boundary.

## Baseline

Fetched main/base: `1c225525ba284ce694f1b234cb12cc514b9c0aee` (P04 PR #16).
The checkout was clean. No existing task branch/PR was found. Actual prerequisite
merges in this ancestry: P02 PR #3 `b663f47de525e132f32afe621cff69ac82633478`,
P06 PR #5 `a473b8c` (CSR dependency inventory), F01 PR #13 `068e2c6`,
P03 PR #14 `eccb9fb`; implementation `f89fcfb`, delivered head `0d0b986`.
P07 PR #4 `0901ad7` and follow-up PR #10 `c32b3f1` remain integrated.
Merge metadata does not replace any historical report's tested revision.

The first commit changes ownership documentation only. `make repo-check` passed
(52 requirement records; no hardware evaluated), raw summary
`.build/runs/repo-2026-11-13T041251.379832+0000-3c810913/summary.json`.
`git diff --check` passed. Historical reports and functional specifications are
unchanged. Role assignments preserve every existing card's acceptance obligation.

## Specification-derived API model (before behavioral comparison)

Sources: module-contracts clock/acceptance and queue/metadata port tables,
queues-and-scheduling transition matrix, verification batching and FP-QUEUE/ORDER
in formal.md. The model is an ordered list per qid and a descriptor owner set:
FREE, RX, QUEUED(q) or TX. It is not a copy of the RTL pointer update algorithm.

At each sampled edge, collect the actual API levels. `admit.valid && admit.accept`
allocates a pre-state FREE descriptor to RX; `commit.valid` publishes an RX-owned
complete descriptor absent from all pre-state lists; legal `dispatch.valid`
removes the pre-state first list member and transfers it to TX; an observed
TX-completion return releases a pre-state TX descriptor. No action occurs in
reset. Validate all actions against pre-state before applying the batch. Return
cannot fund allocation, commit cannot fund empty dispatch, and same-edge pop
cannot fund recommit. RX allocation and publication may coincide for a single-beat
packet; the same newly allocated descriptor is the only allowed exception to
pre-state RX ownership. Stimulus must not manufacture acceptance from intention.

For each queue, accepted dispatch removes the first list item, accepted commit
appends an item, then compare count and nonempty head/tail queries. This directly
covers empty/singleton/longer and same/different-qid races; singleton replacement
leaves the new sole item. For an observed metadata read of a live non-tail item,
expected next is the following list item. Never follow stale tail contents.
A separate port checker can retain observed link writes across reset to check
pre-state read/no-clear semantics, but it cannot supply FIFO expected values.

Reset empties lists and restores owner sets; retained metadata is unowned until
reused. Exercise full queue occupancy, all descriptors held by TX after dispatch,
nonzero RX publication delay, rapid reuse and supported parameter boundaries.
Coverage records sampled events/pre-counts, not requested scenarios. Illegal empty
actions are separate diagnostic tests and never become accepted FIFO operations.

## Retained evidence audit

The author `dv/unit/queues_tb.sv` does use independent ordered lists and a passive
link checker; its event sampling is inside the driver task and admission/commit
are coupled. Retain it as designer evidence; add a separate passive API model
with independently scheduled allocation/publication/TX return and saved coverage.
The author formal harness uses ordered lists and asserted live-link invariants,
not assumed RTL-derived expected next pointers. Its local queued-ID exclusion is
sound for that scope, but does not establish RX/TX/ABORT/FREE ownership. Strengthen
that boundary and qualify fixed witnesses held across later resets. Preserve its
provenance and existing selection; independent results get separate selections.

## Executed qualification

| Check | Result and boundary |
| --- | --- |
| Independent simulation | PASS, all six profiles, seed 23; 18 native/wider-ID/empty-diagnostic cases on actual queue/link/pool RTL. |
| FP-QUEUE / FP-ORDER | PASS, unbounded k-induction; production controller and actual link child, two queues/eight descriptors. |
| Reachability | All 10 covers reached by sample 11 (search bound 24); full, empty publication, same/different-qid collisions, witness dispatch and later reset/reuse. |
| Order/link/count mutations | PASS: intended detections at `a_order`, `a_link_payload`, `a_count`; actual engine FAIL and nonempty counterexamples. |
| Retained `queues` formal route | PASS, proof/cover/intended order detection with the audited strengthened harness. Historical author results remain unchanged. |
| Fixed-witness recipe and source guards | PASS, 13 F01 cases including widths 1/4 and intended missing-stability failures. |
| Coverage extraction | PASS, 12 separate native/wider-ID elaborations; no cross-profile or cross-width merging. |
| Repository / Python | PASS, repo-check, 76 tooling tests, 12 contract/routing tests, syntax and whitespace checks. |
| Full hosted CI | Requested when this PR becomes ready; no hosted PASS asserted here. |

[Durable evidence](P03-independent-dv.json) records exact commands, parameters,
seed, source/dependency digests, actual tested revisions/dirty flags, tools,
measurements, named covers/detectors and hashed raw manifests/artifacts. Final
formal qualification tested clean code head
`3b15d2d2c30a6508a447130639b7685c307b6a2b`; its run is
`.build/runs/formal-rtl-2026-11-13T044657.764649+0000-3cdd838e/summary.json`.
Simulation tested `cef18efc52f916e9d7f489255f7b758c26c6a090` and later heads with
per-run dirty flags preserved. All selected simulation source digests match the
delivered queue/link/pool/model/driver sources; later formal/CI/document changes
did not change those inputs. Base main remains
`1c225525ba284ce694f1b234cb12cc514b9c0aee` after a final fetch.

The executed stack is Verilator 5.054, Yosys 0.70+post at `28ba3cb926fe376fa05ebfc1b921747d011d4557`,
SBY 0.71, Z3 5.4.1 and GCC 14.2.0. Exact Slang/sv-elab identities are in the
JSON. Simulation is two-state; queue profile labels do not establish payload
memory latency behavior or a real TX implementation.

### Sampled transition and ownership coverage

Each profile requires ten legal pre-count/action bins per qid: empty, singleton
or longer list crossed with idle/commit/dispatch/both, excluding accepted empty
pops. All are hit at native and wider ID/count widths. Empty illegal actions are
checked separately for every qid, with/without first publication and next-edge
legal dispatch. No illegal accepted-empty bin is hit by normal traffic.

| Profile | Native sampled cycles | Required bins | Peak owned IDs | Singleton / longer / different-qid collisions |
| --- | --- | --- | --- | --- |
| F0 | 17,040 | 160/160 | 256 | 107 / 238 / 4823 |
| F1 | 17,040 | 160/160 | 256 | 107 / 238 / 4823 |
| I0 | 16,128 | 40/40 | 16 | 254 / 205 / 1463 |
| I1 | 16,128 | 40/40 | 16 | 254 / 205 / 1463 |
| E0 | 16,072 | 20/20 | 8 | 606 / 302 / 870 |
| E1 | 16,240 | 80/80 | 32 | 154 / 115 / 1739 |

The passive model also observes delayed RX publication, IDs retained by TX,
full descriptor occupancy, subsequent return/reuse, live next-link queries,
read/write collisions and reset during active publication/dispatch. Each required
lifetime counter is nonzero. Native descriptor ID/count widths range from 3/4
(E0) to 8/9 (F0/F1); the second elaboration adds one bit to each width. All four
supported qid widths appear across the six profiles.

Production controller line/branch coverage is 7/7 and 12/12 in every elaboration;
link-child line coverage is 1/1 and branch coverage 3/4. The unhit link branch is
an out-of-range read ID at `tm_desc_links.sv:17`; legal stimuli only query in-range
IDs, and native power-of-two IDs cannot encode that case. No exclusion is used
to claim closure. Expression/toggle holes include constant unused immutable-info
fields, widened unused ID encodings and illegal-action/error paths outside normal
legal traffic. The isolated empty diagnostic verifies the sticky error path.
Large arrays may exceed default toggle instrumentation limits. Raw per-elaboration
hole inventories remain saved; there is no whole-system coverage or FSM closure
claim.

The wider-ID compile uses a narrow DV configuration waiver for WIDTHTRUNC only
at the production link child's two range-guarded array accesses (lines 17–20).
The monitor uses explicit integer indexing. No production RTL, embedded assertion,
functional specification, lock or setup input changed.

### Formal assumptions and residual composition

The final reference appends/removes independent lists on API events, checks every
nonempty head/tail/count and asserts every live physical link. Exact write-port
address/data have an independent detector. Packed list/count representation and
Yosys `memory_map` change solver encoding while retaining the actual production
link array, arbitrary stale contents and pre-state read behavior.

The qid and descriptor witnesses are arbitrary top-level inputs, held constant
through later resets with F01's non-reset history flag. Reset is low at the first
two samples and arbitrary thereafter; lists reset, links do not. Safety has no
sink fairness/progress assumption. Reduced parameters are N_RX=1, N_Q=2,
N_CELL=16, N_DESC=8, CELL_BYTES=16, MAX_PACKET_BYTES=128, descriptor IDs 3 bits,
counts 4 bits. The induction search limit is four; the passing result is
unbounded, not a four-cycle safety claim.

P11A must discharge these local assumptions on the real composed implementation:

- Commit qid/ID are in range, total queued occupancy is below capacity and the
  ID is absent from **all pre-state queues**, including a same-edge popped ID.
- `caller_rx_owned[commit.desc]` truthfully denotes RX ownership of a complete
  stored packet, excluding FREE/TX/ABORT references and premature reuse. The
  queue-local theorem does not prove that predicate or packet completion.
- Dispatch is the pre-state eligible head, with matching immutable info and
  unconditional TX acceptance. P04/P11A own scheduler eligibility; P05/P11A own
  actual final-beat descriptor return, cell retirement and reset-epoch composition.

The independent simulation exercises real P02 allocation/return behavior and
models RX/QUEUED/TX endpoint ownership; it does not instantiate production RX,
abort or TX hardware. An auxiliary formal ownership-state model timed out at
300 seconds and is **not PASS**. Its tested harness is retrievable from
`cef18efc52f916e9d7f489255f7b758c26c6a090`; the JSON retains its raw summary and
harness digest. The final required queue proof uses the specification's explicit
caller-assumption boundary. An exploratory ABC PDR export also failed on X bits;
no PDR claim is made. No hardware defect was demonstrated by these experiments.

## Reproduction and evidence retrieval

Use the prepared pinned tools with the common runner:

```sh
for profile in F0 F1 I0 I1 E0 E1; do
  make regression RUN_ARGS="--profile $profile --test queues-independent --seed 23 --timeout 120"
done
make formal-rtl RUN_ARGS='--test queues-independent --test queues --timeout 300'
make formal-symbols RUN_ARGS='--timeout 120'
PYTHONPATH=tools python3 -m unittest discover -s tests/contracts -v
python3 tools/check_light.py
make repo-check
git diff --check
```

The JSON lists the exact `coverage --test queues-independent` commands and input
manifests for each profile. A new run produces new paths; use its native/wide
manifests. Extraction rejects failed/stale/altered/missing data, absent/duplicate
bins and unhit mandatory cases. Source digests and per-case parameters prevent
unlike elaborations from being combined.

Raw manifests point to separate stdout/stderr, configurations, coverage databases,
API-event logs and defect counterexamples. Their paths/digests are in the linked
JSON. Full hosted storage CI runs the same independent simulation, proof and
coverage selections and retains `.build/runs/` as a 14-day artifact. Reproduction
regenerates raw evidence after expiry; historical P03/P04/P02/P06 reports retain
their original identities and scope.
