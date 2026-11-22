# Captured failures

`Case.finish()` saves FAIL, TIMEOUT, INCONCLUSIVE, TOOL_ERROR and UNSUPPORTED
captures under `.build/runs/failures/`, including when `--output` sends the run
elsewhere. The case manifest's `failure_capture` path is checkout-relative.
A successful intended negative finishes as PASS without a failure capture. An
executed HDL assertion can be reported as TOOL_ERROR, so classify after capture.

Each timestamp/test/unique-ID JSON records run and capture revisions, parameters,
seed, commands/cwd/return codes, tool/source identities and bounded stdout/stderr
tails. A hashed binary patch preserves tracked edits and nonignored untracked
files against the capture revision. Raw captures and historical records are
excluded from patches. Verify `changed_since_run_start` and `source_capture_error`
before using a patch as the tested source identity. The manifest reports capture
errors alongside the original case result.

Review the capture before cleanup and apply the [durable evidence policy](../../docs/documentation.md#durable-evidence-for-new-work).
Use the [failure dispositions](../../AGENTS.md#failure-capture) and link repeat
cases to a shared diagnosis. This directory documents the capture workflow.
Use ignored run storage and CI artifacts for new captures and the
[historical baseline](../../docs/results/README.md#historical-baseline) for
tracked captures retired from the active tree.

## Interrupted or ad-hoc runs

Before touching the failing source, identify the partial run output or job log.
Record the interrupted command, working directory, profile/seed, tool identity,
last completed or failing case and actual exit or interruption status. Save
partial logs, configuration, untracked or ignored stimuli and generated inputs
required for replay. An interrupted worker may skip upload, so preserve whatever
is accessible and note any missing evidence. To save the current source from
the checkout root, use the same snapshot routine as the runner.

```sh
mkdir -p .build/runs
capture_dir=$(mktemp -d .build/runs/manual-failure-XXXXXX)
PYTHONPATH=tools python3 - "$capture_dir" <<'PY'
from pathlib import Path
import sys
from failure_capture import snapshot

directory = Path(sys.argv[1])
revision, patch = snapshot(Path.cwd())
(directory / 'source-revision.txt').write_text(revision + '\n')
if patch:
    (directory / 'source.patch').write_bytes(patch)
PY
printf '%s\n' "$capture_dir"
```

Save the partial input and command evidence alongside that snapshot. The snapshot
records source at capture time. Document any drift from the failing source.
To replay a finished or manual capture, start from its saved source revision in
a clean detached worktree, verify the patch digest when available, apply a
nonempty patch with `git apply --binary`, then restore required inputs and run the
recorded command. Bounded tails supplement the full logs retained in run storage.
