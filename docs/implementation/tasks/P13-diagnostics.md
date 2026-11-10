# P13: Regression evidence and checked diagnostic workflow

## Dependencies

P10

## Relevant contracts

- [ triage.md ](../../spec/triage.md)
- [ automation.md ](../../spec/automation.md)

## Scope and primary paths

tools/triage/; triage schemas/fixtures; regression-failure hook; reviewed diagnostic examples

## Deliverable

Implement bounded evidence collection, report validation and optional adapter/interactive report ingestion. Link case/revision/seed/profile, first errors, relevant code/spec context and evidence files. Keep deterministic regression status independent from diagnostic output.

## Validation

Fixture unit tests, failure-hook integration, evidence-path validation and actual reviewed diagnostic cases tied to logs/waveforms/fixes. Preserve wrong/inconclusive suggestions when they occur. No required timed human comparison or accuracy benchmark.

## Exit condition

Diagnostic portion of G7. Ordinary CI requires no model credentials.

Deliver one cohesive reviewable change. If the card is larger than a safe single change, split it along tested component boundaries and record what remains. State actual executed commands/results and unresolved limits in the PR. Update a compact handoff only when unfinished work needs continuation.
