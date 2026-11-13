# P11B: Transmit, scheduler and register property closure

## Objective and prerequisites

Close the selected production TX/DRR/AXI safety claims, separating unconditional safety from progress under explicit environmental assumptions.

Dependencies: [P10](P10-concurrency.md)

## Sources and work boundary

- [formal.md](../../spec/formal.md)
- [interfaces.md](../../spec/interfaces.md)
- [queues-and-scheduling.md](../../spec/queues-and-scheduling.md)
- [registers.md](../../spec/registers.md)

Also read the relevant APIs in `docs/spec/module-contracts.md`, created by P01, and inspect the integrated dependency implementations before changing their boundaries.

`formal/tx/`, `formal/scheduler/`, `formal/csr/`, assertion correspondence, matching DV tests/binds and control-proof selection.

## Execution sequence

1. Inventory FP-TX, FP-SCHED and FP-CSR checks from P04/P05/P06 against current integrated source. Document each property's production target, configuration, assumption and matching simulation assertion.

2. Prove buffered-plus-outstanding capacity, response preservation, stalled-output stability and exactly-once cell/descriptor retirement with arbitrary sink stalls. Include next-link capture, rapid reuse and fixed latency one/two.

3. Check reset invalidation so a prior RAM response cannot produce new-epoch output. State precisely which ownership/memory response assumptions are discharged elsewhere.

4. Prove scheduler grants belong to eligible queue heads, quantum additions/debits follow visit events, deficits stay bounded and true-empty/merged replacement semantics agree with the queue contract.

5. Prove independent AW/W capture, stable B/R responses, one response per accepted transaction and no state mutation on rejected writes. Include overlapping read/write and reset cases.

6. Keep liveness/progress tasks separate and state bounded-stall or progressing-sink assumptions explicitly. Those assumptions must not leak into safety harnesses or suppress a never-ready sink.

7. Reach pending-response stalls, empty/reactivation, simultaneous queue events and AXI channel-order covers. Detect selected credit/quantum/AW-W defects at the relevant intended property.

8. Register control-family selection under `formal-rtl` and compare formal monitor-state translations with simulation SVA semantics. Repair legitimate discrepancies with a reproducing test.

## Required checks

| Area | Evidence required |
| --- | --- |
| TX safety | Fixed response latency 1/2, arbitrary sink stalls, response credits, exact retirement/reuse and reset epochs. |
| DRR safety | Head eligibility, add/debit discipline, bounded deficit and merged empty handling. |
| CSR safety | AW/W separation, stable responses, transaction accounting and rejected-write stability. |
| Assumptions/checkers | Safety independent of sink fairness, separately scoped liveness, reachable covers and intended negative detections. |

## Completion

The interface/control portion of G5 has the selected production safety results and explicit progress scope, with no unexplained assertion-semantic divergence or required inconclusive result counted as complete.

Requirement focus: `IF-01`, `MEM-04`, `MEM-05`, `SCH-01`, `SCH-02`, `SCH-03`, `SCH-04`, `SCH-06`, `CSR-02`, `CSR-03`, `CSR-04`, `CSR-05`, `RST-02`


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
