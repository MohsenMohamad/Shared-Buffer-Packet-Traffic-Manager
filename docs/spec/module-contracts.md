# Module contracts

These APIs freeze component boundaries. P02 implements `tm_axis_rx_fifo_api`,
`tm_cell_pool_api` and `tm_desc_pool_api` under `rtl/common/` and `rtl/pools/`.
`rtl/tm_top.sv` and the remaining APIs in `rtl/include/tm_module_ports.sv` are
**declarations only**. Their elaboration proves frontend compatibility and
parameter checks. Component implementations retain the `_api` names, fields and
timing. Existing
external semantics in [interfaces.md](interfaces.md) remain normative.

## Representation and configuration

[tm_parameters.svh](../../rtl/include/tm_parameters.svh) is the common parameter
list. [tm_types.svh](../../rtl/include/tm_types.svh) defines module-local packed
records, enumerations and width constants. This avoids parameterized packages,
unpacked array ports and synthesizer-specific interface support. Both frontends
consume the same production source files without translated copies. See
[decision 0002](../decisions/0002-module-contracts.md).

The six production profiles and defaults are owned by
[profiles.json](../../verification/profiles.json), matching architecture.md.
`QUANTUM_DEFAULT` defaults to the selected maximum packet length. Index widths
are at least one and at least clog2(capacity); count widths hold the capacity
itself, requiring clog2(capacity+1). `DEFICIT_W` holds
`4096+MAX_PACKET_BYTES-1`. `tm_validate.svh` rejects unsupported parameters,
insufficient widths and TX depth less than read latency+2 by instantiating an
unresolved `TM_INVALID_CONFIGURATION` only in the invalid generate branch.
Both Verilator elaboration and Yosys `hierarchy -check` must reject that branch.
Reduced formal kernels are separately named harness configurations in later
proof work; they do not extend the supported production range.

All multi-lane ports are packed vectors. Lane i is `[i*W +: W]`, lane zero at
the least significant end. The top declaration retains the AXI signal names
and widths in interfaces.md, including **eight-bit input qids**. No queue array
may be indexed until that qid is validated. Internally validated `qid_t` and
`port_id_t` use guarded profile widths. `input_user_t` and `output_user_t` are
64 bits, `status_t` is 45 bits including valid, and `beat_t` is
`DATA_W+DATA_W/8+65` bits. Struct declaration order is most to least significant.

| Record | Fields and width authority |
| --- | --- |
| `beat_t` | data DATA_W, keep DATA_W/8, last 1, user 64; keep includes malformed masks |
| `input_user_t` | reserved 24, tag 16, length 16, qid 8 |
| `output_user_t` | reserved 16 (zero), source 8, tag 16, length 16, qid 8 |
| `status_t` | valid 1, code 4, tag 16, qid 8, length 16; codes 0–6 match interfaces.md |
| `descriptor_t` | head CELL_ID_W, ncell CELL_COUNT_W, length 16, qid Q_ID_W, tag 16, source RX_ID_W |
| `rx_context_t` | phase, raw qid/length/tag, descriptor, head/tail, allocated/reserved counts, beat number, word offset, drain/cleanup flags |
| `service_t` | valid, source, full beat, sop; never a driver transaction |
| `admission_t` | valid, source, raw qid/tag/length, ncell, accept, reason, desc; desc meaningful only when accepted; ncell meaningful only for a validated length |
| `commit_t`, `dispatch_t` | valid, validated qid, desc, complete descriptor info |
| `cell_alloc_t` | valid, id, owning descriptor |
| `cell_return_t` | valid, id, abort_source, qid, descriptor; one selected return per cycle |
| `desc_return_t` | valid, descriptor; distinct TX and abort lanes |
| `abort_mark_t` | valid, source, descriptor, qid, head, allocated and reserved counts; head meaningless for allocated=0 |
| `abort_done_t` | valid, source, descriptor, qid, original reservation ncell |
| `tx_done_t` | valid, descriptor, qid, actual packet length |
| `ram_write_t`, `ram_read_t`, `ram_response_t` | valid plus word address/data as applicable; no response ready |
| `cell_link_write_t`, `desc_link_write_t`, `desc_write_t` | valid, array index, next ID or full descriptor data |
| `config_t` | run, wait_mode, initialized; N_Q cell limits and 13-bit quanta |
| `live_t` | A, F, U, R, free descriptors; packed H, queue counts, deficits; idle, invariant_error |
| `statistics_t` | ten 64-bit global counters, five 64-bit counters per queue, cell-count high-water per queue |
| `stats_command_t` | snapshot and clear pulses |
| `axil_request_t`, `axil_response_t` | all five AXI4-Lite channel levels, including separate AW/W, protection and strobes |
| `trace_t` | one lane for each rx_service, admit, commit, dispatch, cell_alloc/free, abort_mark/done and tx_done event |

