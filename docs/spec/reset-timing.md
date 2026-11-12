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

[R01](../implementation/tasks/R01-reset-timing.md) owns the common executable
constraint recipe and focused qualification before allocator alternatives/P08.
P08 measures the real consumer path; P12 applies the convention to matched full
implementation variants and reports all intended path groups.

The original FIFO and allocator studies used their recorded reset IO assumptions
and reported negative removal slack. Preserve those reports/SDCs as historical
measurements. New scenarios receive new source/constraint identities and results;
they do not retroactively turn the original measurements into PASS.

This remains single-corner, ideal-clock, pre-layout analysis. No CTS, routed reset
distribution, physical recovery/removal closure or silicon guarantee is implied.
