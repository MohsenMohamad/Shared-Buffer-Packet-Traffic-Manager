# Integration status

G0 is qualified on toolchain fixtures; G1 fixes executable module/type/event
contracts. P02 implements and locally verifies registered FIFOs and bitmap
pools. The top and other component APIs remain declarations; integrated
traffic-manager functional gates remain pending.

| Gate | Status | Evidence |
| --- | --- | --- |
| G0 Toolchain | PASS (toolchain fixtures) | [P00 evidence](results/P00-toolchain.md) |
| G1 Contracts | PASS (declarations and batching only) | [P01 evidence](results/P01-contracts.md) |
| G2 Components | PARTIAL: FIFO/pools | [P02 evidence](results/P02-storage-primitives.md); remaining P03–P08 |
| G3 Vertical path | PENDING | P09 |
| G4 Concurrency | PENDING | P10 |
| G5 Verification | PENDING | P11A–P11C |
| G6 Measurements | PENDING | P12 |
| G7 Release | PENDING | P13–P14 |

This table describes the candidate state on a feature branch and the
integrated state on `main`. The linked report identifies tested revisions,
recorded results and validation boundaries; later documentation edits do
not imply a new qualification run.
