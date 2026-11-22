# Verification guidance

Use verification.md and the affected contract. Keep drivers, passive monitors, models, scoreboards and coverage separate.
Use live SV/UVM to check each observed transaction, including complete atomic
edge batches. Sample functional coverage from checked observations. The
scoreboard owns comparisons and mandatory-bin acceptance, including checker
qualification. Use DPI-C only to supply expectations from a justified complex
model. Python may emit stimulus, orchestrate tools and render reports. Expected payload comes from monitored input transfers. Batch same-cycle architectural events before updating models. Preserve malformed-packet stimulus, independent AW/W timing, reset epochs and duplicate tags. Qualify new language/library features with a focused capability test before large-scale use.

Keep checker and stimulus code readable: use descriptive names, separate statements and state transitions, keep functions manageable, and explain non-obvious invariants. Preserve checker independence and qualify behavior-preserving cleanup with existing positive and intended negative cases before extending functionality.

Follow the [root ownership and preparation policy](../AGENTS.md#separate-rtl-and-independent-dv-ownership)
for role-specific source access and task gates.
