# P11C: Coverage review and requirement closure

## Objective and prerequisites

Establish requirement-driven coverage closure backed by actual databases and final functional/proof evidence, with later experiment obligations kept visible.

Dependencies: [P10](P10-concurrency.md), [P11A](P11A-formal-resources.md), [P11B](P11B-formal-interfaces.md)

## Sources and work boundary

- [verification.md](../../spec/verification.md)
- [automation.md](../../spec/automation.md)
- [acceptance.md](../../spec/acceptance.md)

Also read the relevant APIs in `docs/spec/module-contracts.md`, created by P01, and inspect the integrated dependency implementations before changing their boundaries.

`dv/coverage/`, targeted tests/sequences, coverage tooling/exclusions, requirement-test-result links and verification closure results.

## Execution sequence

1. Inventory all 52 requirement IDs and their real test/checker/result links. Identify rows supported only by fixtures or component results where integrated behavior is required. Keep PERF-01..04 and AI-01 linked to their later owning tasks rather than falsely closing them here.

2. Define mandatory functional bins/crosses from verification.md and map each to a risk and supported configuration. Detect empty selections and absent collectors; do not infer hits from test names.

3. Collect saved databases from compatible source/profile builds. Merge only compatible instrumentation and preserve per-profile results so different elaborations cannot conceal a hole.

4. Target unhit required bins with purposeful sequences, especially singleton replacement, credit boundary/current release, cell boundary/stall/latency, abort/TX/admission and reset/pending-response combinations.

5. Review owned RTL line/branch/toggle/FSM holes with their source contexts. Use narrowly justified, configuration-specific exclusions for genuinely unreachable/unsupported instrumentation; a tool-inability record is not an exclusion that proves correctness.

6. Rerun the affected directed/random suites after coverage or design changes and reconcile formal results from both closure branches against the exact integrated source. Any merge-induced executable change needs its affected checks refreshed.

7. Implement `make coverage` in the common runner for extraction, compatible merging and readable/machine-readable summaries. Test missing/corrupt databases, missing bins and incompatible input rejection.

8. Complete the functional/formal coverage review and update the requirement mapping without removing obsolete failures from history or substituting one global percentage for requirements.

## Required checks

| Area | Evidence required |
| --- | --- |
| Functional closure | Every mandatory functional bin hit or reviewed legitimate configuration-specific exclusion; actual saved counters/databases. |
| Code review | Owned code/branch/toggle/FSM holes reviewed by configuration with supported metrics and narrow exclusions. |
| Traceability | Applicable functional/proof rows linked to real tests/results; performance and diagnostic rows explicitly assigned forward. |
| Tooling | Coverage command rejects missing/corrupt/incompatible data and reports unhit bins honestly. |

## Completion

G5: required functional/proof coverage is accounted for, required properties have their actual results, and every remaining experiment/diagnostic obligation has an owner. A schema-only or fixture-only mapping cannot close a hardware requirement.

Requirement focus: Functional IF, LEN, ADM, MEM, Q, SCH, FMT, RST, CSR and PAR families; performance/diagnostic closure remains with P12/P13.

## Early measurement gate

Before P11 closure, require the [P10 packet-rate report and explicit baseline/optimization decision](P10-concurrency.md#packet-rate-diagnosis-and-decision). Keep any proposed optimization and affected revalidation visible; an unreviewed measurement or unresolved proposal cannot silently close this gate. P12 retains full performance acceptance.

## Role assignments

Independent DV owns steps 1–8, functional/code coverage review, targeted tests,
exclusions, coverage tooling and requirement/result mapping. The early measurement
gate above remains required.

[Root ownership policy](../../../AGENTS.md#separate-rtl-and-independent-dv-ownership).
