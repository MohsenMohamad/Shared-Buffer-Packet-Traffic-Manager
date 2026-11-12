# C01: Lightweight iteration and explicit full CI

## Objective

Reduce hosted work while preserving all hardware tests, tool versions and final
required checks. This maintenance task does not block P03. Keep shared preparation,
exact installation validation, consumer checks, per-main-run concurrency and
handoff cleanup.

## Work

1. Run lightweight repository checks and demonstrably toolchain-independent unit/
   syntax checks for every PR push and main push, without path filters or doctor.
   Current `make lint` invokes Verilator; it is not a toolchain-free light check.
   Keep its hardware meaning and use separately named Python/JSON/Markdown/shell/
   workflow checks. Empty selections and import/tool failures are not PASS.
2. Use `pull_request` events opened/synchronize/reopened/ready_for_review/labeled
   for heavy orchestration; retain push-to-main and workflow_dispatch full runs.
   Do not use broad workflow-level Markdown/docs ignores: they can suppress
   explicit ready/label requests and changes to normative contracts.
3. Decide heavy execution at job level. Unlabeled draft pushes run light only.
   Ordinary prose-only pushes can run light only; use a narrow allowlist and
   conservatively treat unknown paths as substantive. Classify the complete PR
   base-to-head change set, not just its last commit; incomplete file enumeration
   must not hide unvalidated code. Specs, task acceptance,
   source registries, instructions, workflow/setup/parser changes are substantive.
   Marking ready or applying `full-ci` explicitly requests full CI, including for
   draft/prose-only PRs. Ignore irrelevant label events. Main/manual always run full.
4. A skipped preparation must skip consumers and cleanup without pretending they
   executed. A stable summary must fail if requested required jobs fail or vanish;
   distinguish intentionally unrequested work from a completed full qualification.
   Keep required-check names usable and report any branch-rules adjustment needed.
5. Add focused event/path/condition checks and actionlint. Cover draft code push,
   ordinary prose-only push, normative-doc push, ready event, full-ci label on a
   draft/docs PR, unrelated label, main push and manual dispatch. Do not change
   existing hardware tests or replace full suites with fixtures.
6. Add the iteration rule to root guidance: draft while iterating, affected local
   checks, meaningful pushes, explicit full hosted request before implementation
   merge. Report observed versus structurally checked behavior. Do not run
   untrusted PR code with a privileged pull_request_target workflow.
7. Cancel the four specifically identified stale queued PR #7 runs only if they
   are still queued and superseded: 43097154036, 43096401788, 43095736199,
   43095516523. Preserve their records and do not cancel current required runs.
8. Make missing-install validation emit a clear actionable error rather than a
   traceback, without accepting an absent/incompatible payload. Explain any cache
   invalidation caused by the helper change; no package upgrade is required.

## Completion

The event truth table and applicable hosted evidence match the policy; full
required suites are retained. No unsupported claim that labeling bypasses a
workflow-level path filter is made.
