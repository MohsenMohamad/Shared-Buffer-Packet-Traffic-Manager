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
Slang flow does not preserve native `anyseq`/`anyconst` attributes/functions as
native symbolic cells. New production harnesses therefore declare arbitrary
stimulus as explicit top-level input ports. A time-varying input needs no
stability assumption. A fixed arbitrary witness needs an explicit, documented
stability assumption over the entire proof, including later DUT resets.

The following recipe is qualified by [F01](../results/F01-formal-symbols.md)
with `make formal-symbols RUN_ARGS='--timeout 120'` at witness widths 1 and 4
on the pinned stack. New P03 harnesses use this pattern directly:

```systemverilog
module witness_example #(parameter int W=4)
  (input logic clk, rst_n, input logic [W-1:0] witness);
  logic f_history_valid = 1'b0;
  always_ff @(posedge clk) begin
    f_history_valid <= 1'b1;
    if (f_history_valid)
      assume(witness == $past(witness));
  end
  // Property-specific DUT connections/assertions/covers follow.
endmodule
```

The witness is arbitrary initially; it is not sampled from DUT state. The
history-valid bit is initialized once and **not reset by rst_n**. Resetting it
would allow a supposedly fixed witness to change across resets. Any domain/range
restriction is a separate assumption justified by the property. An assumption
that fixes the witness must not inadvertently constrain unrelated traffic.

F01 proves constancy unboundedly, checks the change cover is unreachable through
12 steps, and reaches zero/all-ones witnesses, changing stimulus and a later
reset. The native `anyconst` control has matching outcomes. Rejected Slang
decoration and the missing-assumption negative both fail `a_constant` and reach
`c_witness_change`; unknown symbolic functions are separate frontend rejections.
The reachable covers establish non-vacuity, not a production queue proof.

`tools/registry.py` checks the complete formal source/header registration and
transitive literal includes before staging. `tools/formal_symbols.py` rejects
unqualified `anyseq`/`anyconst` attributes and functions (also `allseq`/`allconst`)
across all conditional branches, including multiline/comment/escaped-name
variants. Slang formal command defines are checked too. Comments and string literals do not introduce symbols. Macro includes,
missing/external headers and token concatenation fail closed because their
source expansion is unqualified. This is a source-policy checker, not an RTL
translator. The only raw-symbol exceptions are the two canonical legacy paths
below, checked through their adapter; same-named copies and diagnostic fixtures
cannot add registry exemptions. `make test-unit` also executes the guard tests.

`tools/frontend.py` retains a narrowly qualified anyseq-to-free-input adapter for
the two legacy harnesses `storage_formal` and `csr_formal`. Do not apply it to
DUT state, assume it translates anyconst, or broaden it into a regex-based general
translator. Explicit unsupported-feature fixtures remain diagnostic exceptions;
they cannot bypass the production-source rule.

The existing `make bridge` route compares property inventories/source locations
and proves mutual inclusion of complete assumption predicates against the native-
supported historical control in `verification/representation.json`, including
startup reset and arbitrary later resets. Its control-state equalities are proved
invariants, not environmental restrictions. Keep those scoped checks, production
unbounded/cover/mutation evidence and immediate-assertion monitor semantics.
Bridge equivalence alone does not establish the hardware specification.
