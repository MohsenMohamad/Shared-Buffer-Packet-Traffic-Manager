# Production CSR protocol proof

`make formal-rtl RUN_ARGS='--test csr --timeout 240'` runs FP-CSR against
`tm_axil_regs_api`, with one input, two queues, sixteen cells, eight descriptors,
16-byte cells and maximum packet length 128. No payload or statistics arithmetic
is proved here: live and shadow inputs, initialization and lifecycle inputs are
arbitrary. The UVM `csr` suite checks production statistics separately.

The harness assumes reset low on the first two sampled edges and legal source
stability for stalled AW, W and AR. Later resets and BREADY/RREADY are arbitrary.
There is no coupling between AW and W and no response-ready fairness assumption.
Immediate assertions and saved monitor state preserve the held-valid and
causality checks also exercised by the UVM bus interface and passive model.

| Family | Claim |
| --- | --- |
| Capture | Each free channel accepts independently; captured address/data/strobes remain unchanged until response retirement. |
| Responses | No response without its accepted request; one outstanding request; stable stalled B/R; production within three cycles. |
| Atomicity | Rejected writes leave RUN, policy, all limits and all quanta unchanged. |
| Reset/sticky | Reset suppresses ready/valid; diagnostic error remains sticky between resets. |

The prove task uses unbounded k-induction with depth 8. Covers use bounded
reachability through depth 24: AW first and W first with at least eight cycles
of separation, simultaneous capture, five-cycle simultaneous response stalls,
read/write execution overlap, rejected busy disable and snapshot execution.
The mutation adds a WVALID dependency to AWREADY in a disposable copy of the
production source. Success requires the intended `a_aw_independent`
counterexample and a nonempty trace; a compiler failure is not detection.

This local proof does not establish real datapath event wiring, whole-system
IDLE generation, statistics arithmetic or integrated packet correctness.
