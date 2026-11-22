# Multi-egress pool DV preparation

The replay bench checks old-state allocations, distinct ownership and merged
reservation accounting for the 4×4 primary and 2×2 small profiles. It samples
the public multi-egress edge records through a passive UVM monitor. The
scoreboard reconstructs state from the captured records and checks reported
counts as observations. Preparation establishes replay and checker behavior.

## Reproduction

The prepared toolchain supplies Verilator 5.054 and the locked Accellera
UVM 2020.3.2 library. Use an allowlisted checkout containing the
[registered sources](../../verification/sources/multi-egress-pools-preparation.json),
their scoped runner, and the [public baseline inputs](../../verification/multi-egress-pools/baseline-allowlist.txt).

```sh
make multi-egress-pools-preparation
make multi-egress-pools-preparation RUN_ARGS='--profile small --case stale-owner'
make multi-egress-pools-candidate RUN_ARGS='--profile small'
```

The first command runs both profiles and saves per-case manifests, stimuli,
monitor traces and native covergroup databases under `.build/runs/`. A
single-case replay checks the named witness or expected detector. The
candidate command exits nonzero and records `NOT_RUN` until the production
binding exists.

## Campaign design

Directed episodes construct old ownership through legal reservations, writes,
publication and dispatch. The sampled pool boundary can align a staged write,
TX final acceptances and abort service without modeling payload timing. The
cross cases construct each required count, source and occupancy combination.
The [coverage plan](../../dv/multi_egress_pools/coverage_plan.py) supplies the
required matrix and its exclusion rules. Cleanup cells always retain the unused
abort reservation until completion. A concurrent writer consumes another
reservation, which rules out a write coincident with cleanup at one free cell.

The UVM sequence shuffles and translates occupancy episodes, varying legal
IDs, queue classes, port coordinates, byte lengths, and selected abort-service
delays. The separate traffic ledger generates fresh constrained traffic, with
variable reservation cell budgets, completion masks, mixed ownership phases
and active reset. Each seed includes at least 2,048 generated activity edges
before its final drain. The coverage sampler receives only batches that pass
the passive scoreboard and uses the oracle's pre-edge occupancy. Primary and
small keep separate covergroup databases.

## Production binding

Bind the observed pool events to the accepted actions in
[ABI v1](../spec/multi-egress-interfaces.md#edge-observation). Preserve the
ordered admission prefix, original TX indices and dedicated cleanup index.
Bind the write to its selected physical address and prior staged owner.
Cross-check TX returns with independent output handshakes and cleanup completion
with the abort-service acceptance. Export pre-edge initialization and current
epoch, and sample registered F, U, R, A, D and H after each edge. Cross-check
any ID-only return at its nearest epoch-aware caller before the ID is narrowed.

Composed reachability still needs real ingress staging, publication, queue
binding, and TX acceptance for the scarcity exchanges, full fan-in and
shortest reuse intervals. The pool replay assumes legal caller decisions and
abstract service timing. The candidate also needs an exact RTL revision,
a linked production observation adapter and independent run manifests. Run
read latencies 1 and 2 when the binding exercises the memory interface.

Production RTL qualification, production functional and code coverage, and
formal results are **NOT_RUN**. The [F01-compatible observer](../../formal/multi_egress_pools/README.md)
lists the ownership and conservation targets, covers and caller assumptions.
