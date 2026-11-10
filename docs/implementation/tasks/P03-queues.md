# P03: Descriptor queues and simultaneous update correctness

## Dependencies

P02

## Relevant contracts

- [ buffer-management.md ](../../spec/buffer-management.md)
- [ queues-and-scheduling.md ](../../spec/queues-and-scheduling.md)
- [ formal.md ](../../spec/formal.md)

## Scope and primary paths

rtl/queue/; queue unit tests; formal/queue/

## Deliverable

Implement per-queue descriptor lists and explicit query/enqueue/dispatch APIs. Handle same and different queue updates atomically, especially count=1 dequeue/enqueue. Leave stale unused links uninitialized and never follow them. Keep descriptor ownership through TX completion.

## Validation

Independent list/FIFO model, empty dispatch rejection, longer queue races, stale-link reuse and all supported queue-count widths. Unbounded order/count proof for the production queue controller at a reduced configuration, covers and a missing-last-entry-bypass mutation.

## Exit condition

G2 queue evidence and required local FIFO-order proof.

Deliver one cohesive reviewable change. If the card is larger than a safe single change, split it along tested component boundaries and record what remains. State actual executed commands/results and unresolved limits in the PR. Update a compact handoff only when unfinished work needs continuation.
