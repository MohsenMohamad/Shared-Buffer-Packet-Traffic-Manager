# Memory/TX independent baseline checkpoint

This baseline self-checks a spec-derived passive oracle and the first directed
traces. Production memory/metadata/TX simulation, UVM integration, formal proofs,
performance and mandatory production coverage are **NOT_RUN**. This is the
baseline checkpoint; candidate qualification resumes with steps 3–9 of the
assigned work. P12B retains the structural memory comparison.

## Source and independence boundary

The baseline starts at `origin/main` commit
`8d66a92768f2c72236171731262563814e875352` (including PR #19).
The first policy commit `47084d4` is independently cherry-pickable by RTL,
without waiting for tests. Documentation stays in
[DV PR #20](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/20)
on `verify/packet-store-tx`.

The oracle was written from [interfaces](../spec/interfaces.md),
[buffer management](../spec/buffer-management.md),
[module contracts](../spec/module-contracts.md),
[verification](../spec/verification.md) and [formal](../spec/formal.md), including
the referenced [TX timing contract](../spec/queues-and-scheduling.md#output-engine-backpressure-and-completion).
The P05 card was read after those contracts. No target/dependency RTL, designer
results or retained checker internals were inspected before this baseline commit.
Existing repository/light checks were executed without inspecting their checkers.

[The model](../../dv/model/memory_tx.py) imports only the Python standard library.
[The first tests](../../dv/tests/test_memory_tx_baseline.py) use sealed `Edge`
monitor batches, not UVM driver packet handles, DUT cursors or DUT free counts.
Python provides the offline oracle; existing UVM agents/monitors remain the
required production execution path on resume. There is no replacement bench or
new runner. Baseline direct invocation does not register a production suite.

## Model and environment contract

The local RX/queue environment supplies observed descriptor reservations, cell
allocations, link writes, payload writes and commits. Physical ownership is an
independent ID-to-descriptor map; cells are ordered by observed allocations.
Dispatch metadata are cross-checked against reservation metadata. The local
queue is one ordered commit stream; multi-queue scheduling remains P03/P04/P09
composition. The model does not implement RX admission, abort cleanup or pool
priority selection and does not claim to discharge their contracts.

RAM is 64-bit 1R1W, at most one of each action per sealed edge. Address is
`cell*CELL_WORDS+offset`. The memory response is due exactly at issue edge plus
one/two, has no ready, and compares against the monitored write value at issue.
Same-word read/write is rejected, regardless of any RAM collision semantics.
Expected packet bytes are frozen from monitored writes at commit, with byte zero
in bits 7:0. Accepted output is compared in packet order; keep, last and all user
bits are exact, and only valid data lanes are compared. A held output compares
all data bits, including unused lanes, for stability.

The oracle computes buffered plus current-epoch outstanding credit itself. A
response merely moves a credit from pending to buffered. Only accepted output
returns a slot; same-edge acceptance can fund one new read. It models no
response-to-output combinational bypass. Output data, cell returns, descriptor
returns and completion are distinct observations; a missing/extra return fails.
A cell returns exactly on its last externally accepted beat, the descriptor and
`done` exactly on packet EOF. Next-link capture must be independently witnessed
on an earlier edge before return; links are checked against allocation order.
A returned physical ID becomes allocatable on the following edge.

Reset spans at least two rising edges. The first released edge initializes;
new work can start at the next edge. Ownership, packets, buffered entries,
response validity and completion expectations are flushed. RAM and its physical
response schedule persist. Old-epoch responses are consumed/discarded, never
added to valid output credit. New traffic rewrites its own data; RAM is not
cleared to make stale-response checks pass. The production adapter must also
check control/reset signals outside this oracle's boundary.

## Risk/check/cover matrix

`Self-check` below refers only to synthetic monitor traces. Every production
row remains NOT_RUN until the named candidate checks execute and mandatory bins
are observed; neither a RAM fixture nor a coverage percentage closes P05.

| Risk / requirement | Independent check / named detector | Required observed cases / next campaign |
| --- | --- | --- |
| Response loss, wrong latency/data; MEM-03 | Issue-time RAM snapshot; `MTX_RESPONSE_LATENCY`, `MTX_MEMORY_DATA` | Self-check: latency 1/2. Production: actual 64-bit 1R1W store, simultaneous distinct owned read/write, finite metadata mux ports |
| Lane reversal, partial final beat; LEN-01/02, IF-03 | Monitored bytes and immutable metadata; `MTX_OUTPUT_BYTES/FRAMING/METADATA` | Self-check: 9/17-byte literals, unused lanes, duplicate tags. Production: keeps 1–8; 1/7/8/9, cell−1/cell/cell+1, MAX−1/MAX, single/multi-cell |
| Omitted outstanding credit; MEM-04 | Pre-state buffered+pending−accepted+issued ≤ depth; `MTX_OVERISSUE`, `MTX_FIFO_OVERWRITE` | Self-check: latency 1/2 × depth 4/8, exact-full pending stall through arrival, issue+response+retire, long/final stalls; missing trigger fails `MTX_MISSING_PRESSURE` |
| Early/wrong/double cell return; MEM-05 | External beat ordinal and allocation order; `MTX_CELL_RETIREMENT`, `MTX_LINK_BEFORE_RETURN` | Self-check: cell-final stall after prefetch, delayed EOF, captured next link, earliest following-edge reuse. Production: each boundary, reuse/collision/retirement crosses |
| Early/missing/duplicate completion, leaks | Accepted EOF and independent owner sets; `MTX_COMPLETION`, `MTX_RESOURCE_LEAK`, `MTX_DESC_REUSE` | Self-check: exact normal completion/resource restoration. Production: pool/descriptor integration and exactly-once completion under concurrency |
| Output changes during stall; IF-01 | Complete prior held beat; `MTX_STABILITY` | Self-check: boundary/final hold and named changed-bit rejection. Production: data/keep/last/user across pending response and full FIFO |
| Old response validates new epoch; RST-01/02 | Epoch on issued requests; `MTX_OUTPUT_WITHOUT_RESPONSE`, `MTX_RESET_CONTROL` | Self-check: pending reset at both latencies, unchanged RAM and new distinctive same-ID/tag packet. Production: dispatch/full FIFO/partial cell/stalled-last resets, exact pool restoration |
| Wrong pre-state ownership / collision; MEM-01/03 | Independently reconstructed owned IDs, write phase and read order; `MTX_CELL_REUSE`, `MTX_WRITE_OWNER`, `MTX_PAYLOAD_COLLISION` | Self-check: normal and earliest legal reuse. Production: no same-edge free bypass, forbidden payload collisions and simultaneous distinct-owned-word R/W |
| Random hazards missed / replay | Saved monitor trace, occupancy/outstanding/latency/retirement/reset crosses | NOT_RUN: constrained chains/lengths, independent sink stalls, legal reuse; directed cases remain mandatory |
| First-valid delay / cell bubbles; PERF-01 | Dispatch/valid/accepted timestamps, ready assumptions | NOT_RUN: latency+4 first-valid bound, one beat/clock after fill, zero cell-boundary bubble for CELL_WORDS≥2 |
| Vacuous or constrained-away safety; FP-TX | Production safety with arbitrary sink stalls and explicit memory contracts, F01 explicit inputs | NOT_RUN: unbounded credit/retirement/stability/reset, full-credit/pending-stall/reset-reuse covers; outstanding omission, premature return and stale-valid mutations must hit named detectors |
| False PASS / incomplete registration | Requirement links, nonempty executed production selections, saved bins and antecedent/constraint audit | NOT_RUN: memory-tx simulation/proof/coverage registration; retain all real failures under PR #19 rules and before/fix/retest evidence |

## Hand calculations and results

| Trace | Hand-calculated expectation | Baseline outcome |
| --- | --- | --- |
| Normal, 9 bytes, cell 3 | Address 6 gives `0706050403020100`, address 7 lane 0 gives `08`; bytes 00…08; keeps FF/01; EOF only second beat; user `011234000903` | PASS at latencies 1/2 |
| Boundary, 17 bytes, cells 3→1 | Reads 6,7,2; bytes 00…10; keeps FF/FF/01; cell 3 returns on beat 2 acceptance, cell 1 and descriptor on beat 3 | PASS at latencies 1/2; cell 3 reused on first legal following edge before old EOF |
| Exact capacity | D issued, zero retired gives D credits. After responses: D buffered, zero outstanding. One accepted plus one issued keeps D; response arrival alone releases zero | PASS at (L,D)=(1,4),(1,8),(2,4),(2,8); every case requires full-credit, pending-response-stall and issue/response/retire hits |
| Pending-response reset | One issued read is canceled as TX work; old RAM value remains. New same-ID packet emits only bytes 90…97 after initialization | PASS at latencies 1/2 |
| Deliberate invalid traces | Reverse valid bytes, early cell return, read D+1, response too soon, changed held bit, stale output after reset, corrupt response, wrong keep/user, leaked resources and omitted pressure trigger | Expected detections at eleven exact named detectors; no engine/crash surrogate |

Five unittest methods cover ten positive parameterized traces and eleven expected
negative detections. These results qualify the oracle's initial behavior only;
production seeded-defect qualification remains NOT_RUN.

## Reproduction and source pairing

Use the prepared environment; setup/install is not part of these commands.
On the recorded main base, `make doctor` passed versions, source identity, C++20
and solver SAT/UNSAT checks. On the policy commit, repository checks and light
checks passed (99 tests). On the baseline revision, run:

```sh
python3 -m unittest discover -s dv/tests -p test_memory_tx_baseline.py -v
python3 tools/check_repository.py
python3 tools/check_light.py
git diff --check
```

The baseline commit contains the exact model/tests/commands; no random seed or
HDL tool is used by the Python self-check. See the companion
[execution record](P05-memory-tx-baseline.json) for actual tested revisions,
source hashes, command statuses and tool identities. The initial repository
check found the then-missing execution-record link; its
[capture](../../verification/failures/memory-tx-baseline-missing-record.json)
preserves the source and diagnostic before completing the record. The repaired
repository check passes; this was a documentation defect, not an RTL failure.

For candidate qualification, record the named RTL and DV SHAs before assembling
an isolated worktree. One reproducible assembly, when changes are separate and
do not overlap, is:

```sh
git worktree add --detach ../packet-store-tx-qualification "$RTL_SHA"
git -C ../packet-store-tx-qualification cherry-pick "$DV_BASELINE_SHA"
git -C ../packet-store-tx-qualification rev-parse HEAD
git -C ../packet-store-tx-qualification status --porcelain
```

Set both variables to recorded full commit IDs, include every later DV commit
in dependency order, and record the assembly commands/resulting SHA/dirty state.
If conflicts arise, retain the resolution as part of tested source. Independent DV qualifies the paired
candidate, then verifies the actual merged source under the root policy.

Resume with a named production RTL candidate and this committed DV baseline;
inspect candidate boundaries and retained checker reuse only after the checkpoint.
Connect passive sampling through existing UVM and implement remaining matrix rows
without downgrading any technical obligation. There is currently no P05 RTL
candidate branch/PR available. Stop here until candidate qualification is resumed.
