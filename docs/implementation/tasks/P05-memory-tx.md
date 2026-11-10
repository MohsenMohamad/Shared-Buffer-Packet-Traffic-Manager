# P05: Finite-port packet store and transmit engine

## Dependencies

P03

## Relevant contracts

- [ interfaces.md ](../../spec/interfaces.md)
- [ buffer-management.md ](../../spec/buffer-management.md)
- [ queues-and-scheduling.md ](../../spec/queues-and-scheduling.md)
- [ formal.md ](../../spec/formal.md)
- [ implementation.md ](../../spec/implementation.md)

## Scope and primary paths

rtl/memory/; rtl/tx/; unit tests; formal/tx/

## Deliverable

Implement 1R1W payload storage with fixed one/two-cycle responses and a transmit engine with bounded buffered+outstanding credits. Separate prefetch from retirement state. Carry cell/packet boundaries with responses or equivalent checked cursors. Free cells only at their last accepted output beat and descriptor at packet completion. Capture next links before reuse.

## Validation

Byte patterns across all boundaries, partial cells, long output stalls, pending reads at reset, exact capacity credit boundaries and rapid cell reuse. Compare one/two-cycle memory paths at equal contents/latency-aware checking. Prove bounded response occupancy and exactly-once retirement on reduced production RTL.

## Exit condition

G2 memory/TX evidence. Do not infer extra memory ports.

Deliver one cohesive reviewable change. If the card is larger than a safe single change, split it along tested component boundaries and record what remains. State actual executed commands/results and unresolved limits in the PR. Update a compact handoff only when unfinished work needs continuation.
