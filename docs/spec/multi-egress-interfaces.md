# Multi-egress interface declarations

The [behavior contract](multi-egress-traffic-manager.md) defines sampling,
holding, reset, fixed latency, admission, scheduling and disposition timing.
This document defines the wiring and software-visible ABI. The public ANSI
boundary is [tm_multi_ports](../../rtl/include/multi_egress/tm_multi_ports.sv).
Consumers may use the same scoped dependent types without inheriting production
sources. The [CSR package](../../rtl/include/multi_egress/tm_multi_csr.sv)
publishes constant addresses, word metadata and coordinate helpers.

## Profiles and encodings

| Parameter or width in bits | Primary `PROFILE=0` | Small `PROFILE=1` |
| --- | ---: | ---: |
| Ingresses / egresses / classes per egress | 4 / 4 / 4 | 2 / 2 / 4 |
| Queues / cells / descriptors | 16 / 1,024 / 256 | 8 / 16 / 8 |
| Declared frame bytes | 60–1,536 | 60–192 |
| Ingress ID `R` / egress ID `T` / class ID | 2 / 2 / 2 | 1 / 1 / 2 |
| Queue ID `Q` / cell address `C` / descriptor ID `D` | 4 / 10 / 8 | 3 / 4 / 3 |
| Cell count `K` / descriptor count | 11 / 9 | 5 / 4 |
| DRR deficit | 13 | 13 |

Both profiles use 64-bit beats, 64-byte (512-bit) cells, two captured beats,
four staging cells including assembly, eight disposition entries per ingress,
six prefetch cells including outstanding reads and the serialized cell, and
two bound frame slots per egress. `MEM_RD_LATENCY` is 1 (default) or 2.
`PROFILE` defaults to 0. Other geometry and payload width overrides must
match the selected profile. Unsupported selectors, geometry, payload widths
and latencies each fail at their corresponding elaboration guard.

Indices use at least one bit and otherwise `ceil(log2(size))`. Counts
include the full pool, using at least one bit and otherwise
`ceil(log2(size+1))`. All internal IDs are zero-based. Raw route and class
are compared at full width before forming a queue ID. Class is in 0–3,
destination is in 0–`N_TX-1`, and `qid = 4*destination + class`.

## Packet ports

The packet ports are packed records and one-bit-per-port ready vectors.
For an array of records of width `W`, physical lane `i` occupies
`[W*i+W-1:W*i]`. Valid or ready bit `i` belongs to physical port `i`.
Handshake means valid and ready on the same rising edge. The disposition
has no ready input. A record with valid zero is absent, and its payload is
irrelevant. The first captured input beat supplies metadata and later
beats' metadata is ignored. Valid egress output holds the entire record
through stalls, and the metadata repeats on each beat.

| Port or record | Packed field | Primary bits | Small bits |
| --- | --- | --- | --- |
| `ingress`, 124 bits per port | valid / data / keep / last | 123 / 122:59 / 58:51 / 50 | Same |
| | length / raw destination / raw class / tag / original ECN | 49:34 / 33:26 / 25:18 / 17:2 / 1:0 | Same |
| `egress` | valid / data / keep / last | 114 / 113:50 / 49:42 / 41 | 112 / 111:48 / 47:40 / 39 |
| | ingress ID / egress ID / class | 40:39 / 38:37 / 36:35 | 38 / 37 / 36:35 |
| | length / tag / original ECN / mark request | 34:19 / 18:3 / 2:1 / 0 | Same |
| `disposition`, 52 bits per port | valid / code / length / raw destination / raw class / tag | 51 / 50:48 / 47:32 / 31:24 / 23:16 / 15:0 | Same |

The independent beat type packs data at 72:9, keep at 8:1 and last at 0.
The ingress metadata type packs length at 49:34, destination at 33:26,
class at 25:18, tag at 17:2 and original ECN at 1:0. Within data, byte
`i` is at `[8*i+7:8*i]` and keep bit `i` qualifies that byte. The ordered
bytes `00 11 22 33 44 55 66 77` form `64'h7766554433221100`.
Lengths 65–72 have final keeps `01 03 07 0f 1f 3f 7f ff`.
Lengths 60, 64, 192 and 1,536 have final keeps `0f ff ff ff`.
Original ECN uses `00` Not-ECT, `01` ECT(1), `10` ECT(0), `11` CE.
Mark request is separate and the TM preserves packet bytes.

