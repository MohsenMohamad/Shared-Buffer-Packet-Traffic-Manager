# Repository working agreements

Implement the traffic-manager contracts in `docs/spec/`. Use `docs/spec/README.md` to locate the relevant contract and `docs/implementation/plan.md` for task dependencies. Read the selected task card and guidance nearest the files being changed; unrelated history and specifications need not be loaded.

## Work boundaries

- Complete one cohesive task with its tests, documentation and evidence. Routine edits, local builds, disposable tests and fixes within that task are authorized; continue through failures caused by the change.
- Preserve external behavior and the independent verification contract. Explain a material contract change in the PR and update affected tests/docs together. Never weaken a check simply to make it pass.
- Use the open-source toolchain. Implement and isolate an unsupported check with its reproducer, expected result and truthful status; continue work that does not depend on that capability.
- Avoid unrelated rewrites and new frameworks. Use existing commands and conventions. Keep upstream licenses and required attribution intact.

## Verification and delivery

Run checks appropriate to the changed behavior. Record exact commands, profiles/seeds and results in the supporting results report; summarize outcomes and essential qualifications in the PR. `make repo-check` checks the repository contract only; it does not validate hardware. A missing executable, empty test selection, ignored construct, timeout or unavailable capability is not PASS. Keep production RTL, testbench, formal and synthesis source lists separate.

Keep build outputs in ignored directories. Preserve important decisions in a short topic-specific decision record; record failures and bugs as described in "Failure capture" below. Add a compact task handoff only when work actually remains, naming the current revision, known facts, blockers and next command. Do not accumulate conversation transcripts or per-agent diaries.

Use technical branch/commit/PR names such as `feat/cell-pool` and `fix(queue): preserve head on simultaneous replacement`. Comments explain behavior and constraints. Do not add generated-by banners, tool signatures, assistant coauthor trailers or conversational provenance. Do not fabricate authorship, credentials, results or dependency provenance.

Do not push directly to the default branch, merge PRs, rewrite shared history or change repository access settings as part of implementation. Prepare a reviewable change; the maintainer controls integration. Check the current base revision before starting dependent work.

## Failure capture

Before repairing an unexpected failed check, including designer smoke,
simulation, assertions, formal counterexamples and ad-hoc runs, preserve the
failing source (commit or base plus patch), command/configuration/seed, stimulus
and failure output. Capture first; classify afterward. Finished runner cases save
records under `verification/failures/`; preserve equivalent evidence manually
for ad-hoc/interrupted runs and any inputs the automatic capture cannot retain.
Review and commit the records before session cleanup.

Give every capture a disposition: `rtl-defect`, `verification-defect`,
`specification-ambiguity`, `tool-environment` or `unresolved`. Capture tool/build
errors too; classification must not decide whether evidence is retained.
Confirmed RTL defects also get a short `docs/bugs.md` entry with root cause,
fix and detecting before/after regression. Repeated failures may share a diagnosis.
Expected detections from deliberate faults remain separately labeled. Do not
count syntax/compile errors or mutations as discovered RTL bugs, and do not discard
an unexpected failure because it was easy to fix or found by the RTL author.
See [capture contents and limits](verification/failures/README.md).

## Hosted CI iteration

Keep implementation PRs draft while iterating. Run affected local checks before
meaningful pushes; use `python3 tools/check_repository.py` and
`python3 tools/check_light.py` for toolchain-independent checks. `make lint`
retains its Verilator meaning. Batch meaningful changes rather than pushing
individual edits. When review-ready, mark the PR ready or explicitly request
`full-ci` and wait for the full hosted suites before implementation merge.
A light-only success is not hardware qualification. Main/manual full routes
remain integration gates; see [hosted CI policy](docs/spec/automation.md#hosted-iteration-policy).

## Code Review Rules

- Check readability: descriptive names, separated statements and state transitions, manageable functions, and explanations of non-obvious invariants.

- Review reservation/physical ownership and simultaneous updates against pre-state admission plus merged deltas; flag leaks, double frees and premature reuse.
- Check that reference data originate from observed handshakes and that trace/status assertions are independently cross-checked.
- Check the actual scope of verification evidence. Local proofs, two-state simulation and positive pre-layout slack must not be reported as broader validation.

## Documentation and PR presentation

Follow [documentation conventions](docs/documentation.md) for repository documents, PR bodies and delivery summaries. Lead with the behavior or result; give each paragraph, bullet or table row one purpose. Keep summaries, contracts, reproduction instructions and raw evidence separate.

Use the PR template as a default. Keep validation concise, link to a focused report for full commands, revisions, seeds, digests and measurements, and keep material qualifications beside the result. Label expected seeded-defect detections explicitly. Preserve precise requirements and proof boundaries; never shorten by omitting necessary behavior or limitations. Check Markdown structure and links before delivery. Do not accumulate debugging chronology or duplicate evidence across documents.

## Separate RTL and independent DV ownership

RTL and independent DV have separate owners, branches and PRs; continue an
existing task branch/PR. Role assignments divide the existing technical and
acceptance obligations without dropping checks. Audits remain read-only.

- RTL owns production `rtl/`, embedded designer assertions and designer smoke.
  New smoke lives in `dv/designer/` with separate registration.
- Independent DV owns `dv/` verification except designer smoke: tests, models,
  scoreboards, passive monitors/binds and coverage; `formal/` harnesses, assumptions, covers and mutations; and test, proof,
  coverage and requirement entries in `verification/{suites,formal,coverage,requirements}.json`
  and `verification/sources/*.json`. It owns their handlers and dispatch in
  `tools/run.py`, `tools/formal_storage.py`, suite-specific runner modules and
  `.github/workflows/` selections. Coordinate production source membership with
  RTL; toolchain/setup inputs remain tooling ownership.

Use one active task and this cycle across the separate RTL/DV branches:

1. Independent DV establishes a spec-derived baseline: a self-checked model,
   risk/check/cover matrix and first usable tests, then a checkpoint. This is
   not a full DUT campaign. Commit the model, matrix and self-check/test commands
   before inspecting target RTL, designer results or retained checker internals.
2. RTL develops the candidate and runs available DV checks as well as designer
   smoke. Share bounded policy/documentation commits independently of test work.
3. Independent DV qualifies the exact candidate production source before RTL
   merge. Test RTL and DV together in an isolated worktree built from named RTL
   and DV commits; record both commits, the assembly command and resulting tested
   revision/dirty state in the evidence. Alternate RTL repair and independent DV
   retest until required candidate
   checks pass; retain failures and before/fix/retest evidence.
4. After maintainer integration, confirm the merged production source and refresh
   checks affected by merge changes. Only merge of the passing independent DV PR
   establishes verified scope for acceptance gates.

Coordinate interface changes through shared specs/APIs and label infrastructure-only
results. Reuse valid unchanged evidence, preserve author checks' original
locations/provenance, and audit retained models/properties after the independent
baseline before reuse without relabeling historical results as independent.

Keep hardware defects visible in the open DV PR with the detecting check,
revision/configuration and captured evidence. RTL repairs unmerged production
RTL/embedded assertions on its existing PR; a defect in merged RTL requires a
separate fix PR. Independent DV retests the repaired candidate before merge,
then confirms merged source without weakening expectations, assumptions or coverage.

Use the prepared environment and run `make doctor` on current main before
tool-dependent checks. On failure, report the precise mismatch; do not run setup,
rebuild/install/download tools, edit locks/stamps or bypass validation. Continue
only independent work.
