# P02: Elastic FIFOs, cell pool and descriptor pool

## Objective and prerequisites

Implement reusable storage primitives with accurate pre-state allocation and atomic return accounting. Establish the production formal entry point while proving the first real modules.

Dependencies: [P01](P01-contracts.md)

## Sources and work boundary

- [interfaces.md](../../spec/interfaces.md)
- [buffer-management.md](../../spec/buffer-management.md)
- [formal.md](../../spec/formal.md)
- [automation.md](../../spec/automation.md)

Also read the relevant APIs in `docs/spec/module-contracts.md`, created by P01, and inspect the integrated dependency implementations before changing their boundaries.

`rtl/common/`, `rtl/pools/`, component benches, `formal/pools/` and common-runner registration for these checks.

## Execution sequence

1. Consume P01 APIs and profile/source registration. Implement registered stream FIFOs at depths 2 and 4; define push/pop from actual handshakes and preserve the registered-ready boundary.

2. Implement a parameterized free-bitmap cell pool: allocate only a pre-state free ID, accept at most one return and merge the bitmap/count changes once. A return on a full pool cannot make an allocation succeed on that same edge.

3. Implement the descriptor variant with one allocation and up to two distinct returns. Exercise invalid, duplicate and already-free returns under the P01 error contract; capacity must never be inflated.

4. Write independent FIFO/ownership tests, using a set/count model rather than copying the priority-encoder implementation. Force exhaustion, complete recovery and rapid reuse at more than one supported size.

5. Register a `pools` regression suite. Add `make formal-rtl` through the existing runner for production proof selection; keep `formal-smoke` and its fixture route intact. A production proof must not accidentally run the enabled-counter fixture.

6. Target the real pool modules with free-population, unique allocation, count-bound and merged-return invariants. Reach full allocation, simultaneous allocate/return and invalid-return covers. Use a wrong-delta seeded defect to check the detector.

7. Exercise reset when empty, full and mid-update. Confirm pointer/control reset and held-output behavior without requiring payload clearing.

## Required checks

| Area | Evidence required |
| --- | --- |
| FIFO | Full/empty, blocked push/pop, simultaneous push/pop, wrap/reuse and reset at depths 2/4. |
| Pools | Exhaust/recover at two sizes; allocate plus one/two returns; duplicate/invalid releases; no same-edge return bypass. |
| Proof | Scoped unbounded FP-ALLOC/local FP-DESC invariants on production modules, reachable covers and intended wrong-delta detection. |
| Command integration | Named `pools` regression and production formal selection produce nonempty cases; P00 formal fixture invocation retains its behavior. |

## Completion

The FIFO and pool portion of G2 has executable local evidence and scoped unbounded invariants. Local descriptor bitmap consistency does not yet prove RX/queue/TX ownership composition.

Requirement focus: `IF-02`, `MEM-01`, `MEM-06`, `RST-01`, `PAR-01`