| Code | Disposition |
| ---: | --- |
| 0 | COMMITTED |
| 1 | BAD_ROUTE |
| 2 | BAD_LENGTH |
| 3 | QUEUE_LIMIT |
| 4 | NO_DESCRIPTOR |
| 5 | NO_CELLS |
| 6 | FRAME_ERROR |
| 7 | Reserved |

## Memory and frame identity

There is one always-accepted read command and one always-accepted write
command per edge, each with its own valid and cell address. There is no
command or response ready port. A valid read sampled at edge `t` requires
one valid response at `t+MEM_RD_LATENCY`, echoing its address and full read
tag. Response bytes become eligible for TX at the following edge. A
response converts an existing outstanding credit into an occupied slot
and cannot create a new slot. A new issue consumes one credit, and
retirement releases one slot. Read and write may coincide at distinct
owned addresses. Payload byte `i` uses `[8*i+7:8*i]`; byte zero is first
within the cell and there are no byte strobes on this interface.

| Record | Packed field | Primary bits | Small bits |
| --- | --- | --- | --- |
| `cell_read` | valid / read tag / address | 181 / 180:10 / 9:0 | 161 / 160:4 / 3:0 |
| `cell_write` | valid / address / data | 522 / 521:512 / 511:0 | 516 / 515:512 / 511:0 |
| `cell_response` | valid / read tag / address / data | 693 / 692:522 / 521:512 / 511:0 | 673 / 672:516 / 515:512 / 511:0 |
| Read tag | owner / destination / zero-based frame cell index | 170:13 / 12:11 / 10:0 | 156:6 / 5 / 4:0 |
| Owner | frame identity / queue ID / descriptor ID / opaque tag | 157:28 / 27:24 / 23:16 / 15:0 | 150:22 / 21:19 / 18:16 / 15:0 |
| Frame identity | epoch / ingress ID / sequence number | 129:66 / 65:64 / 63:0 | 128:65 / 64 / 63:0 |

The reset coordinator supplies `epoch_id` at release and holds it for the
epoch. Any epoch whose response can still be presented must have a
different value. Verification supplies distinct epoch values throughout
its run. An integration that flushes all old responses during reset may
tie the input to a constant when batch observation is unused. The
receiver may discard stale responses by clearing validity or comparing
epochs as specified by the behavior contract.

The TM assigns the unsigned 64-bit sequence on first *capture* of a frame,
starting at zero independently per ingress on each epoch. Each next first
capture increments the sequence, including frames later rejected or
aborted. Observers can associate ingress handshakes and per-port ordered
dispositions with that identity. The opaque packet tag is copied and is
free to repeat on the same or a different ingress. One verification run
must stay within the 64-bit sequence and epoch spaces. Descriptor IDs may
be recycled once ownership ends, independently of frame sequence.

## Edge observation

The observation represents the edge sampled by an independent monitor.
Outer `present` is high on every sampled edge outside reset, including
empty batches. The epoch identifies that edge. Each nested presence
field identifies an event committed on that edge, except a WAIT admission
entry which records a considered head without service, and a stale
read-response entry which has no state effect. Capture, egress and
disposition handshakes are observed directly at the packet ports.
Use no observation field or port to backpressure the TM.

