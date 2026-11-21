# Queue and resource control experiment definition

Use the published 4×4 (1,024 cells, 256 descriptors, 1,536-byte maximum) and
2×2 (16 cells, 8 descriptors, 192-byte maximum) profiles. Both retain two
capture beats, four staging cells, eight dispositions, six prefetch slots
and two bound frames per port. The external memory is 512-bit 1R1W at
latencies 1 and 2. The experiment tracks beat lengths and physical cell
identity. Payload SRAM, byte storage and the AXI control peripheral are
outside mapped area.

## Candidates and timing boundaries

| Organization | State and available ports | Edge boundary |
| --- | --- | --- |
| Direct | One descriptor metadata write, one asynchronous lookup per queue from its head ID, a descriptor-indexed queue successor store with one global append and one read per egress | Publish at final write + 1. Bind using old head and old tokens. Dispatch capture registers the payload cursor and frame metadata. |
| Cached | Identical descriptor store and append. Keep one metadata record per queue, with at most one successor metadata lookup per egress. | Empty append and singleton replacement load from publication. Non-singleton pop refills from the old successor, with prior publication visible. Same-edge publication cannot alter the selected head. All refill paths must reach the cache for the next edge. |
| Registered read request | Cached head organization, with one additional edge from binding to memory request eligibility | Dispatch still pops and charges on time. The active or successor slot owns the frame immediately. The request cursor becomes eligible at binding + 2 instead of + 1. Replay this change with identical traffic and capacities if evaluated. |

The admission cone selects distinct lowest pre-edge-free descriptor IDs. A
rotated prefix processes full-width route and length validation, permanent
queue feasibility, resource checks and temporary queue eligibility. It
consumes reservation credit before considering the next lane. Compute
protected free from all old occupancies and carry its prefix delta. Multiply
unsigned 13-bit alpha by widened nonnegative shared remainder, then shift
right by eight once. Apply DROP/WAIT and feed grant IDs and decisions to
registered receive state. One hierarchical first-free cell selector feeds a
registered write address and updates the physical bitmap. Pool updates include
one allocation and all physical return lanes. Admission maintains merged
queue and global credits with TX and cleanup releases.

Cell links have one append-write port and independent combinational TX and
abort lookups. Cursors capture links before reclaim. Inactive entries may
contain stale links or metadata. Validity and exclusive ownership preclude
lookup/write alias on a live link. One final-write slot can publish and
receive a new final on the same edge. RX/cleanup/write/read rotate after
their legal trigger as specified, admission after the first serviced
decision. Return lanes never feed eligibility on their returning edge.
A cleanup request appears on the edge after marking, including when the
marking edge completed an earlier staged write. Payload response tags reserve
credit from issue through acceptance of each cell final. Response visibility
starts on issue + L + 1. Reset asynchronously invalidates control state,
with data and link arrays guarded by live state.

## Directed matrix and acceptance

| Matrix group | Required observations and neighboring cases |
| --- | --- |
| Publish/pop | All egresses bind. Target queue is singleton, longer, then empty. Check old selection, successor, merged bitmap, and next-edge B. Consecutive final writes exchange the slot. |
| Prefix/return | Rotated old last descriptor with simultaneous return; DROP, WAIT and next-edge reuse. All lanes grant with independent materialization and returns. Primary-only maximum is four grants and five return lanes. |
| Cleanup | Coincident TX finals and independent last reclaim, zero-cell cleanup, old staged write with new mark, continuous read/cleanup contention. Test both port counts; the four-edge and 4×k bounds apply to primary. |
| Arithmetic | U=10 versus U=9 at alpha 64 and n=2, zero minima; same-queue prefix; exact static capacity; malformed first beat; invalid route precedes bad length. Test both profiles with capacity-adjusted occupied credit. |
| Binding | 17→16 beat lookahead, strict arrival before/on binding, irrevocable bind, 64.75 versus 65 bytes at old-state credit with 0.5 refill, parked DRR visit. |
| Prefetch | Six slots including response, stall cell-final, simultaneous response/retire/other issue. Measure first-cell issue, response and visibility at L=1 and L=2. |
| Negatives | Preserve legal traces. Deliberately inject early publication, returned-ID bypass, lost cleanup lane, and early response eligibility independently; require the intended detector. |

Replay the original model and reuse its workload definitions. Primary
acceptance is all 9,216 RX and TX beats per port in each latency × balanced
sequence combination after 2,048 warm-up edges. Finish offered frames,
reconcile outcomes and drain every owner. Replay seeded independent ingress
lengths and bounded stall, DROP/WAIT incast, synchronized returns and cleanup.
Diagnostic misses remain visible. The small profile uses legal repeated
60/65/192 and a profile-bounded mixture as an additional diagnostic.

## Mapping and scoped R01 reference

Use pinned Yosys/Slang, bundled ABC and OpenSTA, Nangate45 typical
(1.10 V, 25 °C), ideal 10 ns rising clock, 0.10 ns uncertainty, fixed 0.05 ns
data and reset slew and 10 fF per output. ABC uses the existing BUF_X1/10 fF
recipe. Data min/max input and output delays are 0.2/2.0 ns. Reset asserts
asynchronously. Reference release is modeled relative to the rising
environment launch edge, with 0.2/2.0 ns min/max and separate falling
assertion treatment. The 0.2 ns release is the historical sensitivity
reference. A bench falling-edge drive is a functional stimulus phase.
Require explicit recovery/removal and obtain the input arrival envelope
from the worst slacks with all other assumptions fixed. Actual reset
closure remains conditional on a characterized upstream source and
distribution. Retain negative data and reset slacks.

A feasible control recommendation needs correct directed behavior and drain,
the primary balanced target, and nonnegative setup/hold for each live data
cone at both sizes. Require mapped state/consumer coverage, no unintended
unmapped cells, and supported timing checks. Keep timing-ceiling misses
and any omitted logic explicit. A visibility or ownership contract change
requires maintainer review. A scoped open gate is a valid outcome.

## Admission lookahead after the serial-prefix measurement

Measure a second admission implementation after the serial prefix shows a
primary setup violation. For each lane, compute the static or dynamic fit for
each possible earlier-grant subset in parallel. The actual earlier results
select the matching subset. Precompute up to four ranked IDs from the old
descriptor bitmap and select by the number of earlier grants. The accepted
prefix and same-edge return merge still update the existing registered RX
consumer and resource state. This transformation adds combinational
replication but no clock cycle or ownership boundary. Use the same SDC, reset
reference, area and endpoint criteria. Compare variants with matched
edge-level RTL checks before interpreting timing.

## ABC runtime sensitivity

The reference measurement uses the default allocator mapping recipe. On
large register-array cones, also compare the bundled ABC fast Liberty
mapping script with the same frontend, Liberty, external drive/load
constraints and STA. Identify the mapping script for every number. Fast
and default results can establish sensitivity to synthesis, and matched
architecture comparisons use the same mapping script.
