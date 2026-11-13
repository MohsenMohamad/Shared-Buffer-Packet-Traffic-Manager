# Independent scheduler DV

Production P03/P04 passes the independent scheduler component qualification in
all six registered profiles, both DRR and packet RR. Seeds 17, 31 and 53 and an
exact seed-17 passive-event replay pass in each mode. Local FP-SCHED safety and
separate conditional bounded-response properties are proved by unbounded
k-induction. Production RTL is unchanged.

[Run 43384557984](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43384557984)
completed successfully. The tested synthetic merge is
`97f4a4640cacfe1b05a0988b139d8ac8cd82c3fe`; PR head
`89a615e0b192e1c3a5a0ad6dcbf5b2a613fdbe51` has the identical Git tree
`468356bb754a5ec510e5c784719be40c84b2f8c8`. Work started from merged main
`395ff2ddb5af9c5cb9ac9b3a703d6e6d64a0f281`. Later evidence/requirement edits
are not substitute tested revisions. The [durable evidence](P04-independent-dv.json)
records tools, pins, source/constraint hashes, parameters, seeds, counts,
coverage, event/artifact hashes, detector identities and raw artifact references.
Historical [author P04 results](P04-scheduler.md) retain their original provenance.

## Executed qualification

| Check | Result and boundary |
| --- | --- |
| Pre-state grants and credit | PASS: old heads/lengths, one quantum per nonempty visit, one debit per accepted dispatch, insufficient-credit retention and merged true-empty clearing. |
| Queue/TX interactions | PASS: singleton replacement, longer/same/different-qid updates, all-qid and sparse activation, cursor-wrap arrivals, completion/commit, insufficient-credit/commit and reactivation at inspection. Busy and final-completion edges freeze scanning/additions; continuing visits resume without a second quantum. |
| Constrained traffic/replay | PASS in E0/I0/I1/E1/F0/F1, both modes, three distinct seeds plus replay; random active subsets, bounded lengths, per-queue quanta, gaps/bursts, readiness and long/final-beat stalls. |
| Finite fairness | PASS assertions: continuously backlogged visit counts differ by at most one; quantum-weighted dispatched-byte shares include deficits. Packet-RR packet counts differ by at most one. In-flight bytes are included in dispatch/delivery accounting. |
| Progress | PASS: explicit simulation visit/round deadlines against quantum 64 with every other queue at 4096. Separate reduced formal 96-clock DRR / 48-clock RR response properties are proved under continuous readiness and retirement within 20 clocks. |
| Lifecycle/input boundary | PASS: drained reconfiguration without reset; funded-visit, pending commit, eligible dispatch, completion and owned-stall reset phases; first new-epoch visit starts at q0 with one quantum. Five invalid-neighbor probes hit their intended diagnostics. |
| Production checker qualification | PASS, intended detections: extra quantum and missing dispatch in both modes across profiles; seven additional scheduler defects at E0. Formal also detects a frozen cursor independently of DUT policy state. |
| Saved coverage | PASS: 22/22 baseline and 26/26 extended DRR bins; 13/13 baseline and 24/24 extended RR bins, per executed profile/seed. Extraction validates exact elaboration/source/artifact identity and mandatory bins. This is component coverage, not system closure. |

## Observed traffic and coverage

Each extended case observes 4,800 random traffic cycles across three configuration
/reset epochs. The following are actual observed commit counts for seeds
**17 / 31 / 53**, excluding the separate directed scenarios. The replay has the
same event SHA-256 and publication count as seed 17.

| Profile | Queues | DRR publications | Packet-RR publications | Inclusive credit bound reached |
| --- | --- | --- | --- | --- |
| E0 | 2 | 101 / 109 / 119 | 116 / 109 / 100 | 4223 |
| I0 | 4 | 102 / 100 / 103 | 102 / 103 / 103 | 4351 |
| I1 | 4 | 102 / 100 / 103 | 102 / 103 / 103 | 4351 |
| E1 | 8 | 126 / 127 / 127 | 132 / 125 / 134 | 4607 |
| F0 | 16 | 783 / 781 / 779 | 777 / 781 / 779 | 5631 |
| F1 | 16 | 783 / 781 / 779 | 777 / 781 / 779 | 5631 |

F1/I1 retain their profile settings; the real RAM/TX latency is not exercised
by this component endpoint.

