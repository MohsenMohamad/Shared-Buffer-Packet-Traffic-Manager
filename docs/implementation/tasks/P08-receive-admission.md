# P08: Interleaved receive, admission and abort cleanup

## Objective and prerequisites

Implement per-input receive/drain state and atomic packet reservations so malformed or competing inputs cannot corrupt or strand shared resources.

Dependencies: [P02](P02-storage-primitives.md), [P03](P03-queues.md), [P05](P05-memory-tx.md), [P07](P07-verification-foundation.md), [P02 scaling follow-up](P02-followup-scaling.md), [P07 stimulus follow-up](P07-followup-stimulus.md), [A01 allocator disposition](A01-allocator-selection.md), [R01 reset convention](R01-reset-timing.md)

## Sources and work boundary

- [interfaces.md](../../spec/interfaces.md)
- [buffer-management.md](../../spec/buffer-management.md)
- [registers.md](../../spec/registers.md)
- [verification.md](../../spec/verification.md)
- [formal.md](../../spec/formal.md)

Also read the relevant APIs in `docs/spec/module-contracts.md`, created by P01, and inspect the integrated dependency implementations before changing their boundaries.

`rtl/rx/`, `rtl/admission/`, `rtl/reclaim/`, component integration with real pools/store/queues, receive UVM tests and `formal/credit/`.

## Execution sequence

1. Connect actual P02 pools, P03 queue publication and P05 store/return contracts. Drive static configuration through P01 APIs in the component bench; P06 CSR hardware is wired at P09, not duplicated here.

2. Implement rotating beat-level RR across eligible ingress FIFO heads. Advance on actual service, not capture; input gaps, temporary WAIT shortages or a malformed draining source must not block other eligible inputs.

3. Validate qid before indexing and declared length before computing/reserving a budget. Evaluate admission against pre-cycle U/free-descriptor/H and merge all simultaneous deltas once, with widened arithmetic.

4. Implement DROP/WAIT and reason priority. In WAIT mode leave temporary shortages unserviced, but reject a packet whose cell budget exceeds its static queue cap. Reserve the complete cell budget and one descriptor atomically.

5. Allocate physical cells only for well-formed beats that require them. Update chain metadata with explicit ports. Handle admission plus single-beat EOF using valid newly allocated metadata; publish only after the final valid write.

6. On malformed framing stop writes before the invalid beat, mark abort and drain. For a first-beat format error reserve/count admission but allocate no payload cell; defer descriptor cleanup until at least the next edge.

7. Implement fair abort-context rotation under TX cell-return priority, at most one physical cell return per cycle and up to two descriptor returns. Release the full logical reservation exactly once at abort completion. Never follow a zero-cell head or a stale reclaimed link.

8. Implement status timing and per-input reuse gating: rejected-header status need not wait for drain, whereas FRAME_ERROR waits for cleanup; an aborted input starts a new packet only after drain and cleanup both complete.

9. Run real receive-component tests through the P07 agents/checkers. Assert every accounting equation after combined event batches and begin reduced production ownership/credit proofs; P11A closes the composition.

## Required checks

| Area | Evidence required |
| --- | --- |
| Admission | U=n/n-1, exact/over queue caps, descriptor exhaustion, reason collisions, four captured headers and conservative same-cycle release. |
| Framing | Bad metadata, sparse/partial keep, early/missing/late TLAST, single-beat success, first-beat zero-cell abort and source gaps. |
| Cleanup/concurrency | Several aborts with TX returns/new reservations, exact status timing, no descriptor same-edge allocate/free, complete recovery and reset. |
| Accounting | A+F=N, F=U+R, U+sum(H)=N, unique ownership and independently checked service/admission/status causality. |

## Completion

The receive/resource portion of G2 exercises real storage/queue/pool boundaries with executable independent checking. All required admission/format cases are represented; captured data are never mislabeled as admission or commit.

Requirement focus: `ADM-01`, `ADM-02`, `ADM-03`, `ADM-04`, `ADM-05`, `ADM-06`, `ADM-07`, `ADM-08`, `FMT-01`, `FMT-02`, `FMT-03`, `FMT-04`, `FMT-05`, `FMT-06`, `LEN-03`, `MEM-02`, `MEM-06`, `RST-02`

## Additional entry and timing checks

The P02 scaling and P07 stimulus follow-ups are integrated. Before P08, complete the [A01 allocator evaluation/disposition](A01-allocator-selection.md) and [R01 reset timing convention](R01-reset-timing.md). Use the actual selected allocator under its reviewed contract and the qualified [F01](F01-formal-symbols.md) harness recipe. Recheck the actual allocator consumer path through receive/admission at production capacity, including 1024 cells, under identified tool/library and timing constraints. Report selection-path and overall worst-path timing, fanout and constraint coverage; compare with the standalone findings and distinguish exploratory conditions from any agreed F0 acceptance requirement.

## RTL PR

Steps 1–8 implement real RX/admission/reclaim and production wiring/embedded assertions with separate designer smoke. Coordinate spec/API ownership with DV.

## Independent DV PR

Own step 9 and every admission/framing/cleanup/accounting acceptance row, real-component UVM tests, coverage, local proofs and intended defects. Develop early against APIs; final qualification uses merged actual pools/store/queues/RX. P11A discharges composition; retain consumer-path timing analysis as a distinct measured obligation.

Follow the [separate-owner defect/fix/reverify gates](../plan.md#ownership-and-verification-gates); hardware fixes use another RTL PR.
