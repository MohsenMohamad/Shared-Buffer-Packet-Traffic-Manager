# Regression-failure triage

Build a bounded Python-based utility invoked after regression failures. It gathers test/seed/configuration/RTL revision, first meaningful errors, relevant specification/RTL context and selected transaction traces. An existing LLM produces likely cause, evidence and next debugging steps. Preserve model/prompt identifiers and the generated report.

Check suggestions against logs, waveforms and confirmed fixes. Preserve reviewed examples and their outcomes, including incorrect or inconclusive suggestions when they occur; do not select only favorable outputs. The utility does not certify RTL correctness or replace scoreboards, assertions, formal or engineering review. It need not train a model, autonomously edit RTL, analyze raw massive waveforms, compare human debugging times, or establish a productivity percentage.

Minimum input manifest fields are case ID, test/seed/configuration, RTL revision, first error and evidence-file paths. The report contains suspected cause/location, cited evidence, suggested next checks, uncertainty and model/prompt identifiers. A separate human review records the outcome and the evidence/fix used to check it. The AI result must never turn a failed deterministic regression into a passing hardware result.

## Offline and credential-free operation

Failure reporting MUST work without model credentials. Automatically prepare a bounded evidence bundle after a deterministic regression failure. Provide a documented prompt/report schema and accept a report supplied by an interactive review or an optional provider adapter. Store provider credentials outside the repository; live provider calls are optional and excluded from ordinary CI.

Unit tests use fixed response fixtures and verify extraction, evidence references and schema validation. Mark those tests as fixture tests. Preserve the distinction between fixture tests, a real diagnostic session and a confirmed bug fix. When exact model identification is unavailable, record unknown rather than inventing it.