| Batch member | Max primary / small | Lane order | Relevance and legal simultaneous events |
| --- | ---: | --- | --- |
| Ingress service | 4 / 2 | physical ingress | One serviced beat per ingress, even in discard. `first` identifies header service, `discard` means the beat does not enter assembly, including an offending beat. |
| Admission | 4 / 2 | dense rotating prefix | One considered head per ingress. Full raw metadata retained. Result 0 grant, 1 reject, 2 WAIT pending, 3 reserved. Reason is meaningful on reject/WAIT. `qid_valid` means raw destination/class are valid; requested count is meaningful for legal lengths with valid route. Descriptor is meaningful on grants only. |
| Cell write | 1 / 1 | scalar | Allocation and the corresponding payload write are one event. Uses the command address, with owning frame, cell index and final-cell flag. Can overlap admission, publication, TX returns and cleanup. |
| Publication | 1 / 1 | scalar | Head, cell count, length, original ECN and mark request at publication. A final write on this edge publishes on the next edge. |
| Dispatch | 4 / 2 | physical egress | One binding per egress from a pre-edge queue head. May overlap publication and retirement where the start-of-edge slot state permits binding. |
| Egress service | 4 / 2 | physical egress | One accepted beat per egress. Cell address plus cell-last and frame-last flags tie the transfer to return events. |
| Read issue | 1 / 1 | scalar | `command.valid` qualifies an exact copy of `cell_read`. Next-link value is meaningful only if `next_valid`, which is asserted on a nonfinal cell. |
| Read response | 1 / 1 | scalar | `identity.valid` marks a presented response. `identity` mirrors its valid, tag and address. `accepted_epoch` marks a response associated with the current epoch and its outstanding credit. |
| Abort mark | 4 / 2 | physical ingress | Each serviced malformed active frame can mark an abort, including newly granted frames. Fields name the owner and full reservation. |
| Cleanup | 1 / 1 | scalar | One abort service grant. `done` marks completion, with released reserved credit and a descriptor return. A nonfinal grant returns a cell and has no released credit. A zero-cell cleanup may complete without a cell return. |
| Cell return | 5 / 3 | physical egress 0 through `N_TX-1`, cleanup `N_TX` | All egresses may retire a cell and cleanup may reclaim another on the same edge, independently of the one allocation. |
| Descriptor return | 5 / 3 | physical egress 0 through `N_TX-1`, cleanup `N_TX` | All egresses may retire a final frame and cleanup may finish on that edge, independently of up to `N_RX` prefix allocations. |

Except the ordered admission prefix, arrays retain physical indices including
holes. ID zero is valid with presence asserted. Absent entries and irrelevant
fields do not carry information. For all owner records, the descriptor,
queue, frame and opaque tag name the owner before release or at acquisition.
An abort return is identified by the dedicated cleanup lane.

For accounting, resource eligibility and descriptor IDs come from the pre-edge
pools with preceding prefix grants applied. Returned IDs become selectable the
following edge. Validate beat framing before assembly. Allow a same-edge
grant and abort, and a prior staged write for the aborting frame, with
cleanup starting no earlier than the following edge. Scheduler selection,
token comparison, ECN and prefetch credit eligibility sample their respective
pre-edge state. Merge publication and dispatch on the same queue, and apply
all ownership and counter deltas once. These independent maxima size an edge
batch; the behavior contract defines which combinations are reachable.

### Observation wire layout

For each row, lane zero starts at the indicated base bit. Adjacent lanes
start at `base + i*W`. Divide the row into components from right to left
starting with bit zero of the lane, using the listed widths. This gives
each field the exact inclusive range `[sum(widths to right)+width-1 :
sum(widths to right)]` relative to the lane. `owner` and `frame` expand
as in the memory table. `beat` is 73 bits, ingress `metadata` is 50 bits
and `command` and `identity` use the cell-read layout. Width `1` is
implicit for presence and flags.

| Member | Base primary / small | Lane width primary / small | Lane fields from high to low |
| --- | ---: | ---: | --- |
| Descriptor return | 0 / 0 | 159 / 152 | present, owner |
| Cell return | 795 / 456 | 169 / 156 | present, owner, address (`C`) |
| Cleanup | 1,640 / 924 | 171 / 158 | present, owner, done, released (`K`) |
| Abort mark | 1,811 / 1,082 | 170 / 157 | present, owner, reserved (`K`) |
| Read response | 2,491 / 1,396 | 183 / 163 | identity, accepted_epoch |
| Read issue | 2,674 / 1,559 | 193 / 167 | command, next_valid, next_cell (`C`) |
| Egress service | 2,867 / 1,726 | 171 / 158 | present, owner, address (`C`), cell_last, frame_last |
| Dispatch | 3,551 / 2,042 | 175 / 168 | present, owner, length (16) |
| Publication | 4,251 / 2,378 | 199 / 180 | present, owner, head (`C`), cells (`K`), length (16), original_ecn (2), mark_request |
| Cell write | 4,450 / 2,558 | 181 / 162 | present, owner, cell_index (`K`), address (`C`), final_cell |
| Admission | 4,631 / 2,720 | 210 / 197 | present, frame, metadata, result (2), reason (3), qid_valid, qid (`Q`), requested (`K`), desc (`D`) |
| Ingress service | 5,471 / 3,114 | 206 / 205 | present, frame, first, discard, beat |
| Epoch | 6,295 / 3,524 | 64 / 64 | epoch |
| Present | 6,359 / 3,588 | 1 / 1 | present |

