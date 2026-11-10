# P08: Interleaved receive admission and abort cleanup

## Dependencies

P02, P03, P05, P07

## Relevant contracts

- [ interfaces.md ](../../spec/interfaces.md)
- [ buffer-management.md ](../../spec/buffer-management.md)
- [ registers.md ](../../spec/registers.md)
- [ verification.md ](../../spec/verification.md)
- [ formal.md ](../../spec/formal.md)

## Scope and primary paths

rtl/rx/; rtl/admission/; rtl/reclaim/; component tests; formal/credit/

## Deliverable

Implement beat-level RR over input FIFOs, per-input receive/drain contexts, full-packet cell/descriptor reservations, queue caps, reason priority and DROP/WAIT. Reject permanently impossible queue-cap requests in either mode. Handle first-beat errors without same-edge descriptor return, zero-cell cleanup and fair abort reclamation under TX-return priority. Publish only complete valid packets.

## Validation

Exact credit and descriptor boundaries, four simultaneous headers, source gaps, all malformed cases, multi-abort/TX-return/admission collisions, complete cleanup, status timing and reset. Check all accounting equations after merged events and selected reduced ownership/conservation properties.

## Exit condition

G2 receive/resource evidence. A captured beat is not admission or commit.

Deliver one cohesive reviewable change. If the card is larger than a safe single change, split it along tested component boundaries and record what remains. State actual executed commands/results and unresolved limits in the PR. Update a compact handoff only when unfinished work needs continuation.