The P07 constrained packet object supplies legal random packets. Length choices
weight 1, 8, quantum−1/quantum/quantum+1 and MAX, with a uniform legal interior;
a quantum boundary outside 1..MAX uses MAX. Quanta include 64, 4096 and interior
values. Expected packets are reconstructed from observed commit records, not
sequence objects. A positive probe destroys the sequence object's length after
driving the interface; it cannot supply checker expectations.

Extended bins cover simultaneously backlogged queue counts, cursor wrap, all
queues reactivating within a round, quantum/length relation, stall-duration
classes, packets per visit and reset phase × pre-state TX ownership. Impossible
reset/ownership combinations are explicitly excluded; packet RR additionally
excludes a funded byte-credit visit and multiple packets per visit. All other
mandatory counters must be positive. Excluded impossible bins must remain zero.

Production scheduler emitted line/branch/expression points are fully hit in the
baseline elaborations: DRR 4/4, 18/18, 18/18; RR 4/4, 12/12, 13/13. Toggle holes
remain visible per profile/seed in saved coverage; constant fixture metadata,
unused configuration fields, count/credit bits and zero RR credit are not
promoted to toggle closure. No separate FSM coverage type is claimed. Compatible
elaborations are extracted separately; different profiles/modes are not merged.

## Independent policy and accounting

The retained P07 `tm_schedule_checker` derives FIFO packet lists, lengths,
canonical visits, quanta and TX ownership from architectural events. It decides
from the pre-state before appending the current commit. Singleton replacement
preserves post-debit credit; only merged zero closes and clears a dispatched
visit. Grant legality precedes the separate mandatory baseline timing check.
No observed-grant-following or timing-disabling mode is qualified.

The passive component sampler now reconstructs published packets from the
commit API. The retained author formal properties remain at their original
location. The added `scheduler_policy.svh` derives its own cursor, visit, credit
and ownership history. Expected dispatch advances this model; observed grants
and DUT state never supply reference transitions. Assertions compare grant/head
legality, mandatory timing, credit and state history; RTL-state equalities are
induction lemmas, not assumptions or reference inputs.

Within each fixed-quantum accounting window, every checked edge satisfies:

```text
entered_visits * quantum = dispatched_bytes + deficit + discarded_empty_credit
dispatched_bytes = delivered_bytes + unretired_TX_bytes
```

Reconfiguration first checks the old equations, complete drain and zero deficits.
It then begins a new statistical window without resetting queue, cursor or
credit policy state. This preserves the retained fixed-quantum equation while
checking that newly observed quanta fund the next visit. The retained RUN pauses
stress direct scheduler levels; they do not represent legal busy CSR disable
writes. The separate lifecycle case drains, disables, changes quanta and
re-enables without reset.

For the two continuously backlogged queues, let B be dispatched bytes, D the
current deficit and Q the configured quantum. In addition to visit-count
difference ≤1, the checker asserts the finite share bound
`abs(B0*Q1-B1*Q0) <= Q0*Q1+D0*Q1+D1*Q0`. Packet RR instead asserts a packet-count
difference ≤1 and identical queue/length service after swapping quanta.
These are component assertions, not a P12 system fairness measurement.

## Progress proof boundary

Safety allows arbitrary legal queue events, arbitrary readiness, arbitrarily
long TX stalls and later resets. It has no sink-progress assumption. The named
formal elaboration is N_RX=1, N_Q=2, N_DESC=8, N_CELL=16, CELL_BYTES=16 and
MAX_PACKET_BYTES=128; queue counts 0..2 abstract the P03 boundary. Actual P03
queue/link composition is exercised by simulation.

The separate progress task uses continuously backlogged 128-byte heads, quanta
64/128, TX readiness continuously high and accepted-packet retirement within
20 clocks. A cursor round includes both retirement budgets plus dispatch/scan
edges. Two funded q0 visits give the conservative 96-clock DRR deadline; packet
RR needs one visit and has a 48-clock deadline. Both properties are proved by
unbounded k-induction. Both progress covers are reached. Safety reaches all
12 DRR and 8 RR covers by depth 6 within its configured depth 16.

