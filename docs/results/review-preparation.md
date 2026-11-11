# Review preparation: guidance and CI infrastructure

This stabilization change schedules follow-up work and gives each CI run one validated toolchain preparation producer. It changes no hardware, production API, packet interface, statistics scope or existing result JSON. P03 and later hardware remain paused pending stabilization and reevaluation.

## Starting state and revisions

The workspace was clean on branch `work`. After fetching origin, `chore/review-preparation` was created from `a473b8c535d02b50b23604047f1bae64638c89df`, integrated main containing P00/P01/P02/P06/P07 (PRs #1–#5). Guidance was committed and pushed separately as `cd6b8fd8e7f19b70175df89d45b3b765409ad7fd`. CI infrastructure and its tests are a subsequent commit. No prior stage branch was continued and no existing workspace edits were overwritten.

## Validation boundary

| Check | Observed result | Scope |
| --- | --- | --- |
| Repository contract and whitespace checks | PASS | 52 requirement records and document/source registration; no hardware validation. |
| Runner unit suite | PASS, 21 tests | Includes seven cache tests: compatibility inputs, payload corruption/deletion/mode/link checks, cold/reuse, rejection/rebuild and doctor failure. Producer/consumer subprocesses in these unit cases are controlled fixtures. |
| Actionlint 1.7.12 | PASS | Workflow syntax and reusable-call/input graph; not hosted execution. |
| Real local cold preparation and transfer/reuse | In progress | Final executed results will be recorded separately; unit fixtures alone do not demonstrate installation. |
| New hosted orchestration/cache outcomes | Not yet observed | Existing main workflow successes do not qualify the new orchestration. |

The exact local commands and the hosted cold/hit/invalidation/consumer verification procedure are in [the toolchain guide](../implementation/toolchain.md#one-ci-preparation-producer). The real preparation command is `CXX=g++-14 python3 tools/toolchain_cache.py prepare --jobs 2`; repeated compatible preparation must execute restore-doctor without setup. Each consumer executes strict validation after receiving the archive in its own workspace.

Local unit and syntax checks ran on guidance revision `cd6b8fd8e7f19b70175df89d45b3b765409ad7fd` plus uncommitted CI files. Raw manifests/logs are ignored build artifacts; this report will retain compact final revision/configuration/tool/result and reproduction data after execution. Existing P01/P02 JSON evidence is preserved unchanged. Expiring artifacts are not the only explanation of the result.
