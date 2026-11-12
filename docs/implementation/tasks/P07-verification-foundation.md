# P07: UVM agents, monitors and independent models

## Objective and prerequisites

Build an executable genuine UVM foundation with independent observed-transaction models before the whole TM is available.

Dependencies: [P01](P01-contracts.md)

## Sources and work boundary

- [interfaces.md](../../spec/interfaces.md)
- [verification.md](../../spec/verification.md)
- [toolchain.md](../../spec/toolchain.md)
- [automation.md](../../spec/automation.md)

Also read the relevant APIs in `docs/spec/module-contracts.md`, created by P01, and inspect the integrated dependency implementations before changing their boundaries.

`dv/agents/`, `dv/model/`, `dv/env/`, `dv/tests/`, initial coverage collectors and UVM-foundation runner registration.

## Execution sequence

1. Qualify new sequencer/driver, analysis-port, register/RAL and coverage constructs beyond P00 using small capability cases. Use the pinned UVM library's qualified frontdoor configuration. The no-DPI baseline is a tested service selection, not a universal prohibition; see the [current capability dispositions](../modern-toolchain-decisions.md).

2. Implement packet source/sink agents and AXI4-Lite master/monitor components. Independently randomize valid gaps, ready stalls, AW/W separation and B/R response acceptance. Monitors reconstruct actual handshakes rather than reusing driver intention objects.

3. Define packet identity by source/frame ordinal/epoch with qid and bytes. Preserve duplicate tags, non-SOP metadata behavior and final keep. Reset creates a new epoch and cancels pre-reset expectations.

4. Implement the service-event checker against captured input FIFO contents. Model admission using independently reconstructed scalar credit/queue state; validate disposition/commit causality instead of trusting DUT-reported success or drop.

5. Implement an abstract queue/dispatch policy model and separate black-box packet scoreboard. Batch same-cycle events using P01's pre-state semantics. Do not copy physical cell allocation or linked-list algorithms into the expected model.

6. Build passive coverage collection for the implemented interactions. Keep requirement-driven crosses bounded and preserve unhit bins. Establish assertion binding that later accepts the actual TM trace interface.

7. Exercise a small explicitly named fixture through the complete UVM sequencer/driver/monitor/model path. Inject payload corruption, duplicate/lost delivery and inconsistent service/status events to prove the corresponding checkers can fail.

8. Register `uvm-foundation` as a fixture suite. Save real code/functional coverage and deterministic replay. Full production-model wiring occurs in P09; a successful fixture is not a PASS for the TM's end-to-end requirements.

## Required checks

| Area | Evidence required |
| --- | --- |
| UVM execution | Actual timed sequencer/driver transactions, analysis-port delivery and frontdoor register access using qualified language/library features. |
| Independence | Expected bytes from monitor handshakes, duplicate tags, reset epochs and complete same-cycle batching. |
| Checker qualification | Corruption, duplicate/lost delivery and inconsistent service/status fixtures fail at the intended checker; valid fixture passes. |
| Collection/replay | Saved nonzero code/functional coverage, reproducible same-seed stimulus and independent ready/valid timing. |

## Completion

An executable UVM foundation with qualified models/checkers is available to P08/P09. Fixture results and unimplemented production checks remain distinct.

Requirement focus: `IF-01`, `IF-03`, `LEN-01`, `Q-01`, `CSR-02`, `CSR-03`, `RST-02`

## Qualified follow-up

The [checker readability and constrained packet stimulus follow-up](P07-followup-stimulus.md)
is qualified on its candidate branch before P08. Cleanup precedes generator
functionality in separate commits; the [follow-up record](../../results/P07-followup-stimulus.md)
retains exact positive/negative, coverage and replay evidence. This fixture
qualification does not close production integration requirements.
