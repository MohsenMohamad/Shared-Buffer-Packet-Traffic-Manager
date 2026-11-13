# Integration status

Current main `1c225525ba284ce694f1b234cb12cc514b9c0aee` includes P03 RTL
(PR #14) and P04 RTL (PR #16), alongside P00/P01/P02/P06/P07, F01 and C01.
P03/P04 are **implemented awaiting independent DV** in separate PRs. Their
existing author checks/reports retain their original scope and provenance.
P03 [local independent DV checks](results/P03-independent-dv.md) pass in
[PR #17](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/17);
its verified scope awaits the passing PR's merge. P04 independent DV remains
pending. Remaining datapath declarations do not establish a complete traffic manager.

| Gate | Current scope | Evidence / owner |
| --- | --- | --- |
| G0 | Qualified toolchain fixtures and selected frontend | [Toolchain qualification](results/modern-toolchain.md) |
| G1 | Qualified declarations/configurations; qualified types and declarations | [P01](results/P01-contracts.md), [RTL representation](results/rtl-representation.md) |
| G2 | Implementation/component evidence only; independent P03/P04 DV pending: FIFOs/pools, descriptor queues, DRR/packet RR, CSR/statistics and exercised bench fixture | [P02](results/P02-storage-primitives.md), [P03](results/P03-queues.md), [P04](results/P04-scheduler.md), [P06](results/P06-registers.md), [P07 follow-up](results/P07-followup-stimulus.md); P05/P08 and composition pending |
| G3 | Pending real vertical path | P09 |
| G4 | Pending integrated concurrency/profile evidence | P10 |
| G5 | Pending composition proofs and coverage closure | P11A/P11B/P11C |
| G6 | Pending full matched traffic/implementation studies | P12 |
| G7 | Pending checked diagnostics and release audit | P13/P14 |

The integrated-main CI run
[43264681095](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43264681095)
completed successfully. This records hosted evidence; no new local test execution
is implied by this documentation update. The earlier main failure at `4d55757`
was addressed by the runner race fix merged with PR #10; preserve its history.

## Remaining decisions and work

- [F01](implementation/tasks/F01-formal-symbols.md) qualifies fixed symbolic
  witnesses and fail-closed source guards. [Local results](results/F01-formal-symbols.md)
  close this prerequisite; local queue RTL/proofs are delivered in P03.
- [R01](implementation/tasks/R01-reset-timing.md) establishes shared reset timing
  interpretation; original negative removal measurements remain recorded.
- [A01](implementation/tasks/A01-allocator-selection.md) evaluates the demonstrated
  1024-cell selection bottleneck and records a disposition before P08.
- P08 measures the real allocator/admission consumer path. Standalone timing is
  not an integrated bound; existing statistics area remains separately identified.
- [C01](implementation/tasks/C01-ci-economy.md) owns cheaper hosted iteration and
  minor validator/run housekeeping; it does not establish hardware correctness.

Each results report identifies its tested revisions, assumptions, profiles and
scope. Later prose/merge commits do not replace those identities or create PASS.
See the [current plan](implementation/plan.md) for the remaining dependency order.

## Ownership and verified gates

See the [role split and dependency inventory](implementation/plan.md#ownership-and-verification-gates).
P02/P06 implementation tasks remain complete; retain their valid local evidence.
Separate-owner qualification not established by those reports and their pending
integration/composition checks remain explicit DV gaps, not implementation rework.
The plan retains the verified P09/P11 gates; the
[root ownership policy](../AGENTS.md#separate-rtl-and-independent-dv-ownership)
defines the shared workflow.
