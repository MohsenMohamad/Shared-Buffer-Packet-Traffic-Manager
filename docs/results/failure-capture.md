# Unexpected-failure capture

Finished runner cases retain source and diagnostics before repair. This is
tooling validation; no traffic-manager RTL or HDL qualification is claimed.

The hook is in `Case.finish()`; the implementation is in
`tools/failure_capture.py`. FAIL, TIMEOUT, INCONCLUSIVE, TOOL_ERROR and UNSUPPORTED
are captured. An executed HDL assertion may appear as TOOL_ERROR, so that status
cannot safely be excluded as if it always meant a compile error. Successful
expected-negative cases remain PASS and are not captured.

## Executed checks

| Check | Result |
| --- | --- |
| Capture/reconstruction tests | PASS, nine tests in temporary Git repositories |
| Self-test isolation / external output | PASS, two whole-command regression tests |
| Full light suite | PASS, 99 tests including the nine capture tests |
| Python/JSON/shell syntax | PASS through the light command |
| Repository contract and whitespace | PASS; 52 requirement records retained |

The reconstruction test applies the saved binary patch to a clean checkout and
compares staged, unstaged, new text and new binary inputs. Other tests exercise
all captured statuses, passing expected negatives, source drift, previous-capture
exclusion, concurrent naming, missing/large logs, Git failure and capture I/O
failure. Deleting the original run directory does not erase the saved diagnostics.
The synthetic negative cases are fixtures, not discovered design bugs.

The isolation tests run the complete light command without changing the real
capture directory, and an actual failing repository check in a temporary checkout
with output outside that checkout. Both run in the light CI job. The direct
negative unit case mocks only its capture writer; CLI negatives use copied current
sources in a temporary Git repository. No runtime opt-out/redirect switch exists.
During test development the external-output assertion initially expected the
checker diagnostic on stdout; the checker emits it on stderr. That verification-
test error was corrected in `test_failed_real_check_with_external_output_still_captures`:
changing its `log_tails[0]['stderr']` lookup back to `['stdout']` reproduces the
original failure. It is not an RTL defect.

Executed from main `159659f514734c5950dd1f2160788b242e4da617` plus this PR's
source changes. Commands:

```sh
PYTHONPATH=tools python3 -m unittest discover -s tests/toolchain -p test_failure_capture.py -v
python3 tools/check_light.py
PYTHONPATH=tools python3 -m unittest discover -s tests/runner -v
python3 tools/check_repository.py
git diff --check
```

## Operation and limits

See [capture contents](../../verification/failures/README.md) and the
[root rule](../../AGENTS.md#failure-capture). Captures must be reviewed and
committed; the runner does not commit them automatically. Bounded log tails do
not replace every possible stimulus, generated source or trace. Source drift and
capture failures are explicitly recorded; ad-hoc/interrupted runs need manual
preservation of equivalent evidence before repair.

`tools/evidence.py` is one of `toolchain_cache.INPUTS`, so hosted CI uses a new
cache key and may need a cold producer build. Doctor's setup recipe fingerprints
only `dependencies.json`, `packages.lock.json` and `setup_toolchain.py`; those
inputs are unchanged. This PR alone does not require a reusable-environment
refresh or republish. Continue with the prepared installation if doctor passes;
do not bypass validation. No toolchain was built, installed or resealed locally.
