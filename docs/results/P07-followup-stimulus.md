# P07 follow-up qualification in progress

The checker cleanup is qualified separately from the new packet functionality.
The generator/checker candidate is saved for continuation; final-candidate
qualification and review remain incomplete. All results concern the declared
behavioral fixture, not production traffic-manager behavior. P03+ stays paused.

## Completed checks

| Check | Result | Tested source and boundary |
| --- | --- | --- |
| Original E0 foundation suite, seed 17/replay/19 | PASS | Clean `4d557574e7dfe943df81bfa26e0b6cda75bccc75` |
| Cleanup E0 seed 17/replay/19 and I0 seed 23/replay/25 | PASS | Clean `73f1b9dcbab54089c55fd25ef8d772b0c7012503`; all existing positives and intended negatives |
| Cleanup behavior preservation | PASS | E0 observed primary trace is identical before/after: SHA256 `0dea18a5dbe04ed7f49fa4ef63af1b7bf415ca17d7bb9c42305eca8414a27f65` |
| Approved timeout descendant-race fix | PASS | Separate `752bb9a` commit; 16 focused runner tests, then the full runner unit suite |
| Packet/evidence/policy development run | PASS | Dirty E0 base `752bb9a`, seed 17/replay/19 and small quantum; exploratory source, not final candidate |
| Evidence false-pass guards | PASS | Eight tests reject missing/corrupt/duplicate/stale handshakes, wrong statuses, framing/metadata and empty/malformed records |
| Final candidate and expanded profile suites | NOT_RUN | Required before completing the task or marking the PR ready |

The [compact JSON](P07-followup-stimulus.json) retains revisions, dirty flags,
source/dependency digests, metrics, coverage counts, distributions and replay
hashes. Raw manifests/logs/coverage/records/waves remain under the recorded
ignored `.build/` paths. The exploratory development build preceded later
coverage/analysis edits; it is deliberately not relabeled as final execution.

Cleanup negatives all return nonzero with exactly their intended first UVM
fatal and a nonempty waveform: `BYTE_CORRUPTION`, `BYTE_UNEXPECTED` (duplicate
and stale), `BYTE_LOST`, `STATUS_CAUSALITY`, `SERVICE_DATA`,
`ADMISSION_PREDICATE`, `SCHEDULE_HEAD`, `CSR_RESOURCE`, `BATCH_DUPLICATE`,
`BATCH_MISSING`, `BATCH_STALE`, and I0's additional atomic-limit
`ADMISSION_PREDICATE`. These are expected seeded-defect detections.

The new E0 development run also passes nine constraint rejections, five exact
scheduler defect detections, checked-randomization failure detection, recorded
packet/handshake replay/diversity, boundary/keep/port/queue coverage and random
distribution checks. Illegal grants use `SCHEDULE_GRANT`, wrong heads use
`SCHEDULE_HEAD`, and a missing required baseline dispatch uses
`SCHEDULE_TIMING`. Optimized scheduler timing remains unqualified.

## Reproduction and remaining qualification

Use the repository's existing prepared stack; do not use historical tools:

```sh
export CXX=g++-14
source .tools/activate.sh
make doctor
python3 tools/run.py regression --profile E0 --test uvm-foundation --seed 17 --jobs 2 --output .build/p07-final
python3 tools/run.py regression --profile I0 --test uvm-foundation --seed 23 --jobs 2 --output .build/p07-final
python3 tools/run.py regression --profile E1 --test uvm-foundation --seed 29 --jobs 2 --output .build/p07-final
python3 tools/run.py regression --profile F0 --test uvm-foundation --seed 31 --jobs 2 --output .build/p07-final
make regression RUN_ARGS='--profile E0 --test csr --seed 17'
make regression RUN_ARGS='--profile F0 --test csr --seed 17'
make regression RUN_ARGS='--profile E0 --test contracts --seed 17'
make repo-check
make test-unit
python3 -m unittest discover -s tests/contracts -v
```

The CSR suites consume the shared bench package and therefore need an affected
suite rerun. Inspect saved packet bins, per-case stimulus/distribution data,
handshake/stimulus digests and all exact negative identities. Review the final
source, update active completion/status guidance and curate final evidence.
No P08/P03 implementation or production admission RTL is included.
