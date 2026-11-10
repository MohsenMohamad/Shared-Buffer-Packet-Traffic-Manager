# P12: Traffic benchmarks mapped synthesis and timing

## Dependencies

P11C

## Relevant contracts

- [ architecture.md ](../../spec/architecture.md)
- [ implementation.md ](../../spec/implementation.md)
- [ automation.md ](../../spec/automation.md)

## Scope and primary paths

benchmarks/; constraints/; tools/synthesis/; tools/timing/; docs/results/

## Deliverable

Run shared/fixed capacity, DRR/packet-RR, contention/backpressure and matched implementation experiments. Map I0/I1 with payload and metadata included. Use identified Liberty, ABC constraints and max/min SDC budgets; review unconstrained paths. Retain one-cycle default unless measured trade-offs justify changing it.

## Validation

Traffic distributions/admission/drop/latency/fairness with complete finite-run accounting; F0/F1 long-packet throughput target investigation; matched area/slack/read-latency data. Preserve commands, source hashes and conditions. No power, routed timing or full-size SRAM area claims without their actual flows.

## Exit condition

G6. Report a missed target and diagnosed bottleneck rather than changing the workload.

Deliver one cohesive reviewable change. If the card is larger than a safe single change, split it along tested component boundaries and record what remains. State actual executed commands/results and unresolved limits in the PR. Update a compact handoff only when unfinished work needs continuation.
