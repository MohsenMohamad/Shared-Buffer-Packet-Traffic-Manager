# Verification guidance

Use verification.md and the affected contract. Keep drivers, passive monitors, models, scoreboards and coverage separate. Expected payload comes from monitored input transfers. Batch same-cycle architectural events before updating models. Preserve malformed-packet stimulus, independent AW/W timing, reset epochs and duplicate tags. Qualify new language/library features with a focused capability test before large-scale use.

Keep checker and stimulus code readable: use descriptive names, separate statements and state transitions, keep functions manageable, and explain non-obvious invariants. Preserve checker independence and qualify behavior-preserving cleanup with existing positive and intended negative cases before extending functionality.

## Independent DV ownership

Own tests, API-event models, scoreboards, passive monitors/binds and coverage in
`dv/`; do not edit production RTL or embedded designer assertions. Derive expected
behavior from specifications and accepted API actions, never driver intentions
or DUT-calculated expected state. New designer smoke lives in `dv/designer/`
and has separate registration. Historical `dv/unit/queues_tb.sv` and scheduler
checks retain author provenance; audit them before reuse, without relabeling old
results as independent. Follow the root defect/fix/reverify workflow and final
qualification against merged RTL.
