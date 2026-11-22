# Automation and run evidence

Recommended starting tiers:

| Tier | Contents | Trigger |
|---|---|---|
| Smoke | Directed vertical path, queue collision, short reset, CSR handshake and a few constrained-random seeds | Integration change |
| Control proof | Fast local invariants and reachable covers in the smallest production-module proof configurations | Control RTL change |
| Functional regression | Full directed matrix plus at least 20 diverse seeds/configuration for the main functional profiles; expand based on coverage gaps | Longer scheduled/manual run |
| Parameter regression | Focused scenarios for every required profile | Parameter/interface change and delivery |
| Traffic benchmark | Recorded workloads, stable configurations and reference-policy comparisons | Performance change and delivery |
| Implementation | Mapped synthesis/STA for the primary and small profiles under matched analysis conditions | Microarchitecture change and delivery |

Seed count is a starting execution budget, not evidence of completeness. Record packet/cycle counts and distributions. Serial execution and bounded worker pools are supported. Size parallel work to measured memory and CPU limits.

Each run stores test name, seed, configuration, RTL/bench revision, simulator/UVM version, command, start/end times, result category, first failure and artifact paths. A regression distinguishes functional assertion failure from timeout, license exhaustion, missing executable, malformed input and report-generation error. Tool failure is not a functional PASS or FAIL.

Waveforms should be generated on a failing rerun with the identical revision/seed/configuration. Preserve transaction traces around the first meaningful failure rather than uploading every raw waveform to an LLM.



## Stable command interface

Use `make doctor`, `make repo-check`, `make lint`, `make test-unit`,
`make test-uvm-smoke`, `make formal-smoke`, `make synth-smoke` and `make ci`
for repository and toolchain gates. `make multi-egress-declarations` covers
the two published interfaces at both read latencies.
`make multi-egress-pools-preparation` runs independent pool replay on both
profiles. `make multi-egress-pools-candidate` requires a production adapter
and exact candidate source identity. Unimplemented actions exit nonzero with
NOT_IMPLEMENTED. An unbound candidate exits nonzero with NOT_RUN.

`make repo-check`, `make lint`, `make test-unit`, `make test-uvm-smoke`, `make formal-smoke`, `make synth-smoke` and `make ci`. P01 adds functional `make regression` selection. P02 adds `make formal-rtl` for production-module proofs; `make formal-smoke` retains its capability-fixture meaning. Later tasks add `make coverage`, `make benchmark`, `make synthesis` and `make sta`. Commands take explicit configuration/test/seed options through the common Python runner. Until implemented, a command fails with NOT_IMPLEMENTED; it never reports an empty PASS.

`make repo-check` validates repository documents, requirement data and the raw
artifact rule for tracked worktree changes. Hardware is checked by the separate
tool-capability and subsystem jobs.

Each case writes a JSON manifest containing schema version, UTC times, test/seed/profile, source revision and dirty state, source/dependency/constraint digests, tool versions, argv, result, first failure and artifact paths. Result categories are PASS, FAIL, TIMEOUT, INCONCLUSIVE, UNSUPPORTED, TOOL_ERROR, NOT_RUN and NOT_IMPLEMENTED. Only executed checks can produce PASS. A nonzero tool status, UVM_ERROR/UVM_FATAL or missing completion marker cannot be silently reclassified as PASS.

Use a separate build directory per tool/profile/feature-set. A passing cache from another source revision or feature set is not evidence. Bound subprocess timeouts and parallel compilation. Retain stdout/stderr and transaction traces; collect FST/VCD on failing reruns with the same revision, seed and profile.

GitHub Actions may run the same open-source commands on hosted Linux runners. Core commands must also run in the cloud development workspace. CI does not require an LLM key, a hardware server, a GUI or a container daemon.

## Durable versus execution evidence

Follow the [durable evidence policy](../documentation.md#durable-evidence-for-new-work)
for run output and published evidence. Runner failure records and patches live
under `.build/runs/failures/`, covered by the existing CI run-artifact uploads
after both success and failure. For incomplete or ad-hoc work, follow the
[manual capture instructions](../../verification/failures/README.md#interrupted-or-ad-hoc-runs).

The pinned Slang frontend is used for synthesis and formal. `make formal-symbols` qualifies explicit
fixed/time-varying inputs, source guards and missing-stability negative controls.
`make frontends` qualifies independent current-stack language and memory checks.
Consumers validate the shared installation and never invoke setup. See the
[operational guide](../implementation/toolchain.md) for capability commands.


## Hosted iteration policy

Full CI runs the toolchain capability matrix and both pool replay profiles.
It uploads run artifacts even on failure.
`repository-contracts` checks documents/requirements and screens the complete
PR merge-base-to-head diff for raw artifacts.
`python-unit-syntax` runs Python unit tests and Python/JSON/shell syntax checks
without setup, doctor or HDL tools. Empty/missing selections and import failures
fail. `make lint` remains the separate Verilator capability check.

Light repository and toolchain-independent checks run on every PR/main push,
without path filters. Full prepared-toolchain runs are requested by ready-for-
review or `full-ci`, run for substantive ready PR updates, and always run for
main pushes/manual dispatches. An unlabeled draft or ordinary prose-only push
can avoid heavy preparation. Normative specs, acceptance cards, source registries,
instructions and setup/workflow/parser changes are not cosmetic documentation.

Decide full execution inside a workflow so metadata requests are not suppressed
by broad workflow-level Markdown path filters. Unknown paths are substantive.
Skipped preparation means consumers/cleanup skip; it is not a hardware PASS.
Preserve stable required-check behavior and a truthful full-CI summary.

The only cosmetic path is root `README.md`. All other paths, including writing
instructions in `docs/documentation.md`, are substantive. Classification uses
Git's complete merge-base-to-PR-head diff with full checkout history, including
renamed/deleted source paths; unavailable, malformed or empty diffs conservatively
request full CI for ready PRs. Draft pushes still skip unless `full-ci` is present.
`full-ci` persists across pushes; remove it to return a draft to light iteration.
Only a `labeled` event for `full-ci` requests heavy work. Unrelated labels use an
isolated concurrency group so they cannot cancel an active full request. Normal
PR events supersede previous runs; each main/manual run/attempt stays independent.

`full-ci-summary` is a stable check: it fails on failed/missing policy or light
checks, and on any failed/cancelled/skipped/missing requested full suite. For an
intentional light-only run it reports `NOT_REQUESTED`, never hardware PASS.
Preparation skipped means consumers and cleanup skip. Otherwise cleanup uses
`always()` and waits for all consumers even after failure/cancellation; its
existing verified-artifact deletion and one-day fallback remain in effect.

### Maintainer setup

Create the repository label `full-ci` (exact spelling) if label requests are
wanted; until then, marking ready requests full CI. This change does not create
labels or edit branch protection/rulesets. Maintainers should inspect their
current required checks. The stable names to require for this policy are
`repository / repository-contracts`, `repository / python-unit-syntax` and
`full-ci-summary`. Keep the existing hardware/integration requirements; per-suite
checks alone cannot distinguish an intentional skip from completed qualification.
Require a requested, completed full run before merging implementation work.
A green summary containing `NOT_REQUESTED` establishes only light qualification.
Do not weaken branch rules to accept an unfinished requested run. Check names
for existing consumer suites are unchanged.

See the [C01 results report](../results/C01-ci-economy.md) for structural versus
hosted evidence, reproduction and the helper-change cache invalidation.
