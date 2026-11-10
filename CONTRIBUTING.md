# Contribution workflow

Work from the latest integrated default branch and select one ready task from the implementation plan. Use a short-lived topic branch. Confirm its dependencies and relevant contracts before coding. Deliver one cohesive change with appropriate tests and current documentation.

PR descriptions state the concrete behavior changed, why it is needed, commands/configurations exercised, their actual outcomes and remaining limits. Report unsupported or unexecuted cases explicitly. A reviewer evaluates the diff and evidence against the contract. Fix consequential findings and rerun affected checks before integration.

Keep durable decisions in `docs/decisions/` only when an important alternative, trade-off or compatibility boundary needs preservation. Use an issue or a compact task handoff for a reproducible unresolved problem. Raw tool logs and development transcripts do not belong in the permanent documentation.

Use lower_snake_case for RTL identifiers and descriptive module names. Separate packages, production RTL, UVM, assertions, formal harnesses, scripts and constraints. Python follows the standard library where practical; pin additional dependencies only when justified. Use explicit process return checking, timeouts and deterministic seeds. Comments explain non-obvious invariants and timing, rather than restating statements.

Original source licensing remains the maintainer's choice. Preserve notices for all included third-party material and record external dependency sources. Do not assign an external open-source license to the whole project as an incidental tooling change.
