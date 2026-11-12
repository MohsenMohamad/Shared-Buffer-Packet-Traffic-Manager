# Repository working agreements

Implement the traffic-manager contracts in `docs/spec/`. Use `docs/spec/README.md` to locate the relevant contract and `docs/implementation/plan.md` for task dependencies. Read the selected task card and guidance nearest the files being changed; unrelated history and specifications need not be loaded.

## Work boundaries

- Complete one cohesive task with its tests, documentation and evidence. Routine edits, local builds, disposable tests and fixes within that task are authorized; continue through failures caused by the change.
- Preserve external behavior and the independent verification contract. Explain a material contract change in the PR and update affected tests/docs together. Never weaken a check simply to make it pass.
- Use the open-source toolchain. Implement and isolate an unsupported check with its reproducer, expected result and truthful status; continue work that does not depend on that capability.
- Avoid unrelated rewrites and new frameworks. Use existing commands and conventions. Keep upstream licenses and required attribution intact.

## Verification and delivery

Run checks appropriate to the changed behavior. Record exact commands, profiles/seeds and results in the supporting results report; summarize outcomes and essential qualifications in the PR. `make repo-check` checks the repository contract only; it does not validate hardware. A missing executable, empty test selection, ignored construct, timeout or unavailable capability is not PASS. Keep production RTL, testbench, formal and synthesis source lists separate.

Keep build outputs in ignored directories. Preserve important decisions in a short topic-specific decision record; put a reproducible bug/test/fix summary in the PR or issue. Add a compact task handoff only when work actually remains, naming the current revision, known facts, blockers and next command. Do not accumulate conversation transcripts or per-agent diaries.

Use technical branch/commit/PR names such as `feat/cell-pool` and `fix(queue): preserve head on simultaneous replacement`. Comments explain behavior and constraints. Do not add generated-by banners, tool signatures, assistant coauthor trailers or conversational provenance. Do not fabricate authorship, credentials, results or dependency provenance.

Do not push directly to the default branch, merge PRs, rewrite shared history or change repository access settings as part of implementation. Prepare a reviewable change; the maintainer controls integration. Check the current base revision before starting dependent work.

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
