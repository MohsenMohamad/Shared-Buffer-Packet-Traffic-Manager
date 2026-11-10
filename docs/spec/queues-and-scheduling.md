# Queues scheduling and transmission

Each committed packet has a descriptor containing head cell, cell count, byte length, qid, tag and source input. Each logical queue is a FIFO linked list of descriptor IDs with head, tail and committed-packet count. A descriptor enters a queue only after every valid payload beat is stored.

**Ordering is the order of successful packet commits, not the order of first external input beats across different ports.** Different input packets can complete at different times. The shared ingress arbiter commits at most one packet per cycle, giving an unambiguous order. Within a single input, packet framing already serializes packets.

Dequeue linearizes at `dispatch_fire`: the packet is removed from the queue and owned by the TX engine. Its descriptor is returned only after its final output beat. The queue's committed count excludes this TX packet; H[q] still includes its unreleased cells.

| Pre-state and events for the same queue | Required post-state |
|---|---|
| Empty, enqueue only | head=tail=new descriptor; count=1 |
| Nonempty, enqueue only | append to old tail; update tail; increment count |
| Count >1, dequeue only | head=old head's next; decrement count |
| Count=1, dequeue only | count=0; head/tail values become don't-care |
| Count=1, enqueue and dequeue | dequeue returns old descriptor; head=tail=new descriptor; count remains 1 |
| Count >1, enqueue and dequeue | dequeue returns old head; head advances; new descriptor appends; count unchanged |
| Empty and dequeue requested | no dequeue fires; enqueue, if present, is not bypassed directly to TX |

For different queues, enqueue and dequeue updates both occur. Stale next pointers of removed last entries MUST NOT become new heads. This is the key last-entry bypass case examined in the feasibility checks.

## Deficit round robin scheduling

The scheduler is packet-granular. It never interleaves bytes of different packets. `cursor` resets to zero; each queue has a byte deficit reset to zero. At most one packet is owned by the TX engine in the baseline.

Canonical policy:

1. On entry to a queue's visit, if it is empty, clear its deficit and advance the cursor. Otherwise add its configured quantum exactly once.
2. If its head length fits the deficit and the TX engine can accept a descriptor, dispatch the packet and subtract its byte length.
3. After that packet finishes transmission, continue the same visit without adding another quantum if the queue has another head that fits the remaining deficit.
4. If the next head does not fit, end the visit, retain the deficit and advance the cursor.
5. If the queue becomes empty, clear its deficit and close the visit. Arrivals after that empty transition start a later visit, rather than inheriting idle credit.

An enqueue and dequeue on the same queue use the merged post-update queue count to decide whether it became empty. If the result remains nonempty, preserve the remaining visit credit. While a packet stalls on the output, do not add credit every cycle or every beat.

Packets committed in the current cycle become eligible on the next cycle. A scheduling decision uses pre-cycle queue heads/counts and its documented local state. A plain one-queue-per-cycle scan is acceptable; an active-queue optimization MAY be introduced as a measured variant. It must preserve policy and avoid lost activation events.

The baseline freezes scheduler scanning and quantum additions while TX owns a packet. Debit and any true-empty visit closure occur at dispatch using the merged queue update; the next scan/dispatch decision occurs no earlier than the cycle after TX's final handshake. If a visit resumes on the same still-backlogged queue, do not add quantum a second time. A head that fits the deficit waits for TX availability rather than being skipped because TX is busy. These rules remove idle/busy timing ambiguity from the policy checker.

The deficit width must hold `QUANTUM_MAX+MAX_PACKET_BYTES-1`. For default MAX_PACKET_BYTES=1536 and QUANTUM_MAX=4096, thirteen bits suffice. The bound follows because a backlogged visit ends with deficit smaller than the next packet; a new visit adds at most QUANTUM_MAX once. No idle credit accumulation is allowed.

### Fairness statement

Fairness is byte service among continuously backlogged queues with fixed quanta and a progressing output. It is not equal packet counts, an exact per-packet latency promise, or a guarantee while the sink stalls forever.

For a queue continuously backlogged over R complete visits starting with zero deficit, `served_bytes + final_deficit = R*quantum`. At the end of a backlogged visit, `0 <= deficit < next_packet_length <= MAX_PACKET_BYTES`. Thus service error relative to R*quantum is less than MAX_PACKET_BYTES. Tests MUST compare complete visits/rounds or account for initial/final deficits and packets still in transmission.

The minimum quantum may be smaller than the maximum packet; carry-over across several visits is required and tested. The default quantum equals the maximum packet size to avoid an unnecessarily poor large-packet baseline. Packet RR sends one packet per visited nonempty queue and is used only as a comparison mode.



## Output engine, backpressure and completion

TX stores the selected descriptor's metadata, current cell/word index, remaining bytes/cells and link information. It prefetches payload into a bounded FIFO, respecting outstanding-read credits. A stalled output must not alter payload, keep, last or user, consume data twice, or free a cell twice.

Read/prefetch progress and external retirement progress are distinct. Carry the required cell/packet-boundary metadata alongside each pending response/FIFO beat, or maintain independently checked read and retirement cursors. Never return the prefetch cursor's current cell merely because a different buffered beat handshook at the output.

A cell returns to the pool on the handshake of its last valid output beat. The final partial cell counts as one cell. The descriptor returns on final packet handshake. The next-cell pointer must have been safely captured before the current cell is returned or reused. The stale tail link is never traversed.

Reset invalidates all pending RAM response tags, FIFO entries and TX metadata. A response originating before reset cannot revalidate an output entry after reset.

With RUN=1, a valid committed packet, a free TX engine and a ready sink, dispatch and data fetching MUST eventually occur. For a chosen head whose deficit is already sufficient, dispatch-to-first-output-valid must be at most `MEM_RD_LATENCY+4` cycles. A packet may incur additional scheduler visits when its length exceeds its accumulated credit.

After pipeline fill within an active multi-beat packet, an always-ready sink MUST receive one beat per cycle until that packet's final beat, unless a documented cell-link boundary introduces a bubble. Version-1 target is no cell-boundary bubble for CELL_WORDS>=2; if the first implementation misses this, treat it as a diagnosed performance bug or report the measured bound before changing this requirement.
