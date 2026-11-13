# Captured failures

`Case.finish()` saves FAIL, TIMEOUT, INCONCLUSIVE, TOOL_ERROR and UNSUPPORTED
cases here before repair. A successful intended negative finishes as PASS and
does not create a record. Tool errors are captured because an executed HDL
assertion can have that status; capture is not a diagnosis of an RTL bug.

Each timestamp/test/unique-ID JSON records run and capture revisions, parameters,
seed, commands/cwd/return codes, tool/source identities and bounded stdout/stderr
tails. A hashed binary patch preserves tracked edits and nonignored untracked
files against the capture revision. Existing captures are excluded from patches.
`changed_since_run_start` or `source_capture_error` must be resolved before claiming
the patch reproduces the tested source. The case manifest links the capture;
capture errors are explicit and never replace the original case result.

The files are **not automatically committed**. Inspect and commit relevant captures
with the task's work so they survive workspace/CI cleanup. Set `disposition` to
`rtl-defect`, `verification-defect`, `specification-ambiguity`, `tool-environment`
or `unresolved`, and add a short diagnosis or reference to a shared root cause.
Confirmed RTL bugs also get the root cause, fix and detecting before/after
regression in `docs/bugs.md`. Deduplicate diagnosis, not the original evidence.

Capture occurs when a case finishes, not on every subprocess failure: expected
negative commands may fail inside a passing case. Ad-hoc runs or a process killed
before case completion need equivalent manual capture. Log tails are not full
logs; ignored/generated source, waveforms and unreplayable stimulus are not
archived automatically. Before repair, retain any missing compact input/trace or
source needed for reproduction alongside the record; do not rely only on an
expiring `.build` path. See [Failure capture](../../AGENTS.md#failure-capture).
