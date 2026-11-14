# Reset timing analysis convention

The functional reset contract remains active-low asynchronous assertion,
synchronous release by the environment, and flush/reinitialization without
payload-memory clearing. This document defines reporting/constraint obligations;
it does not claim that a reset-release source has been implemented or characterized.

## Required separation

Report data setup/max and hold/min, reset recovery/removal and reset fanout as
separate categories. Identify the exact clock/reset launch and capture events,
units, uncertainty, reference library/PVT, drives, loads and min/max IO assumptions.
A successful OpenSTA process or valid report does not establish closure.

Reset is not an ordinary data port for selecting external delay assumptions.
Specify a reset-deassertion envelope from an identified source or a clearly
labeled reference analysis model, independently of the observed pass/fail result.
Asynchronous assertion behavior does not justify excluding deassertion checks.
Do not use a blanket reset false path or increase the minimum delay solely to
remove a recovery/removal violation.

If the source boundary is unknown, retain conditional/unresolved reset closure
and report the required deassertion arrival window and margin. A sensitivity
sweep can explain the requirement; it is not measured evidence that the external
source satisfies it. Keep ordinary data constraints explicit and unchanged in
matched comparisons unless a separately recorded experiment changes them.

## Ownership and historical evidence

[R01](../implementation/tasks/R01-reset-timing.md) provides the common executable
[configuration and frozen definition](../../experiments/reset-timing/README.md)
and [focused qualification](../results/R01-reset-timing.md) before allocator
alternatives/P08. `tools/timing_constraints.py` resolves named study/scenario/drive
identities; the focused `make reset-timing` runner checks actual standalone maps.
P08 measures the real consumer path; P12 applies the convention to matched full
implementation variants and reports all intended path groups.

The original FIFO and allocator studies used their recorded reset IO assumptions
and reported negative removal slack. Preserve those reports/SDCs as historical
measurements. New scenarios receive new source/constraint identities and results;
they do not retroactively turn the original measurements into PASS.

This remains single-corner, ideal-clock, pre-layout analysis. No CTS, routed reset
distribution, physical recovery/removal closure or silicon guarantee is implied.

## Executable reference model

The committed `fall-reference-r01` model releases on falling `clk`, with 0..0.2 ns
source-delay envelope; at 10 ns the fixed-slew block-port release is 5..5.2 ns
after the preceding rising edge. This reconciles the functional bench phase;
it does not characterize an external reset network. In `drive` sensitivity,
BUF_X1/Z adds virtual-driver delay and load-dependent slew: report the actual
port envelope separately from the pre-driver SDC envelope. Neither model is a
physical source or a replacement functional contract.

Ordinary data ports retain rising-edge IO constraints. FIFO capability studies
use min/max 0.2/1 ns and 0.05 ns uncertainty; allocator/P08/P12 production studies
use 0.2/2 ns and 0.10 ns uncertainty. All use 10 fF output loads at the locked
Nangate45 typical corner. Changing a boundary or budget requires a new identity;
sharing reset convention alone does not make two full studies matched.

The shared recipe requires explicit reset min/max constraints and both
recovery/removal paths to every mapped asynchronous pin. It rejects timing
exceptions instead of hiding checks. Data endpoint classes, reset gating effects,
reset pins, structural fanout and electrical limits have separate reports.
Derive required **port** release bounds as actual modeled port minimum minus
worst removal slack and port maximum plus worst recovery slack, with the preceding
rising edge as zero. Report the pre-driver source window separately in drive mode.
The recovery/removal interval does not replace reset-gating setup/hold/output
checks or electrical limits. All windows remain conditional on the stated slew,
load, ideal clock and library. No source is established by a sensitivity sweep.
