# P04 scheduler qualification

The production scheduler passes canonical byte DRR and separate packet-RR tests
with actual P03 queues and descriptor links. FP-SCHED safety is proved unboundedly
at a reduced configuration; required covers and the intended extra-quantum
mutation detection pass. Metadata queries and TX retirement are local fixtures.
These results do not establish an integrated payload path or P12 system fairness.

The [compact evidence](P04-scheduler.json) records exact commands, source and
configuration digests, tool identities, seeds, metrics, finite endpoints and
expected-negative identities. Simulation, contracts and P07 fixture tests ran on
clean `2d11b3d25bab931ebcd280a47e12251b8225560a`; formal ran on clean
`ccf85c2ac782843cc09d677e3786f220caee93c4`. The intervening changes affect packet
stimulus and a registration test; the recorded production/formal source hashes
match the delivered sources. Later evidence/documentation commits are not
substitute tested revisions. Work starts from origin/main
`0c65e26cfd81f4f4111e1da00ada2aaa022f2ab0`.

## Executed checks

| Check | Result and boundary |
| --- | --- |
| Production scheduler/queue regression | PASS, E0 and F0, seed 17, both modes; 16 cases per profile including preflight, checker probes and production mutation. |
| Visit arithmetic and interactions | PASS: quanta 64/128/MAX/4096; lengths 1/64/65/MAX; multiple packets per visit, insufficient carry, merged singleton/longer/different-qid updates, busy arrival, true empty/reactivation, readiness and sink stalls. |
| Inclusive credit bound | Real RTL holds 4223 (E0) and 5631 (F0) across readiness stalls without another addition or wrap; all 2/16 qids obtain service. |
| FP-SCHED | PASS, unbounded k-induction in both modes at N_Q=2, N_DESC=8, N_CELL=16, CELL_BYTES=16, MAX_PACKET_BYTES=128. No sink progress assumption. |
| Reachability | All seven DRR and five RR covers reached within depth 16: replacement followed by busy/completion, reactivation, longer/different-qid collisions, readiness wait; DRR additionally reaches carry and continuing visits. |
| Expected seeded defects | Extra quantum on a fitting continuing packet fails production `a_credit` and simulation `SCHEDULE_CREDIT`. P07 bypass/credit/busy/head violations and missing-dispatch timing probes retain their distinct intended detectors. |
| P07 fixture requalification | PASS, E0 seed 17, all 36 cases including replay/diversity, packet constraints and intended negative detections. This remains fixture qualification. |
| Contracts and tooling | PASS, E0 declaration/monitor/option/invalid-parameter and batching/runner checks (76 cases); 73 toolchain unit tests, repository links and whitespace checks. |
| Hosted integration | Final full CI requested on PR #16; no hosted PASS is claimed for the final head in this local record. All six production profiles are registered in the scheduler workflow. |

## Policy and TX ownership

Decisions use pre-state heads/counts/metadata. Current commits affect merged
empty closure without funding a same-edge dispatch. Singleton replacement retains
post-debit credit; a merged zero count clears it before a later activation. The
scheduler freezes scans/additions throughout TX ownership, including the final
handshake edge. A fitting head waits for readiness with no speculative held grant
and no second visit addition. Packet RR rotates after one accepted packet and
elaborates without byte-credit arithmetic.

The existing P07 UVM component models packet lists, static per-queue quanta,
canonical visits and architectural events. It does not read RTL cursor/FSM state
or follow observed grants to create expectations. Illegal-policy checks remain
separate from baseline missing-dispatch timing checks. Independent scalar credit
is compared with production deficits after every edge. Matching simulation
assertions check eligible heads, ownership freeze and bounds. Scanning remains
one queue per free-TX edge; active scanning and lookahead await P09/P10 diagnosis
and an explicit decision.

The isolated simulation mutation sends two one-byte packets with quantum 64.
After the first TX completion, the second dispatch coincides with singleton
replacement, preventing empty-credit discard from hiding the fault. Correct
remaining credit is 62; the mutant adds an extra 64. Qualification requires the
intended first fatal and a nonempty waveform, not a generic crash. Formal also
requires an `a_credit` counterexample and failed engine status.

## Finite byte accounting

Every cycle, starting from the reset epoch's zero deficit, the model checks:

```text
entered_visits * quantum = dispatched_bytes + deficit + cleared_credit
dispatched_bytes = delivered_bytes + unretired_TX_bytes
```

`cleared_credit` records unused credit discarded at true empty closure. It is
zero in the saturated experiments. Entered visits count quantum funding;
`visits0/visits1` in saved endpoint metrics count completed visits. An open visit
must not be mistaken for a completed one.