The five per-queue statistics lanes are ADMITTED_PKTS, RESOURCE_DROPS, TX_PKTS,
TX_BYTES, FRAME_ABORTS, in that order; index is `(q*5+k)*64`. Global order is
registers.md's order. Status code COMMITTED in an **accepted admission decision**
means no rejection reason; the actual COMMITTED status occurs after publication.
An accepted first-beat format error is still admitted and later reports FRAME_ERROR.
`owner_t` is FREE/RX/QUEUED/TX/ABORT; ownership is a protocol invariant, not a
second independently writable descriptor state table.

## Clock, reset and acceptance conventions

`e` denotes the rising edge accepting an action. A ready/valid channel fires
only when both are high at e. Records with only `valid` are unbackpressured
single-edge actions; producers must establish their legality from pre-state.
They are not requests that can be silently dropped. Except where stated,
internal selectors and actions are combinational functions of registered
state and current internal events; they settle before e. They must not drive
combinational paths from external inputs to external outputs. Top packet and
AXI outputs are registered; FIFO heads and all availability/query signals
reflect pre-state. Arbitration advances only on an accepted action.

During reset no action is accepted, no RAM write occurs, and externally
visible valid/ready are low as specified in interfaces.md. Control state,
counts and deficits reset to empty/zero; bitmap pools reset entirely free,
U=F=N_CELL, A=R=H=0, free descriptors=N_DESC. Payload/link/info arrays are not
cleared. Their values are meaningless without a valid owner/count. Top owns
`initialized`, raised at the first rising edge following reset release. RUN
resets low; policy DROP, limits N_CELL and quanta MAX_PACKET_BYTES. Delayed RAM
responses are discarded by TX on reset. Trace/status pulses from old work
are canceled. No component can depend on a stale array value after reset.

## Producer and consumer APIs

The remaining declaration signatures are in
[tm_module_ports.sv](../../rtl/include/tm_module_ports.sv); storage signatures are
in their [FIFO](../../rtl/common/tm_axis_rx_fifo.sv),
[cell pool](../../rtl/pools/tm_cell_pool.sv) and
[descriptor pool](../../rtl/pools/tm_desc_pool.sv) implementations. Signals named here
use exactly the record fields above. All components use the common clock and
reset except the unreset data-only RAM and metadata arrays.

