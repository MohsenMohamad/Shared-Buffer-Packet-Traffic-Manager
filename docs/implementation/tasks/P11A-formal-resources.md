# P11A: Ownership conservation and queue proof closure

## Dependencies

P10

## Relevant contracts

- [ formal.md ](../../spec/formal.md)
- [ buffer-management.md ](../../spec/buffer-management.md)
- [ queues-and-scheduling.md ](../../spec/queues-and-scheduling.md)

## Scope and primary paths

formal/pools/; formal/credit/; formal/queue/; matching RTL fixes/tests; proof reports

## Deliverable

Close production-module pool/descriptor/reservation/queue safety claims with explicit reduced integrated configurations and composition contracts. Verify that local queue ownership assumptions are enforced by the caller. Preserve reset assumptions and payload abstraction boundaries.

## Validation

Unbounded selected conservation/ownership/occupancy/order results, relevant reachable covers and checked mutations. Report every inconclusive task separately. Check assumptions do not constrain away full pools, aborts or concurrent updates.

## Exit condition

Resource portion of G5. Integrated symbolic payload tracking remains stretch.

Deliver one cohesive reviewable change. If the card is larger than a safe single change, split it along tested component boundaries and record what remains. State actual executed commands/results and unresolved limits in the PR. Update a compact handoff only when unfinished work needs continuation.
