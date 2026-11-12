# Functional formal verification

### Proof result vocabulary

- **Proved:** safety property established by an unbounded method for the stated elaborated configuration and assumptions.
- **Bounded checked:** no counterexample through the stated depth; never relabel as unbounded.
- **Cover reached:** demonstrates reachability of a scenario, not correctness.
- **Failed:** a counterexample exists; investigate whether DUT, property or assumptions are wrong.
- **Inconclusive/timeout:** no correctness claim obtained.
- **Equivalence:** behavior matches the chosen reference implementation; does not independently establish its specification.

Retain separate proof statuses per property family. Passing the cell allocator does not prove the full memory manager; proving the queue controller does not prove data bytes survived the payload RAM.

### Required proof families

| Formal ID | Target | Properties | Scope/assumption boundary |
|---|---|---|---|
| FP-ALLOC | Cell pool | Allocation only from a free cell; no duplicate live allocation; count equals free bitmap population; valid/invalid release handling; simultaneous allocation/return. | Local API assumptions are explicit. Prefer proving invalid-return handling rather than assuming it away. |
| FP-DESC | Descriptor pool | Unique descriptor ownership, two simultaneous returns, no count under/overflow, no stale reuse while RX/TX/abort still references it. | Compose local pool proof with ownership controller checks. |
| FP-CREDIT | Admission/reservation | U+sum(H)=N; physical F=U+R; reservations are not overbooked; abort unused/reclaimed credit is released exactly once. | Finite full control configuration, payload abstracted only where data do not affect control. |
| FP-QUEUE | Queue control | Counts and head/tail match an independent abstract FIFO; no loss on last-pop+enqueue; per-queue order for arbitrary operation duration. | Enqueued descriptor is owned and not already queued. Prove the caller enforces that contract separately. |
| FP-TX | Read/output control | Bounded buffered+outstanding reads; no response loss/overwrite; stable stalled output; exactly-once cell retirement; no read after reuse. | Fixed 1/2-cycle RAM response contract. Do not assume sink readiness for safety properties. |
| FP-SCHED | DRR control | Grant eligibility, byte-credit add/subtract discipline, deficit bounds and empty handling. | Arbitrary legal queue events. Progress tasks add separate explicit fairness assumptions. |
| FP-ORDER | Selected per-queue order | An unbounded independent FIFO-order proof on the production queue controller is mandatory. Symbolic packet tracking through a larger integrated commit-to-output path is a stretch task. | Reduced configuration; report exact dimensions and any payload abstraction. Do not imply that a local FIFO proof proves the complete payload path. |
| FP-CSR | Register slave | Independent AW/W capture, stable responses, one response per accepted request, rejected writes do not mutate state. | Legal AXI input stability, arbitrary response backpressure. |

Initial integrated formal profile SHOULD use two input contexts, two queues, four descriptors and eight cells with short bounded packet lengths. That is a reduced formal elaboration, not F0. Increase dimensions only where runtime remains useful. Production-module parameter constraints and formal abstraction knobs must be separate and documented.

### Assumptions, covers and composition

Assume only legitimate environment behavior: clock/reset contract, stable ready/valid source fields while stalled, and a fixed-response-latency memory model. Malformed packet lengths/keep/last are intentionally tested and must not all be assumed legal in a task claiming format/cleanup safety.

For liveness, a progressing sink or a bounded-stall assumption may be necessary. Keep such assumptions out of unrelated safety tasks. If a source never finishes a frame, the spec permits that input to remain draining; it does not permit corruption of other queues.

For every major assumption, document what behavior it excludes and why that exclusion is legitimate. Never constrain away the queue-update collision, empty transition, full buffer or output stall being verified.

Required covers include allocation-to-full, invalid return rejection, simultaneous allocate/free, nonempty queues on two qids, same-queue last-pop+push, admission at an exact credit boundary, output stalls with pending responses, an abort followed by full resource recovery and reset during active work.

Use immediate assertions and explicit monitor state where required by the formal frontend. Maintain matching simulation SVA for the qualified simulator subset. A property ported between simulation and formal must retain its semantics even when its syntax differs. Record unsupported constructs explicitly; never suppress them as a verification workaround.



## Execution requirements

Proof tasks target production modules. A feasibility example or reference-model proof cannot substitute for the corresponding production-module proof. Save each task's configuration, source revision, assumptions, engine status and elapsed time. Reachability covers and selected defect mutations qualify the checker. Distinguish expected mutation failures from unexpected failures.

Selected conservation, ownership, occupancy and queue-order safety claims require passing unbounded results at documented reduced configurations. Additional integrated symbolic payload tracking is a stretch task. A timeout remains inconclusive; do not change the property into a weaker statement just to obtain PASS.

## Selected frontend and arbitrary inputs

Use the frontend registered in `verification/sources/formal.json`. The pinned
`read_slang` flow does not preserve native `anyseq`/`anyconst` declarations as
symbolic cells. `tools/frontend.py` exposes the unchanged production harness's
arbitrary internals as free top-level inputs; it preserves every expression,
assumption, assertion, cover and state update. Do not apply it to DUT state.
`make bridge` compares property inventories/source locations and proves mutual
inclusion of the complete assumption predicates against the native-supported pre-migration Git control in
`verification/representation.json`,
including startup reset and arbitrary later resets. Its additional control-state
equalities are proved invariants, not new environmental assumptions. Retain
production unbounded/cover/mutation checks; bridge equivalence alone is insufficient.
