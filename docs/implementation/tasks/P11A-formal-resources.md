# P11A: Ownership, conservation and queue proof closure

## Objective and prerequisites

Close selected production resource and FIFO-order safety claims with explicit composition, rather than treating local allocator proofs as whole-manager proofs.

Dependencies: [P10](P10-concurrency.md)

## Sources and work boundary

- [formal.md](../../spec/formal.md)
- [buffer-management.md](../../spec/buffer-management.md)
- [queues-and-scheduling.md](../../spec/queues-and-scheduling.md)

Also read the relevant APIs in `docs/spec/module-contracts.md`, created by P01, and inspect the integrated dependency implementations before changing their boundaries.

`formal/pools/`, `formal/credit/`, `formal/queue/`, matching DV tests/binds and resource-proof selection.

## Execution sequence

1. Inventory P02/P03/P08 production harnesses and exact P10 source revisions. Map FP-ALLOC, FP-DESC, FP-CREDIT, FP-QUEUE and FP-ORDER obligations to the module/state owner and existing result.

2. Define the reduced integrated control elaboration suggested in formal.md. Keep formal-only dimensions/abstractions separate from the functional-profile validator; preserve the same production control logic, not a rewritten example allocator.

3. Compose descriptor ownership across FREE/RX/QUEUED/TX/ABORT. Check that allocation, publication, dispatch and both completion paths enforce the local pool/queue assumptions and that no returned ID remains referenced.

4. Prove reservation/physical accounting including unmaterialized credit, partially reclaimed abort cells and coincident normal/abort completion/new admission. Include malformed headers/framing wherever the claim covers cleanup.

5. Preserve the unbounded independent queue FIFO-order result. Prove the caller supplies owned, not-already-queued descriptors; a local assumption alone is not evidence of caller correctness.

6. Audit assumptions individually: legality/stability/reset/response contracts only where warranted; do not exclude full pools, invalid-return detection, aborts or concurrent updates. Keep payload abstraction limited to properties unaffected by bytes.

7. Run required reachable covers for full allocation, exact-credit admission, last-pop/push, multi-qid traffic, abort-to-recovery and active reset. Recheck selected wrong-delta/last-entry defects at their intended property.

8. Register resource-family selection under `formal-rtl`. If a proof fails, inspect the counterexample and report DUT defects for a separate RTL fix PR, or correct property/assumption errors with justification and a matching simulation regression. Keep bounded, unbounded and inconclusive results separate.

## Required checks

| Area | Evidence required |
| --- | --- |
| Required safety | Selected unbounded production conservation, ownership, occupancy and FIFO-order results at documented reduced configurations. |
| Composition | Caller enforcement of queue/pool assumptions and exact RX/queued/TX/abort descriptor lifetime. |
| Reachability/strength | Full/collision/abort/reset covers and intended selected defect detections; no vacuous removal of target scenarios. |
| Scope | Explicit reset, abstraction and parameter manifests; integrated symbolic payload tracking remains stretch. |

## Completion

The resource portion of G5 has the required scoped unbounded results, composition evidence and reachable scenarios. Required timeouts are unresolved proof obligations, not a passing gate.

Requirement focus: `MEM-01`, `MEM-02`, `MEM-06`, `Q-01`, `Q-02`, `Q-03`, `Q-04`, `Q-05`, `ADM-02`, `FMT-06`, `RST-02`


## Harness semantics

Use [F01](F01-formal-symbols.md) and the current formal specification for new
symbolic inputs. A fixed descriptor/packet witness stays constant through later
resets; arbitrary sink or traffic inputs remain unconstrained except for explicit
legitimate protocol assumptions. Preserve property names, covers and intended
negative detections when changing harness representation. Native diagnostics are
historical/minimized controls, not the parser for current production types.

## Independent DV role

This is a DV task/PR: tests, models, binds, coverage, harnesses and registration.
All existing behavior/check/acceptance obligations remain. Production RTL and
embedded designer assertions are owned by separate RTL fix PRs. Develop DV early;
final qualification targets the actual merged implementation. P11 closure requires
verified P09/P10 and reviewed baseline/optimization disposition; adopted executable
optimizations require passing independent DV merge and affected G5 refresh.
Follow the [ownership gates](../plan.md#ownership-and-verification-gates).
