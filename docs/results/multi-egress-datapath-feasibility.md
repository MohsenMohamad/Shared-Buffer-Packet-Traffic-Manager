# Multi-egress datapath feasibility

The primary 4×4 cycle model met the balanced fixed-permutation beat-rate
target at read latencies of one and two for repeated 60-, 65-, and 1,536-byte
frames and the specified repeating length mixture. The candidate uses one
512-bit cell read and one 512-bit cell write per cycle, four staging cells per
ingress and six prefetch cells per egress. The [multi-egress contract](../spec/multi-egress-traffic-manager.md) specifies its edge
behavior. The [queue/control prerequisite](../implementation/plan.md#next-assignment-and-queuecontrol-prerequisite)
covers physical metadata realization and timing before freezing dependent RTL.

## Sustained demand

For each legal frame length `L` from 60 through 1,536, a dense stream transfers
`B(L)=ceil(L/8)` beats and produces or consumes `C(L)=ceil(L/64)` cells per
frame. At sustained line-side beat rate with back-to-back frames, each
direction needs at most `4*C(L)/B(L)` cell accesses per cycle for four
streams of that length. For arbitrary length mixtures the per-stream ratio
is a beat-count-weighted average of `C(L)/B(L)`, so the maximum applies
independently in each direction. Simultaneous RX and TX need independent
write and read service. The analysis assumes a single clock, no framing
overhead beats, unicast and one cell write/read per cell.

The one-cell region (60–64 bytes) needs 1/2 access per cycle per direction.
For every region containing `k >= 2` cells, the maximum is
`4*k / (8*(k-1)+1)`. It decreases strictly with `k` and is first reached
at lengths 65–72, where two cells cross in nine beats per stream. The
peak sustained demand is **8/9 read and 8/9 write per cycle**. At 1,536
bytes the ratio is 1/2 again. This average leaves no guarantee about
staging, request overlap, or cell availability at the next beat deadline.

## Workloads and reproduction

The [Python model](../../tools/multi_egress_feasibility.py) uses static per-queue
limits of 1,024 cells, a shared pool of 1,024 cells and 256 descriptors,
packet RR, and the candidate's finite ports and edge ordering. It charges
whole-frame credit at ordered header service, services up to four ingress
beats and captures up to four per cycle, grants one cell write and one
cell read, and publishes at most one descriptor on the next edge after a
final write. A pre-edge head lookup and independent pop per egress are
available every cycle. It accounts for at most four normal cell/descriptor
returns and one independent abort grant per edge, with returns applied
after the reservation decision. Response latency is fixed and credits
cover pending and resident prefetch cells through acceptance. Descriptor
and cell occupancy are counted, while physical ID selection, data bytes,
link array contents, and the logic implementing port availability are
abstracted. The study does not exercise RTL, α, DRR, shaping, ECN or reset.

All four sources start at edge 0 and offer one beat per cycle when allowed,
holding the current offer when blocked. Balanced routes map ingress `i`
to egress `(i+1) mod 4`, use class 0 and keep all sinks ready from edge 0.
Run aligned repeated 60, 65 and 1,536-byte lengths, then repeat the sequence
`60,65,1536,64,129,1518,61,513` in lockstep. A supplemental permutation run
starts the mixture at a different sequence position for each ingress.
Warm up for 2,048 edges, then measure the next 9,216 edges without changing
the traffic. After the window finish any already offered frame, stop new
offers, drain and check per-source capture, rejection/abort, publication and
delivery totals and pool recovery. Account for accepted beats, useful bytes
from valid lanes, ingress and egress TLASTs, commits, backpressure, ready
idle cycles, peak occupancy and drops separately. Window counts can include
different frame boundaries at the two interfaces.

| Separate case | Deterministic input and check |
| --- | --- |
| One bounded sink stall | Aligned mixture with egress 0 unready at offsets 32–63 of each 256 cycles. The other egresses sustain their balanced rate and admitted packets drain. |
| Incast DROP | All ingress streams target egress 0, one class per ingress, with repeated 60 or 1,536-byte frames. Observe descriptor exhaustion for short frames and cell-credit exhaustion for long frames; the output stays busy and every rejection is accounted. |
| Incast WAIT | The 60-byte incast with temporarily blocked headers retained; all input ports make progress under this ready pattern, and all offered frames finish after the source cutoff. |
| Synchronized returns | Hold each egress on its first final beat, then release all when they have reached it and edge 64 has passed or arrived. Check four accepted cell and descriptor returns and four concurrent dispatches. Aligned short packets also bring four final cells to write arbitration together. |
| Cleanup contention | Every eighth frame at ingresses 0 and 1 is declared as 1,536 bytes and marked malformed on serviced beat 130. Remaining beats drain. Observe concurrent aborts, an abort-cell return sharing an edge with TX cell returns, and recovery of both reservations. The two unaffected egresses sustain line-side delivery. |

All runs use deterministic inputs, with no random seed. From the repository root:

```sh
python3 tools/multi_egress_feasibility.py --expect-gate
for depth in 1 2 3; do
  python3 tools/multi_egress_feasibility.py --case balanced --assembly "$depth"
done
for depth in 1 2 3 4 5; do
  python3 tools/multi_egress_feasibility.py --case balanced --prefetch "$depth"
done
python3 tools/multi_egress_feasibility.py --case balanced --assembly 2 --prefetch 3 --expect-gate
make repo-check
python3 tools/check_light.py
PYTHONPATH=tools python3 -m unittest discover -s tests/runner -v
git diff --check
git diff --check origin/main...HEAD
```

## Balanced model results

Identical window counts at both latencies. Traffic figures are per active
port. Peaks are over the whole run across all four ports, with the larger
peak of the two latencies shown.

| Frame sequence | Accepted / delivered beats | Accepted / delivered useful bytes | Captured / committed / delivered frames | Peak reserved credits / physical cells / descriptors |
| --- | ---: | ---: | ---: | ---: |
| 60 | 9,216 / 9,216 | 69,120 / 69,120 | 1,152 / 1,152 / 1,152 | 12 / 8 / 12 |
| 65 | 9,216 / 9,216 | 66,560 / 66,560 | 1,024 / 1,024 / 1,024 | 27 / 16 / 14 |
| 1,536 | 9,216 / 9,216 | 73,728 / 73,728 | 48 / 48 / 48 | 196 / 100 / 12 |
| Aligned mixture | 9,216 / 9,216 | 73,181 / 73,165 | 147 / 147 / 149 | 204 / 108 / 24 |

Each run had one accepted and one delivered beat per port per cycle, zero
input stalls, zero ready-but-idle egress cycles and zero drops. After drain,
the captured, committed and delivered counts per source matched at
1,408, 1,252, 59 and 182 for the four rows respectively. The phased
mixture also reached one beat per port per cycle with zero stalls or drops.

Four ready write lanes contend in aligned cases. At 65 bytes, the two
arrivals per ingress on adjacent edges require up to seven cycles from
staging to the cell write, including the one-cycle visibility delay.
The maximum wait from continuously eligible read request to grant was
three cycles. The measured post-edge response flight depth was one or
two globally according to latency. Balanced per-ingress assembly occupancy
peaked at three with the candidate depth, and per-egress prefetch occupancy
peaked at six. Following a transfer, compare the next cell's first usable
edge (`issue+latency+1`) with its no-bubble deadline (previous transfer
edge plus one). The minimum margin was four cycles within a frame and
**zero cycles at a frame boundary** across the aligned workload set.

One assembly cell per ingress first fails at ingress staging. The aligned
65-byte burst caused 2,304 input stall cycles per ingress per window, even
with six prefetch cells. With four assembly cells, prefetch depths one and
two fail on output, with no input stalls for aligned 65 bytes. Two prefetch
cells at latency two left 1,676 otherwise-ready cycles per egress without
deliverable data for that workload. The observed fix is staging and earlier
read overlap; the shared memory service rate supports the tested workload.
The smallest passing balanced pair in this sweep was **two assembly cells
and three prefetch cells per port**, tested together at both latencies.
Four and six retain room for workload and implementation variation. These
are empirical depths for the measured schedules; there is no all-traffic
minimum or guaranteed margin for extra metadata stages. Shared occupancy
peaks refer to the tested 1,024-cell/256-descriptor configuration and are
not a minimum shared-pool size.

## Stress model results

Latency-two measurements are below. At latency one, the gating outcomes
and the reported stall/incast totals match. Natural boundary offsets in the
cleanup case change its affected-egress counts slightly.

| Case | Accepted / delivered beats | Useful bytes accepted / delivered | Window frames captured / committed / delivered | Stalls and rejects | Peak credit / physical cells / descriptors |
| --- | --- | --- | --- | --- | ---: |
| Bounded egress 0 stall | 9,216 per ingress; 8,064 on egress 0, 9,216 elsewhere | 73,181 per ingress; 64,025 on egress 0, 73,165 elsewhere | 147 per ingress; 147 per ingress; 131 on egress 0, 149 elsewhere | 1,152 sink-stall cycles on egress 0; zero input stalls and rejects | 381 / 288 / 46 |
| DROP, 60 | 9,216 per ingress; 9,216 on egress 0 | 69,120 per ingress; 69,120 on egress 0 | 1,152 and 288 per ingress; 1,152 on egress 0 | Zero input stalls; 864 descriptor rejects per ingress | 256 / 255 / 256 |
| DROP, 1,536 | 9,216 per ingress; 9,216 on egress 0 | 73,728 per ingress; 73,728 on egress 0 | 48 per ingress; 14/15/15/14 committed; 48 delivered | Zero input stalls; 35/34/33/35 cell-credit rejects | 1,009 / 985 / 43 |
| WAIT, 60 | 2,304 per ingress; 9,216 on egress 0 | 17,280 per ingress; 69,120 on egress 0 | 288 captured and committed per ingress; 1,152 delivered | 6,912 input stall cycles per ingress; zero rejects | 256 / 255 / 256 |

The returns case reproduced four-way retirement and dispatch at both
latencies. The cleanup case had two pending aborts and an abort-cell return
sharing an edge with up to two accepted TX-cell returns. At latency two it
delivered 9,216/2,277/2,278/9,216 beats and
66,560/16,445/16,446/66,560 useful bytes per egress. There were 36 format
aborts per affected ingress in the window and 45 each after drain, with no
resource rejects. The normal streams continued to publish and deliver.
After drain, all cases matched captured frames to their outcomes and
restored the pools.

Read/write progress uses rotating arbitration among continuously eligible
ports. Retirement and release of shared credit rely on sinks accepting
beats. The bounded-stall case has adequate shared credit for its **finite**
window. Indefinitely extending that overload can exhaust the pools.
Dedicated rotating cleanup grants allow abort recovery during TX returns
and even while the source is still draining. No finite WAIT service bound
follows if credit only becomes intermittently available or a destination
never resumes.

## Source and validation scope

The branch baseline is Step 1 merge
`cf08ec7ee9b742540786376d2052987f08ca42a5` (PR #28).
The study uses Python 3.12.14 with no external dependencies. Resource sizes,
workloads, latencies and command switches above define the measured scope.
Synthesis, STA, production throughput, independent DV and formal qualification
for the multi-egress design remain NOT_RUN.

### Original execution

The model, depth sweep and repository checks ran on clean commit
`a2690790b91f9ad1c15cdad912636a536673d36b`. In that checkout the model and
its Python commands use `tools/tm_v2_feasibility.py` (SHA-256
`4388baacd0aa1b54b4494bdf50ea71c9ac9b493a6ffb2b7e5ab88e88802e95f7`).
The candidate and minimum-pair commands passed. The deliberately reduced
configurations produced the recorded gate misses. Repository contracts,
117 Python tests and syntax checks, two runner isolation tests, and whitespace
checks passed.
