# Implementation plan

Task cards define assignments; [specifications](../spec/README.md) define behavior.
Use the committed working/documentation rules and the actual current source tree.
Completion of a fixture or local proof does not close an integrated gate.

## Multi-egress migration and gates

The active design started at the Step 1 merge
`cf08ec7ee9b742540786376d2052987f08ca42a5` (PR #28). The
[multi-egress contract](../spec/multi-egress-traffic-manager.md) selects one
shared 512-bit read and one shared 512-bit write per cycle, with independent
ingress staging and egress prefetch. The
[cycle model](../results/multi-egress-datapath-feasibility.md) met
the primary 4×4 balanced fixed-permutation target at both modeled read latencies
for repeated 60-, 65-, and 1,536-byte frames and the specified repeating length
mixture. Queue/control realization and independent hardware acceptance are open.

| Area | Active design and required evidence |
| --- | --- |
| Resource pools | Prove widened cell and descriptor selection, exact merges and no bypass. Use the public geometry and qualify distinct old IDs, reservation ownership and cleanup. |
| Queues | Preserve FIFO order by publication. Check concurrent egress pops, merged active bitmaps, singleton replacement and pre-edge successor visibility. |
| Scheduler | Qualify per-egress byte DRR, packet round robin, strict priority, shaping visits, token buckets and successor binding. |
| Memory and TX | Qualify one shared 512-bit read and write per edge, per-egress prefetch and successor state, both read latencies, backpressure, reset epochs and simultaneous returns. |
| Registers | Qualify decoupled AW/W, controls and snapshots, and count simultaneous datapath events coherently. |
| Ingress and admission | Check framing, prefix-ordered reservations, protected capacity, independent drain and dedicated cleanup. |
| Timing | Use the reset convention and measure the actual selection and consumer paths at both geometry sizes before architecture freeze. |

### Public declarations and queue/control prerequisite

The [public declarations](../spec/multi-egress-interfaces.md) define the stream,
event-batch, memory, profile and CSR boundaries. Run the separately registered
`make multi-egress-declarations` fixture gate before consuming a declaration change.
Independent DV prepares and freezes expectations from the public declarations
and behavior contract. Queue/control analysis can use the declarations and the
feasibility study. Production RTL and independent DV retain separate owners,
branches and PRs under the [root role policy](../../AGENTS.md#separate-rtl-and-independent-dv-ownership).

**Queue/control feasibility is a prerequisite for freezing the dependent
multi-egress queue, allocator and datapath microarchitecture.** Demonstrate
a finite organization for one publication per edge, four pre-edge scheduler
selections and dispatches, simultaneous enqueue/pop with active-bitmap maintenance, and
the specified descriptor and cell return vectors including cleanup. Include
actual link/head read muxes or equivalent head caching, concurrent counter
deltas, and four prefix-ordered admission decisions with distinct pre-state
descriptor IDs. Work through same-queue updates, full/empty exchanges, and
concurrent admissions with a reclamation burst. Show bounded abort and read
service under their stated assumptions. Use a cycle-accurate prototype or
equivalent edge-level analysis including real metadata latency. Characterize
representative mapped queue, admission and allocation paths at small and
primary control sizes under R01 constraints. If the concrete design needs
extra stages, re-run the balanced target with those stages and document an
accepted change to buffering, scheduling or memory organization before
committing dependent RTL. Keep the primary capacity and throughput workload.

The [control timing follow-up](../results/TM04-control-timing.md) updates the
[queue/control experiment](../results/TM04-queue-control.md). The balanced
same-edge admission map meets setup and hold in the primary profile with
runtime-selectable modes. Buffer splits clear capacitance in the isolated
primary admission, cached-head and cell-control fixtures. Composed maps
still need load repair. Physical reset remains conditional on the source
and distribution. The cached-head organization meets the
balanced beat target at both latencies. The staged admission organization
misses that target with the published buffering. Keep the freeze gate open
pending the remaining reset and integration characterization.

The [composed timing study](../results/TM04-composed-timing.md) closes slew,
capacitance and data timing in its bounded fixtures with buffer-only
repairs. The [queue/control decision](../decisions/0010-multi-egress-queue-control.md#composed-control-disposition)
keeps the freeze gate open for reset ownership and remaining integration
timing.

Also replay independent legal frame-length streams on all four inputs under
the same fixed one-to-one routing. The supplemental review probe used default
buffers, `random.Random(104729 + ingress_id)` per ingress, and uniform choices
from `(60, 64, 65, 72, 129, 1536)`. In the same 9,216-cycle window it had one
ready-but-idle egress cycle at read latency one and two at latency two, with
zero input stalls and zero frame loss after drain. The next frame's first
cell was still pending at each missed boundary. Diagnose and replay those
boundaries in the concrete timing study. The balanced fixed-permutation
workloads above remain the acceptance gate.

### Multi-egress integration and release acceptance

- **SV/UVM.** Independently score bytes, framing, metadata, order and
  dispositions from passive ingress/egress/control monitors. Cross-check
  ordered trace batches and credit deltas against observed handshakes and a
  separately derived policy model. Qualify omission/duplication/corruption
  detectors and repeated tags. Execute the base gate and separate
  mixed-destination, bounded stall, incast DROP/WAIT, shaping and ECN tests.
  For mixed destinations, rotate each source's egress each frame and check
  committed order and per-egress service without imposing the permutation
  rate. For shaping, exercise queue-only, port-only and dual limits with
  fractional refill, stalls, saturation and high-priority competition.
  Compare against binding-time byte budgets and the allowed delivery burst.
  Check zero unexplained loss, duplication or leaks and complete frame and
  resource accounting after drain. Use both latencies, at least three random
  seeds per applicable profile, and deterministic directed replay.
- **SVA and coverage.** Bind checks for stall stability, frame boundaries,
  reset epoch, old-state grants, distinct reservations/returns, fixed response
  timing, prefetch credit and binding/debit. Observe required bins for each
  port/class, every legal final keep, partial cells, length bounds, full pools,
  same-edge publish/pop/return, contested abort, late strict arrival, bucket
  comparison at threshold, all ECN codepoints and resets with pending work.
  Review critical crosses and justified exclusions against the multi-egress
  requirement matrix. Record checker and intended-fault detection evidence.
- **Selected formal.** Prove conservation including reserved versus assigned
  credit, unique cell/descriptor ownership and reclaim, bounded occupancy and
  outstanding responses, and per-queue FIFO order through concurrent
  publication/dispatch and reset. Require reachable collision, full-capacity
  and abort/retire/reset covers. Use the small profile or document each reduced
  kernel and its composition premises. Safety must permit arbitrary legal
  stalls. Progress bounds name arbitration, token and sink assumptions.
  Record proof mode, depth or induction, exact tool/source and any timeouts.
- **Mapped synthesis and pre-layout STA.** Map the small profile with actual
  memory and control, or characterize a real macro. Give primary-profile
  control timing, payload bits, defined RAM latency/ports and separate memory
  assumptions. Use the reference 10 ns clock, 2 ns I/O and
  0.10 ns uncertainty using explicit min/max delays, slew/load and reset checks.
  Record library identity, PVT, constraints, setup/hold slack and constrained
  path groups. Match function and capacity for variants where possible, and
  keep memory accounting comparable.
- **Gate closure.** Establish separately qualified component scopes first,
  then independently run the integrated multi-egress gates at named combined
  RTL and DV sources and confirm exact merged sources. Register suites and coverage
  through the existing tooling. Retain compact replay inputs, source, commands
  and results at their recorded SHAs.

### Directed multi-egress qualification obligations

Each applicable launch assignment carries forward the trigger, expected
observation and targeted detector from this table. Independent DV owns
executable scenarios and the frozen policy oracle.

| Risk | Directed trigger and expected observation | Targeted detector |
| --- | --- | --- |
| Publish while dispatching | Dispatch old singleton A on the publication target queue and old heads on other egresses while publishing B to A's queue. B becomes head and tail, with merged nonempty asserted. Repeat with a longer queue (follow old successor) and an empty target (first selectable on the next edge). | Dropped append, stale head, bad active bitmap or same-edge selection of B. |
| Prefix grants vs returns | Start with one free descriptor, enough cells and multiple eligible heads. Overlap a TX/abort return. Only the first prefix candidate may receive the old free ID. Check individual DROP outcomes, WAIT pending and next-edge reuse. Separately align four accepted TX finals with final abort reclaim and account for five distinct cell and descriptor returns and their merged deltas. | Return bypass, duplicate allocation, lost high/cleanup lane or wrong merged credit. |
| Admission arithmetic and first-beat validation | Small profile with zero minima, zero target occupancy, `A[q]=64`, a free descriptor and a 65-byte header requesting two cells. `U=10` grants (shared remainder 8, threshold 2); `U=9` gives temporary QUEUE_LIMIT (threshold 1), rejecting in DROP and holding in WAIT. Invalid route plus invalid length gives BAD_ROUTE without reservation. Valid header with a malformed first serviced beat reserves and aborts on one edge, writes/publishes nothing, then cleans up once and emits FRAME_ERROR. | Pre-reservation threshold, precedence swap, malformed write or double cleanup. |
| Late strict priority | Prepare a tentative low choice while the active frame goes from 17 to 16 unaccepted beats. A token-eligible high head published before binding wins. If published on the low binding edge it becomes visible next edge and the bound low successor survives stalls. Check no pop, debit or speculative read for tentative work. | Early ownership/charge, missed strict priority or changed binding under stall. |
| Dual shaping and parked DRR | Compare a 65-byte head at pre-edge balance 64.75 with 0.5 refill, then at 65. Test queue-only and port-only limiting balances and both enabled. Debit once at binding before refill. Park an open visit while token-blocked and resume its saved deficit without a second quantum. Name eligibility and service assumptions for fairness. | Post-refill eligibility, repeat debit, lost deficit or double quantum. |
| Exact credits and reset | Occupy six prefetch slots including a pending response and a stalled cell-final beat. At `issue+L` the response moves existing credit. The full pre-edge egress cannot issue on that edge even if it retires a cell. Align response and retirement with issue to another egress and a simultaneous payload write to a distinct owned cell, at L=1 and L=2. Reset with pending/held work then reuse IDs and tags with distinctive bytes after restart. | Early/surplus issue, late response, payload collision or stale data, credit, return or status. |
| ECN and snapshot coherence | Publish below and at the threshold with a coincident reservation or return. ECT(0) and ECT(1) mark at threshold using pre-edge H, unlike Not-ECT and CE. Snapshot during live increments, read in both half orders and check the same pre-edge sample. Use a scoped near-low-word-boundary harness for carry and saturation. Use independent AW/W and held responses with real RTL, including merged increments. | Post-edge ECN sample, wrong marking, torn words, bad carry or dropped increments. |
| Full rate and head-of-line isolation | Run the balanced primary permutations and supplemental pending-first-cell replay at both latencies. Stall one egress with shared capacity available while other eligible flows continue. Reconcile packet, byte and ownership totals and attribute shared-capacity pressure and local scheduling/prefetch stalls separately. | Missed eligible beat, flow coupling, accounting error or misattributed pressure. |

Use [P05 qualification](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/4634d5a4dacb00304635ddb64a3f83747d8b03e8/docs/results/P05-candidate-qualification.md) as the model
for exact stimulus, independent expectations, mandatory observed bins,
legal neighbors and named detector outcomes. P05 preparation PR #23,
RTL PR #24, interface-check repair PR #25 and qualification PR #26 establish
that workflow at their recorded scopes. Preserve the documented P05
preparation exposure. Follow [P04 evidence](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/4634d5a4dacb00304635ddb64a3f83747d8b03e8/docs/results/P04-scheduler.md)
for byte-DRR visit accounting, finite fairness and conditional progress.
Historical component evidence retains its original scope.

Apply this standard to every new traffic-manager task prompt at the assigned
role's boundary. Pin the profile, latency, seeds, source identities and
decision criteria. For each critical obligation, give the stimulus,
independent expected transition, required observed coverage, legal neighbor,
intended detector and replay command. Add cases when a concrete risk warrants
them and preserve the first unexpected counterexample.

- **Independent DV preparation.** Set the allowed-source boundary before the
  first command. Audit provenance, doctor, source policy, test discovery and
  repository-wide checks for transitive reads. Use a scoped alternative or
  record the blocked check and continue permitted work. Commit the
  specification-derived model, literal witnesses and mandatory coverage
  before reviewing retained checkers.
- **RTL implementation.** Start fresh under the root ownership policy.
  Consume only published commands and bounded public results from the
  trusted black-box runner. Keep DV bodies out of searches, diffs and
  traces. Report candidate checks unavailable if the adapter is missing
  and run the applicable designer checks.
- **Independent production qualification.** Use the frozen model against
  named RTL. After freeze, bind observation, coverage, formal and disposable
  mutations to the actual RTL. Require real SV/UVM passive observation,
  directed triggers, at least three deterministic seeds per applicable
  profile plus exact replay, complete shutdown accounting and applicable
  proofs with reachable covers. Preserve failures before repair.
- **Candidate and merged-source confirmation.** Record named RTL and DV
  commits and the tested pre-merge tree in isolation. On refresh compare
  production sources, transitive headers, contracts, registrations,
  parameters and build/proof settings, then rerun affected checks without
  replacing original execution identities. Select actual merged RTL
  after integration and finish required hosted CI. Keep queue/control
  timing open until the dependent microarchitecture prerequisite closes.

## Current order

1. Implement the widened resource pools against the public behavior and ABI.
   Follow [allocator selection](tasks/A01-allocator-selection.md) for the timing baseline.
2. Bind and independently qualify the candidate using the frozen pool replay
   and proof obligations. Confirm the actual merged sources.
3. Implement and qualify queues, scheduler, memory/TX, ingress/admission/cleanup
   and CSR/statistics at their public boundaries. Record dependencies and policy
   decisions before implementing consumers.
4. Establish reset ownership and close the composed timing and functional gates
   on production RTL. Use both published profiles and both read latencies.

[Current status](../status.md) records evidence and remaining scope. Historical
sources and results remain available at the [retired baseline](../results/README.md#historical-baseline).
