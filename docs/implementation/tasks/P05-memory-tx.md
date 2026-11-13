# P05: Finite-port packet store and transmit engine

## Objective and prerequisites

Implement the actual finite-port store and a transmit engine whose prefetch cannot overwrite output data or release live cells.

Dependencies: [P03](P03-queues.md)

## Sources and work boundary

- [interfaces.md](../../spec/interfaces.md)
- [buffer-management.md](../../spec/buffer-management.md)
- [queues-and-scheduling.md](../../spec/queues-and-scheduling.md)
- [formal.md](../../spec/formal.md)
- [implementation.md](../../spec/implementation.md)

Also read the relevant APIs in `docs/spec/module-contracts.md`, created by P01, and inspect the integrated dependency implementations before changing their boundaries.

`rtl/memory/`, `rtl/tx/`, memory/TX benches, `formal/tx/` and memory-TX suite registration.

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

## RTL PR

Steps 1–5 implement finite-port store/metadata/TX, embedded assertions and separate designer smoke. Coordinate API changes with DV.

## Independent DV PR

Develop early; own tests/models/scoreboards for steps 6–7, independent proof/cover/mutation and registration in step 8, and all required acceptance rows. Final qualification runs merged RTL at both latencies; RTL merge precedes passing DV merge. No delayed-memory fixture substitutes for structural hardware.

Follow the [separate-owner defect/fix/reverify gates](../plan.md#ownership-and-verification-gates); hardware fixes use another RTL PR.
