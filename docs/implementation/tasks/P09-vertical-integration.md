# P09: Single-packet end-to-end vertical integration

## Dependencies

P04, P05, P06, P07, P08

## Relevant contracts

- [ architecture.md ](../../spec/architecture.md)
- [ interfaces.md ](../../spec/interfaces.md)
- [ buffer-management.md ](../../spec/buffer-management.md)
- [ queues-and-scheduling.md ](../../spec/queues-and-scheduling.md)
- [ verification.md ](../../spec/verification.md)

## Scope and primary paths

rtl/tm_top.sv; integration source lists; dv/env/; dv/tests/vertical/; integration trace bindings

## Deliverable

Connect the actual production modules and real UVM bench. Begin with one active input/queue inside a supported profile; do not replace shared storage or queue control with a convenience FIFO. Integrate trace events, status and statistics. Keep all top-level ports and the full elaborated profile intact.

## Validation

Input monitor to output scoreboard through actual allocated cells, one/multi-cell payloads, partial final bytes, output stalls, read latency 1/2, reset and correct final resource state. Confirm assertions and coverage collectors executed.

## Exit condition

G3. Single-active-flow testing is an integration milestone, not the final concurrency claim.

Deliver one cohesive reviewable change. If the card is larger than a safe single change, split it along tested component boundaries and record what remains. State actual executed commands/results and unresolved limits in the PR. Update a compact handoff only when unfinished work needs continuation.
