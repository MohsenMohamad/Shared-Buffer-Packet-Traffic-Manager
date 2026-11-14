# R01 reset timing definition

This definition is committed before new measurements. It freezes events, model,
conditions and decisions for R01; [config.json](config.json) owns numeric values.
Original allocator SDCs/results and historical FIFO results remain unchanged.

## Events and model boundary

`clk` rises at 0, 10, 20 ns and falls at 5, 15 ns. Functional actions sample
rising edges. `rst_n` asserts on a falling signal transition asynchronously and
must remain low over at least two rising clock edges. Deassertion is its **rising
signal transition**. Recovery checks that release precedes the next rising clock;
removal checks that release follows the previous rising clock. Assertion is not
the release event. No case analysis, false path, disabled timing or multicycle
exception is permitted for reset. Both transition senses remain timed to retain
reset gating effects; recovery/removal use the library's active reset arcs.

The reference model launches release at the ideal **falling clock edge**, with
0..0.2 ns transport to the block input. At 10 ns this means an absolute block-port
release envelope of 5.0..5.2 ns after the preceding rising clock. These values are
an analysis reference, fixed before measurements, not a characterized driver,
board, synchronizer or routed reset tree. The zero lower bound represents absent
characterized minimum transport; it is not a chosen passing minimum delay.
SDC uses `-clock_fall` for reset alone. The bench's falling-edge release in
[dv/README.md](../../dv/README.md) is a deterministic functional stimulus phase,
consistent with this edge relationship, but establishes no physical delay/slew
bound. Environmental synchronous release means a clock-related safe release;
this analysis does not change reset, startup, flush or memory-retention semantics.

The boundary is the mapped block input through library cells to reset pins and
reset-controlled data/output endpoints. Clock is ideal, no source latency, CTS,
wire RC, routing, OCV or multicorner analysis. Nangate45 typical is 1.10 V / 25 C,
ns and fF (cell area in library square micrometres). Require the locked library
SHA and doctor/tool identities. No physical reset source is present in this repo.

## Conditions and path completeness

FIFO E0 depth 2/4 retains capability data budgets of 0.2/1 ns and 0.05 ns
uncertainty. Allocator I0/F0 cell/descriptor and future P08/P12 use 0.2/2 ns and
0.10 ns uncertainty. These are different full constraint setups sharing one
reset convention; no FIFO-to-allocator speed comparison is implied. All ordinary
data input/output min/max delays reference rising `clk`; outputs have 10 fF each.
Primary mode uses 0.05 ns transition on all nonclock inputs, including reset;
sensitivity substitutes BUF_X1/Z library drive for those inputs on identical
netlists. Neither is an implemented external source. Ideal clock slew is zero.
ABC uses the existing allocator constrained mapping template, BUF_X1 and 10 fF;
FIFO is newly mapped with that recipe, not a reproduction of the retired FIFO
mapping flow. All actual registered production sources are read using Slang;
no oracle, consumer stub or behavior change is introduced.

Report data setup/hold, reset recovery/removal, reset-to-data/output effects and
mapped reset fanout separately. Preserve register-to-register, input-to-register,
register-to-output and input-to-output paths where present; demand max/min paths
for every output and every reachable reset pin. Keep allocator selection,
availability and count endpoints identifiable. Count direct root reset loads,
buffer-tree nets and total asynchronous pins separately from clock/data fanout.
Missing required constraints, empty required paths, diagnostics or incomplete
mapping invalidate measurement; negative slack alone does not.

## Predeclared decisions and qualification

Run both drive modes on identical maps for every point and all three scenario
identities. `rise-phase-sensitivity-r01` changes only reset launch phase;
`rise-historical-shape-r01` uses rising launch and 0.2/2 ns reset delays, under a
new identity. Hold ordinary data constraints fixed within each point/mode.
No envelope will be tuned in response to slack. Sensitivity shows dependence on
the assumed source, not measured evidence of a real source.

Measurement execution PASS requires complete constrained data and reset paths,
correct expected state/live outputs, no unmapped cells or diagnostics, and
explicit rejection of every configured deliberate negative. Exercise negatives
on actual mapped FIFO and allocator. Missing min/max, reversed envelope, wrong
reset name, blanket false path, missing removal and malformed Tcl must be rejected
by their intended validation, not by a generic crash. No fallback to max-only or
recovery-only evidence is allowed.

Each timing category closes locally iff all its reported required path slacks
are nonnegative. Negative slack is valid evidence and a local FAIL. Derive the
required port release window from worst recovery/removal slack and the declared
launch phase: minimum arrival = modeled minimum minus removal slack; maximum
arrival = modeled maximum plus recovery slack. Report endpoints and margins.
This interval pertains to recovery/removal only; reset gating/data checks remain
separately required. Report an empty window honestly. Source closure stays
UNRESOLVED without a characterized source; nonnegative reference-model checks
support only CONDITIONAL closure. Fanout is a structural observation, not slack
or reset-distribution signoff. Existing allocator architectural conclusions and
functional evidence are not requalified by R01. P08 consumer and P12 integrated
studies remain future work and must use the shared configuration API with new
study/scenario identities if assumptions change.

## Executable interpretation clarification

`set_driving_cell` models both the virtual BUF_X1 input driver delay and its
load-dependent output slew. Its SDC delay envelope is referenced **before** that
virtual driver; actual block-port release includes the driver delay reported by
OpenSTA. Fixed-slew mode has no virtual driver delay. Report both the SDC source
window and actual modeled block-port window, and derive required port windows
from port arrival minus removal slack / plus recovery slack. This clarifies the
existing drive sensitivity, without changing its envelope or choosing a delay
from observed slack. Neither source is physical characterization.

OpenSTA can include recovery/removal even with `-to` register data pins. The
reset-effects report therefore explicitly selects the `clk` path group, while
reset-pin reports retain `asynchronous`. Bulk endpoint enumeration must prove
every mapped asynchronous pin and output has max/min coverage, and mapped/STA
inventories must agree. These are evidence corrections, not timing exceptions.
