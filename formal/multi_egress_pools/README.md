# Multi-egress pool proof targets

Production binding and proof execution are **NOT_RUN**. The observer exposes
FP-ALLOC, FP-DESC and FP-CREDIT targets for the widened pool boundary. Connect
it to the named production revision before using any property or cover as
hardware evidence.

| Target | Assertions | Covers |
| --- | --- | --- |
| FP-ALLOC | Old free membership, live distinct returns, free population and merged bitmap | Physical exhaustion, write with returns, full cell return fan-in and next-edge ID reuse |
| FP-DESC | Old free prefix selections, distinct grants and returns, merged bitmap and count | Descriptor exhaustion, grant with returns, full grant and return fan-in and next-edge ID reuse |
| FP-CREDIT | Nonnegative old credit prefix, per-queue merged deltas, global conservation and exact cleanup completion | Zero-cell cleanup, coincident normal and abort returns, and reset with live work |

## Binding

Use the public profiles first. Primary has four ingress grants, four TX
lanes and one cleanup lane. Small has two ingress grants, two TX lanes and one
cleanup lane. Any reduced elaboration must preserve the assertion semantics
and state its configuration-specific cover limits. Bind to the actual state
representing free membership and live counters. A design with a different
representation must expose equivalent passive observations. Bind the write
event to the accepted allocation and each release to its respective physical
accepted lane. Preserve dense grant order and all physical return indices.

- Admission supplies spec-legal granted reservations and routes. Prove
  prefix legality at the combined admission/allocator boundary. A local
  caller assumption is insufficient for a composition result.
- RX supplies a staged cell with current-epoch owner and one unmaterialized
  unit of credit. Bind the write owner-match signal to derived ownership and
  credit checks at that boundary.
- TX ties returns to accepted cell-final and packet-final beats, including
  correct descriptor and epoch. Bind owner-match signals before any ID-only
  narrowing. A caller must exclude stale ownership before presenting an
  ID-only physical release.
- Cleanup returns only live cells of a marked abort and atomically releases
  remaining credit at completion. Bind the cleanup owner-match signal to the
  epoch-aware cleanup state. Establish the completing ingress's exclusion
  from the current grant prefix.
- Reset follows the contract's hold and synchronous release rules. Bind
  initialization to the first usable state. Prove current-epoch ownership
  before unmasking new work.

Use explicit symbolic top-level inputs. The witness-stability assumptions hold
through later DUT resets. Safety tasks impose no progressing-sink, service
fairness or arbitration assumptions. Progress tasks may use named eligibility
bounds and progressing sinks. Run separate covers for a later initialized
epoch and composed reclamation. For any memory-facing binding, run latencies
one and two with the public response contract.

Register production Slang/SBY source lists only when the exact modules and
adapter are available. For each property family, retain proof mode, engine
result, covers and counterexamples. Exercise a selected bitmap-delta and a
reservation-delta mutation after binding.
