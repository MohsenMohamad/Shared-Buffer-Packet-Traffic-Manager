# Multi-egress traffic manager

The traffic manager (TM) is single-clock, store-and-forward and unicast. In
the primary 4×4 profile, four independent 64-bit ingress streams feed four
independent 64-bit egress streams through shared cell and descriptor pools.
Classification, FCS removal and insertion, and applying ECN to packet bytes
are external. PFC requests,
probabilistic marking/WRED, multicast and cut-through are outside this contract.

The [specification index](README.md) identifies which design each contract
applies to. The [implementation plan](../implementation/plan.md#multi-egress-migration-and-gates)
defines the implementation entry and acceptance gates. The [public interface](multi-egress-interfaces.md)
defines packed declarations, observation lanes and the CSR address map.

## Profiles and target

| Parameter | Primary functional profile | Small implementation and proof profile |
| --- | --- | --- |
| Ingress / egress / classes per egress | 4 / 4 / 4 | 2 / 2 / 4 |
| Stream width / cell width | 64 bits / 512 bits | 64 bits / 512 bits |
| Cell pool / descriptor pool | 1,024 cells (64 KiB) / 256 | 16 cells (1 KiB) / 8 |
| Declared frame length | 60–1,536 bytes | 60–192 bytes |
| Fixed cell-read latency | 1 or 2 cycles | 1 or 2 cycles |
| Local staging per ingress | 2 captured beats, 4 cells including assembly, 8 disposition records | Same |
| Local prefetch per egress | 6 cells including outstanding reads and the cell being serialized; 2 frame slots | Same |

Ingress IDs, egress IDs and queue control width scale with the profile. The small
profile retains port contention, partial tails, multiple queues, stalls, aborts
and same-edge returns. It omits four-way fan-in, the long-frame tail and
primary-size resource selection and mux depth. Further reduced proofs must
identify their parameter restrictions and assumptions. Small-profile timing
and proofs apply within their reported boundaries.

The base target is one accepted beat per active ingress and one delivered beat per
active egress per cycle in the sustained, balanced fixed-permutation test. The
sources offer dense streams with successive packets starting on the next beat,
each sink is always ready, shaping is disabled, admission has adequate capacity
and packet RR supplies work-conserving selection. All frames in the test must
commit and deliver exactly once across warm-up, measurement and drain. The
[acceptance runs and accounting](../results/multi-egress-datapath-feasibility.md#workloads-and-reproduction)
define the input sequences and reporting. Mixed destinations, shaping, downstream
stalls and incast have separate checks.

## Streams and framing

All edges and handshakes refer to rising core-clock edges. Stream and status
outputs depend on registered state, apart from asynchronous reset gating.
Capture occurs only on valid and ready. A source holds the full offered beat
stable until capture and may insert gaps. Frames cannot interleave within a
port. Each byte
uses lane `i` at bits `8*i +: 8`, with the earliest byte in lane 0. Valid frame
bytes include Ethernet headers and pad, with FCS removed. Padding is part of
the declared count. Preamble and interframe gap are outside the TM.

The first captured beat at a frame boundary carries a 16-bit declared byte
length, 8-bit destination egress, 8-bit class, 16-bit opaque tag and 2-bit
original ECN metadata. Later input metadata is ignored. The next captured beat
after an accepted external `TLAST` starts a new frame; a source that omits that
boundary cannot announce a new frame by changing metadata. Class 0–3 maps to
`qid = 4 * egress + class`. Out-of-range egress or class is rejected before any
queue lookup. Tags may repeat. Egress presents destination, class, length, tag,
original ECN, ingress ID and a mark-request bit on every beat. Unused lanes are
unspecified.

Let `b = ceil(length/8)`. A valid frame has `b` beats, full keep on beats 1
through `b-1`, and `TLAST` only on beat `b`. Final keep equals
`(1 << (((length-1) % 8)+1)) - 1` in eight bits. A length outside the profile
is rejected. Early or missing `TLAST` and wrong keep are framing errors after
admission, including on the first serviced beat. Validate each beat before it
enters assembly. Discard through the next serviced `TLAST`, counting the
offending beat itself as the boundary if it carries `TLAST`. A bad header
takes its header error disposition even if its framing is also malformed.

The registered ingress FIFO may capture a first beat before admission. First
payload service requires a successful whole-frame reservation on the same or an
earlier edge. Header rejection services the beat as discard and allocates
nothing. A format-aborted frame stops new assembly and enters cleanup. Drain
and cleanup run independently, and the next frame on that ingress needs both
to complete. A missing future `TLAST` holds just that ingress in drain until
reset or a boundary arrives. Cleanup can release its entire reservation before
that boundary.

Each ingress emits an unbackpressured disposition pulse with original route,
class, length and tag. Records are allocated in ingress header-service order
and presented in that order, at most one pulse per ingress per cycle. A record
becomes ready after the edge that rejects the header, publishes a good frame,
or completes format-abort cleanup. Emit the first ready record at the next
eligible edge. Reject and abort status do not wait for drain. Backpressure a
new header locally if its disposition slot is unavailable after that edge's
status pop. Codes are `COMMITTED=0`, `BAD_ROUTE=1`, `BAD_LENGTH=2`,
`QUEUE_LIMIT=3`, `NO_DESCRIPTOR=4`, `NO_CELLS=5`, `FRAME_ERROR=6`.

## Admission and conservation

`U` is unreserved cell credit, `D` is the free-descriptor count and `H[q]`
counts queue-owned reservation credit, including RX, queued, dispatched and
aborting frames. A good header for length `L` consumes `n = ceil(L/64)`
credits and one unique free descriptor atomically. Static mode requires
`H[q]+n <= LIMIT[q]`, with each limit in cells in `[0,N_CELL]`. Static limits
may sum to more than the pool size; both shared pools always apply.

Dynamic mode configures integer protected minima `M[q]` in cells with
`sum(M) <= N_CELL`. `alpha[q] = A[q]/256`, with unsigned integer
`A[q]` in `[0,4096]`. Evaluate each candidate against the pre-edge state
after earlier reservations in the same batch, before returns:

```text
P = sum(max(0, M[j] - H[j])) over all queues j
S = U - P
E = max(0, H[q] - M[q])
E_next = max(0, H[q] + n - M[q])
x = E_next - E
S_next = S - x
```

With sufficient total credit and a descriptor, `x=0` fits the protected
minimum. For `x>0`, require `S_next >= 0` and
`E_next <= floor(A[q] * S_next / 256)`. Use widened nonnegative arithmetic
and round down once after multiplication. The post-reservation threshold affects
new decisions only. Later changes to shared free credit never evict a frame.
Minimums protect cells; the descriptor pool has no protected allocation.

Up to one header per ingress is considered in a cycle. Visit eligible capture
FIFO heads in rotating port order, starting at port 0 after reset. Each
successful reservation updates the prefix credit, queue occupancy and
descriptor selection seen by later headers. A failed request consumes no
credit. Advance the cursor to the port after the first serviced header decision
in the batch; retain it on an empty batch. Same-edge returns are reusable
starting on the following edge. Cell and descriptor allocation need only pick
a unique pre-edge-free ID, with no numeric ordering requirement.

Decision precedence is `BAD_ROUTE`, `BAD_LENGTH`, permanently impossible
`QUEUE_LIMIT`, `NO_DESCRIPTOR`, `NO_CELLS`, then temporary `QUEUE_LIMIT`.
A queue request is permanently impossible if its test fails with all queues
empty, full shared capacity and free descriptors. Static and dynamic tests in
that state use the configured limits/minima. DROP rejects temporary shortages
and drains. WAIT keeps resource-blocked heads pending, including a valid header
that lost to the batch prefix. WAIT always rejects invalid or permanently
impossible headers. A first beat with valid metadata can reserve then abort on
the same edge, without materializing a cell.

At every edge let `A_phys` be assigned physical cells and `R` be physically
free but reserved cells. Enforce
`N_CELL = A_phys + U + R = U + sum(H)`.
Each physical cell and each descriptor has exactly one owner. Cells assigned
to an aborting frame remain assigned until reclaimed. Accounting uses widened
sums of all same-edge deltas:

| Event | Δ assigned cells | Δ reserved free cells | Δ U | Δ H[q] |
| --- | ---: | ---: | ---: | ---: |
| Reserve n | 0 | +n | −n | +n |
| Write one reserved cell | +1 | −1 | 0 | 0 |
| Retire one accepted output cell | −1 | 0 | +1 | −1 |
| Physically reclaim one abort cell | −1 | +1 | 0 | 0 |
| Finish abort cleanup of n credits | 0 | −n | +n | −n |

Descriptor ownership moves through free, RX, queued, bound TX or abort. It is
returned on accepted final output beat or completed abort cleanup. A prefetched
copy is not another owner. Aborted physical cells return immediately to the
free-ID pool on the following edge, while credit stays reserved until cleanup
completes. A recycled ID may serve a different already-reserved frame.

## Datapath and ordered events

- **Beat service.** Each ingress may capture and service one beat per edge.
  Registered capture visibility starts at the next edge. Captured beats go to
  that ingress's assembly; cells are staged in ingress order, including across
  frame boundaries. Local capacity includes partial assembly. A local staging
  pop may exchange with a push on the same edge. A good final beat closes
  assembly and the ingress may service the next header before the final write
  or publication. Each staged cell carries its owning receive context.
- **Cell write.** Write at most one complete 512-bit cell per edge, selected
  by work-conserving rotating ingress arbitration over staged cells visible at
  the start of the edge. Advance the cursor past the granted port. Assign
  the physical address and extend its frame's link on that edge. The memory
  ports are independent and ownership forbids same-address read/write. A
  pre-edge write grant for a valid prefix may complete when a later beat marks
  its frame aborted. Include that cell in cleanup and invalidate all unwritten
  staging of that frame before the next arbitration.
- **Publication.** The edge after a good final cell write publishes its
  descriptor and emits the enqueue event. One registered publication slot can
  pop and take the next final write on the same edge. A final write cannot
  wait for a scheduler grant. The global final-write grant orders competing
  completions; queues are FIFO by publication. The new descriptor is visible
  for selection on the following edge. Cells and descriptors remain reserved
  throughout publication and dispatch.
- **Queue updates.** Each egress can dispatch one descriptor from its pre-edge
  queue heads. Apply a same-edge append and pop as one update. A pop of the sole
  old entry plus a push leaves the push as both head and tail; a pop of a
  non-last entry follows the old successor and appends to the old tail. An
  empty queue cannot dispatch a same-edge publication. The active bitmap equals
  the merged nonempty state. An egress dispatch owns the frame exclusively until
  final transfer and serializes frames in its binding order across classes.
- **Read and response.** Issue at most one 512-bit read per edge with rotating
  arbitration across eligible egresses. Per egress, issue the oldest bound
  frame's next unread cell before reading for its successor. Capture the next
  link at issue except on the last cell. An issue at edge `t` produces a
  mandatory tagged response at `t+L`, visible to TX starting at `t+L+1`.
  Reserve a local prefetch slot at issue for the response through acceptance of
  that cell's last beat. Eligibility uses pre-edge slot credit. Never let a
  stalled port consume slots from another egress. Output can serialize from a
  complete prefetched cell starting at its first beat and presents all fields
  unchanged while valid and stalled.
- **Retirement and cleanup.** Retire a cell only on acceptance of its last
  valid beat and retire a descriptor only on acceptance of the final frame
  beat. Up to four egresses may return a cell and descriptor on the same edge.
  A dedicated rotating abort service can return one further cell and finish
  at most one abort per edge, independently of TX. Start cleanup no earlier
  than the edge after abort marking. It may finish on the edge of its last
  abort-cell return, or on its first grant for zero cells. Cell credit and
  descriptor return atomically at cleanup completion.

| Control or storage resource | Primary candidate service and organization |
| --- | --- |
| Payload | One shared synchronous 512-bit read and one shared 512-bit write per cycle, fixed response latency with no response backpressure |
| Cell links | Register array with one append write, one TX link lookup and one separate abort link lookup per cycle |
| Descriptor information | One publication write per cycle, one metadata read mux per queue head, up to 16 concurrent head reads |
| Queue links and state | Descriptor-indexed link registers sharded by egress; one append-link write globally, one successor lookup per egress, merged queue registers |
| Pools and accounting | One cell allocation, up to five cell returns, up to four descriptor allocations and five descriptor returns per cycle; prefix grants and merged register deltas |
| Local staging and prefetch | Per-ingress cell assembly/staging and per-egress response/retirement storage sized by profile; independently serviced, with one response routed globally per cycle |

These are finite service assumptions for the candidate. The plan gates use of
the wide register muxes, update lanes and assumed latencies on queue/control
feasibility. With functioning storage, each continuously eligible cell request
is served within four arbitration edges in the primary profile. Each marked
abort gets a service grant within four edges while it is pending, including
under coincident TX returns. A marked frame with `k` assigned cells finishes
cleanup within `4*max(1,k)` edges after marking, independently of drain or
sink progress. A permanently stalled egress retains only its own
local prefetch and bound frames, but shared credits can fill with traffic
destined there. It cannot directly stall arbitration, drain, service or delivery
elsewhere. New admissions elsewhere still require both pools and their queue
policy. A WAIT request progresses only if its complete reservation becomes
available on its turn; scarce intermittent credit or an indefinitely stalled
sink gives no unconditional admission bound.

## Scheduling, lookahead and shaping

Each egress keeps its own active-queue bitmap and rotating class cursor,
initialized to zero. Packet RR is the next eligible class in rotation with
advance after each dispatch. Pure DRR uses byte quantum `64..4096` per queue
(default maximum frame length) and byte deficit. Strict-priority plus DRR
selects the configured high class ahead of the other classes whenever that
head is eligible. Strict service leaves lower-class visit state untouched.
A continuously eligible high class can starve lower classes. A cap can create
opportunities when the high head lacks tokens and lower heads fit, provided
the port bucket and sink permit service. The cap alone gives no unconditional
lower-class rate or latency guarantee.

A binding opportunity exists if no frame is bound, or if only the active frame
is bound and at most 16 beats of it remain unaccepted at the start of the edge.
Pure metadata preparation during the current frame may generate a tentative
choice without changing ownership, queue state, deficits or tokens. Reevaluate
with current pre-edge heads and token eligibility at binding. A newly visible
high head can supersede tentative low work. Dispatch is binding: pop the head,
place it in the active or next slot, and then permit its payload read on a
subsequent edge. A bound successor remains binding through stalls and later
high arrivals. When the active frame retires, the bound successor is first
eligible to emit on the following edge.

In DRR, inspect one token-eligible active queue at each binding opportunity,
starting with the current visit if still eligible, then in cursor order.
Skip empty and token-blocked classes. On a new visit add one quantum. If the
head fits, dispatch and debit the full declared byte length on that edge.
Retain the visit and set the cursor to that class if more entries remain.
On true emptiness, clear the visit and advance past that class. If the head
fails to fit,
end the visit, keep its deficit, advance to the next class and try again at a
later binding opportunity. In pure DRR with no shaping this is canonical byte
DRR with merged-queue emptiness. A temporarily token-blocked open visit parks
without adding credit; move to the next class and keep that visit's state.
Resume a parked visit without a second quantum. If the merged queue is empty,
close its visit and clear deficit. Close a visit only once at insufficient
deficit or true emptiness. Initialize credits to zero; bound the deficit by
`4096 + MAX_FRAME_BYTES - 1`. No visits or charges occur with both slots full.
With sufficient tokens, a progressing sink and finite head length, positive
quanta allow a backlogged class in the DRR set to earn service; strict traffic
must leave binding opportunities for that set.

Each queue and egress port has an independently enabled maximum-rate bucket.
Rate is unsigned Q16.16 bytes per core cycle in `[0,8]`; an enabled bucket
requires positive rate and integer capacity between `MAX_FRAME_BYTES` and
65,535 **bytes**. Compare the enabled buckets' pre-edge balances against the
whole frame length. Require both to fit. Atomically debit that length from both
enabled buckets on the dispatch edge. Then refill all enabled buckets by their
configured rate and saturate at capacity. Initialize enabled balances to full
on RUN enable. The debit is made once even if no output beat transfers on the
dispatch edge; stalls do not refund or repeat it. The rate envelope applies to
bytes bound in an interval, at most capacity plus elapsed refill. Delivered
bytes can include up to two previously bound frames beyond that envelope per
egress, or per queue on its egress. This packet-granular shaper allows bursts
after backpressure.

## ECN, control and counters

ECN marking is enabled per queue with a threshold of 1 through `N_CELL`
cells. Sample pre-publication-edge `H[q]`, including this frame's reservation,
other RX and queued frames, and unreleased TX/abort credit. Same-edge
reservations and returns affect the next sample. With marking enabled and
`H[q] >= threshold`, request CE for ECT(0) (`10`) and ECT(1) (`01`).
Not-ECT (`00`) and already CE (`11`) never request a change. Rejected or
aborted frames have no output mark. Preserve original ECN metadata and packet
bytes; external integration applies an asserted request before sending the
frame onward.

The 32-bit AXI4-Lite slave accepts independent AW and W, with one outstanding
write and one outstanding read. It presents a stable response within three
core cycles of the completed request, and holds it until handshake. Reads
sample pre-edge register state. Configuration provides global RUN and DROP/WAIT,
static/dynamic admission, per-queue limits/minimum/α, quanta, queue bucket and
ECN settings, and per-egress mode, strict class and port bucket. Reset selects
RUN=0, DROP/static, full per-queue static limits, zero minima/α, pure DRR
with default quanta, and disabled marking and buckets (valid inactive bucket
settings use max-frame capacity and rate 8). Change policy only with RUN=0
and idle. A write disabling RUN requires idle, including no captured data,
blocked headers, drain contexts, statuses or internal work. A malformed stream
stuck in drain can be recovered by reset. Validate merged byte strobes and
cross-field ranges atomically. Misaligned mapped accesses and invalid or
read-only writes return SLVERR. Unmapped addresses return DECERR. A zero-strobe
mapped write succeeds without changes. The [CSR map](multi-egress-interfaces.md#axi4-lite-register-map)
defines addresses, field encodings and error precedence.

Counters are 64-bit unsigned and saturating. Per ingress port and class,
count captured beats/valid bytes, captured TLASTs, admissions, publications,
and each rejection/abort disposition once, with an unclassified bucket for
invalid class. Attribute capture counters with the frame's first-captured
class, counting set keep lanes even on discarded input. Count each outcome
at its decision, publication or completed cleanup edge. For a valid route,
per queue track the admission/publication/disposition outcomes plus
dispatches, retired frames/bytes and mark requests. Expose instantaneous
`H`, queue depth in committed descriptors, and high-water values updated from
merged edge state. Per egress count accepted beats/bytes/frames. Count
`valid && !ready` and `ready && !valid` cycles separately while RUN is enabled.
Count accepted bytes by keep population and frames by accepted TLAST. Report
global free cell credit, physical free cells and free descriptors. For any
counter with multiple contributors, sum the event increments before saturation.
Provide a software-triggered atomic snapshot of pre-edge counters and
occupancies for coherent split reads. Snapshot has no effect on live
counters. Reset clears counters and snapshot. No control or status consumer can
backpressure datapath events.

## Reset epochs and observation

Assert common active-low reset asynchronously and hold it across at least two
rising edges. The environment releases it synchronously. Packet ready, output
valid, disposition valid and AXI response valid are low during reset, with no
memory write or request accepted. Reset discards FIFO contents, partial and
staged cells, descriptors, queues, admission/cleanup/scheduler state, buckets,
statistics and unfinished bus operations. RAM and stale link contents may
persist. Clear response tags/validity or distinguish epochs so any pre-reset
response, including one physically arriving after release, cannot alter
prefetch, counters or credits. Initialize free pools and control state by the
first edge after release and keep packet capture disabled until initialized
and RUN is enabled. No pre-reset packet or disposition is emitted in the new
epoch. Stream partners reestablish packet boundaries on reset release.

Expose verification events for ingress service and ordered admission vectors,
cell allocations and writes, publication, dispatch, read issue/response with
epoch and identity, abort mark/cleanup, accepted cell returns and descriptor
reclaims. Include port, qid and relevant owner identity and reason. Bundle an
edge's full event set and presence bits. Independent monitors check against the
external stream and bus handshakes, including captured-but-unserviced data and
status timing. Byte comparison ignores invalid lanes and uses ingress frame
identity and published order, including repeated tags.
