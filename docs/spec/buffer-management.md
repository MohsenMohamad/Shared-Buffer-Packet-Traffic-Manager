# Admission and shared-buffer management

The registered FIFOs feed a one-beat-per-cycle, rotating round-robin arbiter. The arbiter advances its cursor only when it services a FIFO beat. It is work-conserving among eligible FIFO heads. It does not lock one input until the end of a packet: four receive contexts allow beat-level interleaving between inputs. An input gap therefore does not stop an unrelated active input.

The reset cursor is zero. Starting at the cursor, select the first eligible input, wrapping around. An active, admitted packet is eligible when its next well-formed beat can be stored. A draining input is eligible to discard a beat. An input in cleanup may drain remaining frame beats, but cannot start a new packet until cleanup finishes. A new header in WAIT mode is ineligible while a temporary resource shortage prevents its reservation; other eligible inputs are still considered. A permanently inadmissible header is eligible to be rejected as specified below.

### Admission predicate

For a supported header, let `n=ceil(L/CELL_BYTES)`, `U=unreserved cell credit`, `D=free descriptors` and `H[q]=cells owned or reserved by queue q`.

`admit = valid_qid && valid_length && (H[q]+n <= Q_LIMIT[q]) && (D>0) && (U>=n)`.

The predicate uses pre-cycle registered resource state. Cells/descriptors released during the same cycle are available for a new reservation on the following cycle; no same-cycle free-to-allocate bypass is required. This deterministic rule prevents a hidden combinational resource feedback path.

In DROP mode, a failing header is consumed and the packet is drained. Priority when several conditions fail is BAD_QID, BAD_LENGTH, QUEUE_LIMIT, NO_DESCRIPTOR, NO_CELLS. In WAIT mode, otherwise valid headers with a temporary resource shortage remain at the FIFO head. Invalid metadata is always rejected/drained. A packet requiring `n>Q_LIMIT[q]` is also rejected as QUEUE_LIMIT in either mode, because it can never fit that static policy; `n<=Q_LIMIT[q]` but `H[q]+n>Q_LIMIT[q]` is a temporary shortage and waits in WAIT mode. Default mode is DROP. Validate qid before indexing any per-queue array.

Successful admission reserves all `n` cell credits and one descriptor atomically. A physical cell address need not yet be assigned for every reserved cell. Positive admission cannot later fail merely because other packets consumed the remaining storage. It can still be aborted for malformed framing or canceled by reset.

### Receive context

Each input context stores phase, qid, length, tag, descriptor ID, head/tail cell IDs, allocated-cell count, expected beat number, word offset, frame-drain completion and abort-cleanup state. Recommended phases are IDLE, RECEIVE, DRAIN_REJECT and ABORT_DRAIN. Cleanup and draining may overlap.

A new cell is allocated only for the first well-formed beat requiring that cell. The prior tail's next link is written when a new cell extends the chain. The number of cells in the packet defines the traversal boundary; the final cell's stale next-link value is never read. The first cell/descriptor fields need explicit bypass handling for a valid single-beat packet that is admitted and committed in the same service operation.

### Packet validation and cleanup

Legal lengths are 1 through MAX_PACKET_BYTES. There is no minimum Ethernet-frame length requirement. Framing errors are early TLAST, missing TLAST on the declared final beat, incorrect keep on any beat, and excess data beyond the declared length. Evaluate format before writing an invalid beat or allocating a new cell for that beat.

An admitted malformed packet MUST NOT be committed or partly transmitted. Stop writing it, mark it aborted and drain to an observed TLAST. Already allocated cells are reclaimed at a bounded one-cell-per-cycle rate subject to output-release priority. Its remaining reservation is released atomically at abort completion, not silently forgotten. The descriptor remains owned until cleanup completes. No reclamation action may reference a descriptor or cell after it has been returned to its pool.

If the first serviced beat has valid admission metadata but malformed framing, admission still reserves the packet budget/descriptor and counts as admitted. That edge records an aborted context with zero allocated cells and performs no payload write. Cleanup may finish no earlier than the following cycle. Never return a descriptor on the same edge on which that descriptor was first allocated. Zero-cell cleanup must not read an uninitialized head/next pointer.

## Resource accounting and memory organization

