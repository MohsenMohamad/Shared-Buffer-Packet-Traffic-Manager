# UVM foundation uses signal observations and a declared fixture

Historical decision: current tool/frontend restrictions and their dispositions
are covered by [decision 0006](0006-modern-toolchain.md). The active
[P07 follow-up](../results/P07-followup-stimulus.md) records the readable checker
phases, constrained packet qualification and separate baseline timing checks. The original evidence
and behavioral choices below remain historical records.

P07 supplies reusable UVM agents and independent models before the complete
traffic manager exists. The behavioral fixture is owned by the
`uvm-foundation` simulation source registry; production, synthesis and formal
registries never inherit it. The fixture is not a TM implementation.

Every stream, AXI, status, policy and reset monitor emits an explicit sample
on every rising edge. Their local stamps follow the same reset contract.
Only the coordinator seals `(epoch, cycle)` after all sources report. Missing,
duplicate, mixed-cycle and stale callbacks are fatal. No driver object enters
a model. An interface adapter for production must present the P01 packed
records with exactly the same edge semantics.

The byte checker uses external captures, source/frame ordinals and observed
statuses. It checks per-source/per-queue surviving order without treating tags
as keys. The separate service checker matches a FIFO of raw captures before
applying reservation/materialization/release deltas. Physical IDs are only
ownership cross-checks; no reference pointer RAM, linked list or bitmap
allocator is copied. The scheduling checker maintains packet lists and DRR
visit state from validated commits, independently of actual output bytes.

The foundation scheduler uses one queue inspection each free-TX cycle, adding
quantum and evaluating that head in the same inspection. TX completion unfreezes
inspection on the following edge. This is the allowed baseline scan policy;
production adapters must not silently align the checker to observed grants.
The initial configuration is DROP, full queue limits and default quantum;
model limits/WAIT and quantum are explicit configuration inputs. Configuration
changes must be coordinated with the eventual CSR integration, not inferred
from admission outcomes.

A standard UVM report-server extension preserves error/fatal messages and
terminates them with nonzero status. This avoids the simulator's zero-exit
`$finish` path and prevents execution after a fatal; the reference library is
unmodified.

The fixture has a scratch RW register at address zero to qualify RAL accesses,
independent AW/W, concurrent read/write and response stalls. That scratch
register is deliberately not the production ID register. `tm_register_block`
declares the complete production address map for later hookup; only the
fixture block has executable frontdoor/predictor evidence here. Resource reads
at 0x24/0x28/0x2c are additionally checked against the model's AR-edge pre-state.

Verilator/UVM remain unmodified and use the pinned P00 `UVM_NO_DPI` baseline.
The fixture advances behavioral state after edge sampling and prepares actions
on the falling edge, avoiding monitor/DUT races. This half-cycle fixture
implementation is not a synthesizable timing claim. Two-state simulation,
fixture coverage and seeded checker detections do not establish production
correctness, X propagation, memory timing, performance or coverage closure.
