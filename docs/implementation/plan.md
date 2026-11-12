# Implementation plan

The task cards define engineering assignments; [the specifications](../spec/README.md) define required behavior. Follow the committed repository working and documentation rules. A task's component evidence does not by itself close the entire integration gate.

## Dependencies and ownership

Shared APIs, state/array ownership and source/profile registration are fixed in P01 before components diverge. Component tasks add their real tests and local proofs; P11A/P11B close production composition rather than postpone all verification until the end.

| Task | Assignment | Dependencies |
| --- | --- | --- |
| P00 | [Open-source toolchain and executable capability gates](tasks/P00-toolchain.md) | seed |
| P01 | [Module contracts, types and reference interfaces](tasks/P01-contracts.md) | P00 |
| P02 | [Elastic FIFOs, cell pool and descriptor pool](tasks/P02-storage-primitives.md) | P01 |
| P03 | [Descriptor queues and simultaneous update correctness](tasks/P03-queues.md) | P02 |
| P04 | [Deficit round robin and packet-RR comparison](tasks/P04-scheduler.md) | P03 |
| P05 | [Finite-port packet store and transmit engine](tasks/P05-memory-tx.md) | P03 |
| P06 | [AXI4-Lite configuration and coherent statistics](tasks/P06-registers.md) | P01 |
| P07 | [UVM agents, monitors and independent models](tasks/P07-verification-foundation.md) | P01 |
| P00 refresh | [Current toolchain and frontend qualification](tasks/P00-followup-modern-toolchain.md) | integrated P00/P01/P02/P06/P07 |
| P01 representation | [Qualified RTL representation](tasks/P01-followup-representation.md) | P00 refresh; before allocator characterization |
| P02 follow-up | [Production allocator scaling](tasks/P02-followup-scaling.md) | P02, P01 representation; before P08 |
| P07 follow-up | [Readable checkers and constrained packet stimulus](tasks/P07-followup-stimulus.md) | P07; before P08 |
| P08 | [Interleaved receive, admission and abort cleanup](tasks/P08-receive-admission.md) | P02, P03, P05, P07 and both follow-ups |
| P09 | [Single-flow end-to-end vertical integration](tasks/P09-vertical-integration.md) | P04, P05, P06, P07, P08 |
| P10 | [Full subsystem concurrency and parameter regression](tasks/P10-concurrency.md) | P09 |
| P11A | [Ownership, conservation and queue proof closure](tasks/P11A-formal-resources.md) | P10 |
| P11B | [Transmit, scheduler and register property closure](tasks/P11B-formal-interfaces.md) | P10 |
| P11C | [Coverage review and requirement closure](tasks/P11C-coverage.md) | P10, P11A, P11B |
| P12 | [Traffic benchmarks, mapped synthesis and timing](tasks/P12-measurements.md) | P11C |
| P13 | [Regression evidence and checked diagnostic workflow](tasks/P13-diagnostics.md) | P10 |
| P14 | [Independent integration audit and release evidence](tasks/P14-release.md) | P12, P13 |

## Stabilization before the next implementation stage

