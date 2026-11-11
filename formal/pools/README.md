# Production storage proofs

Run all tasks with `make formal-rtl RUN_ARGS='--timeout 240'`. Select one family
with `--test cell`, `--test descriptor`, `--test fifo2` or `--test fifo4`; repeated
selections combine distinct families. The default and only profile is E0.
`verification/formal.json` owns these elaborations. `formal-smoke` continues to
run the independent P00 fixture and cannot select these proofs.

| Family | Production configuration | Safety assertions | Covers |
| --- | --- | --- | --- |
| FP-ALLOC | `tm_cell_pool_api`, 16 cells, ID width 5, one return | Free population equals count, count bounds, live/free complement, no live allocation, lowest free selection, pre-state release acceptance, sticky error | Exhaustion, invalid return, allocate/return, full recovery without reset, reset while owned |
| Local FP-DESC | `tm_desc_pool_api`, 8 descriptors, ID width 4, two returns | Same invariants; duplicate counted once; independent valid returns survive invalid lanes | Same plus two distinct returns, allocate/two returns, owned duplicate |
| FIFO | `tm_axis_rx_fifo_api`, depths 2/4, complete 137-bit beat | Independent shift queue equals occupied circular slots, occupancy bounds, head order, ready/valid/empty, held output, pointer relation | Full, simultaneous push/pop, stall, wrap, drain without reset, reset during nonempty work |

The only assumption is low reset on the first two sampled rising edges. Later
resets, enable, allocation requests, return IDs and source/sink inputs are
arbitrary. No return is assumed valid; no readiness/fairness or source stability
assumption is needed for these safety proofs. This permits more input behavior
than a legal integration source. Reset is modeled at clock boundaries using
Yosys `async2sync`; these results do not analyze analog reset release or glitches.
FIFO storage remains unreset and no payload abstraction reduces the beat width.

`bitmap_properties.svh` maintains an independent live-ID set and validates
per-lane acceptance against it. Its count-population assertion detects the
seeded return-credit increment of two. `fifo_properties.svh` shifts an abstract
queue instead of copying the circular implementation. Simulation checks the
same order/occupancy semantics with an SV queue and the same held-output property
with concurrent SVA; formal uses explicit previous-cycle state. Proof mode uses
unbounded k-induction with a four-step search; cover mode searches up to 40
steps. Cover success requires every enabled cover to be reached. A prove result
is not a bounded safety claim, and a cover result is not a safety proof.

The runner stores each generated SBY configuration, source hashes, assumptions,
engine status, commands, elapsed times and traces in its ordinary manifests.
Wrong-delta cases pass qualification only on an actual `a_population`
counterexample, nonzero formal status and a saved VCD. A missing tool or unrelated
failure cannot qualify the mutation. See the [P02 report](../../docs/results/P02-storage-primitives.md)
for executed results and the local ownership limitation.
