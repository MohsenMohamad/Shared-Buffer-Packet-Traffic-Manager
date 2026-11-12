# P07 readable checkers and constrained packet stimulus

The P07 follow-up passes checker, packet-generator and replay qualification on
the declared behavioral fixture. This completes the follow-up candidate before
P08; it does not validate a production traffic-manager datapath. P03+ remains
paused, and no production RTL is changed.

## Tested sources and results

Checker cleanup was committed separately at
`73f1b9dcbab54089c55fd25ef8d772b0c7012503` and qualified before packet functionality.
The original baseline is clean `4d557574e7dfe943df81bfa26e0b6cda75bccc75`.
E0's primary observed trace is identical before/after cleanup: SHA256
`0dea18a5dbe04ed7f49fa4ef63af1b7bf415ca17d7bb9c42305eca8414a27f65`.

Local final foundation runs use clean `6cf7a55` for E0/F0 and clean `e0b32b9`
for I0/E1. The latter changes timeout classification and checker indentation.
`6397a2a` additionally completes shared CSR header registration.
[Hosted run 43256790591](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43256790591)
passes all 21 jobs at merge-ref
`58591e7ff55b9b66a215c149426b9b38720e65a2`, whose Git tree is verified identical
to head `6397a2ad7937ed1ec955d72d5ddb1b8fefbb64c2`.
Later documentation commits do not replace these tested revisions.

| Qualification | Result | Boundary |
| --- | --- | --- |
| Cleanup E0/I0 | PASS | Existing positives, small quantum, replay and every applicable intended negative |
| Expanded E0/I0/E1/F0 suites | PASS: 150 cases, including 75 expected detections | Genuine UVM agents, monitors, models, constraint probes and declared fixture |
| Packet constraints | PASS: legal generation and nine UNSAT checks per profile | Reject zero/oversize length, invalid source/qid, empty keep, inconsistent counts, pattern and gap |
| Recorded stimulus and coverage | PASS | Exact accepted inputs, valid output bytes, dispositions, boundaries, distributions and saved bins checked |
| Replay/diversity | PASS | Primary/replay stimulus and handshake hashes match; alternate seed changes both; same pinned stack only |
| Affected CSR suites | PASS | Local E0 plus all six hosted profiles; 64-bit counters, 8-bit rollover and intended coupling detection |
| Runner/contract tests | PASS: 53/12 tests | Includes eight evidence guards and the approved timeout-race regression |
| Hosted CI | PASS: all 21 jobs | Also includes existing contracts, storage, capability and production-component proof gates |

The [compact JSON](P07-followup-stimulus.json) retains actual revisions/dirty
flags, source/dependency/configuration digests, tool identities, commands, case
catalogs, first-fatal identities, waveform hashes, coverage counts, distributions
and replay hashes. Raw execution data remain build/CI artifacts. Exploratory dirty
runs and rejected development builds are excluded from accepted qualification.

## Independent checking and expected detections

The cleanup separates capture/status collection, pre-state decisions, releases,
merged credit updates and conservation checks. Captured beats still cannot fund
same-cycle registered-FIFO service; returns cannot fund same-cycle admission.
Only the complete-cycle coordinator calls models. Expected bytes remain derived
from observed input handshakes, with epoch/source/ordinal identity and duplicate
tags. Existing reset, simultaneous-update and malformed cases still execute.

Each applicable original negative passes only with its exact first UVM fatal,
nonzero process status and nonempty waveform, both after cleanup and in the
expanded final suites:

| Seeded defect | Intended first fatal |
| --- | --- |
| Corrupted payload | `BYTE_CORRUPTION` |
| Duplicate delivery | `BYTE_UNEXPECTED` |
| Lost delivery | `BYTE_LOST` |
| Wrong status | `STATUS_CAUSALITY` |
| Wrong serviced beat | `SERVICE_DATA` |
| Wrong admission decision | `ADMISSION_PREDICATE` |
| Wrong scheduled head | `SCHEDULE_HEAD` |
| Stale post-reset output | `BYTE_UNEXPECTED` |
| Wrong resource CSR | `CSR_RESOURCE` |
| Duplicate/missing/stale callbacks | `BATCH_DUPLICATE` / `BATCH_MISSING` / `BATCH_STALE` |
| Optimistic same-cycle admission | `ADMISSION_PREDICATE`; requires at least two source ports |

New isolated scheduler probes reject empty-queue bypass, insufficient credit
and dispatch while TX is busy at `SCHEDULE_GRANT`; wrong head/order at
`SCHEDULE_HEAD`; and a missing required baseline dispatch at `SCHEDULE_TIMING`.
The positive probe checks credit carry, merged last-pop/commit, TX freeze and
true-empty closure. Checked randomization failure stops at `PACKET_RANDOMIZE`
before any item is sent. These are expected seeded-defect detections, not
naturally discovered production bugs.

Policy state advances from independently expected heads/visits, never from
observed grants. Baseline timing is explicit: one queue inspection per free-TX
edge, with inspection resuming after final output handshake. There is no
permissive grant-following mode; optimized scheduler timing remains unqualified.

## Recorded packet evidence

