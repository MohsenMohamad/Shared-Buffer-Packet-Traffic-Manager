# Fresh memory/TX expectations

This is independent preparation, not hardware acceptance. Expectations are frozen
before retained-checker audit. Authority: interfaces.md, module-contracts.md,
buffer-management.md, queues-and-scheduling.md, verification.md and formal.md in
`docs/spec/`. Only `rtl/include/` public declarations were consulted. No target
or dependency implementation is an expectation source.

## Sample and transaction boundary

One complete immutable sample per rising edge contains explicit idle records as
well as actions. Packet data originate in observed payload writes, physical
lifetime in observed reserve/allocate/commit/dispatch/return actions. Descriptors
are identified by epoch and reservation ordinal, not opaque tag. An output beat
is compared with the committed write image and repeated output metadata; only
kept byte lanes matter. A driver packet object, a DUT pointer or a reported free
count never supplies an expected value.

Validate reserve/dispatch/returned IDs against pre-state. Then apply all legal
actions atomically, including reserve+allocate+info-write+payload-write+commit.
A simultaneous return cannot fund allocation or reservation. Newly written
metadata is visible after the edge. Commit cannot bypass an empty queue into
dispatch. Normal cell/descriptor returns must exactly match the external output
handshake; neither read issue nor response arrival retires resources.

## Hand-derived arithmetic and timing

Let B be live-epoch arrived beats not yet externally accepted, O live outstanding
reads, I an issue, R a due response, and T an external transfer (each 0 or 1).
At every edge, B'=B+R-T, O'=O+I-R, and B'+O'=B+O+I-T <= depth.
A response does not create credit. At full capacity an issue requires T=1;
response+issue+retire leaves occupancy unchanged. A response cannot be
backpressured. Read at e must have exactly one response sampled at e+L, L=1/2.

| Pre (B,O), depth | R,I,T | Post (B,O) | Consequence |
| --- | --- | --- | --- |
| (3,1),4 | 1,0,0 | (4,0) | Full response arrival must fit |
| (2,2),4 | 1,1,1 | (2,2) | Legal full-credit exchange |
| (2,2),4 | 1,1,0 | (3,2) | Illegal overissue |
| (7,1),8 | 1,0,0 | (8,0) | Full depth-eight arrival |
| (6,2),8 | 1,1,1 | (6,2) | Legal depth-eight exchange |

For latency one, reads at e,e+1 respond e+1,e+2. For latency two,
reads at e,e+1 respond e+2,e+3. Both can issue every edge; latency changes
outstanding capacity, not data ordering. Responses carry no tag/address in the
public API, so observed issue order supplies their identity.

For byte index j: physical word = chain[j//CELL_BYTES]*CELL_WORDS +
(j%CELL_BYTES)//8; byte lane=j%8. Keeps for remainders 1..7,0 are
01,03,07,0f,1f,3f,7f,ff. Lengths 1,7,8,9,C-1,C,C+1,MAX-1,MAX exercise
word/cell/tail boundaries. For C=16, chain [5,1,9], L=35: words
[10,11,2,3,18], keeps [ff,ff,ff,ff,07], cell returns at beat indices
1,3,4; descriptor completion only at index 4. Duplicate tags cannot merge
these lifetimes.

Independent conservation is N=A+F=A+U+R; F=U+R;
N=U+sum(H). For a normal committed packet, each externally retired cell adds
one U and removes one A,H. Descriptor free count changes only on reservation
or final completion. Shutdown requires no live descriptor/cell, pending read,
response/output obligation, held valid, queued packet or unreturned credit.
Reset cancels old delivery/ownership obligations rather than requiring a drain.

## Environment assumptions and DUT guarantees

Environment: fixed latency 1/2 RAM, no same-word read/write collision, legal
ownership actions, reset low for at least two sampled edges and synchronous
release, no new work before initialization, stable ready/valid inputs. Illegal
stimulus is rejected explicitly, not counted as a DUT detector success.
DUT: ordered responses/output, stable valid/data/keep/last/user during stalls,
complete exactly-once delivery and cell/descriptor retirement, legal credit and
no stale new-epoch output. Numeric free-ID policy is checked separately from
ownership; tag renaming and unused lanes preserve behavior, arbitrary ID or
cycle transformations need not. Timing/progress checks have an explicit ready-
sink boundary; arbitrary sink stalls are legal for safety.

Arrays survive reset. RAM response obligations from physical pre-reset reads
still mature, but their TX tags/credits are abandoned. New identical IDs/tags
must refer to distinctive new writes; stale data cannot satisfy new output.
Metadata has one cell-link writer/two combinational muxes, one descriptor-link
writer/query and one descriptor-info writer/N_Q head queries. No same-edge
metadata read bypass is promised. A public link query shows the value available
before return; only later production binding/inspection can establish the
internal latch and exact structural coverage.

## Risk, check and observed cover matrix

| Risk / contract | Independent check | Required observed scenario |
| --- | --- | --- |
| MEM-03 response timing/order | Due-cycle queue from sampled reads; observed-write image | L1/L2, missing/wrong/late/extra response, 1R1W collision |
| MEM-04 overwrite/overissue | B+O-I/T equations and independent event counts | depth4/8 full arrival, full stall, response+issue+retire |
| IF-01/LEN-01/02 bytes | Committed write image; lane-by-lane output | all keeps, word/cell/MAX edges, unused lanes |
| IF-01 held output | Compare all fields including valid on following edge | ordinary/cell-final/packet-final stalls |
| MEM-05 lifetime | Output-index boundary; observed chain and captured link | fragmented chains, early/missing/wrong/duplicate free |
| MEM-06 completion | Exact final output/descriptor event bijection | missing final output/done, duplicate tag, leak |
| Metadata ownership | Pre-state owner plus combined actions | atomic first-beat commit; return/reuse next edge |
| RST-02 flush | Epoch reset with persistent arrays and physical response schedule | dispatch/pending/full/partial/cell-final/packet-final |
| Monitor completeness | Sealed epoch/cycle sources, explicit idle | missing/duplicate/mixed/stale sample/collector omission |
| Nonvacuity | Required triggers and nonempty evidence rejected | absent dispatch/read/output/return/reset trigger |

## Formal preparation boundary

FP-TX safety uses arbitrary sink readiness; fixed physical response latency and
legal committed descriptor/metadata are assumptions, never inferred from DUT
state. Check outstanding+buffered bounds, ordered response tags, held output,
exact retirement, capture-before-reuse and reset flushing. Progress adds a
separate bounded-stall/ready-sink assumption, then first valid <= L+4 and no
within-packet cell bubble for CELL_WORDS>=2. Covers: full FIFO with pending
response, full response+issue+retire, final hold, fragmented next-cell reuse,
reset during pending and complete resource restoration. Use explicit arbitrary
top inputs and history state that survives reset for fixed witnesses (F01).
Production property binding, prove/cover/mutation, performance and RTL coverage
are NOT_RUN until actual named RTL exists in a later task.

## Qualified expectation corrections

The DV-owned model uses contract length to determine expected final/cell
completion, so a corrupt observed TLAST cannot define its own correct retirement.
Full descriptor information (including head and ncell) is checked independently
at reservation write, commit and dispatch. These are clarifications from the
published interfaces and ownership table, made during checker qualification;
no target implementation informed them. The P07 reuse audit is limited to
`tm_sample`, `tm_stamp`, passive stream sampling, the held-stream assertion and
report termination. No retained expected-byte/policy oracle or checker is reused.
The preparation define excludes those unrelated checkers from compilation.
