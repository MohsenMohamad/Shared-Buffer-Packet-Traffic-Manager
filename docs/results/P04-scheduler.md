# P04 scheduler qualification

The production scheduler implements canonical byte DRR and a separate packet-RR
elaboration. Validation targets the scheduler with real P03 queue/link modules;
metadata queries and the packet-granular TX endpoint are test fixtures. This is
not a proof of the future integrated TX payload path or P12 system fairness.

## Contract and verification boundary

The scheduler decides from registered heads/counts/metadata. Current commits
only affect merged empty closure. A singleton replacement retains post-debit
credit; a true empty transition clears it before a later activation. TX ownership
blocks all scans and additions, including the completion edge. A fitting head
waits for readiness without another visit addition. Packet RR rotates after one
accepted packet and has no byte-credit arithmetic.

The existing P07 UVM checker uses packet lists, static per-queue quanta, canonical
visit state and architectural events. Policy legality and baseline missing-grant
timing remain separate detectors. Finite accounting uses
`added = dispatched + deficit + cleared` and
`dispatched = delivered + in_flight`; for a continuously backlogged interval
`cleared=0`. Idle-credit discard must not be counted as service. In-flight bytes
are the unretired remainder of the TX-owned packet.

FP-SCHED targets production RTL with abstract legal P03 queue/query transitions.
Safety assumes legal static quanta, valid selected lengths, count transitions
and stable heads until removal. No safety task assumes a progressing sink.
Simulation composes actual queues with the independent packet model. Directed
progress checks use a finite, ready TX endpoint; they are not an unbounded
liveness proof.

## Reproduction

```sh
make regression RUN_ARGS='--profile E0 --test scheduler --seed 17'
make regression RUN_ARGS='--profile F0 --test scheduler --seed 17'
make formal-rtl RUN_ARGS='--test scheduler --timeout 240'
python3 tools/check_repository.py
python3 tools/check_light.py
```

Both modes run for each selected production profile. The scheduler workflow runs
the suite at all six production sizes and includes FP-SCHED. The raw
run manifests, logs, coverage and counterexamples live under `.build/runs/` and
are retained by hosted CI.

## Results

Implementation qualification is in progress. Final results, tested source
identity, tool versions and coverage scope are recorded before review readiness.
