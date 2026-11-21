# 0010: Multi-egress queue/control feasibility

**Keep the dependent RTL freeze gate open.** Finite queue metadata, old-state
admission and independent link service can reproduce all eight primary balanced
traffic windows in the edge model. The serial primary admission prefix misses
10 ns. A separately mapped lookahead prefix preserves reservation and return
visibility. It reduces the setup deficit and still misses the target. The
[measured results](../results/TM04-queue-control.md) give the exact outcomes.

Carry forward same-edge cached-head refill as the primary queue candidate.
It lowers the number of concurrent descriptor lookups, preserves next-edge
publication visibility and retains one binding opportunity per egress per
edge. The mapped primary cache and cell-control cones need load repair
and matched timing checks. Keep dedicated TX and abort link service and
the 1R1W 512-bit payload interface. The registered request experiment adds one edge after ownership
binds. Its late first-cell handoffs make it a weaker default at the published
buffer depths.

Before freezing the architecture, choose a primary admission implementation
that preserves atomic rotated prefixes, or review a contract change with
explicit reservation and reuse edges. Re-measure the static and dynamic
consumers, including early availability, four grants, all return lanes and
next-edge policy feedback. A staged alternative also needs exact-latency
replay with the current pools, including the small mixed workload and the
supplemental primary handoffs. Time composed scheduler, token, receive and
TX/cleanup paths and characterize the reset release source and distribution.

## Timing follow-up

Carry the balanced, same-edge prefix and cached heads into the next
composition review. The [follow-up](../results/TM04-control-timing.md)
meets the reference 10 ns data target in the isolated primary admission
fixture with both modes enabled. The balanced reductions preserve grant,
reservation, service and return visibility. A serialized two-edge admission
batch improves setup, but loses balanced throughput with the published
capture and staging depths. Retain it as a diagnostic.

Keep the dependent RTL gate open. The maintainer's next decision is whether
to carry the balanced same-edge control forward for integrated timing after
identifying the reset release boundary. Compare that boundary with the
required release window and check the remaining scheduler and datapath
composition before freezing the design.
