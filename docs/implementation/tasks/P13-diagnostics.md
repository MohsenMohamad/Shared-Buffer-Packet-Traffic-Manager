# P13: Regression evidence and checked diagnostic workflow

## Objective and prerequisites

Integrate useful checked diagnostic assistance while preserving deterministic verification results and credential-free normal CI.

Dependencies: [P10](P10-concurrency.md)

## Sources and work boundary

- [triage.md](../../spec/triage.md)
- [automation.md](../../spec/automation.md)

Also read the relevant APIs in `docs/spec/module-contracts.md`, created by P01, and inspect the integrated dependency implementations before changing their boundaries.

`tools/triage/`, report/evidence schemas, common-runner failure hook, fixed-response tests and reviewed diagnostic examples.

## Execution sequence

1. Consume the existing case manifests and first meaningful failure from tools/run.py/tools/evidence.py. Do not build another regression runner or parse an unrelated summary as the source of truth.

2. Implement bounded collection of case/revision/profile/seed, relevant log/transaction excerpts and selected RTL/spec context. Validate evidence paths and truncation; do not recursively bundle the repository, secrets or huge raw waveforms.

3. Define report fields for suspected cause/location, cited evidence, next checks, uncertainty and model/prompt identifiers. Support interactive report ingestion; an optional provider adapter must not be required for ordinary operation.

4. Attach collection to actual deterministic regression failures and preserve their original status, return code and artifacts even when collection/provider/report validation fails.

5. Test extraction, bounds, path/reference validity, malformed/missing reports and absent credentials with fixed response fixtures. Label those as fixture tests rather than live diagnostic evidence.

6. Run a real diagnostic session on an actual recorded regression failure, which may be an explicitly labeled seeded failure. Check the suggestion against logs/waveforms and a confirmed fix or counter-evidence. Keep the outcome reviewed/correct/partial/wrong/inconclusive as justified; do not invent unavailable model identifiers.

7. Register `triage` checks in the existing test/CI path, exercise the actual failure hook and preserve reviewed examples. No timed human baseline, required accuracy percentage, model training or automatic RTL repair is added.

## Required checks

| Area | Evidence required |
| --- | --- |
| Offline operation | Evidence generation and fixture checks work without model credentials; deterministic status survives triage errors. |
| Robustness | Bounded input, valid references, missing/malformed data, path handling and optional adapter failures. |
| Real integration | A recorded regression failure invokes collection; at least one actual diagnostic review is tied to evidence and its checked outcome, distinct from response fixtures. |

## Completion

The diagnostic portion of G7 and AI-01 has a real failure-to-reviewed-report example and executable credential-free tests. A missing live session remains an explicit unfinished requirement rather than a fixture-based substitute.

Requirement focus: `AI-01`
