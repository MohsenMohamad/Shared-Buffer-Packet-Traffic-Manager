# P10: Full subsystem concurrency and parameter regression

## Dependencies

P09

## Relevant contracts

- [ architecture.md ](../../spec/architecture.md)
- [ verification.md ](../../spec/verification.md)
- [ automation.md ](../../spec/automation.md)
- [ acceptance.md ](../../spec/acceptance.md)

## Scope and primary paths

rtl integration fixes; dv/sequences/; dv/tests/; regression configuration; requirement mapping

## Deliverable

Exercise all inputs/queues, same-queue cross-port commit order, pool pressure, malformed cleanup, DRR reactivation, configuration accesses and reset races. Complete the required F0/F1/I0/I1/E0/E1 matrix. Keep directed concurrency tests and diverse constrained-random regressions reproducible.

## Validation

Mandatory directed matrix with checker qualification; seeded regressions per functional profile; resource recovery and no stale/reset-epoch delivery. A fix includes a regression that fails before the fix. Report each unsupported or unexecuted check.

## Exit condition

G4. No unexplained deterministic failures.

Deliver one cohesive reviewable change. If the card is larger than a safe single change, split it along tested component boundaries and record what remains. State actual executed commands/results and unresolved limits in the PR. Update a compact handoff only when unfinished work needs continuation.
