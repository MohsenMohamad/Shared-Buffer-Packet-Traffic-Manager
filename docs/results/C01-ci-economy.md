# C01 CI iteration qualification

The light/full policy preserves the existing hardware suites and pinned dependencies.
Local structural tests qualify event selection and summary failure behavior; they
are not hosted hardware results. Base: `eb99f7e7152b1880c2e2aafa0d0a77602a68ec42`.
Tested implementation: `511ccb51adacba26a08e2c756cc49c5f4917b3c7`, clean detached
worktree without `.tools` or `.deps`; Python 3.12. Subsequent documentation updates
do not imply rerunning hardware.

| Event / complete PR diff | Full requested | Evidence |
| --- | --- | --- |
| Unlabeled draft code push | No | Local policy test |
| Ready ordinary README prose push | No | Local policy test |
| Ready substantive or normative-doc push | Yes | Local policy test |
| Ready event, including docs-only draft metadata | Yes | Local policy test |
| `full-ci` on draft/docs PR; subsequent push with label | Yes | Local policy test |
| Unrelated label, including on a labeled PR | No | Local policy and concurrency checks |
| Main push / manual dispatch | Yes | Local policy and preserved concurrency checks |
| Incomplete/empty file selection on ready PR | Yes | Local fail-closed tests |
| Earlier code commit followed by prose commit | Yes | Actual temporary Git history diff test |
| Prepare intentionally skipped | Consumers and cleanup skipped | Local workflow checks |
| Consumer failed/cancelled; prepare failed/cancelled | Cleanup runs | Local guarded-`always()` checks |
| Requested suite failed/skipped/missing | Summary fails | Local per-job negative checks |

## Local reproduction and boundaries

Run from a clean checkout, without `.tools` or `.deps`:

```sh
python3 tools/check_repository.py
python3 tools/check_light.py
actionlint -version
actionlint
git diff --check
```

Local checks passed: 63 unit tests; 34 Python, 23 JSON and one shell source
syntax checks; repository contracts (52 requirements); actionlint and diff checks.
A real `toolchain_cache.py validate` invocation in the clean worktree exited 1,
printed the missing-manifest recovery instructions and emitted no traceback.

Actionlint 1.7.11 was downloaded from its official release for local validation;
no repository dependency versions changed. Python/JSON/shell syntax and all
Python units run directly, without invoking the hardware runner or installed
HDL tools. Existing unit tests intentionally exercise fake-tool failures and
mocked preparation/doctor entry points; those are not hosted tool qualification.
The empty-discovery negative test prints TOOL_ERROR as expected; the enclosing
unit suite must still finish OK with a nonzero case count. Missing selection,
syntax errors, import failures and nonzero test status fail the light job.

The original structural cleanup assertion now requires `always()` combined with
`needs.prepare.result != 'skipped'`. The original main/manual concurrency
assertions remain, with the unrelated-label prefix removed before evaluating
those original invariants. Existing hardware tests and consumer commands are
unchanged.

## Cache and stale runs

`tools/toolchain_cache.py` is itself a compatibility-key input. Its new
missing-install diagnostic therefore invalidates existing installation keys
once, even though the package locks and tool versions are unchanged. The next
requested full run can require a cold producer build; consumers still reject
unsealed/incompatible payloads and never build. No cache-generation bump or
acceptance-semantic change was made.

Only the four C01-listed old PR #7 runs were considered for cancellation:
43097154036, 43096401788, 43095736199 and 43095516523. Their head SHAs were verified
against merged PR #7 and superseded by its final head. GitHub read APIs reported
`queued`, but every cancellation request returned “Cannot cancel a workflow run
that is completed”. Cancellation is not confirmed; records were preserved and
no other runs were targeted.

The repository currently has no `full-ci` label. Reading main branch protection
returned HTTP 403 with this integration, so required-check configuration could
not be inspected. No settings/rules were changed. Maintainer setup is described
in [automation](../spec/automation.md#maintainer-setup).

## Hosted observations

[PR #12](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/12)
opened as draft. Its [opened-event run 43281763248](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43281763248)
at `511ccb51adacba26a08e2c756cc49c5f4917b3c7` completed successfully: repository
contracts, Python unit/syntax and policy passed; preparation, every consumer and
cleanup were actually skipped. The summary log reported `NOT_REQUESTED: light
checks succeeded; full qualification did not execute`.

A single ready-for-review request follows the evidence update. Its live status
and run link are recorded in PR #12's validation table; a pending run is not full
qualification. The other event rows remain structural checks. Main/manual and
each skip variant do not receive separate expensive matrices solely for demonstration.
