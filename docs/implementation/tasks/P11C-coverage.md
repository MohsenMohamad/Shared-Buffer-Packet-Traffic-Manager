# P11C: Coverage review and requirement closure

## Dependencies

P10, P11A, P11B

## Relevant contracts

- [ verification.md ](../../spec/verification.md)
- [ automation.md ](../../spec/automation.md)
- [ acceptance.md ](../../spec/acceptance.md)

## Scope and primary paths

dv/coverage/; targeted sequences; requirement mapping; coverage exclusions; curated results

## Deliverable

Close critical functional bins through purposeful tests, inspect owned RTL code/branch/toggle/FSM coverage and document configuration-specific justified exclusions. Keep requirement-to-test-to-result links current. Remove obsolete skips and detect empty regressions.

## Validation

Readable and machine-readable coverage summaries backed by actual databases, final directed/random results for required profiles and remaining validation boundaries. Do not invent a global percentage as a correctness claim.

## Exit condition

G5 coverage portion. Every mandatory bin is hit or has a reviewed legitimate exclusion.

Deliver one cohesive reviewable change. If the card is larger than a safe single change, split it along tested component boundaries and record what remains. State actual executed commands/results and unresolved limits in the PR. Update a compact handoff only when unfinished work needs continuation.
