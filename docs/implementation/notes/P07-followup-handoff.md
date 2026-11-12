# P07 follow-up checkpoint

Paused at the maintainer's request. Candidate implementation is `0234441` on
`feat/dv-foundation-followup`, based on fetched `origin/main` `4d55757`.

- `73f1b9d` is the separate behavior-preserving checker cleanup. Clean E0/I0
  suites pass, including every exact intended negative. E0 trace is unchanged.
- `752bb9a` is the explicitly approved timeout-test race fix. Focused and full
  runner tests pass; process disappearance no longer crashes `/proc` inspection.
- `0234441` adds the constrained legal packet object, separate malformed raw
  controls, recorded handshake/stimulus validation, passive packet coverage,
  separate scheduler policy/baseline timing checks, and real runner/CI cases.
- Exploratory E0 execution passes all original/new cases, including constraints,
  intended negatives, distributions and replay. The exact final candidate has
  **not** been qualified. Coverage/analysis edits followed the exploratory build.
  There are no known unresolved execution failures on the successful exploratory
  source; earlier syntax/width-warning builds are retained as rejected attempts.

Next command from the repository root:

```sh
export CXX=g++-14
source .tools/activate.sh
make doctor
python3 tools/run.py regression --profile E0 --test uvm-foundation --seed 17 --jobs 2 --output .build/p07-final
```

Then execute the remaining commands in the [partial result record](../../results/P07-followup-stimulus.md),
inspect saved records/bins/distributions/digests and exact negative detectors,
review the final change, update task/spec/status completion guidance and compact
final evidence, and check hosted CI before marking the draft PR ready. Keep
fixture qualification distinct from production verification. P03/P08 and
production admission RTL remain outside scope and paused.
