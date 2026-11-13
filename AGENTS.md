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

RTL and independent DV have separate owners, branches and PRs. Work on one
active task at a time; completion does not automatically hand over to another
role. Audits remain read-only. The task cards link here rather than restating
or overriding this workflow.

- RTL owns production `rtl/`, embedded designer assertions and designer smoke.
  New smoke lives in `dv/designer/` with separate registration.
- Independent DV owns `dv/` except designer smoke; `formal/` harnesses,
  assumptions, covers and mutations; verification suite/source/requirement/
  coverage registries; and their runner handlers and CI selections. Coordinate
  production source membership with RTL; setup inputs remain tooling ownership.

### Preparation, implementation and independent qualification

1. Prepare independent verification first from specifications and public type/port
   declarations. Preparation never discovers, reads or runs target or dependency
   RTL implementations. Freeze and commit expected behavior before auditing any
   retained oracle/checker for reuse. Preparation merge establishes no hardware
   acceptance.
2. Start a fresh RTL task after preparation. RTL never reads independent DV
   models, checkers, tests, sequences, harnesses, mutations or implementation
   reports. Its handoff contains commands, public APIs, source identities and
   bounded symptoms only, without private vectors or verification code.
3. Independently qualify the actual new RTL source against frozen expectations.
   Production DV may inspect NEW RTL for binding, coverage, formal, mutations and
   debug, never to choose expected behavior. Only DV changes expectations, with
   contract justification. Retain provenance for any audited reused checks.
4. Validate the RTL candidate before RTL merge. Combine named RTL and DV commits
   in an isolated worktree; record both commits, the combined tree and any merge
   resolution or dirty diff. Never copy another owner's code into a PR merely
   to run tests. Repairs to unmerged RTL remain on its RTL PR; defects in merged
   RTL get a separate fix PR. Follow candidate qualification with exact merged-
   source confirmation. Only passing independent qualification establishes its
   stated acceptance scope.

### Verification-preparation acceptance criteria

- Derive byte order, fixed unbackpressured memory response timing, metadata,
  ownership and external retirement from contracts and observed actions/writes.
  Distinguish legal environment assumptions, DUT guarantees, policy and timing.
  Maintain a risk/check/cover matrix without driver handles, DUT cursors/free
  counts or copied implementation logic as expected answers.
- Hand-check latency/depth, complete issue/response/retirement equations, all
  final keeps, word/cell/maximum boundaries, fragmented chains and duplicate
  tags. Permit contract-legal atomic event batches, including reserve/first
  allocation/write/commit, while rejecting same-edge returned-ID reuse.
- Qualify each critical detector with its own missing, wrong and duplicate
  events, missing final output/completion and leaks; legal neighboring traces
  pass. Selected detector removals and wrong model deltas must fail their
  intended self-tests rather than crash or trigger an unrelated alarm.
- Generate bounded replayable sampled transactions for exact-capacity stalls,
  response+issue+retire, final-beat holds and early reuse. Sweep supported
  latency/depth/cell/length boundaries. Cross-check hand-derived bytes/lifetimes
  and independent conservation equations. Test only contract-valid tag-renaming
  and unused-lane invariants; do not require unsupported ID/timing invariance.
- Qualify reset at dispatch, pending-read, full-FIFO, partial-cell, cell-final
  and packet-final boundaries. Preserve array contents, reuse IDs/tags with
  distinctive new bytes, and reject stale response output/credit. Tie reset
  width, initialization and new-work timing to the published contract.
- Prepare actual SV/UVM stimulus, passive edge sampling, independent checking,
  assertions and observed bins through P07 infrastructure. Qualify legal/corrupt
  signal or sealed-monitor replay, missing/duplicate/mixed-cycle samples,
  omissions, missing triggers and nonempty shutdown. Plan F01-compatible FP-TX
  safety/progress assumptions and covers separately.
- Register distinct oracle/bench qualification and future DUT execution in the
  existing runner with exact commands and source lists. Preparation compiles
  public declarations/packages and DV infrastructure only, never inherited
  production lists or dependency regressions. Missing implementation and empty
  selection must be explicit non-success, never oracle PASS. Review parameter
  rejection and the absence of memory response backpressure.
- Retain executed preparation results, observed baseline bins, exact commands
  and detector qualification, with no unexplained critical oracle failures.
  Production tests, performance, formal proof and DUT coverage remain NOT_RUN
  during preparation. Production qualification requires observed mandatory bins,
  exact-source execution, at least three random seeds per applicable component
  profile plus replay, and complete transaction/resource accounting at shutdown.

Capture unexpected failures before repair and classify afterward under the
failure policy above. Intentional negatives use isolated fixtures, never fake
repository captures or capture opt-outs; real failures remain captured even
when output is outside the repository. Enter confirmed future RTL defects in
`docs/bugs.md` immediately with a reproducer, then root cause, fix and independent
before/fix/retest evidence. Model/tool defects and planted faults are not natural
RTL discoveries; there is no bug quota.

Use the prepared environment and run `make doctor` on current main before
tool-dependent checks. On failure, report the precise mismatch; do not run setup,
rebuild/install/download tools, edit locks/stamps or bypass validation. Continue
only independent work.
