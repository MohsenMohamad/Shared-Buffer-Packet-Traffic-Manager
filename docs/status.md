# Integration status

## v2 4×4 target

The [v2 contract](spec/tm-v2-4x4.md) and
[cycle feasibility study](results/tm-v2-feasibility.md) define the next
design. The balanced model sustained one beat per active port per cycle in
each direction at both read latencies, including 60-byte frames and 65-byte
cell tails. v2 RTL, independent DV, proofs and mapped timing are pending.
The [plan](implementation/plan.md#v2-migration-and-gates) assigns public
declarations next and gates the dependent datapath on queue/control feasibility.

## v1 one-egress evidence

P05 packet RAM, finite-port metadata and credited TX merged in
[PR #24](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/24).
[PR #26](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/26)
integrated component qualification of RTL merge `3ede1a5e40791ff00d98a0faa8389154d632e0c5`.
Evidence covers two-state execution across six profiles, saved coverage and
accounting, and reduced unbounded FP-TX safety. The
[qualification report](results/P05-candidate-qualification.md) records exact
executions, proof premises and the pending caller/pool composition and coverage
closure. The [PR #23 preparation evidence](results/P05-fresh-dv-preparation.md)
documents pre-model dependency RTL/results exposure. Historical preparation
independence remains unestablished.

| Gate | Current scope | Evidence / owner |
| --- | --- | --- |
| G0 | Qualified toolchain fixtures and selected frontend | [Toolchain qualification](results/modern-toolchain.md) |
| G1 | Qualified declarations/configurations; qualified types and declarations | [P01](results/P01-contracts.md), [RTL representation](results/rtl-representation.md) |
| G2 | Scoped FIFO/pool, queue, scheduler, RAM/metadata/TX, CSR and bench-fixture evidence. P08 and composition remain pending. | [P02](results/P02-storage-primitives.md), [P03](results/P03-queues.md), [P04](results/P04-scheduler.md), [P05](results/P05-candidate-qualification.md), [P06](results/P06-registers.md), [P07 follow-up](results/P07-followup-stimulus.md) |
| G3 | Pending real vertical path | P09 |
| G4 | Pending integrated concurrency/profile evidence | P10 |
| G5 | Pending composition proofs and coverage closure | P11A/P11B/P11C |
| G6 | Pending full matched traffic/implementation studies | P12 |
| G7 | Pending checked diagnostics and release audit | P13/P14 |

Main CI passed after the [PR #27 checkout repair](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/27)
at `61d4c4c2b751642e6b79a995b710f186a8ce0281`. The
[full main run 43622745467](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43622745467)
passed all six P05 jobs. The qualification report retains the prior staging
failure, its exact source and the fixed checkout behavior.

## Evidence and ownership

The v1 G3–G7 rows record the uncompleted one-egress gates. The active route
follows the [v2 migration and gates](implementation/plan.md#v2-migration-and-gates),
including R01/A01 analysis for v2 and a new ingress/admission assignment.
Existing reports retain their exact tested revisions, assumptions, profiles and
scope. The [dependency inventory](implementation/plan.md#dependency-evidence-inventory)
records the P02/P06 component evidence and remaining independent composition
needs. The [root ownership policy](../AGENTS.md#separate-rtl-and-independent-dv-ownership)
defines separate RTL and independent DV assignments.