| Component / producer → consumer | Event, timing and backpressure | Ownership and arbitration |
| --- | --- | --- |
| `tm_axis_rx_fifo_api`: stream → FIFO → arbiter | s_valid/s_ready captures s_beat at e; m_valid/m_ready services m_beat at e. No fall-through; a captured beat is first visible after e. Registered s_ready may insert a full-to-pop bubble; held m_beat remains stable. `enable=RUN && initialized`. | One FIFO per input; one write and read each per edge, simultaneous push/pop merged; depth 2/4. `empty` is registered-state query. |
| `tm_rx_arb_api`: FIFO heads / admission eligibility → admission | `service.valid` and one-hot `pop` consume one eligible valid head at e. `heads` carries BEAT_W per port; `sop` comes from RX contexts. No secondary acceptance/ready. | Cursor starts zero, rotates after service only, selects first eligible head wrapping from cursor. It never locks a whole frame. |
| `tm_admission_api`: FIFO heads / service / config / live / available IDs → pools, metadata, queue, RAM, reclaimer, statuses | Rejected or accepted header decisions occur on SOP service at e. WAIT temporary shortages suppress eligibility, permanently invalid headers remain eligible. Actions `admit`, `cell_alloc`, `cell_link_write`, `desc_write`, `payload_write`, `commit`, `abort_mark` linearize at e. `status` is registered, visible in the cycle following the appropriate decision/completion. | Owns all per-input RX contexts, sop and eligibility; queries every head without consuming it. Checks format before write/allocation. At most one reserve, cell allocation, extension, payload write, commit and abort mark per edge. No new frame is serviced until previous disposition is emitted and drain/cleanup permit reuse. |
| `tm_cell_pool_api`: admission allocation / selected return → available ID/count | `available_id` valid iff available; pre-state bitmap selection (lowest free ID). Allocation record must name that ID. One allocate and one return at e, returned ID first eligible after e. | Owns cell free bitmap and physical free count F. No free-to-allocate bypass. Return arbitration is outside this pool. |
| `tm_desc_pool_api`: accepted admit / TX return / abort return → available ID/count | Lowest pre-state free ID; accepted admit allocates at e. Two independently valid return lanes merge with the allocation at e; no return bypass. | Owns descriptor free bitmap/count D. Dispatch does not return a descriptor. |
| `tm_resource_accounting_api`: accepted admit / materialization / selected return / abort_done → scalar resource state | Apply the table in buffer-management.md once per e: reserve n, materialize ≤1, TX release ≤1, abort physical release ≤1, finish reservation ≤1. | Sole owner of U/R/A/H. F output is an accounting cross-check of cell-pool F, never an admission substitute. Widen signed intermediates then validate bounds. |
| `tm_metadata_api`: RX / queue writes → TX, reclaimer, queues/scheduler | Combinational pre-state read muxes; writes at e, visible after e. No same-edge write/read bypass. IDs meaningful only under owner/count validity. | Owns cell-next, desc-next and descriptor-info arrays; exact ports below. |
| `tm_queue_ctrl_api`: commit / dispatch / old_head_next → heads/tails/counts, next_write | Commit publishes at e; dispatch removes pre-state head at e. Query arrays visible after e. Empty queue cannot dispatch from a concurrent commit. No ready on publication; capacity was reserved. | Sole owner of queue head/tail/count. Merges same/different queue operations; count=1 replacement sets both head/tail to committed descriptor and never reads stale old next. |
| `tm_drr_api`: heads/counts/info, config, commit, TX availability/completion → dispatch/deficits | `dispatch.valid` is **dispatch_fire**, gated by tx_ready and legal pre-state head/credit. TX accepts unconditionally at e. No held speculative grant. Current commit affects merged empty detection, not pre-state head eligibility. | Owns cursor, visit-active state and deficits; quantum once per visit. Freeze scanning/additions while TX owns a packet. After tx_done at e, earliest new decision is e+1. `SCHED_MODE=0` gives packet RR. |
| `tm_packet_ram_api`: RX write / TX read → TX response | Requests valid at e; latency L means response is sampled at e+L (L=1/2), no ready. Read response may stream every edge; write and read each ≤1. Address is a physical word index. | One 64-bit write and synchronous read port. Same-word collision forbidden; no defined collision result. Reset does not clear RAM. |
| `tm_tx_api`: dispatch / RAM response / next link / sink ready → reads, output, cell_return, tx_done | `dispatch_ready` means no packet/FIFO/outstanding response. Dispatch accepted at e. Reserve FIFO slots for every read response; output handshake retires data. Cell return at that cell's last external handshake; tx_done at packet's last handshake. | Owns packet/read/retire cursors, outstanding tags and FIFO. Link query is combinational; latch next link before returning current cell. No tail traversal. Fixed RAM responses cannot stall. |
| `tm_abort_reclaim_api`: abort_mark / TX-return occupancy / next link → abort physical return, abort_done | Mark at e first eligible for cleanup at e+1, including zero-cell abort. Return at most one cell per edge; `tx_cell_return_valid` suppresses abort return. Completion may coincide with reclaiming final allocated cell. | Owns cleanup traversal state; fair rotating selection among marked RX contexts. Capture next before free. Abort completion returns original reserved budget and descriptor, not one extra physical cell. Drain completion is separately owned by RX. |
| `tm_axil_regs_api`: bus / live / initialized / live+shadow stats → config, bus response, stats commands | AW/W independent registered holds. One read and write may overlap. Execution after needed captures; B/R valid within three cycles. Read-before-write. stats_command pulses on execution edge. | Owns bus state and writable config; top supplies initialized. No new write acceptance until B retires. Snapshot reads consume shadow_stats; resource reads consume live. Range/lock/strobe/error rules remain registers.md. |
| `tm_statistics_api`: events / output retirement / stall samples / RUN / live / stats_command → live and shadow stats | Count validated architectural events at e, modulo 2^64; output_fire/beat increments TX_BYTES by accepted keep lanes at that edge, TX_PKTS on tx_done. Snapshot at e captures pre-update live counters/high-water. Clear while disabled+idle clears live/shadow. Reads never clear. | Sole owner of statistics and high-water arrays. Uses merged post-update H to update live high-water, avoiding a one-cycle missed peak. Per-cycle input stall is OR of external input stalls. |

