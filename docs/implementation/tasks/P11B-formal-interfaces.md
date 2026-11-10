# P11B: Transmit scheduler and register property closure

## Dependencies

P10

## Relevant contracts

- [ formal.md ](../../spec/formal.md)
- [ interfaces.md ](../../spec/interfaces.md)
- [ queues-and-scheduling.md ](../../spec/queues-and-scheduling.md)
- [ registers.md ](../../spec/registers.md)

## Scope and primary paths

formal/tx/; formal/scheduler/; formal/csr/; matching RTL fixes/tests; proof reports

## Deliverable

Complete the selected read-credit/retirement, dispatch/deficit and AXI4-Lite safety properties on production RTL. Separate unconditional safety from bounded-stall liveness assumptions. Check semantic correspondence to simulation assertions.

## Validation

Production configuration/assumption manifests, no stale output/read after reset/reuse within scope, arbitrary sink stalls for safety, simultaneous register events, covers and selected negative checker tests.

## Exit condition

Interface/control portion of G5 with honest result scope.

Deliver one cohesive reviewable change. If the card is larger than a safe single change, split it along tested component boundaries and record what remains. State actual executed commands/results and unresolved limits in the PR. Update a compact handoff only when unfinished work needs continuation.