### Required accounting invariants

Define:

- `A`: physical cells currently assigned to packets, including aborted packets being reclaimed.
- `F`: physically free cell addresses, equal to the free-bitmap population.
- `U`: cells available for new packet reservations.
- `R`: physically free cells whose credit remains reserved, including unmaterialized receive reservations and already reclaimed cells held until abort completion.
- `H[q]`: reserved or assigned cell credit held by packets of queue q.

At every architectural boundary after reset:

`N_CELL = A + F = A + U + R`.

`F = U + R` and `N_CELL = U + sum_q H[q]`.

All quantities are nonnegative and bounded. These equations deliberately account for reservations and in-flight ownership; `free + queued = capacity` is insufficient.

| Event | A | F | U | R | H[q] |
|---|---:|---:|---:|---:|---:|
| Reserve n cells | 0 | 0 | −n | +n | +n |
| Materialize one reserved cell | +1 | −1 | 0 | −1 | 0 |
| Commit a complete packet | 0 | 0 | 0 | 0 | 0 |
| Consume a normal packet's final beat of a cell | −1 | +1 | +1 | 0 | −1 |
| Physically reclaim one aborted cell | −1 | +1 | 0 | +1 | 0 |
| Finish abort cleanup of n-cell reservation | 0 | 0 | +n | −n | −n |

Several events may occur in one cycle. Compute a combined next state using widened signed deltas, validate its range, then assign the final unsigned registers. Separate nonblocking assignments that each overwrite the same counter are prohibited.

### Physical pool allocator

The preferred version-1 implementation is a registered free bitmap with priority selection and a free-count register. It accepts at most one cell allocation and one cell return per cycle. Allocation chooses a cell free in the pre-cycle bitmap. An invalid return is detected; it must not create extra capacity. Lower-level allocator proofs may allow arbitrary invalid return requests and establish that state remains consistent.

The normal output-cell return takes precedence over abort-cell reclamation. Abort work advances when no output return occupies the port. With supported CELL_WORDS at least two, an active output cannot require a new cell return every clock indefinitely. The abort controller rotates fairly among pending input contexts. It MUST return no more than one physical cell per cycle.

The descriptor pool is also a bitmap. One reservation allocates at most one descriptor per cycle. A normal output packet and an abort may finish together, so the bitmap/counter MUST handle up to two descriptor returns and one allocation atomically, with no allocation bypass from those returns. Descriptor ownership states are FREE, RX, QUEUED, TX or ABORT; exactly one is true.

### Payload memory

The logical payload-memory interface is one write port and one synchronous read port, width 64 bits. Address is `cell_id*CELL_WORDS+word_offset`. There is at most one write request and one read request per clock. Read latency is fixed at one or two cycles and responses cannot be backpressured.

The TM MUST reserve output-FIFO capacity for every in-flight read. No read may issue if its eventual response lacks storage. Track buffered beats plus outstanding responses, including an output handshake that returns a FIFO slot in the current cycle. Parameterizing RAM latency without changing that accounting is a required stress case.

Read/write collisions on the same physical word are forbidden by ownership and commit rules; the memory's read-during-write behavior is not a correctness mechanism. The selected output packet's cells are not returned until the last beat from the relevant cell is accepted by the external output. Returning a cell before that point is not permitted in the baseline, even if an alternative prefetch scheme could make it safe.

For the default 64-KiB store, simulation may use an abstract 1R1W memory with this exact contract. The small implementation profiles MUST include a fully mapped register-based memory, or explicitly characterize and include a real macro. An uncharacterized black box cannot contribute invented area or timing.

### Metadata storage

Cell-next links, descriptor-next links and descriptor information are separate from payload data. Version 1 permits register-based metadata arrays with explicitly documented read multiplexers. An implementation MUST state each array's read/write ports rather than assuming an unlimited-port SRAM.

Baseline bounds are one cell-link write per accepted new-cell extension; one descriptor-information write per new reservation; and one descriptor-next write per enqueue. Queue head/tail/count arrays use merged enqueue/dequeue updates. TX and abort-reclaimer link reads require two independent register-array read muxes or an explicit one-port arbiter; either is allowed if latency/progress constraints hold. These implementation choices MUST be included in area reporting.
