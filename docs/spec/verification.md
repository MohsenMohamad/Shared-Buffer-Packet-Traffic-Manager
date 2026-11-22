# Multi-egress verification

Derive independent expectations from the [behavior contract](multi-egress-traffic-manager.md)
and [public ABI](multi-egress-interfaces.md). The
[requirement catalog](../../verification/requirements.json) contains requirement IDs
and expected behavior. Associate test IDs with requirements in suite or coverage
definitions. Publish measured outcomes separately.

## Stimulus, checking and coverage

Use SystemVerilog/UVM drivers and independent passive packet, control, memory
and edge-event monitors. Reconstruct accepted transactions from handshakes.
Check output bytes, metadata, disposition and ordering from independent frame
and resource ownership models. Check trace batches against port observations.
Retain the checked pre-edge state, accepted events and expected next state in
replayable evidence.

Behavioral scoreboards compare each observed transaction live. An atomic
architectural edge is one transaction. Derive pre-edge legality and compare
post-edge state before sampling functional coverage. The SV/UVM campaign
checks required bins, seeded detectors, reproducibility and exact drain. Keep
temporal assertions and formal properties at their respective boundaries.
C/C++ through DPI-C may supply expected values when the reference model is
demonstrably too complex for SV. The SV scoreboard owns the comparison and
verdict.

Python may generate stimulus, launch tools, propagate named tool outcomes
and render emitted results. Missing or failed execution and missing completion
are non-success. Python must never reconstruct observed state, compare DUT
transactions, qualify a fault from trace contents or decide functional coverage
acceptance. Apply the same boundary to behavioral checker qualification.

Run directed cases and seeded stimulus in both profiles, and both fixed read
latencies wherever the memory interface participates. Add targeted cases for
reachable coverage holes. The [implementation plan](../implementation/plan.md#directed-multi-egress-qualification-obligations)
lists important concurrency and threshold witnesses, expected outcomes and
detectors. Use positive neighbors and isolated intended negatives to qualify
detectors. Require observed mandatory bins, reproducible seeds and complete
frame and resource accounting after drain. Report code coverage, functional
coverage and proof results with their respective denominators and scope.

## Preparation and qualification

Follow the [role boundary](../../AGENTS.md#separate-rtl-and-independent-dv-ownership).
During preparation, derive and commit the model, directed witnesses and
coverage rules from the public inputs in a clean, allowlisted projection.
After freeze, bind the prepared checks and [formal properties](formal.md)
to production sources at a named revision. Report fixture replay, production
qualification and composition separately.
