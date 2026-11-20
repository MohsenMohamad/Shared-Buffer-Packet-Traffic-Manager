# Contribution workflow

Work from the latest integrated default branch and select one ready task from the implementation plan. Use a short-lived topic branch. Confirm its dependencies and relevant contracts before coding. Deliver one cohesive change with appropriate tests and current documentation.

PR descriptions lead with the concrete problem and resulting behavior. Summarize validation outcomes, keep essential qualifications visible, and link to the authoritative evidence. Report unsupported or unexecuted cases explicitly. Follow the [documentation conventions](docs/documentation.md) and the PR template. A reviewer evaluates the diff and evidence against the contract. Fix consequential findings and rerun affected checks before integration.

Keep durable decisions in `docs/decisions/` only when an important alternative, trade-off or compatibility boundary needs preservation. Use an issue or a compact task handoff for a reproducible unresolved problem. Follow the [durable evidence policy](docs/documentation.md#durable-evidence-for-new-work) for run output and reproduction inputs.

## Front-page review

When a PR changes supported functionality, a user-facing command, a navigation
link or a verified milestone visible from the front page, review and update
the affected [README](README.md) text and its linked [status entry](docs/status.md)
in the same PR. Routine refactors, fixes without front-page impact and repeated
passing runs require no README update.

## Code and licensing

Use lower_snake_case for RTL identifiers and descriptive module names. Separate packages, production RTL, UVM, assertions, formal harnesses, scripts and constraints. Python follows the standard library where practical; pin additional dependencies only when justified. Use explicit process return checking, timeouts and deterministic seeds. Comments explain non-obvious invariants and timing, rather than restating statements.

Original source licensing remains the maintainer's choice. Preserve notices for all included third-party material and record external dependency sources. Do not assign an external open-source license to the whole project as an incidental tooling change.