## AXI4-Lite register map

Byte addresses and data are each 32 bits. WSTRB has one bit per byte lane,
and AWPROT/ARPROT are three bits each, accepted without interpretation.
All map words use four-byte alignment. AW and W may arrive independently.
Read and write each permit one outstanding request with stable responses
held until accepted. Apply the completion bound in the behavior contract.

The response is `OKAY=00`, `SLVERR=10` or `DECERR=11`. An absent word
is DECERR even when unaligned. Within an allocated word, an unaligned access
is SLVERR. Aligned mapped writes with zero strobe succeed without side
effects, including on read-only words. All other writes to read-only words,
reads of the write-only trigger, and reserved or invalid merged values
return SLVERR. Error reads return zero. Unlisted read bits return zero.
Merge strobed bytes with the pre-edge value, using zero as the base for
the trigger. Reject the entire operation if any reserved bit of that
merged value is set, or if resulting field, cross-register or state
constraints fail.

### Global words

| Address | Name | Access | Bits and reset value |
| --- | --- | --- | --- |
| 0x0000 | ABI_VERSION | RO constant | 31:0 = 1 |
| 0x0004 | RUN | RW | bit 0 enable, reset 0 |
| 0x0008 | STATUS | RO live | bit 0 idle, bit 1 initialized, bit 2 snapshot valid, reset 0 |
| 0x000c | ADMISSION | RW policy | bit 0 WAIT, bit 1 dynamic, reset 0 (DROP/static) |
| 0x0010 | SNAPSHOT | WO | bit 0 trigger, merge base 0 |
| 0x0014 / 0x0018 / 0x001c | Unreserved credit / physical free cells / free descriptors | RO live | low `K` / `K` / descriptor count bits, zero before initialization, full pool at initialization |
| 0x0020 / 0x0024 / 0x0028 | Same three pool counts | RO snapshot | same bit ranges, reset 0 |

Policy writes require `RUN=0` and idle. RUN 0→1 requires initialization
and idle and fills enabled balances. RUN 1→0 requires idle, including
empty captured data, blocked headers, contexts, dispositions and internal
work. A write preserving RUN has no state transition. The same AXI error precedence applies during RUN transitions. STATUS idle
is asserted when initialized and all owned work and ingress/disposition
state are empty, regardless of RUN. Committing a trigger with bit zero
set captures all counters and listed snapshot occupancies from the
pre-edge state and sets snapshot valid. A trigger with bit zero clear
has no effect. Snapshot is legal while running. A coincident read samples
the previous snapshot. Either word may be read first and both halves
remain stable until the next trigger or reset. Snapshot reset is all zero
and each published counter saturates at `2^64-1`.

### Queue words

Base `0x1000 + 0x100*(4*egress+class)`, with implemented coordinates
`egress=0..N_TX-1`, `class=0..3`.

