# R01: Shared reset timing and constraint interpretation

## Objective and entry

Establish a single constraint convention before P08 and before comparing allocator
alternatives. Consume [implementation analysis](../../spec/implementation.md),
[reset timing](../../spec/reset-timing.md), the FIFO timing qualification and
[allocator measurements](../../results/allocator-scaling.md).

The active-low reset is asynchronously asserted and synchronously released by
the environment. Existing negative removal slack is a result under the recorded
0.2 ns minimum-input-delay scenario, not evidence of a characterized reset source.

## Work

1. Before new measurements, commit the clock/reset event definitions, modeled
   source/boundary, data versus reset IO delays, slew/drive, loads, uncertainty,
   units, path groups and decision rules. Do not choose a new delay after seeing
   which value makes slack positive.
2. Separate data setup/hold, reset recovery/removal and reset fanout. Explain
   assertion versus deassertion events. Ground a reference reset-release envelope
   in a stated upstream source or a clearly labeled analysis model. If the real
   boundary is unavailable, report the required release window and conditional or
   unresolved reset closure; no arbitrary value establishes physical closure.
   Reconcile the existing bench's falling-edge reset-drive convention with the
   STA release model; a testbench drive phase is not a characterized reset source.
3. Add the shared constraint/configuration mechanism used by new allocator, FIFO,
   P08 consumer and P12 studies. Retain original SDCs/results as historical inputs.
   Document intentional differences in data IO budgets between capability and
   production studies; a shared reset convention does not make their full setups
   identical. Avoid blanket reset false paths or dropped recovery/removal checks.
4. Run focused matched checks on the actual mapped FIFO and allocator under the
   stated convention; exercise missing/bad reset constraints and retain meaningful
   path endpoints. Keep measurement validity separate from timing closure.
5. Update relevant experiment documentation and P08/P12 entry requirements. Do not
   add a reset synchronizer, change reset polarity/flush behavior, or claim CTS,
   routed parasitics or multi-corner signoff as part of this analysis task.

## Completion

One reviewed convention and executable recipe are shared by future studies,
old violations remain visible, and data/reset results have separate scopes and
owners. Unresolved physical assumptions are explicit. R01 is required before
A01's measured comparison and P08; it does not block queue implementation.