`tm_packet` uses SV `rand` fields, weighted length classes, inline constraints,
`solve before` and checked `randomize()` results. Packet constraints relate length
to beat/cell counts and final keep; conversion constructs payload/last/metadata
and supplies raw items to the existing agents. The qualified modern stack
supports these features directly. Raw items remain unrestricted for malformed
traffic. The sufficient no-DPI frontdoor configuration is retained; no new
framework, backdoor or optional service dependency is introduced.

Each packet case separately records nine boundary packets, eight final keep
widths, a profile-lane sweep, 128 random packets and ten directed controls.
The controls cover invalid qid, zero/oversize header length, sparse/empty/partial/
wrong-final keep, early/late last, and ignored non-SOP metadata. Their statuses
are exactly `1,2,2,6,6,6,6,6,6,0`. Legal constraints are never disabled to create
these cases. Existing directed source controls are preserved.

| Primary run | Seed / alternate | Recorded packets | Captured / output beats | Random length-class counts (0/1/2/3) | Saved owned functional bins hit/total |
| --- | --- | ---: | ---: | --- | ---: |
| E0 | 17 / 19 | 157 | 717 / 699 | 32 / 25 / 20 / 51 | 46 / 50 |
| I0 | 23 / 25 | 159 | 1,558 / 1,540 | 29 / 38 / 15 / 46 | 58 / 63 |
| E1 | 29 / 31 | 163 | 3,338 / 3,320 | 26 / 37 / 18 / 47 | 94 / 101 |
| F0 | 31 / 33 | 171 | 9,224 / 9,206 | 29 / 32 / 16 / 51 | 136 / 149 |

Classes weight word boundaries, cell boundaries, maximum boundaries and the full
legal range in a 2:2:1:3 ratio. Fixed broad envelopes reject collapsed class,
pattern and gap distributions; every random source/qid must occur. The JSON also
records actual random length, cell-count and final-width histograms. Forced
coverage is kept separate from random distributions; uniform solver output is
not assumed.

The passive collector and saved counters account for all legal observed frames,
including the directed metadata case. Every required packet source, qid, length
boundary and final keep-width bin is nonzero. Broader foundation bins and code
points remain unhit and visible in raw coverage; coverage closure is not claimed.
`stimulus.jsonl` contains configurations and emitted beats; `handshakes.jsonl`
contains passive accepted input/output/status observations. Neither supplies UVM
checker expectations. Both records are hashed for replay and seed diversity.

The generator is paced below resource pressure. Original concurrent traffic,
reset epochs, barrier ordering and atomic resource probes remain separate checks.
These results do not establish production WAIT admission, RAM timing, concurrent
abort traversal, scheduler fairness/performance, X propagation or integrated
requirement closure.

## Affected CSR and timeout regression

The shared bench package is also compiled by CSR suites, with all new headers
registered in that source set. Saved E0/F0 CSR coverage was inspected directly:
all 12 mandatory AW/W-order × stall × concurrent-read bins are nonzero. E0 records
565 reads/540 writes and 17 reduced-width rollovers; hosted F0 records
1,195/1,184 and 21 rollovers. Each has 17 snapshots, two collisions, two clears
and three resets with pending channels. Both intended coupling negatives stop
at `CSR_AW_W_INDEPENDENCE` with nonzero status and a waveform. Hosted I0/I1/E1/F1
CSR suites also pass.

The separate approved `752bb9a` fix addresses the
[main-run failure](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43220856538/job/131191959645):
`/proc/<pid>/stat` is read directly, and `FileNotFoundError`/`ProcessLookupError`
mean the child exited. Live-child and unexpected-read-error checks remain.
The focused regression forces both disappearance races, checks live/zombie
states and preserves unexpected exceptions. Current local and hosted unit suites
pass; no default-branch history is changed.

## Reproduction and retention

Use the repository-selected installation, with the locks in
`tools/dependencies.json` and `tools/packages.lock.json`:

```sh
export CXX=g++-14
source .tools/activate.sh
make doctor
python3 tools/run.py regression --profile E0 --test uvm-foundation --seed 17 --jobs 1 --output .build/p07-final
python3 tools/run.py regression --profile I0 --test uvm-foundation --seed 23 --jobs 1 --output .build/p07-final
python3 tools/run.py regression --profile E1 --test uvm-foundation --seed 29 --jobs 1 --output .build/p07-final
python3 tools/run.py regression --profile F0 --test uvm-foundation --seed 31 --jobs 1 --output .build/p07-final
python3 tools/run.py regression --profile E0 --test csr --seed 17 --jobs 1 --output .build/p07-affected
make regression RUN_ARGS='--profile F0 --test csr --seed 17'
make regression RUN_ARGS='--profile E0 --test contracts --seed 17'
make repo-check
make test-unit
python3 -m unittest discover -s tests/contracts -v
```

The last F0/contract commands reproduce checks executed in hosted CI rather than
a duplicate local run. Cleanup reproduction uses `73f1b9d` and the same E0/I0
commands with `.build/p07-clean-commit`; original E0 uses `4d55757` and
`.build/p07-before`. Fetch the recorded revisions before historical replay.
Compilation, seeds, configurations and failures remain separate case manifests.

Raw local data are under the recorded ignored `.build/p07-*` directories.
[CI artifacts](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43256790591)
retain logs, records, coverage and waves for 14 days. The downloaded F0 CSR
archive was inspected and hashed; its artifact ID and measurements are in the
JSON. Regenerate expired artifacts using the tested revision and commands above.
