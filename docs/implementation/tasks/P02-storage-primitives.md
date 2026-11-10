# P02: Elastic FIFOs cell pool and descriptor pool

## Dependencies

P01

## Relevant contracts

- [ interfaces.md ](../../spec/interfaces.md)
- [ buffer-management.md ](../../spec/buffer-management.md)
- [ formal.md ](../../spec/formal.md)

## Scope and primary paths

rtl/common/; rtl/pools/; component tests; formal/pools/

## Deliverable

Implement registered stream FIFOs and parameterized bitmap pools with pre-state allocation. The cell pool supports one return; descriptor pool supports two distinct returns. Detect invalid/duplicate returns without inflating capacity. Merge allocation and return deltas once. Exercise genuine reuse at more than one supported size.

## Validation

FIFO full/empty and concurrent push/pop; allocator exhaustion and recovery; simultaneous one allocation/two descriptor returns; duplicate/invalid return; reset. Obtain scoped unbounded pool invariants and reachable covers; qualify a wrong-delta mutation.

## Exit condition

G2 component evidence. No same-cycle free-to-allocate bypass.

Deliver one cohesive reviewable change. If the card is larger than a safe single change, split it along tested component boundaries and record what remains. State actual executed commands/results and unresolved limits in the PR. Update a compact handoff only when unfinished work needs continuation.
