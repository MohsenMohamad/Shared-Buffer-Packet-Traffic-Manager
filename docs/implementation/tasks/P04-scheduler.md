# P04: Deficit round robin and packet-RR comparison

## Dependencies

P03

## Relevant contracts

- [ queues-and-scheduling.md ](../../spec/queues-and-scheduling.md)
- [ verification.md ](../../spec/verification.md)
- [ formal.md ](../../spec/formal.md)

## Scope and primary paths

rtl/scheduler/; scheduler model/tests; formal/scheduler/

## Deliverable

Implement one-quantum-per-visit byte accounting, carry-over, true-empty credit clearing and scheduler freezing during TX ownership. Honor merged enqueue/dequeue empty semantics. Implement packet RR as a separate comparison mode. Use explicit bounded widths.

## Validation

Mixed short/long packets, unequal quanta, quantum smaller than packet, reactivation, simultaneous replacement, output stalls and finite endpoint accounting. Independent dispatch-policy checks plus grant/credit safety properties and covers.

## Exit condition

G2 scheduler evidence. No credit growth per stalled cycle or per packet within a continuing visit.

Deliver one cohesive reviewable change. If the card is larger than a safe single change, split it along tested component boundaries and record what remains. State actual executed commands/results and unresolved limits in the PR. Update a compact handoff only when unfinished work needs continuation.
