# P14: Independent integration audit and release evidence

## Dependencies

P12, P13

## Relevant contracts

- [ acceptance.md ](../../spec/acceptance.md)
- [ automation.md ](../../spec/automation.md)
- [ verification.md ](../../spec/verification.md)
- [ formal.md ](../../spec/formal.md)
- [ implementation.md ](../../spec/implementation.md)

## Scope and primary paths

docs/status.md; README.md; docs/results/; release manifest; integration fixes if needed

## Deliverable

Audit integrated behavior and evidence against the specification and requirement matrix. Reproduce the documented clean-environment entry points. Check runtime/dependency pins, result scopes, unsupported checks, architecture diagrams and component reuse. Update repository claims to match actual results.

## Validation

Clean-checkout CI/commands, all gates accounted for, no unexplained failures, reviewed limits and exact source/release revision. Independent review reports consequential findings without manufacturing a required number of issues.

## Exit condition

G7 release readiness. The maintainer controls the final merge/tag.

Deliver one cohesive reviewable change. If the card is larger than a safe single change, split it along tested component boundaries and record what remains. State actual executed commands/results and unresolved limits in the PR. Update a compact handoff only when unfinished work needs continuation.
