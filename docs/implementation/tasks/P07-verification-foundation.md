# P07: UVM agents monitors and independent models

## Dependencies

P01

## Relevant contracts

- [ interfaces.md ](../../spec/interfaces.md)
- [ verification.md ](../../spec/verification.md)
- [ toolchain.md ](../../spec/toolchain.md)
- [ automation.md ](../../spec/automation.md)

## Scope and primary paths

dv/agents/; dv/model/; dv/env/; dv/tests/; verification/requirements.json

## Deliverable

Build reusable packet source/sink and AXI4-Lite agents, passive monitors, sequence items, model interfaces and a real UVM environment. Use a small declared component fixture to exercise the bench before full TM integration. Expected bytes originate from monitored captures. Batch trace events and independently validate service/admission/status causality. Do not copy the RTL allocator or linked list into the reference model.

## Validation

Actual sequencer/driver transactions, analysis-port delivery, duplicate tags, partial final words, independent AW/W order, sink/source stalls, reset epochs and a deliberately corrupting fixture detected by the scoreboard. Qualify UVM/RAL/coverage constructs actually used.

## Exit condition

Executable verification foundation. A fixture result is labeled separately from production TM verification.

Deliver one cohesive reviewable change. If the card is larger than a safe single change, split it along tested component boundaries and record what remains. State actual executed commands/results and unresolved limits in the PR. Update a compact handoff only when unfinished work needs continuation.
