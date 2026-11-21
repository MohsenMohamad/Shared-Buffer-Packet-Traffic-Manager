# Queue/control timing follow-up

PR #31 merged as `4d4356e1125d1b18c04c9eaa478cd7425c00e026` with head
`d6c05433186e78d509f70100470c95754ca7a3b4`. The fetched `origin/main`
and starting revision for `analysis/multi-egress-control-timing` are that
merge. The initial doctor passed on the merge revision.

## Comparison criteria

Use the [PR #31 evidence](../../docs/results/TM04-queue-control.md) and
its [measurements](../../docs/results/TM04-queue-control.json). Rerun serial
and lookahead with the short ABC script. Map each follow-up admission variant
with the same short script, both profile sizes and live registered RX and
resource consumers. Fix the mode only for path attribution on the same mapped
netlist. Start with same-edge cached-head refill and retain the registered
request model as a diagnostic. Compare default ABC on the cached-head and
cell-control cones to the corresponding default baseline.

Use the committed [reference SDC](reference.sdc) throughout. The Nangate45
typical corner is 1.10 V and 25 °C, with an ideal 10 ns clock, 0.10 ns
uncertainty, 0.2/2.0 ns min/max data I/O budgets, 0.05 ns slew and 10 fF
outputs. Reset release uses the same 0.2/2.0 ns envelope after the rising
launch edge. Report recovery, removal and any reset-to-write checks. Derive
the required arrival window and keep closure conditional on the real source
and distribution. Check setup, hold, transition and capacitance independently.
Count mapped state and load live physical-width ports. Measure representative
composed cones separately from the isolated fixtures.

Check both runtime-selectable modes, rotated successful-grant prefixes,
reason precedence, physical ownership and after-edge accounting. Compare the
zero-cycle candidate against the original fixtures plus directed legal
neighbors and independent resource recomputation. Any added admission edge
requires matching workload replay at both read latencies, explicit state
and observation boundaries, and maintainer review. Keep the dependent RTL
freeze gate open if any required result is missing or fails.
