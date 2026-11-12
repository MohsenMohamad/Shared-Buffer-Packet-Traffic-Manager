# Production queue proof boundary

`make formal-rtl RUN_ARGS='--test queues --timeout 300'` proves FP-QUEUE and
FP-ORDER on `tm_queue_ctrl_api` connected to the production `tm_desc_links`
child. There is no invented next-pointer input: the controller reads the old
head from that array, and the array receives the controller's one write port.
P05 must instantiate this child once in `tm_metadata_api`; head/tail/count
remain solely in the controller.

The named reduced configuration uses N_RX=1, N_Q=2, N_CELL=16, N_DESC=8,
CELL_BYTES=16 and MAX_PACKET_BYTES=128. These are legal production parameters,
including the minimum supported descriptor capacity, rather than relaxed
validation guards. Descriptor IDs are 3 bits and counts are 4 bits. Cell and
packet information do not affect queue control; payload, scheduler, immutable
metadata and TX are outside this proof.

The reference stores independent ordered descriptor lists. Accepted dispatches
shift those lists; successful commits append their IDs. Expected order/count
never comes from RTL links. Inductive assertions relate every live list edge to
the **actual child's** stored link, assert unique queued IDs, and compare all
counts and nonempty heads/tails. Unused slots and last links are unconstrained,
including after reset. These representation assertions are proved invariants,
not assumptions. Safety uses unbounded k-induction (depth limit 4); covers search
16 samples. Reachability is not a safety proof.

## Environment and P11A discharge

- Reset is low for the first two samples and arbitrary thereafter. SBY uses
  `async2sync`/`dffunmap` for the asynchronous production reset. This is a sampled
  functional proof, with no reset recovery/removal timing claim.
- On commit, qid/ID are in range, the ID is absent from **every pre-state list**,
  and total queued occupancy is below N_DESC. A same-edge pop cannot justify
  committing its old descriptor. Full occupancy itself remains reachable.
- A commit denotes a legal RX-owned, complete packet. The local mathematical
  restrictions above capture queued-ID disjointness/capacity; they do **not**
  establish RX versus TX/ABORT/FREE ownership. P11A must prove unique ownership,
  legal publication after reservation/materialization, and absence of reuse
  before TX final retirement or abort completion using the actual P02 pool.
- `request_pop` and `pop_qid` are arbitrary inputs. The harness emits the API's
  accepted `dispatch.valid` only for a nonempty pre-state reference list, with
  its old head ID. Head equality is asserted independently. Empty requests
  cannot use concurrent publication. P04/P11A must discharge scheduler eligibility,
  matching descriptor/info and unconditional TX acceptance at dispatch.
- There are no sink-progress/fairness assumptions or restrictions on collision
  timing, arbitrary later resets, qid selection or stale link values. Inputs use
  F01's explicit top-level-port recipe; no fixed witness is needed.

The cover task reaches same-queue last-pop/push, longer replacement, two nonempty
qids with independent changes, full occupancy, empty request with publication,
active reset collision and publication after reset. No cover-only stimulus
constraints are added. The mutation replaces only the singleton head assignment
with `old_head_next`; success requires a real `FAIL` trace naming `a_order`,
not a parse error, timeout or unrelated assertion.

Exact executed results and residual composition obligations are in the
[P03 report](../../docs/results/P03-queues.md). This proof does not establish
commit-to-output byte order, descriptor final-return timing, scheduler behavior,
or whole-system resource conservation.