P00, P01, P02, P06 and P07 are integrated at `a473b8c535d02b50b23604047f1bae64638c89df` (PRs #1–#5). These completed stages retain their recorded component/fixture boundaries. P03 and later hardware remain paused during this stabilization pass and its reevaluation.

1. Complete the [P00 toolchain refresh](tasks/P00-followup-modern-toolchain.md), retaining shared CI preparation and the durable evidence policy.
2. Complete [P01 representation](tasks/P01-followup-representation.md) with the tested recipe before allocator characterization.
3. Complete the focused [P02 allocator-scaling follow-up](tasks/P02-followup-scaling.md) now, before P08. Commit and push constraints and decision criteria before experiments; review measured findings without presupposing replacement.
4. The [P07 readability and constrained-stimulus follow-up](tasks/P07-followup-stimulus.md) is qualified on its candidate branch before P08; see [executed evidence](../results/P07-followup-stimulus.md).
5. Reevaluate stabilization results. P03 remains the next new implementation stage; completed stages and hardware scope are unchanged.
6. Measure basic packet rate in P09, expand diagnosis in P10, and explicitly accept the measured baseline or propose optimization after P10 before P11 closure. P12 retains the full benchmark study.

## Starting and integrating work

Check the actual default branch and prerequisite implementations before starting a dependent task. A completed candidate on an open PR is available for review, not yet an integrated dependency. Reuse its existing implementation; do not regenerate it merely because a task card changed.

Use one implementation task followed by a fresh review of its exact base/head revisions. A practical serial order that satisfies every dependency is:

1. P00, then P01.
2. P02, P07, P03, P06, P04, P05.
3. P08, P09, P10.
4. P11A, P11B, P11C.
5. P12, P13, P14.

The original independent waves remain possible: P02/P07, P03/P06, P04/P05, P11A/P11B and P12/P13. Use them only when both bases contain their prerequisites and shared edits have an explicit owner. In particular, `tools/run.py`, `Makefile`, CI, shared model APIs and `verification/requirements.json` are shared integration surfaces, even when RTL paths are disjoint. Integrate and review each wave before starting dependent work. Initially keep at most two implementation branches active; this is a coordination recommendation, not a hardware limit.

The cards may span more than one session. Continue a saved task using its existing branch/state rather than silently dropping acceptance checks. An API change updates affected callers/tests together. A change after proof or coverage closure refreshes the checks it affects; P12 implementation variants and P13 failure-hook edits are included in the final audit.

## Command implementation ownership

This table specifies work to implement. It does not claim that future suites already exist. The integrated P00 guide and runner define commands actually available at that revision.

| Stage | Command/registration work | Verification boundary |
| --- | --- | --- |
| P00 | Setup/doctor, repo/lint/unit, UVM/formal/synthesis smoke and capability CI | Independent capability fixtures |
| P01 | Functional profiles, source registration and named `regression` suites; single functional seed; initial `contracts` suite | Compilation/elaboration and model-interface checks |
| P02 | Add `formal-rtl` target/action with production family selection; `pools` regression/proof suites | Actual FIFO/pool RTL; retain `formal-smoke` fixture behavior |
| P03–P08 | Register `queues`, `scheduler`, `memory-tx`, `csr`, `uvm-foundation`, `receive` as applicable | Component RTL or explicitly named UVM fixture; applicable local proofs |
| P09 | `vertical` regression and actual subsystem CI smoke | Production TM with one active flow |
| P10 | `concurrency` and parameter suites; functional regression/CI expansion | Concurrent integrated TM |
| P11A/P11B | Resource/control production proof-family selections | Actual reduced production elaborations and composition |
| P11C | `coverage` extraction, compatible merging and summaries | Saved real databases and reviewed bins |
| P12 | `benchmark`, `synthesis`, `sta` | Actual workloads and matched mapped TM variants |
| P13 | Triage unit/failure-hook checks in existing runner | Offline fixture checks plus actual diagnostic evidence |
| P14 | Clean-environment entry-point and release-evidence audit | Exact final integrated candidate |

Selection grammar and profile handling are implemented/documented with the owning stage, using the common runner. P00's `--test` CI-gate selector and two-seed replay requirement must not be imposed blindly on later single-test functional replay. Preserve capability compatibility while adding those routes. Do not reuse a fixture result to satisfy a production suite.

## Requirement accounting

Each card names requirements it contributes to, not permission to mark all of them PASS after a local test. Keep `verification/requirements.json` tied to tests, actual outcomes and scope. P10 establishes integrated functional/parameter evidence; P11A/P11B establish the selected production proofs; P11C reconciles required verification coverage; P09/P10 establish early packet-rate measurements and a pre-P11 baseline decision; P12 owns the full performance experiments and P13 owns AI-01. P14 checks all 52 obligations against the final source.

Use reduced formal dimensions only under the documented formal elaboration/abstraction contract. They do not expand the supported functional profile range. Required unresolved proofs/tests block their gate; recording a truthful unsupported or inconclusive status is not completion of that obligation.
