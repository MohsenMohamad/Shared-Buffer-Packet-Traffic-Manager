# P12: Traffic benchmarks, mapped synthesis and timing

## Objective and prerequisites

Measure the actual TM and matched implementation variants without conflating reference-policy models, abstract storage or fixture timing with production hardware.

Dependencies: [P11C](P11C-coverage.md)

## Sources and work boundary

- [architecture.md](../../spec/architecture.md)
- [implementation.md](../../spec/implementation.md)
- [automation.md](../../spec/automation.md)
- [verification.md](../../spec/verification.md)

Also read the relevant APIs in `docs/spec/module-contracts.md`, created by P01, and inspect the integrated dependency implementations before changing their boundaries.

`benchmarks/`, `constraints/`, `tools/synthesis/`, `tools/timing/`, bounded memory-variant RTL/tests when needed and measured results.

## Execution sequence

1. Freeze workload definitions, profiles, sample/warm-up rules and measurement boundaries before comparisons. Record offered/admitted/delivered/dropped traffic and endpoint packets/resources, not just successful completions.

2. Implement `make benchmark` through the common runner. Compare shared versus fixed partitions at equal payload/descriptor capacity and the same traffic/service. Label a fixed-partition admission-policy model as a model, not synthesized alternate RTL.

3. Compare DRR/packet RR for mixed short/long packets with equal and unequal quanta. Account for complete visits or finite deficits/in-flight packets. Measure capture-to-completion and commit-to-first-valid separately with sample counts and p50/p95/p99/max.

4. Run F0/F1 saturated 1536-byte traffic, default quanta and no sink stalls against the 0.85 output-beats/cycle target. Diagnose scan, link, cell-boundary and RAM-credit costs. Measure minimum-packet and contention/backpressure workloads as well.

5. Implement/verify the required equal-capacity I0/I1 one-stage flat versus two-stage banked/register-pipelined read structures. If P05 only delayed a behavioral response, add the real structural variant here. Model its latency in credits; physically parallel banks are not an unchanged extra-port SRAM.

6. Rerun byte/ownership/latency regressions for any new RTL variant and affected coverage/proof checks before claiming comparison equivalence. Keep the one-cycle default unless measured trade-offs justify an explicit change.

7. Implement `make synthesis` and `make sta` with production-only source lists, identified Liberty/ABC constraints and included payload/metadata/FIFO/control hardware for I0/I1. State the observation-logic boundary consistently.

8. Apply the specified initial 10-ns clock, 2-ns I/O budgets, 0.10-ns uncertainty and explicit min/max slew/load assumptions. Inspect max/min groups, unconstrained paths and valid exceptions. Do not cut a valid path to improve slack.

9. Compare cell area, setup/hold slack, registers/storage, read latency and measured throughput under matched library/PVT/capacity/conditions. Keep large abstract-SRAM logic area separate from storage assumptions. Investigate missed targets rather than changing workloads silently.

## Required checks

| Area | Evidence required |
| --- | --- |
| Traffic experiments | Equal-budget sharing comparison, DRR/RR byte fairness, both latency metrics and finite-run accounting under pressure/stalls. |
| Targets | F0/F1 large-packet target and minimum-packet measurements; explicit diagnosis for misses. |
| Structural comparison | Actual flat/banked variants at matched capacity; affected functional/coverage/formal checks after executable changes. |
| Implementation | Mapped I0/I1 including storage/metadata, explicit max/min constraints, constrained-path review and matched area/slack/latency/throughput evidence. |

## Completion

G6: reproducible matched traffic and implementation studies with diagnosed target outcomes. Any later executable variant change refreshes affected G5 evidence. No routed timing, silicon power or black-box total-area result is implied.

Requirement focus: `PERF-01`, `PERF-02`, `PERF-03`, `PERF-04`, `SCH-05`

## Earlier baseline

Consume the P09/P10 packet-rate measurements and pre-P11 baseline decision, then perform the full study above. Early measurements do not replace the matched benchmark matrix or extend the 1536-byte utilization target to minimum packets.
