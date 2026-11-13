# P10: Full subsystem concurrency and parameter regression

## Objective and prerequisites

Exercise the complete concurrent TM and required functional configurations with deterministic directed checks and reproducible constrained-random traffic.

Dependencies: [P09](P09-vertical-integration.md)

## Sources and work boundary

- [architecture.md](../../spec/architecture.md)
- [verification.md](../../spec/verification.md)
- [automation.md](../../spec/automation.md)
- [acceptance.md](../../spec/acceptance.md)

Also read the relevant APIs in `docs/spec/module-contracts.md`, created by P01, and inspect the integrated dependency implementations before changing their boundaries.

DV-owned `dv/sequences/`, `dv/tests/`, assertion/coverage refinements, regression profiles and requirement mapping.

## Execution sequence

1. Build a directed checklist from IF/LEN/ADM/MEM/Q/SCH/FMT/RST/CSR/PAR rows in verification.md. Reuse existing component and vertical tests; identify which claims still need full integrated evidence. Full performance experiments and AI workflow remain owned by P12/P13; the early packet-rate diagnosis below is required here.

2. Run all inputs/queues with source gaps and same-queue cross-port traffic. Force the shorter later-started packet to commit first, singleton and longer-list replacement, different-qid updates and no same-edge empty dispatch.

3. Force exact reservation/descriptor boundaries, simultaneous normal/abort returns with admission, DROP/WAIT contention and queue limits including RX/TX/abort ownership. Pair each collision with the relevant independent checker and coverage observation.

4. Combine malformed keep/last/length cases with active other inputs and long sink stalls. Resume traffic, drain complete frames and require full resource/IDLE recovery. Keep the specified never-ending-frame exception distinct from an actual leak.

5. Exercise scheduler small quanta, reactivation and busy ownership alongside CSR accesses. Test legitimate drain/reconfigure and rejection of busy disable; combine snapshots with real event increments.

6. Reset during reservation, queue transition, pending response, stalled output, abort and AXI response. Verify epoch isolation and real counter/pool reset. Run the required F0/F1/I0/I1/E0/E1 parameter matrix with profile-relevant boundary cases.

7. Run the full directed matrix and at least 20 distinct constrained-random seeds per main F0/F1 profile as the existing starting budget. Record actual traffic/cycle counts; use coverage gaps to choose targeted additions rather than presenting seed count as completeness.

8. Qualify the integrated checking with selected specified defects, including payload corruption and relevant accounting/queue/read-credit/scheduler/AXI errors. Keep disposable mutants separate from production code. Add regressions for naturally found bugs.

9. Expand subsystem CI smoke and named `concurrency`/parameter suites through the common runner. Update requirement-to-test links with actual scopes; do not mark P12/P13 requirements passing because functional traffic passed.

## Required checks

| Area | Evidence required |
| --- | --- |
| Directed concurrency | Every mandatory functional row has an executed applicable test/checker or explicit unresolved status; key collisions are deliberately reached. |
| Random/parameters | Main-profile seeded traffic plus all six profile regressions; stable replay and no omitted failing seeds. |
| Reset/recovery | All in-flight reset phases; drained runs recover resources; no stale epoch traffic or unjustified drops. |
| Checker strength | Intended seeded-defect detections and pre-fix failing regressions for natural defects; no result from empty or fixture-only runs. |

## Completion

G4: required concurrent functional and parameter regressions execute without unexplained deterministic failures. Coverage/formal closure and performance/diagnostic requirements remain separate gates.

Requirement focus: Functional IF, LEN, ADM, MEM, Q, SCH, FMT, RST, CSR and PAR families; performance/diagnostic closure remains with P12/P13.

## Packet-rate diagnosis and decision

Expand the P09 baseline with saturated 64-byte and 1536-byte traffic, one backlogged queue and representative multi-queue traffic. Use an always-ready output for internal-overhead characterization; separate runs with output stalls quantify external backpressure. Commit configuration, warm-up/measurement windows, boundary counting, clocks and traffic generation before interpreting results. Verify sustained backlog and record delivered packets/beats, elapsed cycles and interpacket gaps, including distributions and sample counts.

Define an exhaustive, non-double-counted per-cycle attribution over the measurement window. Count a delivered beat as productive. For idle output cycles, classify a pending valid beat blocked by ready as output stall; otherwise classify lack of dispatch eligibility due to scanning empty queues as empty-queue scanning, selection/dispatch work with eligible backlog as scheduling/dispatch, and an active transfer awaiting memory/read-credit/data as memory/data availability. State and justify precedence for overlapping causes, record reset/warm-up outside the window, and identify any residual/unclassified cycles explicitly. Cross-check category totals against elapsed cycles and use trace observations to substantiate causal labels rather than inferring them only from a low utilization number.

After P10, record an explicit reviewed decision to accept the measured baseline or propose a scoped optimization with its validation plan before P11 closure. There is no agreed hard minimum-packet utilization target; the 1536-byte target must not silently apply to 64-byte packets. This decision does not close P12's full benchmark, fairness, latency and implementation studies.

## Independent DV role

This is a DV task/PR: tests, models, binds, coverage, harnesses and registration.
All existing behavior/check/acceptance obligations remain. Production RTL and
embedded designer assertions are owned by separate RTL fix PRs. Develop DV early;
final qualification targets the actual merged implementation. P11 closure requires
verified P09/P10 and reviewed baseline/optimization disposition; adopted executable
optimizations require passing independent DV merge and affected G5 refresh.
Follow the [ownership gates](../plan.md#ownership-and-verification-gates).

## Optional optimization: separate RTL and DV PRs

The packet-rate decision may retain the measured baseline. If optimization is
adopted, the RTL owner supplies the scoped implementation/designer smoke PR;
independent DV supplies a separate PR retaining all policy/data/ownership/timing
expectations, checking measured benefit and rerunning affected regression,
proof and coverage. Merge RTL first, then the passing DV PR before P11 closure.
