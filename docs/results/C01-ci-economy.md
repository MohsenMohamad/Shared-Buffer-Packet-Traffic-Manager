# C01 CI iteration qualification

The light/full policy preserves the existing hardware suites and pinned dependencies.
Local structural tests qualify event selection and summary failure behavior; they
are not hosted hardware results. Base: `eb99f7e7152b1880c2e2aafa0d0a77602a68ec42`.
The executable maintenance revision is identified by this PR's implementation
commit; subsequent report-only updates do not imply rerunning hardware.

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

Hosted draft and ready-request results will be linked here after the maintenance
branch is pushed. The event truth table above remains structural evidence unless
an actual run is explicitly cited. Main/manual and each skip variant will not
receive separate expensive matrices solely for demonstration.