Each endpoint below follows 160 accepted dispatches with both queues kept
backlogged. Queue 0 has 64-byte packets; queue 1 has 1536-byte packets. The TX
packet at the endpoint has not retired any bytes yet.

| Mode | Quanta q0/q1 | Dispatched q0/q1 | Delivered q0/q1 | Deficits q0/q1 | In flight |
| --- | --- | --- | --- | --- | --- |
| DRR | 1536/1536 | 9856/9216 | 9792/9216 | 896/0 | q0: 64 |
| DRR | 64/128 | 9472/18432 | 9408/18432 | 0/384 | q0: 64 |
| Packet RR | 1536/1536 | 5120/122880 | 5120/121344 | 0/0 | q1: 1536 |
| Packet RR | 64/128 | 5120/122880 | 5120/121344 | 0/0 | q1: 1536 |

These are finite component accounting checks, not a system throughput or
unbounded fairness measurement. Progress tests use a finite, progressing TX
endpoint; no unconditional latency under infinite sink stalls is claimed.

## Coverage scope

Saved coverage closes 22/22 mandatory DRR bins and 13/13 mandatory packet-RR bins
in both E0 and F0. Dimensions include queue-update kind, pre-state TX ownership,
head fit and the first inspected head after a true empty/reactivation. Directed
reactivations exercise below/equal/above-credit heads. All qids are additionally
required to dispatch by the test's observed-service mask.

Three collision × pre-owned-TX bins are impossible: accepted dispatch cannot
occur while TX already owns a packet. The collision creates new ownership;
subsequent busy/completion is covered separately. Packet RR excludes the three
byte-fit bins and six byte-fit/reactivation crosses because it has no deficit
policy. Exact exclusions and raw bin counters are saved in the evidence.

| Owned scheduler RTL counters | E0 DRR | E0 RR | F0 DRR | F0 RR |
| --- | --- | --- | --- | --- |
| Line | 4/4 | 4/4 | 4/4 | 4/4 |
| Branch | 18/18 | 12/12 | 18/18 | 12/12 |
| Expression | 18/18 | 13/13 | 18/18 | 13/13 |
| Toggle | 258/750 | 166/750 | 962/1900 | 451/1900 |

These are Verilator's emitted points for `rtl/scheduler/tm_drr.sv`, not a
whole-design percentage. Toggle holes include unused config fields, fixed
fixture head/source/tag metadata, higher count/length bits, high credit bits on
less heavily exercised qids, and constant-zero RR credit. They remain visible;
no general toggle closure or waiver of future integrated coverage is claimed.
No separate FSM coverage type was emitted. Visit/TX states are checked by policy,
assertions and covers; this is not an FSM coverage signoff.

## Proof and reproduction

[FP-SCHED scope](../../formal/scheduler/README.md) defines the arbitrary-input,
reset, static-quantum and legal queue/query assumptions. Counts 0..2 abstract the
P03 boundary; actual queue/link composition is tested in simulation. No safety
proof assumes a progressing sink. Caller ownership, metadata correctness and
real TX completion remain composition obligations.

Use the selected pinned installation; a fresh setup should use `CXX=g++-14`.
The local existing installation was revalidated after verifying that recipe
executable AST, package/source pins and archived UVM bytes were unchanged from
its recorded successful setup. Current doctor passed. A fresh setup attempt
failed after a compiler-path change discarded CMake's workspace install prefix;
that attempt is retained as TOOL_ERROR, not PASS. Executable hashes and the
revalidation boundary are recorded in the compact evidence.

```sh
CXX=g++-14 python3 tools/run.py regression --profile E0 --test scheduler --seed 17 --jobs 2 --timeout 120
CXX=g++-14 python3 tools/run.py regression --profile F0 --test scheduler --seed 17 --jobs 2 --timeout 120
CXX=g++-14 python3 tools/run.py formal-rtl --test scheduler --timeout 240
CXX=g++-14 python3 tools/run.py regression --profile E0 --test contracts --seed 17 --jobs 2 --timeout 120
CXX=g++-14 python3 tools/run.py regression --profile E0 --test uvm-foundation --seed 17 --jobs 1 --timeout 120
python3 tools/check_repository.py
CXX=g++-14 python3 tools/check_light.py
git diff --check
```

Raw manifests, logs, saved coverage and counterexamples are under `.build/runs/`;
the compact evidence names each run. Hosted scheduler artifacts retain these
outputs by profile. Regenerate them with the commands above after artifacts
expire. Requirement mappings are scoped component results; global requirements
and G2 remain open for the unimplemented integrated packet path.
