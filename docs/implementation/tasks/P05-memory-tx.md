# P05: Finite-port packet store and transmit engine

## Objective and prerequisites

Current stage: **MERGED-SOURCE PASS** for the scoped RAM/metadata/TX component
at PR #24 merge `3ede1a5e40791ff00d98a0faa8389154d632e0c5`.
Production confirmation uses tested DV/combined revision
`fd129b1e0d7566c460962b6869aa2274f7a24fa9`, tree
`c1c3033decc4fc1b16aab4702ac9da4714ef2353`. See
[qualification and merged-source evidence](../../results/P05-candidate-qualification.md)
and [public interface results](../../results/P05-candidate-public.json).
The required full DV and main runs passed as recorded on
[DV PR #26](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/26).
See [integration status](../../status.md) for the post-merge checkout repair.

Dependencies: [P03](P03-queues.md)

Prepared evidence is in [PR #23 results](../../results/P05-fresh-dv-preparation.md).
All six scoped oracle/UVM profiles pass; the report records a confirmed pre-model dependency RTL/results exposure.
Historical preparation independence acceptance is not established and requires
independent review. The subsequent candidate and actual merged-source results
do not retroactively clear that caveat. Preparation alone established no hardware
acceptance; current component evidence and its limits are recorded separately.

## Sources and work boundary

- [interfaces.md](../../spec/interfaces.md)
- [buffer-management.md](../../spec/buffer-management.md)
- [queues-and-scheduling.md](../../spec/queues-and-scheduling.md)
- [formal.md](../../spec/formal.md)
- [implementation.md](../../spec/implementation.md)

Also read the relevant APIs in `docs/spec/module-contracts.md`, created by P01, and follow the [root workflow](../../../AGENTS.md#preparation-implementation-and-independent-qualification)
for source access, preparation acceptance and candidate/merged-source gates.

`rtl/memory/`, `rtl/tx/`, memory/TX benches, `formal/tx/` and memory-TX suite registration.

## Implemented RTL and production-DV scope

The following obligations define the delivered implementation and production-DV
scope. Verification uses unchanged specification-derived expectations and actual
integrated RTL; original candidate/proof executions retain their identities.

## Execution sequence

1. Use P01 RAM/descriptor/link contracts and P03 dispatch ownership. Implement the logical 64-bit 1R1W payload interface with fixed one/two-cycle responses and no response backpressure. Complete the production metadata wrapper: reuse P03's descriptor-link child, add the single-writer cell-next and descriptor-info arrays, and preserve the documented two cell-link read muxes, per-queue head-info queries and queue-next query. Keep all array owners unique and include their finite ports in tests/area scope.

2. Define bounded buffered-plus-outstanding accounting before issuing reads. Include simultaneous response arrival and output handshake in the credit update, preventing overissue at exact capacity.

3. Separate read/prefetch progress from external retirement. Carry cell/packet boundary metadata with responses or use independently checked cursors; do not free whichever cell the prefetch cursor currently names.

4. Generate exact output bytes, keep/last/user and preserve them under stalls. Capture the next-cell link before reuse. Return a cell only on its last externally accepted beat and the descriptor only at final packet completion.

5. Flush pending response tags, FIFO entries and TX state on reset without clearing payload RAM. A pre-reset response must never validate post-reset data.

6. Test both latencies at matched contents using distinct byte patterns over word/cell boundaries, partial final cells and rapid reuse. State metadata link-read ports/latency rather than inventing unlimited RAM ports.

7. Check dispatch-to-first-valid and steady multi-beat behavior under an always-ready sink. Diagnose cell-boundary bubbles against the specified bound rather than hiding them in throughput averages.

8. Register `memory-tx` simulation/proof suites. Prove reduced production read-credit and retirement safety with arbitrary sink stalls; reach stalled-pending-read covers and detect omission of outstanding-read credits. Physical banked comparison remains separate P12B work; a delayed behavioral read alone does not establish it.

## Required checks

| Area | Evidence required |
| --- | --- |
| Data and timing | Partial words/cells, multi-cell patterns, fixed read latencies 1/2, exact FIFO credit boundaries and long immediate stalls. |
| Ownership/reset | Correct cell/descriptor retirement, captured next link, rapid reuse, pending responses at reset and no stale output. |
| Port/performance | At most 1R1W, no ownership-forbidden collision, specified first-valid bound and measured within-packet/cell-boundary behavior. |
| Proof/checker | Production credit/retirement properties, reachable pressure, and intended outstanding-credit mutation detection. |

## Completion

| Current P05 evidence | Status and boundary |
| --- | --- |
| Production data/metadata/credit/ownership/reset checks | PASS across the retained six-profile matrix; fresh sixteen-run integrated I1 confirmation also passes. |
| Exact merged source | PASS at the RTL merge above. All sixteen fresh trace hashes match the original corresponding runs. |
| Reduced FP-TX | Four unbounded safety proofs and all required covers/mutation detections retain applicability through verified input equality; arbitrary sink stalls remain permitted. |
| Transaction/resource shutdown and saved coverage | PASS; no live resource or response obligation remains. Numeric code counters do not establish coverage closure. |
| Final hosted integration gate | Required full DV and main runs passed. The full main run after the PR #27 checkout repair also passed. |
| Remaining scope | Historical preparation provenance review, caller/pool composition and P12B structural comparison remain separate; no retroactive independence or structural signoff is claimed. |

The memory/TX portion of G2 has real byte/latency/ownership checks for both response latencies and scoped safety evidence. Any missed specified timing/performance bound is identified before dependent integration.

Requirement focus: `IF-01`, `LEN-01`, `LEN-02`, `MEM-03`, `MEM-04`, `MEM-05`, `RST-02`, `PERF-01`

## Role assignments

- RTL: steps 1–5, store/metadata/TX implementation, embedded assertions and designer smoke.
- Independent DV: tests/models/scoreboards in steps 6–7, proof/cover/mutation and
  registration in step 8, and all required acceptance rows.

[Root ownership policy](../../../AGENTS.md#separate-rtl-and-independent-dv-ownership).
