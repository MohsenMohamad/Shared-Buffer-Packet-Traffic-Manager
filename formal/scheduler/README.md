# FP-SCHED scope

`make formal-rtl RUN_ARGS='--test scheduler --timeout 240'` targets the production
`tm_drr_api` in DRR and packet-RR elaborations at N_RX=1, N_Q=2, N_CELL=16,
N_DESC=8, CELL_BYTES=16, MAX_PACKET_BYTES=128. This is a named reduced formal
configuration, not the full E0/F0 system.

The harness uses arbitrary top-level inputs and two initial reset samples.
Later resets, RUN, TX readiness and completion timing are arbitrary. Quanta are
fixed at arbitrary legal per-queue values 64..4096, even across resets. Completion
requires TX ownership. No ready/progress/fairness bound is assumed for safety.

The P03 query boundary is abstracted by merged count transitions (0..2 entries
per qid), immutable pre-state heads until pop, and selected lengths 1..MAX.
A new commit cannot bypass an empty pre-state queue. Counts permit same/different
qid commit/dispatch collisions, singleton replacement, true empty/reactivation
and arbitrarily long TX stalls. Actual P03 queue/link composition is exercised
separately by the scheduler UVM suite and P03's production FIFO-order proof.
This proof does not establish payload, descriptor allocation or integrated TX
correctness.

Properties check accepted grant eligibility and head identity, baseline dispatch
presence, per-edge add/subtract/clear equations, unchanged credit and visit state
through busy/completion edges, TX ownership, and inclusive arithmetic bounds.
Inductive invariants require a closed visit's credit to be below MAX_PACKET_BYTES.
All safety results use unbounded k-induction; covers have depth 16. Covers reach
singleton replacement followed by stalled TX completion, true empty/reactivation,
longer same-qid and different-qid updates, a readiness wait, DRR carry and a
continuing visit. DRR-only credit covers are absent from the RR elaboration.

The source-copy mutation adds a second quantum only when a continuing packet
already fits and TX can accept it. Qualification requires an `a_credit`
counterexample, a failed engine status and a nonempty trace. The UVM regression
independently requires the corresponding `SCHEDULE_CREDIT` failure. Neither a
frontend crash nor an unrelated property failure qualifies the mutation.
