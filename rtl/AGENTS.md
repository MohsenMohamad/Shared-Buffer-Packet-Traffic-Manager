# RTL guidance

Use the relevant interface, buffer-management, scheduling and register contracts. Define widths from parameters with guarded index widths. Merge concurrent updates once per state element. Keep payload memory ports and latency explicit. No inferred latches, implicit nets or unsized arithmetic in resource counters. Document scoped lint waivers; do not blanket-disable checks. Add a focused regression for a functional fix.

## RTL owner and designer smoke

The RTL owner changes production modules and embedded assertions in a separate
PR from independent DV. New designer smoke belongs in `dv/designer/`, separately
registered; it supports implementation review and does not establish independent
qualification. Coordinate shared spec/API changes early with DV. Merge RTL before
final independent DV qualification; handle DV-detected hardware defects in a
separate RTL fix PR. Historical author evidence retains its original scope.
