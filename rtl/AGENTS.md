# RTL guidance

Use the relevant interface, buffer-management, scheduling and register contracts. Define widths from parameters with guarded index widths. Merge concurrent updates once per state element. Keep payload memory ports and latency explicit. No inferred latches, implicit nets or unsized arithmetic in resource counters. Document scoped lint waivers; do not blanket-disable checks. Add a focused regression for a functional fix.
