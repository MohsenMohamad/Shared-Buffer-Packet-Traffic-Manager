# Multi-egress pool proof targets

The harness binds FP-ALLOC, FP-DESC and FP-CREDIT to the production pool's
registered free bitmaps and counts and to the physical lanes at the three
state-owning submodules. [Run results and reproduction](../../docs/results/TM07-pool-qualification.md)

| Target | Assertions | Reachability |
| --- | --- | --- |
| FP-ALLOC | Old-free membership, legal staged write, distinct live returns, exact bitmap and count deltas | Exhaustion with a return, next-edge reuse, write with returns, all physical lanes |
| FP-DESC | Distinct old-free rank selections, committed-lane projection, distinct returns and exact bitmap/count deltas | Descriptor exhaustion with returns, next-edge reuse, full grants and return fan-in |
| FP-CREDIT | Old credit prefix, exact queue deltas, global conservation, reset and initialization | Zero-cell, partial and final cleanup, highest TX lane with cleanup, active reset |

## Assumptions

The symbolic inputs are top-level ports. The cell and descriptor witness IDs
hold after their first sample, including across later reset. The harness
requires reset to start asserted and to cover two rising edges before
release. It models readiness independently for the caller. The ordinary
safety and cover jobs allow arbitrary legal stalls.

The aggregate caller derives free membership and old credit from shadow
state. It requires a legal committed prefix, distinct live returns, a prior
staged unit for each offered write and enough old queue credit for each
release. Cleanup completion may release its old reserved credit and the
cell it reclaims on that edge. A simultaneous write needs its own old
reserved unit. This model allows arbitrary ownership associations within
those aggregate preconditions. The separate frame ledger binds physical
IDs to a live frame and queue, checks per-frame reserved and materialized
counts, and permits TX finishes only when the last assigned cell returns.
The directed exhaustion job schedules a legal fill and return in the full
small profile. It leaves selected addresses to the DUT.

## Small-profile safety

The default small formal run proves selection, the two bitmap transitions,
credit deltas, credit preservation, the reserved-free transition, reset and
lane routing, and the caller's old-credit budgets. Each SV proof elaborates
one property group against the production instance. The credit-preservation
job also checks the integer one-edge step using the proved queue partition.
Reset supplies the induction base, and the exact RTL deltas and range proof
show that the stored counts implement the step without truncation.

Use `--profile small --formal-mode lemmas` for the focused proofs and
`--lemma NAME` to isolate one. The `prove` and `bmc` selections still run
the full harness with its frame ledger and F01 observer by default.
Both cover modes retain that ledger. The general cover run includes a
same-edge grant, write, TX final and cell-bearing final cleanup witness.
Unbounded component safety applies to the small profile. The primary gate
uses the live campaign and the full-capacity cover.

## Composition

- Admission must establish static or dynamic policy eligibility and the
  rotating commit prefix before the pool's committed reservation inputs.
- RX must tie the write offer to a pre-existing staged reservation and the
  selected address to the accepted memory write.
- TX must derive the physical return lanes from real `valid && ready`
  handshakes. Check cell-last, frame-last and epoch before narrowing the
  owner to its pool IDs.
- Cleanup must derive the dedicated lane from the marked abort and the
  service acceptance. Prove exact residual credit and exclusion of the
  completing ingress from the commit prefix.
- Reset coordination must establish physical release and integration
  timing, then prevent stale memory responses from crossing epochs.

The isolated pool has no memory response interface. The proof modes and
actual capacities in the run report distinguish local safety, bounded
checks and covers from these composition obligations.