For a valid single-beat packet, admission, first materialization, write and
commit may occur at the same edge. `desc_write.info.head` uses the selected
new cell, not the prior RX context. One descriptor-info write at reservation
captures immutable fields (head, total cell budget, length, qid, tag, source).
A malformed first beat writes no payload or link; its unused head is irrelevant
because that descriptor never publishes. Commit includes the full immutable
info for independent cross-checking, not a second writer of descriptor memory.

TX and abort outputs feed one top-level return selector. TX wins; abort advances
only if selected. Normal return also increments U/decrements H. Abort physical
return increments R; only abort_done releases its entire original reservation.
Top wires tx_done and abort_done to **separate** descriptor return lanes. It
assembles live_t from owning components, ORs/latches invariant errors, and
computes IDLE from FIFOs, all RX/drain/cleanup contexts, queues, TX/FIFO/read
state and full resource restoration. There is no competing top-level counter
writer. No new admission can use a same-edge release.

## Array ports and merged updates

| State | Writer and actual ports | Read and hazard rule |
| --- | --- | --- |
| Cell bitmap / F | cell pool, one clear + one set per edge | Pre-state free selector/count. Invalid return cannot create a bit. |
| Descriptor bitmap / D | descriptor pool, one clear + two sets per edge | Pre-state selector/count. Returns must be distinct owned IDs. |
| U/R/A/H | accounting, one combined delta per edge | Admission reads registered U/H; H includes RX, queued, TX and aborted reservation. |
| RX context | admission, one serviced-context update plus independently addressed cleanup notification | Per-port phase queries for arbitration. If service and abort_done hit one context, merge drain/cleanup flags; never start a new frame on that edge. |
| Cell-next array | metadata, one RX extension write | Two independent combinational read muxes: TX and abort. New extension writes previous tail; stale final next is never read. |
| Descriptor-info array | metadata, one reservation write | N_Q independent read muxes at current queue heads. A future lower-port implementation needs an explicit arbitration/latency contract change. |
| Descriptor-next array | metadata, one enqueue write | One combinational read mux at dispatched old head. `next_write` targets old tail only when it remains in queue (no count=1 replacement write needed). |
| Queue head/tail/count | queue controller, one commit and one dispatch merged | Whole pre-state arrays queried. Count>1 pop follows old next; same-queue push appends to old tail. Different queues both update. |
| Deficits/cursor/visit | scheduler only | Dequeue debit and empty transition use merged count. No quantum addition during TX busy. |
| Live/shadow stats/high-water | statistics only | Parallel CSR read muxes, pre-update snapshot. Multiple same-counter events merge before modulo assignment. |
| Config / AXI holds | registers only | Config changes disabled+idle. Snapshot/clear are commands, not second writers. |
| TX FIFO / outstanding | TX only | Buffered+outstanding ≤ depth; current output retirement may return a read credit. |

Pool returns are checked against **pre-state** ownership. Out-of-range and
already-free IDs are ignored and set the sticky invariant-error indication.
For duplicate descriptor returns, set the bit once/count once and flag the
second lane; valid distinct returns still proceed. Allocation and a valid
return cannot refer to the same ID, since allocation requires pre-state FREE
and return requires pre-state owned. A spurious return of an ID being allocated
is invalid and cannot undo the allocation. Queue/accounting illegal actions
are invariant violations and simulation failures; no recovery from a corrupted
internal state is promised. Error detection must not inflate capacity or hide
the original failure. Invalid pool requests are not counted as accepted release
events by accounting/statistics/trace.

## Independent observation and atomic batching

The stable observation payload is `trace_t`. Its `valid` bits describe actions
at e, not driver intent or a delayed CSR report. Fields extend interfaces.md
with source/length/owner context so checkers can cross-check causality without
reading free-bitmap algorithms. `abort_mark` with allocated=0 is representable;
one TX completion plus one abort completion and a reserve are representable in
one batch. The verification adapter remains passive and is omitted from synthesis source ownership; internal event records used by statistics remain production declarations.
Implementations expose these records through a verification-only bind adapter;
there is no functional trace producer in the G1 declaration-only top.

