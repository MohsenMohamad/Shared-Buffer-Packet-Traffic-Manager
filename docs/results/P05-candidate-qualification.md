# P05 qualification and merged-source confirmation

**MERGED-SOURCE PASS** for RTL merge/current main
`3ede1a5e40791ff00d98a0faa8389154d632e0c5`, within the existing component scope.
GitHub confirms this is PR #24's actual merge commit. Fresh production execution,
coverage and accounting pass with the integrated source selected explicitly.
Earlier candidate/applicability records below retain their own execution identities.
Required final full-CI and relevant main-CI conclusions are recorded on
[PR #26](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/26);
a light-only result does not satisfy that final merge handoff.

## Post-qualification merge CI checkout repair

After PR #26 merged at `a96121fe723ba1c84a5169f6507c629341762bef`, main push run
[43617402959](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43617402959)
failed all six memory/TX jobs during staging. No DUT build or execution occurred
in those attempts. The later public-artifact errors are secondary: staging never
produced a result to upload.

This is a workflow checkout defect. Default `actions/checkout` behavior detached
the PR merge ref but attached the `main` branch for a push. The unchanged P05
staging guard correctly refused attached HEAD. The repair pins checkout to
`${{ github.sha }}` for every event, keeping both clean/detached safety guards.
The merge tree `a5f3b43885611b20edd9ece172b647094e4ebc21` exactly matches the
qualified DV delivery, so the failure does not demonstrate an RTL contract
violation or change earlier qualification inputs/results.

All six complete job logs and per-job dispositions were captured before repair
under `verification/failures/p05-postmerge-checkout-43617402959/`. A regression
exercises the actual staging helper against isolated Git push/PR commit checkouts,
and confirms attached main is still rejected. Its initial fixture omitted Python
cache ignores; that separate light-check failure was preserved before aligning
the fixture with the real repository. No staging check was relaxed.

Local checks pass: repository contracts, 115 light tests, two capture-isolation
tests, doctor on actual merged main, and real staging of that detached main
checkout. The production RTL, checkers, parameters, formal properties, timeouts
and prepared toolchain are unchanged. The focused CI checkout repair PR records
its final hosted validation. Main remains blocked by this configuration defect
until maintainer integration of that repair and a successful subsequent main run;
the original failed attempt is not relabeled PASS.

## Actual integrated-source confirmation

| Input | Actual identity |
| --- | --- |
| GitHub RTL PR #24 merge | `3ede1a5e40791ff00d98a0faa8389154d632e0c5` |
| Current main at confirmation | `3ede1a5e40791ff00d98a0faa8389154d632e0c5` |
| Previously qualified RTL head | `dc7682f16dcdba05b1f2b7d80b1bf11732d17c47` |
| Previous applicability delivery | `c8dfe3d290775eef855dad7937f9ba38e14c3c52` |
| Tested DV commit, after normal main merge | `fd129b1e0d7566c460962b6869aa2274f7a24fa9` |
| Actual combined/test checkout revision | `fd129b1e0d7566c460962b6869aa2274f7a24fa9` |
| Actual combined/test tree | `c1c3033decc4fc1b16aab4702ac9da4714ef2353` |
| Common entire qualified-head/merged-main tree | `6e9b5deaf839a89cc88c9dd8570af02e40fc37e9` |

Main was fetched and the merge identity obtained independently from GitHub.
The actual merge and qualified head have identical complete trees: no production
source, header, public contract, registration or configuration difference exists.
The existing DV branch incorporated main with a normal merge, no shared-history
rewrite, conflict or resolution. The PR diff against merged main is DV-only;
no production or designer source was modified.

The tested checkout also exactly matches the canonical tree from combining the
previous applicability delivery and qualified RTL head. Compared with the prior
actual execution, all 215 audited behavior/configuration files match, including
resolved DUT/formal include closures, profiles, checkers and build/proof settings.
The seven differences are the already-published applicability reports, README,
candidate pin and requirement-evidence metadata. Requirement semantics are unchanged.
Per-file SHA-256, include resolutions and the exact Git comparisons are retained
under `merged_source_confirmation` in the existing evidence index.

| Fresh integrated check | Result |
| --- | --- |
| Prepared doctor on merged main and tested DV checkout | PASS; tool versions, dependency digests and setup stamp unchanged. |
| Repository and light checks | PASS; all 114 light tests, including the public-response check. |
| Actual production confirmation | PASS; I1, both latencies and FIFO depths, seeds 17/31/53 plus seed-17 replay: four builds, sixteen runs, child exit zero. |
| Mandatory bins and old/new trace comparison | PASS; all sixteen trace hashes, counts and functional-bin counts match the original corresponding runs. |
| Saved production coverage | PASS; all sixteen fresh manifests validated against actual source, binary and artifact hashes. |
| Independent reset-aware accounting replay | PASS; all six equations in every fresh trace, with zero outstanding/buffered beats or live cells/descriptors at shutdown. |

The seed-17 runs each accept 500 beats/3,864 bytes, return 261 cells and complete
43 packets. Intentional reset cancellations are counted separately. First valid
is three/four cycles for latency one/two within bounds five/six; all 32 cells are
unreserved at shutdown. Per-seed counts, reset crosses, public stimulus and masked
expected/observed output hashes are in both the full and public reports.

Use the prepared installation's checkout path. Reproduce the actual tested source
by detaching at the recorded tested DV commit, whose history already includes
merged main; its tree must match the table. The executed public command is:

```sh
python3 tools/p05_candidate.py --rtl-revision 3ede1a5e40791ff00d98a0faa8389154d632e0c5 --profile I1 --seed 17 --jobs 2
```

Current candidate/CI selection pins the actual RTL merge SHA and records phase
`merged-source`. The existing CI staging/identity guard validates that integrated
source; it does not silently select the previous candidate. The merge is already
an ancestor of the DV branch, so staging needs no additional candidate merge.
Historical commands remain below for their named source identities.

Input equality retains the original six-profile 96-run matrix, four unbounded
FP-TX proofs, four cover runs with ten covers each, and intended mutation
detections without relabeling old executions. Unaffected local proofs/regressions
were not repeated merely for a new SHA. The separately required ready-for-review
full hosted workflow executes its configured suites as the final integration gate.
Relevant merged-main CI is
[43608539930](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43608539930);
final run conclusions and exact delivery identities are recorded on PR #26.

Fresh local merged-source checks had no failures or RTL defect. The first final
hosted attempt (`43609541413`, delivery `1b22a7d66c494efed9ebe05b93ef954f49ab62b7`)
was interrupted in F0 scheduler by a GitHub worker shutdown, exit 143. All
completed cases in its log passed; unfinished work remains non-success. The full
available job log, annotations and exact-source manual capture are committed
under `verification/failures/p05-merged-ci-scheduler-F0-43609541413.*`. The worker
stopped before even always-upload steps, so private in-flight process artifacts
were unavailable; that evidence limit is explicit. Disposition is tool/environment.
No RTL, expectation, timeout or setup change is made. A fresh required full run
must complete, with the final result recorded on PR #26. The historical preparation-independence caveat remains unresolved;
this result does not establish retroactive provenance acceptance. Safety retains
its reduced FP-TX assumptions and caller/pool composition limits. P12B structural
comparison is separate, and code-coverage closure is not claimed. The maintainer
controls PR #26 integration; this task does not merge it.

## Historical pre-merge verdicts

**PRE-MERGE APPLICABILITY PASS** for refreshed PR #24 head
`dc7682f16dcdba05b1f2b7d80b1bf11732d17c47`. The pre-merge DV gate is satisfied
within the recorded component scope. The mapping and fresh confirmation below
extend applicability; original executions retain their original identities.

**PRE-MERGE CANDIDATE PASS** for production RAM, finite-port metadata and TX at
RTL revision `479b5c1ceee2eee8db58d863bd5de5e20305cc8c`. All required local functional, coverage,
source-fault and reduced production safety checks pass. No RTL defect is
confirmed. Hosted CI remains a separate required integration gate, recorded on
[qualification PR #26](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/26).
All six candidate jobs also pass on hosted run
[43581916024](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43581916024)
at delivery input `90363c81c814ee8a35b97128acb2eb1b1dfb62f3`, including E0 proofs, covers
and mutation qualification. That run exposed the separate exact-set contracts
test defect retained below. The final full gate after its DV-only repair is
recorded on PR #26 without relabeling these executed sources.
The qualification PR remains available for exact merged-source confirmation.
Neither this PR nor [RTL PR #24](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/24) is merged by this task.

The historical preparation provenance qualification remains unchanged. The
current reuse audit checks contractual expected-byte, credit and lifetime
computations against public specifications and observed actions. It does not
retroactively clear the earlier model-author exposure documented in
[the preparation report](P05-fresh-dv-preparation.md) and
[exposure inventory](P05-source-exposure.json).

## Historical refreshed-head applicability

The refreshed candidate incorporates main/repair #25 and changes RTL-author
result records. Independent Git/blob comparison confirms unchanged relevant
inputs; the RTL author's statement and designer test outcomes are not the basis
for this applicability verdict.

| Input | Actual identity |
| --- | --- |
| Original qualified RTL | `479b5c1ceee2eee8db58d863bd5de5e20305cc8c` |
| Refreshed RTL | `dc7682f16dcdba05b1f2b7d80b1bf11732d17c47` |
| Main / repair #25 | `a4df0dd61802355e91b4c0c96e57b79241c86851` |
| Executed DV input | `dc541cd5fe428a1dc7e1f1e175e1dfe1c2fc52dc` |
| Fresh confirmation combined commit | `47080a820dc9fc506a2c2ec85e474387d3c11f39` |
| Fresh confirmation combined tree | `643ecf9d742c16757001845103ba1e70cc79ed53` |
| Original final-delivery combined tree | `2748b19207641bc861dbb3c4aa7733a104f6ea1a` |

The fresh combination is clean, with no conflicts or resolutions. It uses the
existing detached checkout at the prepared installation path; the submitted DV
worktree contains no production RTL. Both combinations can be reconstructed by
locally merging the respective RTL head into the recorded DV input. Generated
merge commit timestamps may differ; the recorded tree must match.

| Independently compared input group | Byte-identical files |
| --- | --- |
| Entire production RTL, including all transitive RTL headers | 19 |
| Public contracts and P05 task card | 17 |
| Registrations, profiles and parameters | 19 |
| DV and formal inputs | 79 |
| Runner, build/proof/setup configuration and workflows | 58 |
| Tests, including the merged interface repair | 36 |

All 228 files match between the original final-delivery combination and the
refreshed combination. Both registered DUT/formal include closures were resolved
and compared. Candidate-to-candidate changes are limited to the two RTL-author
reports and the three already-incorporated repair files. Combined-to-combined,
only `P05-memory-tx-rtl.md` and `.json` differ. No executable, parameter, contract,
checker, assertion, assumption, mutation, compile flag or solver configuration
changed. Tool versions, dependency digests and the prepared setup stamp match
the original evidence. The index records per-file SHA-256 and include mappings;
the public report carries group fingerprints and interface results.

Freshly executed checks all PASS:

- Doctor on current main and the clean refreshed combination; no setup changes.
- Repository contracts and all 114 light tests on the combined checkout,
  including the repaired public-response interface check.
- The published command below: four I1 latency/depth builds and sixteen actual
  production runs (latencies 1/2, depths 4/8, seeds 17/31/53 plus seed-17 replay),
  child exit zero, all mandatory bins and shutdown checks satisfied.
- Saved production coverage validation for all sixteen fresh runs. An independent
  replay of each fresh trace also passes all six reset-aware accounting equations,
  ending with no live cells/descriptors, pending reads or buffered output.

```sh
python3 tools/p05_candidate.py --rtl-revision dc7682f16dcdba05b1f2b7d80b1bf11732d17c47 --profile I1 --seed 17 --jobs 2
```

Each fresh trace hash, count and functional-bin count equals its corresponding
original I1 run. For seed 17, every latency/depth configuration accepts 500 beats
and 3,864 bytes, returns 261 cells and completes 43 packets; reset cancellations
are accounted separately. First valid is three/four cycles for latency one/two,
within bounds five/six; all 32 cells are unreserved at shutdown. Per-seed metrics,
public input/output hashes, exact commands and actual fresh manifests are saved
under the refreshed-head mapping, separate from the original 96-run table.

The unchanged inputs support applicability of the existing six-profile 96-run
matrix, four unbounded safety proofs, four cover runs (ten covers each), and
intended simulation/formal mutation detections. Those unaffected checks were
not rerun merely for the changed SHA. The sixteen new runs are confirmation,
not a relabeled replacement for the original executions. No new unexpected
failure or RTL defect was observed.

The original DV full CI [43582750040](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43582750040)
passed all 34 jobs at the recorded DV delivery. Refreshed RTL full CI
[43591176269](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43591176269)
is independently verified as completed/success at the refreshed head, all 28 jobs
successful. For this evidence/pin-only update, PR #26 stays draft and its persistent
`full-ci` request is removed: light checks validate delivery without mechanically
repeating unchanged heavy suites. This is not a new full-CI execution claim.

There is no new technical blocker to the scoped pre-merge qualification gate.
The historical preparation-independence caveat remains unresolved and still
requires independent review; it is not cleared by input equality or CI. P12B
structural comparison retains its scope. Exact merged-source confirmation is a
separate NOT_RUN follow-up after maintainer integration. Keep #26 open for it;
neither #24 nor #26 is merged here.

## Exact sources and isolation

| Input | Revision |
| --- | --- |
| Main / merged interface repair PR #25 | `a4df0dd61802355e91b4c0c96e57b79241c86851` |
| Exact RTL candidate | `479b5c1ceee2eee8db58d863bd5de5e20305cc8c` |
| Executed functional DV revision | `93eaae785a9ba7c42618c6e4c7c920099405dc85` |
| Executed FP-TX DV revision | `2e81b00d0f6072c8f8f61c8bcf0d7bfcc5ba4b29` |
| Functional combined revision | `2c8f3f1349ab5c89ac3827824a1824144fa003ea` |
| Functional combined tree | `d3bd50047b7775d39a70c0e4cb923d4bcfb4a2d1` |
| FP-TX combined revision | `3f8a6cfaddbbaa23bbbb4afb02903b268b1bc441` |
| FP-TX combined tree | `9aa68fffba67cc225414053afe6f07349d2f3ac3` |

Both combinations had no merge resolutions. The submitted branch is DV-only.
Candidate RTL is present only in the detached combined checkout at the original
prepared installation path; the DV branch has a separate worktree. A symlinked
secondary installation failed doctor and was preserved before relocating source
checkout roles. The unchanged doctor then passed. Setup inputs, locks and stamps
were not edited and tools were not rebuilt.

Later evidence/registry commits retain these actual executed identities. They
do not relabel execution onto a later delivery commit. The
[execution index](P05-candidate-qualification.json) records per-case revisions,
configuration, commands, seeds, source/artifact hashes, counters and coverage.
Every preserved failure has published main/RTL/DV reconstruction inputs; all
canonical recombination trees match the captured source trees.

## Executed component evidence

| Check | Result and boundary |
| --- | --- |
| Actual production execution | PASS: 96 runs across all six named profiles; latencies 1/2, depths 4/8, seeds 17/31/53 and identical seed-17 replay. There are 24 profile-labelled builds and 16 distinct effective parameter configurations because F0/F1 and I0/I1 share base geometry. |
| Physical RAM | PASS: 64-bit logical 1R1W, exact unbackpressured response timing, distinct-word overlap, pending responses during reset and unchanged post-reset readback. Matched-content response digests agree across both latencies/depths. |
| Data/metadata | PASS: keeps 01/03/07/0f/1f/3f/7f/ff, word/cell/MAX edges, fragmented chains, distinct byte patterns, duplicate tags, ignored lanes, all sources/qids, maximum descriptor, both cell-link muxes, every head-info mux and descriptor-next query. Return/completion tuples are checked independently. |
| Credit and stalls | PASS: exact buffered-plus-outstanding capacity, response arrival under stall, simultaneous full-capacity issue/response/retirement, long holds and every cell/packet-final hold. Required bins fail when absent. |
| Ownership/reuse | PASS: earliest next-edge and constrained-random delayed reuse; old payload/link alteration; no tail traversal, early/double returns, overwrite, loss or wrong-owner completion. Actual reads/writes remain on distinct owned words. |
| Reset | PASS: dispatch, pending read, full FIFO, partial cell, cell-final and stalled packet-final phases. Arrays persist; restarted IDs/tags carry distinctive bytes; no stale valid or resource leak remains. |
| End accounting | PASS: frozen oracle and independent ledger finish empty. An observed-trace audit also accounts for physical responses, live arrivals, reset-cancelled pending/buffered beats, bytes, cells and descriptors. All six independent total equations pass in every run. |
| Saved coverage | PASS: all 96 unmutated coverage inputs validate against HDL, adapter/checker, binary, sample and coverage hashes. Numeric line/branch/expression/toggle counts are saved per elaboration; no code-coverage closure or P12B structural comparison is claimed. |
| Source-copy detector qualification | PASS: omitted outstanding credit, premature return and stale-response validity hit their intended simulation and formal detectors. Final-output suppression hits bounded missing-final shutdown. Simulation servers exit normally and the legal neighbor passes; crashes do not qualify. These are expected seeded negatives, not discovered RTL bugs. |
| Standard/affected regressions | PASS: doctor, repository contracts, 114 light tests, two runner capture tests, E0 oracle qualification (20 runner cases), fresh I1 P07/UVM replay qualification (32 runner cases), E0 contracts (76 runner cases including four doctor cases and twelve contract units), and repository lint/compile-error fixtures. Oracle/bench counts each include four doctor cases and remain separate from production execution. |
| Opaque command | PASS: I1 command executed with child exit 0; public stimulus and expected/observed results are retained separately from full DV diagnostics. |

The baseline below is seed 17, latency 1, depth 4. Counts span intentional reset
cancellations; completed packets alone do not describe all dispatched work.
Full per-seed/reset cancellation equations and final restored resources are in
the index. Other seeds and replay pass independently.

| Profile | Accepted beats | Accepted bytes | Cell returns | Completed packets |
| --- | --- | --- | --- | --- |
| F0 | 2976 | 23684 | 392 | 43 |
| F1 | 2976 | 23684 | 392 | 43 |
| I0 | 500 | 3864 | 261 | 43 |
| I1 | 500 | 3864 | 261 | 43 |
| E0 | 298 | 2268 | 159 | 43 |
| E1 | 1003 | 7876 | 268 | 43 |

Always-ready first valid is observed at L+2 cycles (3 for L1; 4 for L2), within
the specified L+4 bound. After fill, accepted-beat gaps and observed cell-boundary
gaps are one cycle in continuously ready packets. The index records readiness
premises, measured extrema and nonzero boundary counts. These are TX-component
measurements; scheduling/admission and whole-top throughput are outside this scope.

## Production FP-TX

All four configurations complete **unbounded k-induction**, with arbitrary sink
stalls and later resets, through the selected Slang/Z3 flow. Maximum induction
search depth is two; this is a completed induction proof, not a two-cycle bounded
claim. N_RX=1, N_Q=2, N_CELL=16, N_DESC=8, CELL_BYTES=16 and MAX_PACKET_BYTES=128
are production-supported formal dimensions. Every legal packet chain prefix
comes from a fresh arbitrary eight-cell permutation captured per dispatch.
Non-tail owned links remain committed; tails and returned links are arbitrary.

| RAM latency | FIFO depth | Safety result | Prove wall time |
| --- | --- | --- | --- |
| 1 | 4 | PROVED | 29.11 s |
| 1 | 8 | PROVED | 81.12 s |
| 2 | 4 | PROVED | 38.52 s |
| 2 | 8 | PROVED | 150.37 s |

Each configuration reaches all ten covers: full credit, full credit with pending
responses, pending sink stall, full exchange, final hold, pending reset, same
ID/tag reuse after pending reset, changed used chain link on a new dispatch,
returned-link alteration and completion. Three L2/depth4 production mutations
produce their intended named counterexamples. Safety has no progressing-sink or
maximum-stall assumption. [The assumption audit](../../formal/tx/README.md)
records the memory/ownership abstraction and asserted correspondence lemmas.
Caller/pool composition and physical RAM structure are not proved by FP-TX.

## Findings and retained limits

All 34 unexpected records are retained:
22 verification defects and
12 tool/environment outcomes.
They cover binding/stimulus/CI defects, candidate-only proof selection leaking into the default storage gate, missing mandatory stimulus, incomplete
induction history, secondary-worktree tool paths, frontend lowering limits and
solver budgets. Source/input/command/output evidence was captured before repair.
The index links each disposition and exact source reconstruction.
Seven additional records preserve intended CLI-negative statuses whose direct
unit invocation exposed a capture-isolation defect. Those negatives now execute
in the existing isolated runner fixture with real capture enabled. They remain
separate from unexpected functional failures and seeded RTL faults.

Earlier SMT timeouts/UNKNOWN and ABC preprocessing failures remain non-success.
They are not silently replaced by a proof claim on their old source. Current
completed proofs use explicit legal-history and response-contract assertions,
not assumptions that suppress hazards. Frozen expected behavior was not changed
to match RTL. No production RTL was repaired; `docs/bugs.md` needs no new RTL
entry for these DV/tool failures.

This is two-state component execution plus reduced unbounded safety. Historical
preparation independence acceptance is not retroactively established. P12B
retains structural comparison. At the original pre-merge execution, exact merged-source confirmation was
NOT_RUN. The actual integrated-source result above completes that follow-up
without changing these original execution identities.

## Historical candidate reproduction and RTL-facing command

Use the prepared installation's original checkout path. In that disposable
checkout, detach at a recorded DV input and merge the named RTL locally. These historical instructions kept
unmerged candidate RTL out of the submitted DV branch. The current branch now
contains merged main, with a DV-only PR diff:

```sh
git fetch origin 2e81b00d0f6072c8f8f61c8bcf0d7bfcc5ba4b29 479b5c1ceee2eee8db58d863bd5de5e20305cc8c
git switch --detach 2e81b00d0f6072c8f8f61c8bcf0d7bfcc5ba4b29
git merge --no-ff 479b5c1ceee2eee8db58d863bd5de5e20305cc8c -m 'test: combine exact P05 candidate'
make doctor
python3 tools/check_repository.py
python3 tools/check_light.py
```

The resulting tree must equal `9aa68fffba67cc225414053afe6f07349d2f3ac3`. At that phase CI performed the
same isolation at its prepared path with `python3 tools/p05_ci.py`. Current CI
selection instead pins the actual merged source as described above.

```sh
python3 tools/p05_candidate.py --rtl-revision 479b5c1ceee2eee8db58d863bd5de5e20305cc8c --profile I1 --seed 17
python3 tools/p05_candidate.py --rtl-revision 479b5c1ceee2eee8db58d863bd5de5e20305cc8c --profile E0 --formal --timeout 600
```

Run the functional entry for F0/F1/I0/I1/E0/E1. Each entry crosses L1/L2 and
D4/D8 with three seeds plus replay. Raw underlying commands are in the execution
index. The wrapper preserves child status; a missing/empty result cannot PASS.
[Public results](P05-candidate-public.json) contain source identities, effective
configuration, seed, interface-level counts and measurements. Per-case semantic
`public-inputs.jsonl`, `public-output-checks.jsonl` and
`public-interface-result.json` hold public stimulus and masked expected/observed
behavior without DV source excerpts. Full stdout/stderr, raw samples, coverage
and counterexamples remain in local/CI DV artifacts. Commands regenerate them
after hosted artifact expiry.

PR #24 now includes the merged interface repair and has passing required CI.
The refreshed-head applicability mapping above satisfies the scoped pre-merge
DV gate. Any further candidate change requires recorded identity and affected retesting.
The maintainer controls RTL integration. Keep qualification PR #26 for final
exact merged-source confirmation before its own merge; neither PR is merged here.
