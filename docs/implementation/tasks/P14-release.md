# P14: Independent integration audit and release evidence

## Objective and prerequisites

Independently establish release readiness from the exact integrated source and reproducible evidence, including changes introduced after verification closure.

Dependencies: [P12](P12-measurements.md), [P13](P13-diagnostics.md)

## Sources and work boundary

- [acceptance.md](../../spec/acceptance.md)
- [automation.md](../../spec/automation.md)
- [verification.md](../../spec/verification.md)
- [formal.md](../../spec/formal.md)
- [implementation.md](../../spec/implementation.md)

Also read the relevant APIs in `docs/spec/module-contracts.md`, created by P01, and inspect the integrated dependency implementations before changing their boundaries.

Integrated source/evidence audit, `docs/status.md`, `README.md`, release manifest and focused findings; repairs use the existing review/repair workflow.

## Execution sequence

1. Inspect the actual final tree, dependency locks, source lists and requirement matrix before trusting summaries. Reconcile G0-G7 with integrated work, not merely merged PR labels.

2. Audit module/port/reset/resource/trace/CSR boundaries against P01 and the normative contracts. Check that every production path uses the intended implementation and no component fixture remains wired into the TM.

3. Inspect all 52 requirement links, mandatory bins/exclusions and selected proof-family results. Verify reduced formal assumptions and the distinction between local queue-order safety and integrated byte checking.

4. Reproduce documented clean-environment setup and command entry points. Run final required functional/parameter, selected production proof, coverage, benchmark and implementation checks at their documented scope; identify actual run/artifact revisions and accessible hosted CI status.

5. Check that P12 RTL variants or P13 runner changes did not leave earlier G5 results stale. Recheck affected executable paths after integration rather than carrying forward a pass from an unrelated revision.

6. Perform focused negative checks for silent pass risks: empty selection, missing required test/result, inactive assertion/coverage collector, unintended fixture source list and diagnostic status overwrite. Reuse the existing checker-qualification cases rather than manufacturing arbitrary defect quotas.

7. Record consequential findings with source locations, scenario, evidence and severity. Route demonstrated repairs through the repair task with detecting regressions; re-review the resulting exact revision before closing the audit.

8. Update claims, diagrams, reuse examples and the release manifest to match demonstrated behavior and stated boundaries. Required unresolved failures, proof obligations or live diagnostic gaps prevent a full readiness claim. Maintainer merge/tag control remains unchanged.

## Required checks

| Area | Evidence required |
| --- | --- |
| Traceability | Exact integrated source/configurations, all 52 requirement obligations and G0-G7 evidence reconciled. |
| Reproduction | Clean-checkout documented entry points and actual final hardware/proof/measurement checks with scoped artifacts. |
| Integration integrity | No fixture substitution, interface drift, stale post-variant evidence or independent-runner duplication. |
| Audit closure | Consequential findings repaired and re-reviewed, or readiness explicitly withheld with remaining obligations. |

## Completion

G7 release readiness is established only for the exact audited candidate with all required gate obligations met. A report containing unresolved required failures is a useful audit, not a completed release.

Requirement focus: Functional IF, LEN, ADM, MEM, Q, SCH, FMT, RST, CSR and PAR families; PERF-01–04 and AI-01 are included in the final release audit.
