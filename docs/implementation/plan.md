# Implementation plan

Dependencies are integration requirements. Start a dependent task from the default-branch revision that actually contains those dependencies, not from an older task workspace. Independent tasks may use separate branches after shared contracts are integrated.

| Task | Deliverable | Dependencies |
|---|---|---|
| P00 | [Open-source toolchain and executable capability gates](tasks/P00-toolchain.md) | seed |
| P01 | [Module contracts types and independent reference interfaces](tasks/P01-contracts.md) | P00 |
| P02 | [Elastic FIFOs cell pool and descriptor pool](tasks/P02-storage-primitives.md) | P01 |
| P03 | [Descriptor queues and simultaneous update correctness](tasks/P03-queues.md) | P02 |
| P04 | [Deficit round robin and packet-RR comparison](tasks/P04-scheduler.md) | P03 |
| P05 | [Finite-port packet store and transmit engine](tasks/P05-memory-tx.md) | P03 |
| P06 | [AXI4-Lite configuration and coherent statistics](tasks/P06-registers.md) | P01 |
| P07 | [UVM agents monitors and independent models](tasks/P07-verification-foundation.md) | P01 |
| P08 | [Interleaved receive admission and abort cleanup](tasks/P08-receive-admission.md) | P02, P03, P05, P07 |
| P09 | [Single-packet end-to-end vertical integration](tasks/P09-vertical-integration.md) | P04, P05, P06, P07, P08 |
| P10 | [Full subsystem concurrency and parameter regression](tasks/P10-concurrency.md) | P09 |
| P11A | [Ownership conservation and queue proof closure](tasks/P11A-formal-resources.md) | P10 |
| P11B | [Transmit scheduler and register property closure](tasks/P11B-formal-interfaces.md) | P10 |
| P11C | [Coverage review and requirement closure](tasks/P11C-coverage.md) | P10, P11A, P11B |
| P12 | [Traffic benchmarks mapped synthesis and timing](tasks/P12-measurements.md) | P11C |
| P13 | [Regression evidence and checked diagnostic workflow](tasks/P13-diagnostics.md) | P10 |
| P14 | [Independent integration audit and release evidence](tasks/P14-release.md) | P12, P13 |

## Recommended integration waves

1. P00.
2. P01.
3. P02 and P07 may run independently.
4. P03 and P06 may run independently.
5. P04 and P05 may run independently.
6. P08, then P09, then P10.
7. P11A and P11B may run independently; integrate them before P11C.
8. P12 and P13 may run independently.
9. P14.

Review and integrate each wave before dependent work starts. Keep at most two independent implementation branches active initially; this is a coordination policy rather than a technical limit. A review evaluates the exact candidate revision. New commits invalidate evidence for changed behavior and may require a focused re-review.

The task table describes deliverables, not a promise that every card fits one session. Local proofs/tests accompany component work; final closure tasks do not defer all verification until the end.
