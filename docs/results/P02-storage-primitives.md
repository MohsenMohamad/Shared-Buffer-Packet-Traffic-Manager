# P02 storage component evidence

The FIFO and pool portion of G2 has executable local evidence. The cell and
descriptor APIs allocate only the lowest pre-state free ID and merge accepted
allocation/returns once per edge. Invalid/duplicate requests cannot inflate
capacity. This is local storage evidence: **RX/queue/TX/abort descriptor ownership
composition, reservation accounting and integrated packet behavior remain
unproved.** G2 as a whole remains partial.

## Sources and environment

Work started from integrated P01 base
`c493b7b9cd8006078adb8b141c19adafe424a633ed5d`. Final component and compatibility
runs target implementation revision `040863d` (full revision and per-file hashes
are retained in the curated machine-readable evidence). Later changes to this
report, status and requirement annotations do not change the tested RTL or
benches. Some runs overlap those documentation edits and truthfully record a
dirty worktree; tested behavioral hashes are checked against the final sources.

`make setup JOBS=4` installed the repository's locked dependencies without
changing pins or upstream sources. Actual doctor checks passed: Verilator
5.054, Yosys 0.52 at `fee39a3284c90249e1d9684cf6944ffbbcbb8f90`, SBY v0.71,
Z3 4.13.3, OpenSTA 2.0.17 and GCC 14.2.0. Tools ran with two compilation workers
on a workspace limited to two CPU cores and 8 GiB memory.

## Executed results

| Check | Result | Essential scope |
| --- | --- | --- |
| `pools`, E0/I0/E1/F0/F1/I1, seed 17 | PASS: 12 executions | FIFO depths 2/4; cell/descriptor capacities 16/8, 32/16, 64/32 and 1024/256. |
| FP-ALLOC, 16 cells | Proved, unbounded | Production cell API and kernel; 23.25 seconds. |
| Local FP-DESC, 8 descriptors | Proved, unbounded | Production descriptor API and kernel; 5.85 seconds; no controller ownership composition. |
| FIFO depths 2/4, 137-bit beats | Proved, unbounded | Independent queue/order and held-output invariants; 7.19/63.07 seconds. |
| Production covers | All reached | 5 cell, 8 descriptor and 6 covers at each FIFO depth; bounded reachability, not safety. |
| Wrong-delta cell/descriptor mutations | PASS: expected detection | Both fail `a_population` with saved counterexample VCDs. |
| P00 `formal-smoke` | PASS | Original counter prove/cover/expected mutation; remains fixture-only. |
| E0/F0 `contracts` | PASS | Both frontends, 100 intended invalid elaboration rejections and 12 Python contract/routing tests per suite. |
| Runner unit/lint and repository checks | PASS | Orchestration, fixture lint/rejection and document checks; no extra hardware scope. |
| Hosted storage workflow | NOT_RUN | Workflow added; no hosted execution result asserted. |

[P02-storage-primitives.json](P02-storage-primitives.json) curates 13 final runs,
including exact commands, profile/seed, source hashes, elapsed times, expected
negative outcomes, reached cover labels/steps and raw manifest/log hashes.
Curating verifies registered source hashes against the delivered files. The
machine-readable report preserves each case's actual tool status separately
from an expected-negative qualification result.

## Executed component checks

The `pools` suite uses an independent SV queue for full beat data and live-ID
sets/counts for pool ownership. It checks empty/full behavior, blocked actions,
concurrent push/pop, wrap and reuse, disable/drain behavior, held output and
reset collisions. Pool cases exhaust resources, reject allocation funded only
by a same-edge return, exercise one allocation plus two returns, count owned
duplicates once, reject already-free/out-of-range returns and wrong allocation
IDs, preserve valid independent lanes, return every live member and reuse IDs
for 1,200 cycles. Reset covers free, exhausted and active states. Count/error
expectations are checked after every sampled edge.

All selected production profiles run FIFO depths two and four. Pool ID widths
are enlarged by one bit to make invalid encodings observable even at
power-of-two capacities. Functional pool capacities remain supported production
sizes; the profile registry is unchanged. Seed 17 controls the randomized FIFO
source/payload/backpressure portion; pool stress is directed. A source holds its
beat until its actual handshake. No complete packet traffic is generated.

## Proof boundary

The production proof route is separate from `formal-smoke`, which still executes
the P00 counter prove/cover/mutation fixture. Named configurations and property
mapping are documented in [the proof guide](../../formal/pools/README.md).
Pool proofs target the real API wrappers and bitmap kernel at 16 cells/8
descriptors with widened ID encodings. Arbitrary invalid requests remain legal
formal inputs. The only assumption is low reset at the first two sampled edges;
subsequent resets, enable, source/sink stalls and all action inputs are arbitrary.
Yosys `async2sync` models reset at clock boundaries, without analog reset-release
or glitch analysis.

Unbounded pool invariants establish count/population equality, bounds,
free/live complement, lowest-free allocation, unique live allocation, pre-state
return validation, duplicate suppression and sticky errors. Covers include
exhaustion, invalid return, allocation/return, full recovery without reset and
reset while owned; descriptor covers additionally reach two distinct returns,
allocation plus two returns and a duplicate owned return. Cell recovery reaches
step 35, requiring the separate 40-step cover bound.

Wrong-delta experiments change a disposable copy's accepted-return increment
from one to two. Both real pool configurations detect `a_population` with an
actual assertion counterexample and saved VCD; these are **expected negative
checks**, not unexpected production failures. The production source has no
mutation parameter. A tool failure cannot qualify either detector.

The FIFO proof compares occupied circular slots with an independent shift queue,
retaining all 137 data/keep/last/user bits. It checks occupancy, pointer relation,
ready/valid/empty, head order and stalled-output stability. The same stability
claim runs as simulation SVA. Payload storage is unreset. See
[decision 0003](../decisions/0003-storage-primitives.md) for the shared vector-array
representation used by both frontends. Local FIFO order does not prove the
production queue controller or complete payload path.

## Reproduction and artifacts

From the repository root with the toolchain prerequisites:

```sh
make setup JOBS=4
for profile in E0 I0 E1 F0 F1 I1; do
  make regression RUN_ARGS="--profile $profile --test pools --seed 17"
done
make formal-rtl
make test-unit
make lint
make formal-smoke
make regression RUN_ARGS='--profile E0 --test contracts --seed 17'
make regression RUN_ARGS='--profile F0 --test contracts --seed 17'
make repo-check
git diff --check
```

The production formal route defaults to a 240-second per-task timeout. Proof
mode uses unbounded k-induction; its finite induction search is not a bounded
safety claim. Cover mode has a separate 40-step bound. Functional simulation
uses the ordinary 120-second execution/1,200-second build bounds. Builds and
proofs keep independent directories.

Raw manifests under ignored `.build/runs/` retain UTC times, commands, source,
dependency/constraint hashes, versions, results, first failure and separate
logs. Each formal case retains its generated SBY configuration, engine status
and cover/mutation traces. Reproduction regenerates raw artifacts after workspace
expiry. The added storage workflow runs the same commands and retains artifacts
for 14 days; hosted execution is not claimed here.

Initial frontend qualification errors and long-search timeouts are excluded
from final passing evidence. No ignored construct, unavailable tool, empty
selection or timeout is reported as PASS. Verilator provides two-state component
simulation; no X/Z, integrated UVM, full-system formal or mapped TM implementation
result is claimed. Existing capability lint/formal results remain fixture-only.
