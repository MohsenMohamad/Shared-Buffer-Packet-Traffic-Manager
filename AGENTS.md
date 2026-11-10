# Repository working agreements

Implement the traffic-manager contracts in `docs/spec/`. Use `docs/spec/README.md` to locate the relevant contract and `docs/implementation/plan.md` for task dependencies. Read the selected task card and guidance nearest the files being changed; unrelated history and specifications need not be loaded.

## Work boundaries

- Complete one cohesive task with its tests, documentation and evidence. Routine edits, local builds, disposable tests and fixes within that task are authorized; continue through failures caused by the change.
- Preserve external behavior and the independent verification contract. Explain a material contract change in the PR and update affected tests/docs together. Never weaken a check simply to make it pass.
- Use the open-source toolchain. Implement and isolate an unsupported check with its reproducer, expected result and truthful status; continue work that does not depend on that capability.
- Avoid unrelated rewrites and new frameworks. Use existing commands and conventions. Keep upstream licenses and required attribution intact.

## Verification and delivery

Run checks appropriate to the changed behavior and report exact commands, profile/seed and result. `make repo-check` checks the repository contract only; it does not validate hardware. A missing executable, empty test selection, ignored construct, timeout or unavailable capability is not PASS. Keep production RTL, testbench, formal and synthesis source lists separate.

Keep build outputs in ignored directories. Preserve important decisions in a short topic-specific decision record; put a reproducible bug/test/fix summary in the PR or issue. Add a compact task handoff only when work actually remains, naming the current revision, known facts, blockers and next command. Do not accumulate conversation transcripts or per-agent diaries.

Use technical branch/commit/PR names such as `feat/cell-pool` and `fix(queue): preserve head on simultaneous replacement`. Comments explain behavior and constraints. Do not add generated-by banners, tool signatures, assistant coauthor trailers or conversational provenance. Do not fabricate authorship, credentials, results or dependency provenance.

Do not push directly to the default branch, merge PRs, rewrite shared history or change repository access settings as part of implementation. Prepare a reviewable change; the maintainer controls integration. Check the current base revision before starting dependent work.

## Code Review Rules

- Review reservation/physical ownership and simultaneous updates against pre-state admission plus merged deltas; flag leaks, double frees and premature reuse.
- Check that reference data originate from observed handshakes and that trace/status assertions are independently cross-checked.
- Check the actual scope of verification evidence. Local proofs, two-state simulation and positive pre-layout slack must not be reported as broader validation.