[tm_monitor_types.svh](../../dv/model/tm_monitor_types.svh) defines the packed
monitor batch: epoch/cycle/reset, all external stream levels/beat fields, output
levels, full AXI channel levels, per-input status and architectural trace.
[events.py](../../dv/model/events.py) supplies immutable Python records and an
executable collector/example policy boundary. P07 UVM agents publish matching
samples through the [bench package](../../dv/env/tm_bench_pkg.sv); these records
do not replace the executable UVM agents/checkers.

A coordinator accepts one explicit sample, including idle, from each RX monitor,
output monitor, bus monitor, status monitor, policy observation adapter and reset
monitor for the same `(epoch, cycle)`. Only the coordinator seals a batch after
all callbacks arrive. Missing, duplicate, stale or mixed-cycle reports fail;
callbacks cannot mutate policy state. On reset assertion the coordinator starts
a new epoch, resets/abandons packet and policy expectations, and invalidates old
responses. A new epoch may restart cycle numbering.

Packet identity is `(epoch, source port, frame ordinal)`, with qid attached after
monitored SOP. Tags may repeat. Packet bytes come exclusively from actual input
handshakes. The service checker maintains abstract FIFO beats from those captures;
a same-edge external capture cannot fund a service from an empty registered FIFO.
The policy checker consumes independently validated admission/service/release/
commit/dispatch events and scalar resource credit, not DUT free counts or copied
physical links. Physical IDs are diagnostic/cross-check fields only. The byte
checker matches committed packet objects against actual output transfers.

For each sealed batch, first validate all admission/dequeue decisions from the
same pre-state; then atomically apply all credit and list deltas. A simultaneous
release cannot justify admission; a commit cannot bypass an empty queue. A last
pop plus push leaves the new packet as the sole list entry. The executable
example exhaustively permutes all six callback sources in its single-input
scenarios (720 orders each), including reserve+materialize+TX release+TX/abort
descriptor returns, rejected optimistic admission, duplicate tags and reset.
It demonstrates batching, not a complete policy/scheduler/byte/physical model.

## Runner and source ownership

[Source registries](../../verification/sources/production.json) keep production,
simulation, formal and synthesis purposes separate. Simulation inherits
production and adds monitor headers. Synthesis/formal inherit production only;
the formal set adds only production storage harnesses/properties from
`formal/pools/`. No mapped TM synthesis target exists. Capability
fixtures remain under tests/toolchain and never enter production source lists.
Each contracts case records the selected source set, parameter values, source
hashes and exact frontend command in the P00 evidence manifest.

`make regression RUN_ARGS='--profile E0 --test contracts --seed 17'` executes
G1 declaration/layout elaboration through both pinned frontends, monitor-record
compilation through Verilator, positive option variants, intentional invalid
elaborations and the Python batching/runner tests. Repeat for F0/F1/I0/I1/E0/E1.
Regression defaults to profile F0. No seed is required for declaration compilation; the default 17 controls replayable
permutation traversal in the batching example. Exactly one explicit positive
31-bit seed is accepted for this suite. The `pools` suite registers FIFO/pool component tests in the same runner;
`formal-rtl` separately selects the production storage proofs. See
[storage proof scope](../../formal/pools/README.md) and the
[P02 results](../results/P02-storage-primitives.md). Future functional suites
register their profile/source ownership and handler in the same runner.

P00 commands retain `toolchain`, CI `--test` gate selection and at least two
distinct seeds for UVM replay/seed-diversity qualification. Regression suite
selection is independent: empty, duplicate, unknown suite/profile and invalid
seed selections fail. `formal-rtl` defaults to E0 and accepts distinct `cell`, `descriptor`, `fifo2`
and `fifo4` selections; it accepts no random seed. `formal-smoke` retains the
P00 fixture route. Other unfinished commands remain NOT_IMPLEMENTED. A
passing declaration case is never evidence that IF/ADM/MEM/Q/SCH/CSR behavior
exists; full PAR-01 functional regression remains for later component integration.

P07 registers the simulation-only `uvm-foundation` source set and regression
suite independently of production, storage, formal and synthesis lists.
`make regression RUN_ARGS='--profile I0 --test uvm-foundation --seed 23'`
executes real UVM agents/RAL, the declared behavioral fixture, independent
observed-transaction models, saved coverage and exact seeded detections.
The P01 packed records remain unchanged. See [bench reuse](../../dv/README.md)
and [fixture evidence](../results/P07-verification-foundation.md); fixture
qualification never substitutes for production TM requirement closure.
