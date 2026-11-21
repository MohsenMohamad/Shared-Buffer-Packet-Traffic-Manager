# Integration status

## Multi-egress traffic manager

The [multi-egress contract](spec/multi-egress-traffic-manager.md) defines the
primary 4×4 profile and a smaller implementation and proof profile. The
[cycle model](results/multi-egress-datapath-feasibility.md) sustained one beat
per active port per cycle in each direction at both read latencies for the
balanced fixed-permutation runs with repeated 60-, 65-, and 1,536-byte frames
and the specified repeating length mixture. Multi-egress RTL,
independent DV and integrated qualification are pending.
The [public declarations](spec/multi-egress-interfaces.md) publish the packet,
cell memory, observation and control interfaces. The [declaration validation](results/TM03-multi-egress-declarations.md)
covers both profiles and read latencies. The
[implementation plan](implementation/plan.md#multi-egress-migration-and-gates)
gates the dependent datapath on queue/control feasibility. The
[finite queue/control experiments](results/TM04-queue-control.md) met the
primary balanced workload at both latencies. The
[control timing follow-up](results/TM04-control-timing.md) meets scoped
primary setup and hold with balanced same-edge admission. Buffer splits
clear the isolated primary fixtures' pin capacitance violations. Composed
maps still need load repair. The reset reference violates removal and needs
a characterized upstream release. Cached heads preserve balanced
throughput at both latencies. The measured admission stage misses it.
The [control decision](decisions/0010-multi-egress-queue-control.md) leaves
the dependent RTL freeze gate open.

## Single-egress traffic manager evidence

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
| G0 | Qualified toolchain fixtures and selected frontend | [Toolchain qualification](results/toolchain-qualification.md) |
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

G3–G7 remain open for the single-egress design. The active route follows the
[multi-egress migration and gates](implementation/plan.md#multi-egress-migration-and-gates),
including R01/A01 analysis for the multi-egress design and a new
ingress/admission assignment.
Existing reports retain their exact tested revisions, assumptions, profiles and
scope. The [dependency inventory](implementation/plan.md#dependency-evidence-inventory)
records the P02/P06 component evidence and remaining independent composition
needs. The [root ownership policy](../AGENTS.md#separate-rtl-and-independent-dv-ownership)
defines separate RTL and independent DV assignments.
