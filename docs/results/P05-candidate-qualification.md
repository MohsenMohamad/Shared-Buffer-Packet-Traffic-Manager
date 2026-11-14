# P05 exact-candidate qualification

Production RAM/metadata/TX functional qualification has passed a complete
96-run matrix on candidate `479b5c1ceee2eee8db58d863bd5de5e20305cc8c`.
The pre-merge verdict remains **PENDING** while the production safety proof,
refreshed evidence export and hosted checks complete. No RTL defect is confirmed.
The qualification PR remains draft. This report is updated with final tested
source identities and bounded findings before a verdict is issued.

The repair merge/base is `a4df0dd61802355e91b4c0c96e57b79241c86851` (PR #25).
The submitted `verify/p05-dv-qualification` branch contains DV/tools/registries,
CI, results and failure records only. Candidate RTL is combined in a detached
checkout at the original prepared installation path, with the DV branch in a
separate worktree. No candidate production file is copied into its PR.

## Current evidence and boundary

| Area | Executed result |
| --- | --- |
| Production simulation | PASS: all six profile geometries, latency 1/2, depths 4/8, seeds 17/31/53 and seed-17 replay |
| Data/metadata | PASS: all keeps, word/cell/MAX edges, fragmented chains, source/qid coverage, duplicate tags, ignored lanes and exactly-once completion |
| Pressure/reuse/reset | PASS: mandatory observed full credit/exchange, long and final holds, earliest/random legal reuse, altered old payload/links, six reset phases, distinctive restarted bytes and shutdown accounting |
| Physical RAM | PASS: 64-bit 1R1W, fixed response timing, distinct-word overlap, physical responses through reset and unchanged post-reset readback |
| Source-copy detectors | PASS: omitted outstanding credit, premature return and stale-response validity; legal neighbor passes. A missing-final-output detector is separately exercised. |
| FP-TX | Covers and intended counterexamples reached. Unbounded proof remains pending; SMT timeouts/UNKNOWN and ABC preprocessing errors are retained as non-success. |
| Standard checks | Doctor passes on main and the detached combination. The repaired interface check and 113 light tests pass. |
| Hardware structural comparison | Outside this result; P12B retains the comparison. |
| Exact merged-source confirmation | NOT_RUN: PR #24 is unmerged; this pending follow-up does not itself block a pre-merge verdict. |

Expectations come from [the frozen contract](../../dv/memory_tx/contract.md),
published APIs and the unchanged observed-write oracle/resource ledger. New RTL
was inspected for binding, formal mapping, source-copy mutations and diagnosis.
The [historical preparation provenance qualification](P05-fresh-dv-preparation.md)
remains intact; this execution does not retroactively establish independence
acceptance for the earlier preparation.

## Reproduction

Use the prepared checkout path for tools. A secondary worktree cannot share its
installation through symlinks: doctor correctly rejects resolved executables
outside that checkout. That failure is preserved. The detached combination at
the original installation path passes without changing setup inputs or stamps.

In a clean detached checkout of the qualification revision, combine the exact
RTL candidate locally, retaining both inputs and the resulting tree. CI uses
`python3 tools/p05_ci.py` in its disposable detached checkout. The repository
branch itself must remain DV-only.

The opaque RTL-facing component command is:

```sh
python3 tools/p05_candidate.py --rtl-revision 479b5c1ceee2eee8db58d863bd5de5e20305cc8c --profile I1 --seed 17
```

It returns the underlying failure status and stores full private diagnostics.
The public result links semantic input stimulus, expected/observed interface
checks, configurations, seeds and contract violations without DV source excerpts.
Run it for F0, F1, I0, I1, E0 and E1. Each invocation crosses both latencies and
depths and runs three seeds plus replay; a smaller diagnostic selection through
`tools/run.py` is not full-matrix closure.

```sh
python3 tools/p05_candidate.py --rtl-revision 479b5c1ceee2eee8db58d863bd5de5e20305cc8c --profile E0 --formal --timeout 300
```

[FP-TX assumptions and proof boundaries](../../formal/tx/README.md) distinguish
arbitrary-stall safety from always-ready performance. Expected behavior was not
changed to match the candidate. Every unexpected failure is retained under
`verification/failures/`, with diagnosis after capture. Missing mandatory bins
remain failures; the directed full-exchange witness repairs a stimulus gap,
not an expectation. Source-copy faults are labeled expected negatives.

Do not merge the qualification PR or PR #24 while required checks/findings remain
open. PR #24 must also include the merged interface repair and pass its own
required CI. Neither PR is merged by this qualification task.
