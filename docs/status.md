# Integration status

Main includes P00/P01/P02/P03/P06/P07, F01 and C01 through
`0c65e26cfd81f4f4111e1da00ada2aaa022f2ab0` (PR #15).
This branch adds [P04 scheduler component qualification](results/P04-scheduler.md);
it does not close the integrated G2 gate.
The qualified toolchain, ANSI declarations and shared types, allocator characterization and P07
constrained-stimulus/readability follow-up are merged. The top and unimplemented
components remain declarations; complete traffic-manager behavior is pending.

| Gate | Current scope | Evidence / owner |
| --- | --- | --- |
| G0 | Qualified toolchain fixtures and selected frontend | [Toolchain qualification](results/modern-toolchain.md) |
| G1 | Qualified declarations/configurations; qualified types and declarations | [P01](results/P01-contracts.md), [RTL representation](results/rtl-representation.md) |
| G2 | Partial: FIFOs/pools, descriptor queues, DRR/packet RR, CSR/statistics and exercised bench fixture | [P02](results/P02-storage-primitives.md), [P03](results/P03-queues.md), [P04](results/P04-scheduler.md), [P06](results/P06-registers.md), [P07 follow-up](results/P07-followup-stimulus.md); P05/P08 and composition pending |
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
