# P05 exact-candidate qualification

**PRE-MERGE CANDIDATE PASS** for production RAM, finite-port metadata and TX at
RTL revision `479b5c1ceee2eee8db58d863bd5de5e20305cc8c`. All required local functional, coverage,
source-fault and reduced production safety checks pass. No RTL defect is
confirmed. Hosted CI remains a separate required integration gate, recorded on
[qualification PR #26](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/26).
The qualification PR remains available for exact merged-source confirmation.
Neither this PR nor [RTL PR #24](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/24) is merged by this task.

The historical preparation provenance qualification remains unchanged. The
current reuse audit checks contractual expected-byte, credit and lifetime
computations against public specifications and observed actions. It does not
retroactively clear the earlier model-author exposure documented in
[the preparation report](P05-fresh-dv-preparation.md) and
[exposure inventory](P05-source-exposure.json).

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
| Standard/affected regressions | PASS: doctor, repository contracts, 114 light tests, two runner capture tests, E0 oracle qualification (20 runner cases), fresh I1 P07/UVM replay qualification (32 runner cases), and repository lint/compile-error fixtures. Oracle/bench counts each include four doctor cases and remain separate from production execution. |
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

All 32 unexpected records are retained:
20 verification defects and
12 tool/environment outcomes.
They cover binding/stimulus/CI defects, missing mandatory stimulus, incomplete
induction history, secondary-worktree tool paths, frontend lowering limits and
solver budgets. Source/input/command/output evidence was captured before repair.
The index links each disposition and exact source reconstruction.

Earlier SMT timeouts/UNKNOWN and ABC preprocessing failures remain non-success.
They are not silently replaced by a proof claim on their old source. Current
completed proofs use explicit legal-history and response-contract assertions,
not assumptions that suppress hazards. Frozen expected behavior was not changed
to match RTL. No production RTL was repaired; `docs/bugs.md` needs no new RTL
entry for these DV/tool failures.

This is two-state component execution plus reduced unbounded safety. Historical
preparation independence acceptance is not retroactively established. P12B
retains structural comparison. Exact merged-source confirmation is NOT_RUN while
PR #24 is unmerged; that follow-up does not block this pre-merge verdict.

## Exact reproduction and RTL-facing command

Use the prepared installation's original checkout path. In that disposable
checkout, detach at a recorded DV input and merge the named RTL locally. Keep
`verify/p05-dv-qualification` itself free of production RTL:

```sh
git fetch origin 2e81b00d0f6072c8f8f61c8bcf0d7bfcc5ba4b29 479b5c1ceee2eee8db58d863bd5de5e20305cc8c
git switch --detach 2e81b00d0f6072c8f8f61c8bcf0d7bfcc5ba4b29
git merge --no-ff 479b5c1ceee2eee8db58d863bd5de5e20305cc8c -m 'test: combine exact P05 candidate'
make doctor
python3 tools/check_repository.py
python3 tools/check_light.py
```

The resulting tree must equal `9aa68fffba67cc225414053afe6f07349d2f3ac3`. CI performs the
same isolation at its prepared path with `python3 tools/p05_ci.py`.

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

PR #24 must include the merged interface repair and pass its own required CI.
Any changed RTL candidate requires recorded identity and affected retesting.
The maintainer controls RTL integration. Keep qualification PR #26 for final
exact merged-source confirmation before its own merge; neither PR is merged here.