Simulation uses all MAX-byte heads, quantum 64 on q0 and 4096 elsewhere. With
`T=3*ceil(MAX/8)`, a DRR visit funds at most `floor((4096+MAX-1)/MAX)` packets;
packet RR funds one. The round budget is
`N_Q*(2+packets_per_visit*(T+1))`. The q0 head must dispatch within
`ceil((MAX-initial_credit)/64)` funded visits in DRR, or one RR visit; initial
credit is zero in this directed window. The per-round deadline is asserted on
every cycle, independently of the fixture watchdog. At F0/F1 the DRR response
budget is 665472 clocks, below the fixture's one-million-clock watchdog.

A 240-second local DRR progress attempt was inconclusive under concurrent
compilation. The recorded completed local/hosted tasks use 600 seconds; they
retain the same property and assumptions. No bounded result is relabeled as
an unbounded proof.

## Named negative qualification

Each simulation negative requires its intended first fatal and a nonempty
waveform. Formal negatives require engine FAIL, a nonempty trace and the named
base-case assertion; induction-only failures and unrelated crashes do not count.

| Source-copy defect | Intended simulation detector |
| --- | --- |
| Extra quantum on a continuing packet | `SCHEDULE_CREDIT` |
| Omitted dispatch, DRR and packet RR | `SCHEDULE_TIMING` |
| Lost credit after an insufficient visit | `SCHEDULE_CREDIT` |
| Quantum on every readiness-wait cycle | `SCHEDULE_CREDIT` |
| Debit incoming publication's length instead of old head's length | `SCHEDULE_CREDIT` |
| Dispatch during TX ownership | `SCHEDULE_GRANT` |
| Clear credit on singleton replacement | `SCHEDULE_CREDIT` |
| Retain credit on true empty transition | `SCHEDULE_CREDIT` |
| Packet RR fails to advance after dispatch | `SCHEDULE_HEAD` |

Formal continuing-quantum, missing-dispatch and frozen-cursor mutations fail
`a_credit`, `a_policy_timing` and `a_policy_cursor`, respectively. The retained
P07 bypass, credit, head, busy and missing-grant probes keep their separate
policy/timing detectors.

Input probes detect unowned/wrong-descriptor completion with `SCHED_INPUT_DONE`,
already-queued publication with `SCHED_INPUT_COMMIT`, and a running quantum
change with `SCHED_INPUT_CONFIG`. A stale completion after reset is diagnosed
with `SCHED_INPUT_DONE` after checking that the unowned new epoch's queue/credit
state is intact. Filtering stale completions during newly owned work remains
a P09/P11B caller obligation; the component does not promise tolerance of
invalid neighbor actions.

## Reproduction and retained evidence

Use the prepared pinned installation and run `make doctor`; do not rebuild or
replace tools to bypass a mismatch. Exact CI commands are:

```sh
for profile in E0 I0 I1 E1 F0 F1; do
  CXX=g++-14 python3 tools/run.py regression --profile "$profile" --test scheduler --seed 17 --jobs 2 --timeout 240
done
CXX=g++-14 python3 tools/run.py formal-rtl --test scheduler --timeout 600
```

Each regression builds both production modes, runs seeds 17/31/53 and replay,
checks saved counters/hashes and executes the registered negative selections.
Seven additional scheduler mutants run at E0. Extract exact saved cases with:

```sh
python3 tools/run.py coverage --profile E0 --test scheduler --coverage-manifest .build/runs/RUN/scheduler-mode1-stress-17/manifest.json
PYTHONPATH=tools python3 -m unittest discover -s tests/toolchain -p 'test_scheduler*.py'
```

Replace RUN with an actual passing run from the evidence record. The eleven
scheduler evidence tests check intended-detector matching, missing/unhit/
impossible/duplicate bins, source/profile/parameter/artifact mismatch, random
publication consistency, and preservation of result/source identity in exports.
They qualify evidence handling; they do not substitute for production tests.

The `scheduler-summary-PROFILE-97f4a...` artifacts contain compact manifests.
The corresponding `scheduler-PROFILE-97f4a...` artifacts retain raw stdout/stderr,
saved databases, traces and build commands. IDs, hashes and run directories are
in the durable JSON. Regenerate raw artifacts with the commands above after
hosted retention expires. Repository/link, syntax and whitespace checks were
also run; their success is not hardware qualification.

P09/P11B still own real metadata/TX and epoch/caller composition. P09/P10 retain
packet-rate attribution and the reviewed baseline/optimization decision; P12
retains system fairness. Only merge of the passing independent DV PR establishes
its verified acceptance scope. No integrated payload-path or system coverage
closure is claimed here.
