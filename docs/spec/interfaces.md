# Interfaces and reset

All transfers are sampled on the rising edge of `clk`. Except reset assertion, top-level outputs MUST be functions of registered state rather than combinational functions of incoming interface signals. All externally visible channels remain stable under backpressure. Reset input `rst_n` MUST be held low across at least two rising edges; release is synchronous to `clk` by environmental contract. The block does not generate this reset.

During reset, all output `TVALID`, `BVALID` and `RVALID` signals are low and no packet-memory write is performed. Packet memory contents and stale link-array entries need not be reset; validity, pool ownership and queue state are reset. No stale pre-reset payload becomes valid after release.

Packet-input `TREADY` is low while reset is asserted, RUN=0 or initialization is incomplete. The AXI4-Lite slave remains usable while RUN=0. The baseline resets bitmap/control state directly and raises `initialized` on the first rising edge after reset release; it does not sweep or clear the payload RAM. An alternative serial pool initializer must state its bounded startup latency and keep packet acceptance disabled until completion.

### Packet input streams

Each input uses an AXI4-Stream-compatible packet subset:

| Signal per input | Width | Meaning |
|---|---:|---|
| `s_axis_tvalid`, `s_axis_tready` | 1 each | Beat transfers when both are high |
| `s_axis_tdata` | 64 | Byte 0 is bits 7:0 |
| `s_axis_tkeep` | 8 | Contiguous least-significant valid byte lanes |
| `s_axis_tlast` | 1 | Final beat of the externally framed packet |
| `s_axis_tuser` | 64 | Declared metadata, sampled on the first beat of a packet |

Input metadata layout: bits `[7:0]` queue ID, `[23:8]` declared byte length, `[39:24]` opaque 16-bit tag, `[63:40]` ignored/reserved. The queue ID is eight bits even when only sixteen queues are implemented, so invalid encodings are detectable rather than silently truncated.

Packets are contiguous in framing on an individual input: no interleaving of two packets within one input is allowed. Gaps in `TVALID` within a packet are legal. Different inputs may progress independently. `TVALID` must not wait for `TREADY`; once valid is asserted, data, keep, last and user remain stable until transfer. This project restricts legal keep patterns: every nonfinal beat is `8'hff`; the final beat has exactly the number of bytes implied by `L`. General AXI-Stream sparse/null-byte behavior is not supported by the packet endpoint.

The ingress FIFO accepts beats before resource admission. Consequently:

1. An external input handshake means a beat was captured into an ingress FIFO.
2. Admission happens when the ingress arbiter services the first FIFO beat.
3. Commit happens after the final, well-formed beat has been written.
4. Delivery happens at output handshakes.

These are different events. `TREADY` is not an advance promise that a packet will be admitted. Verification MUST distinguish them.

### Packet output stream

One 64-bit output has `m_axis_tvalid/tready/tdata/tkeep/tlast/tuser`. Packets are not interleaved on this output. Valid output fields remain stable while stalled.

Output user layout preserves queue ID, declared length and tag at the same bit positions; bits `[47:40]` identify the input port and `[63:48]` are zero. Metadata is repeated across all beats of the packet. Tag values need not be globally unique and are never used to decide ownership or routing. The scoreboard MUST not rely exclusively on tag uniqueness.

The final output keep mask is `(1 << (L mod 8))-1`, or `8'hff` when `L mod 8=0`. Invalid byte lanes are ignored by the checker and may contain any value. The output packet length and payload bytes exactly match a successfully committed input packet.

### Packet disposition outputs

Each input has an unbackpressured status pulse:

`rx_status_valid`, `rx_status_code[3:0]`, `rx_status_tag[15:0]`, `rx_status_qid[7:0]`, `rx_status_len[15:0]`.

A consumer MUST sample these pulses each clock; they are not an AXI channel. At most one status occurs on an input per cycle. The input cannot service a new packet before its previous disposition has been emitted, although its FIFO may already contain following beats.

| Code | Name | Timing and meaning |
|---:|---|---|
| 0 | `COMMITTED` | Pulse in the cycle following valid EOF service and queue publication |
| 1 | `BAD_QID` | Rejected at header processing; no reservation |
| 2 | `BAD_LENGTH` | Rejected at header processing; no reservation |
| 3 | `QUEUE_LIMIT` | Rejected for the selected queue's cell budget |
| 4 | `NO_DESCRIPTOR` | Rejected because no descriptor is available |
| 5 | `NO_CELLS` | Rejected because insufficient unreserved cell credit exists |
| 6 | `FRAME_ERROR` | An admitted packet was malformed; status is emitted only when its reservation and descriptor have been fully reclaimed |

Header rejection status follows the admission decision by one cycle and does not wait for discarded `TLAST`. A rejected input remains in drain state until `TLAST` is consumed. A format-aborted input becomes reusable only after both drain completion and resource cleanup. A malformed frame without a future `TLAST` may leave its input in drain state until reset; other inputs MUST continue to make progress.

Reset cancels all outstanding statuses and packets. There is no obligation to emit one status per pre-reset packet after reset.

### Control interface

The AXI4-Lite slave uses 32-bit data, 32-bit addresses, four write strobes, three protection bits (ignored) and the normal five channels. It supports one outstanding read and one outstanding write concurrently. AW and W MUST be accepted independently: either may arrive first. Independent hold registers are mandatory; never require AWVALID and WVALID to coincide.

No new write address/data transaction is accepted until the previous B response retires. Read and write transactions may overlap. Responses remain valid and stable while backpressured. A response is produced within three core cycles of receiving both AW/W, or AR, when not reset; the consumer may delay retirement arbitrarily.

`OKAY=2'b00`, `SLVERR=2'b10`, `DECERR=2'b11`. Misaligned mapped accesses return SLVERR; unknown addresses or queue indices return DECERR. Nonzero-strobe writes to read-only registers return SLVERR. Zero-strobe writes to a mapped address are successful no-ops. Byte strobes merge writable fields before range validation; an invalid merged value returns SLVERR and leaves the entire register unchanged. Read/write collisions are read-before-write: read data reflect pre-write registered state.

## Verification observation contract

Provide a verification-only `tm_trace_if` or an equivalent stable bind interface. Events are `rx_service(port, beat, is_sop)`, `admit(qid, tag, ncell, desc_id, accept, reason)`, `commit(qid, desc_id)`, `dispatch(qid, desc_id, len)`, `cell_alloc(id,desc)`, `cell_free(id,source)`, `abort_mark(desc)`, `abort_done(desc,qid,ncell)` and `tx_done(desc)`.

These observations let a policy checker align with architectural linearization points without copying the linked-list implementation. They MUST be cross-checked against packet-input/output monitors and resource invariants. A DUT-generated “success” event is not independent evidence that payload or admission was correct. The black-box packet scoreboard remains separate.

Do not use trace ports as hidden control inputs. Remove them for reported synthesis or include their area consistently in every compared variant. Document which boundary is measured.
