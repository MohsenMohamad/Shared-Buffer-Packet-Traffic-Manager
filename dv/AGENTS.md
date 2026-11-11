# Verification guidance

Use verification.md and the affected contract. Keep drivers, passive monitors, models, scoreboards and coverage separate. Expected payload comes from monitored input transfers. Batch same-cycle architectural events before updating models. Preserve malformed-packet stimulus, independent AW/W timing, reset epochs and duplicate tags. Qualify new language/library features with a focused capability test before large-scale use.

Keep checker and stimulus code readable: use descriptive names, separate statements and state transitions, keep functions manageable, and explain non-obvious invariants. Preserve checker independence and qualify behavior-preserving cleanup with existing positive and intended negative cases before extending functionality.
