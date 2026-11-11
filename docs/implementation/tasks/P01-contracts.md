# P01: Module contracts, types and reference interfaces

## Objective and prerequisites

Freeze the contracts needed for independently developed components and make the existing runner capable of selecting future hardware tests. No functional TM datapath is claimed in this stage.

Dependencies: [P00](P00-toolchain.md)

## Sources and work boundary

- [architecture.md](../../spec/architecture.md)
- [interfaces.md](../../spec/interfaces.md)
- [buffer-management.md](../../spec/buffer-management.md)
- [queues-and-scheduling.md](../../spec/queues-and-scheduling.md)
- [registers.md](../../spec/registers.md)
- [verification.md](../../spec/verification.md)
- [automation.md](../../spec/automation.md)

`rtl/include/`, top-level interface declarations, `docs/spec/module-contracts.md`, model/event interfaces, profile/source registration and focused elaboration tests.

## Execution sequence

1. Inspect the integrated P00 runner and locks. Identify its current profile, seed and selection restrictions before extending it. Preserve the existing capability invocation behavior and fixtures.

2. Create `docs/spec/module-contracts.md` and link it from the specification index: for every producer/consumer boundary define fields/widths, reset values, acceptance event, response latency, backpressure, arbitration and state ownership. Cover RX service/admission, pool allocation/returns, queue publication/query/dispatch, RAM requests/responses, TX completion, reclamation and CSR configuration/statistics.

3. Identify one owner for each shared array and counter. Specify its actual read/write ports and the atomic merged updates, including one allocation/two descriptor returns, enqueue/dequeue replacement and simultaneous TX/abort release. Define duplicate/invalid-return handling consistently with the invariant-error contract.

4. Define metadata/status/trace types without truncating invalid qids. Fix profile dimensions, guarded widths and deficit bounds. Distinguish reduced formal elaborations from supported functional profiles.

5. Define packet/service/policy model inputs and a complete per-cycle event batch. Use a small executable model-interface example to show that callback order cannot change pre-state admission or empty-queue dispatch decisions.

6. Create separate production/simulation/formal/synthesis source descriptions and the profile registry. Extend the common runner with `regression` selection: named suites, explicit profiles and replayable single functional seeds. Preserve the two-seed requirement for P00 replay qualification and the existing CI-gate selectors.

7. Register a `contracts` suite for compile/elaboration and model-interface checks. Compile production declarations through both the qualified simulation and synthesis frontends. If a type/interface is unsupported, qualify an equivalent portable representation before downstream components depend on it.

8. Check all six functional profiles and invalid elaborations. Publish API decisions before component work; subsequent tasks consume these contracts rather than inventing signal names or parallel model APIs.

## Required checks

| Area | Evidence required |
| --- | --- |
| Frontend compatibility | Actual production type/port declarations compile under the pinned simulation and synthesis frontends; a stub is labeled elaboration-only. |
| Profiles | F0/F1/I0/I1/E0/E1 dimensions; minimum/maximum widths; invalid sizes, inadequate read-credit FIFO depth and deficit-width rejection. |
| Event interface | Same-cycle reserve/release and last-pop/push yield the same expected state under different callback arrival orders. |
| Runner extension | `regression` can select `contracts` by profile and one seed; unknown/empty selections fail; existing toolchain capability selection/replay still works. |

## Completion

G1: module APIs, shared types, source/profile ownership and independent event batching are executable and documented. The contracts suite runs; no component functionality is inferred from declaration compilation.

Requirement focus: `PAR-01`

## Representation follow-up

Consume the [current frontend qualification](P00-followup-modern-toolchain.md),
then complete [the focused representation change](P01-followup-representation.md)
before allocator characterization. Existing API/parameter/ownership contracts
remain normative; old frontend limitations are reassessed by executable evidence.
