# P06: AXI4-Lite configuration and coherent statistics

## Dependencies

P01

## Relevant contracts

- [ interfaces.md ](../../spec/interfaces.md)
- [ registers.md ](../../spec/registers.md)
- [ verification.md ](../../spec/verification.md)
- [ formal.md ](../../spec/formal.md)

## Scope and primary paths

rtl/csr/; register tests/model; formal/csr/

## Deliverable

Implement independent AW/W capture, one outstanding read/write, stable responses, strobes, errors, disabled/idle policy lock and coherent snapshot counters. Distinguish live resource state from shadow statistics. Reset and error semantics follow the specification.

## Validation

AW-before-W/W-before-AW, B/R stalls and overlap, zero/partial strobes, mapped/misaligned/unmapped accesses, read-before-write collisions, busy disable, shadow capture against event updates and counter rollover in a reduced-width test configuration. Protocol safety properties.

## Exit condition

G2 control-plane evidence. No driver or CPU platform is required.

Deliver one cohesive reviewable change. If the card is larger than a safe single change, split it along tested component boundaries and record what remains. State actual executed commands/results and unresolved limits in the PR. Update a compact handoff only when unfinished work needs continuation.
