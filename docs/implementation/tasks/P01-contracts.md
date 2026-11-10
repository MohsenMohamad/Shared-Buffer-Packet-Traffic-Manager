# P01: Module contracts types and independent reference interfaces

## Dependencies

P00

## Relevant contracts

- [ architecture.md ](../../spec/architecture.md)
- [ interfaces.md ](../../spec/interfaces.md)
- [ buffer-management.md ](../../spec/buffer-management.md)
- [ queues-and-scheduling.md ](../../spec/queues-and-scheduling.md)
- [ registers.md ](../../spec/registers.md)
- [ verification.md ](../../spec/verification.md)

## Scope and primary paths

rtl/include/; docs/spec/module-contracts.md; dv/model interfaces; verification/requirements.json

## Deliverable

Define the top-level packed port interface, shared types and internal module APIs before component implementations diverge. Specify ready/valid events, request/response latency, arbitration points, two descriptor returns, trace fields and merged update ownership. Define independent packet/policy model inputs and per-cycle event batching. Preserve existing external semantics; resolve material ambiguities with a documented decision. Provide compile/elaboration checks without pretending incomplete components are functional.

## Validation

Compile types/port declarations with the selected simulation and synthesis frontends; check minimum/maximum profile widths and invalid configurations. Demonstrate that the reference interface can express concurrent admission/release and last-pop+push without callback-order dependence.

## Exit condition

G1. Shared interfaces are integrated before dependent parallel tasks begin.

Deliver one cohesive reviewable change. If the card is larger than a safe single change, split it along tested component boundaries and record what remains. State actual executed commands/results and unresolved limits in the PR. Update a compact handoff only when unfinished work needs continuation.