| Offset | Name | Access | Field bits | Legal value and reset |
| --- | --- | --- | --- | --- |
| 0x00 | Static limit | RW policy | 10:0 | 0–`N_CELL`, reset `N_CELL` |
| 0x04 | Protected minimum | RW policy | 10:0 | 0–`N_CELL`, sum across queues ≤ `N_CELL`, reset 0 |
| 0x08 | Alpha | RW policy | 12:0 | 0–4,096 encoded as A/256, reset 0 |
| 0x0c | Quantum | RW policy | 12:0 | 64–4,096 bytes, reset `MAX_FRAME_BYTES` |
| 0x10 | Bucket enable | RW policy | 0 | 0 or 1, reset 0 |
| 0x14 | Bucket rate | RW policy | 19:0 | Q16.16, 0–0x80000 encoded, reset 0x80000 |
| 0x18 | Bucket capacity | RW policy | 15:0 | 0–65,535 bytes, reset `MAX_FRAME_BYTES` |
| 0x1c | ECN enable | RW policy | 0 | 0 or 1, reset 0 |
| 0x20 | ECN threshold | RW policy | 10:0 | 1–`N_CELL` cells, reset 1 |
| 0x24 / 0x28 / 0x2c / 0x30 | H / queue depth / high-water H / high-water depth | RO live | low `K` / descriptor count / `K` / descriptor count bits | reset 0 |
| 0x34 / 0x38 / 0x3c / 0x40 | Same four occupancy values | RO snapshot | same bit ranges | reset 0 |
| 0x48 + 8*i, +4 high | Queue counters | RO snapshot | 31:0 per word | reset 0 |

The queue counters in index order are admitted, published, BAD_LENGTH,
QUEUE_LIMIT, NO_DESCRIPTOR, NO_CELLS, FRAME_ERROR, dispatched, retired
frames, retired bytes and mark requests. Publication accounts for
COMMITTED. BAD_ROUTE has no valid queue coordinate.

### Egress words

Base `0x2000 + 0x100*egress`, with `egress=0..N_TX-1`.

| Offset | Name | Access | Field bits | Legal value and reset |
| --- | --- | --- | --- | --- |
| 0x00 | Scheduling mode | RW policy | 1:0 | 0 pure DRR, 1 packet RR, 2 strict priority plus DRR, reset 0 |
| 0x04 | Strict class | RW policy | 1:0 | 0–3, reset 0 |
| 0x08 | Bucket enable | RW policy | 0 | 0 or 1, reset 0 |
| 0x0c | Bucket rate | RW policy | 19:0 | Q16.16, 0–0x80000 encoded, reset 0x80000 |
| 0x10 | Bucket capacity | RW policy | 15:0 | 0–65,535 bytes, reset `MAX_FRAME_BYTES` |
| 0x18 + 8*i, +4 high | Egress counters | RO snapshot | 31:0 per word | reset 0 |

An enabled queue or egress bucket requires a positive rate and capacity
at least `MAX_FRAME_BYTES`. Validate that dependency on a write to any
of the three bucket words. Configure rate and capacity before enabling
when the current settings are insufficient. Egress counter index order
is accepted beats, bytes, frames, valid-without-ready cycles,
ready-without-valid cycles.

### Ingress counter words

Base `0x3000 + 0x400*ingress + 0x80*bucket`. Ingress is
`0..N_RX-1`. Buckets 0–3 denote valid raw class and bucket 4 is
unclassified, regardless of the destination. Every word is RO snapshot,
reset zero. The low word is at offset `8*i`, and the high word at
`8*i+4`. Ingress counter index order is captured beats, captured valid
bytes, captured TLASTs, admitted, published, BAD_ROUTE, BAD_LENGTH,
QUEUE_LIMIT, NO_DESCRIPTOR, NO_CELLS and FRAME_ERROR.

### Address separation and split words

Primary queue bases run from 0x1000 to 0x1f00, and small from 0x1000
to 0x1700. Egress bases end at 0x2300 and 0x2100. The last implemented
ingress bucket bases are 0x3e00 and 0x3600. Occupied offsets end at
0x9c per queue, 0x3c per egress and 0x54 per ingress bucket. Each maximum
is below its stride, the five ingress buckets fit within an ingress
stride, and the four address regions are disjoint. Invalid coordinates
return the unmapped sentinel `0xffffffff`. Address helpers may also
construct holes within a valid coordinate's stride for decode testing.
The map has 1,135 primary words and 573 small words.

For example, queue (0,0) admissions `0x01234567_89abcdef` read as low
`0x89abcdef` at 0x1048 and high `0x01234567` at 0x104c.
Publications `0xfedcba98_76543210` use 0x1050 and 0x1054.
Live H at 0x1024 and snapshot H at 0x1034 use distinct words.
