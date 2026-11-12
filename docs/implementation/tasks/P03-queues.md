# P03: Descriptor queues and simultaneous update correctness

## Objective and prerequisites

Implement descriptor-linked FIFO queues with exact publication/dispatch linearization and safe reuse of stale metadata.

Dependencies: [P02](P02-storage-primitives.md), completed [F01 symbolic-input qualification](F01-formal-symbols.md). Use the qualified recipe and exact command in the [F01 results](../../results/F01-formal-symbols.md).

## Sources and work boundary

- [buffer-management.md](../../spec/buffer-management.md)
- [queues-and-scheduling.md](../../spec/queues-and-scheduling.md)
- [formal.md](../../spec/formal.md)

Also read the relevant APIs in `docs/spec/module-contracts.md`, created by P01, and inspect the integrated dependency implementations before changing their boundaries.

`rtl/queue/`, independent queue tests, `formal/queue/` and queue-suite registration.

## Execution sequence

1. Use P01 query/enqueue/dispatch contracts and the P02 descriptor ownership boundary. The queue controller owns head/tail/count; metadata owns descriptor-next and immutable descriptor information. Implement the descriptor-link array as a reusable production child with the specified single-write/combinational pre-state read boundary, and use it in queue tests/proofs. P05 reuses that child in the metadata wrapper; do not create a second independently owned link array or a behavioral-only substitute.

2. Implement pre-state queue queries and successful-commit publication. An enqueue to an empty queue is not eligible for same-edge dispatch. Removing a descriptor transfers it to TX; it does not free it.

3. Implement every same-queue case from the specification as a merged update. At count one, concurrent dequeue/enqueue returns the old descriptor and leaves the new descriptor as both head and tail.

4. Handle count greater than one and different-queue enqueue/dequeue without losing either change. Keep stale unused links unreset and ensure traversal never follows a stale last-entry pointer.

5. Build an independent list/FIFO model. Run ID reuse and alternating same/different-qid updates across supported queue widths; include empty dispatch attempts and maximum occupancy.

6. Create FP-QUEUE/FP-ORDER harnesses for the production queue controller. Prove ordering/count against an abstract FIFO with explicit legal-owner inputs; preserve those assumptions for caller checking in P11A. Use F01's qualified top-level-input recipe for arbitrary/fixed witnesses, held across later resets. Do not introduce native anyconst/anyseq attributes or unsupported temporal formal syntax into a new Slang harness.

7. Reach last-pop/push and two-qid covers; demonstrate that removing the required last-entry bypass triggers the ordering checker. Register the `queues` simulation and production-proof suites.

## Required checks

| Area | Evidence required |
| --- | --- |
| Queue transition matrix | All empty/singleton/longer same-queue cases, different-qid updates, next-cycle publication visibility and empty dispatch rejection. |
| Reuse | Returned IDs reused with stale link contents; multiple queue-count widths; no descriptor returned merely at dispatch. |
| Order proof | Unbounded reduced production-controller FIFO order/count result, reachable collision covers and intended last-entry mutation detection. |

## Completion

The queue portion of G2 and required local FIFO-order proof are established. Caller ownership enforcement remains an explicit composition obligation, not an unproven implicit assumption.

Requirement focus: `Q-01`, `Q-02`, `Q-03`, `Q-04`, `Q-05`, `MEM-01`, `PAR-01`

## Component result

Implemented with the production controller/link child and local verification in
[P03 results](../../results/P03-queues.md). P04 scheduler, P05 metadata/TX
integration and P11A caller-ownership discharge retain their separate scope.
