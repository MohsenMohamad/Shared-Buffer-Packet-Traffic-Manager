# P05: Finite-port packet store and transmit engine

## Objective and prerequisites

Current stage: fresh independent verification preparation from specifications
and public declarations only. Prepare the finite-port store/TX expectations and
qualified bench before a fresh RTL task. This preparation establishes no
hardware acceptance.

Dependencies: [P03](P03-queues.md)

Prepared evidence is in [PR #23 results](../../results/P05-fresh-dv-preparation.md).
All six scoped oracle/UVM profiles pass; the report records a confirmed pre-model dependency RTL/results exposure.
Independence acceptance is not established and requires independent review. This remains a
preparation PR, with no hardware acceptance or automatic RTL handover.

## Sources and work boundary

- [interfaces.md](../../spec/interfaces.md)
- [buffer-management.md](../../spec/buffer-management.md)
- [queues-and-scheduling.md](../../spec/queues-and-scheduling.md)
- [formal.md](../../spec/formal.md)
- [implementation.md](../../spec/implementation.md)

Also read the relevant APIs in `docs/spec/module-contracts.md`, created by P01, and follow the [root workflow](../../../AGENTS.md#preparation-implementation-and-independent-qualification)
for source access, preparation acceptance and candidate/merged-source gates.

`rtl/memory/`, `rtl/tx/`, memory/TX benches, `formal/tx/` and memory-TX suite registration.

## Later RTL and production-DV scope

The root policy defines the current preparation acceptance criteria. The
following implementation/check obligations remain for later separately assigned
tasks; this card does not authorize automatic handover.

## Execution sequence

1. Use P01 RAM/descriptor/link contracts and P03 dispatch ownership. Implement the logical 64-bit 1R1W payload interface with fixed one/two-cycle responses and no response backpressure. Complete the production metadata wrapper: reuse P03's descriptor-link child, add the single-writer cell-next and descriptor-info arrays, and preserve the documented two cell-link read muxes, per-queue head-info queries and queue-next query. Keep all array owners unique and include their finite ports in tests/area scope.

2. Define bounded buffered-plus-outstanding accounting before issuing reads. Include simultaneous response arrival and output handshake in the credit update, preventing overissue at exact capacity.

3. Separate read/prefetch progress from external retirement. Carry cell/packet boundary metadata with responses or use independently checked cursors; do not free whichever cell the prefetch cursor currently names.

4. Generate exact output bytes, keep/last/user and preserve them under stalls. Capture the next-cell link before reuse. Return a cell only on its last externally accepted beat and the descriptor only at final packet completion.

5. Flush pending response tags, FIFO entries and TX state on reset without clearing payload RAM. A pre-reset response must never validate post-reset data.

6. Test both latencies at matched contents using distinct byte patterns over word/cell boundaries, partial final cells and rapid reuse. State metadata link-read ports/latency rather than inventing unlimited RAM ports.

7. Check dispatch-to-first-valid and steady multi-beat behavior under an always-ready sink. Diagnose cell-boundary bubbles against the specified bound rather than hiding them in throughput averages.

8. Register `memory-tx` simulation/proof suites. Prove reduced production read-credit and retirement safety with arbitrary sink stalls; reach stalled-pending-read covers and detect omission of outstanding-read credits. Physical banked comparison work is completed in P12; a delayed behavioral read alone does not establish it.

## Required checks

| Area | Evidence required |
| --- | --- |
| Data and timing | Partial words/cells, multi-cell patterns, fixed read latencies 1/2, exact FIFO credit boundaries and long immediate stalls. |
| Ownership/reset | Correct cell/descriptor retirement, captured next link, rapid reuse, pending responses at reset and no stale output. |
| Port/performance | At most 1R1W, no ownership-forbidden collision, specified first-valid bound and measured within-packet/cell-boundary behavior. |
| Proof/checker | Production credit/retirement properties, reachable pressure, and intended outstanding-credit mutation detection. |

## Completion

The memory/TX portion of G2 has real byte/latency/ownership checks for both response latencies and scoped safety evidence. Any missed specified timing/performance bound is identified before dependent integration.

Requirement focus: `IF-01`, `LEN-01`, `LEN-02`, `MEM-03`, `MEM-04`, `MEM-05`, `RST-02`, `PERF-01`

## Role assignments

- RTL: steps 1–5, store/metadata/TX implementation, embedded assertions and designer smoke.
- Independent DV: tests/models/scoreboards in steps 6–7, proof/cover/mutation and
  registration in step 8, and all required acceptance rows.

[Root ownership policy](../../../AGENTS.md#separate-rtl-and-independent-dv-ownership).
