# Integration status

| Gate | Status | Evidence |
|---|---|---|
| G0 Toolchain | PASS (native capability fixtures) | [P00 evidence](results/P00-toolchain.md) |
| G1 Contracts | PENDING | P01 |
| G2 Components | PENDING | P02–P08 |
| G3 Vertical path | PENDING | P09 |
| G4 Concurrency | PENDING | P10 |
| G5 Verification | PENDING | P11A–P11C |
| G6 Measurements | PENDING | P12 |
| G7 Release | PENDING | P13–P14 |

A PR that completes a gate updates this compact summary to its post-merge state. The copy on main describes the integrated repository; a feature-branch copy is a candidate state. Link evidence to the exact revision and artifact. A component PR can contain its own local evidence before an integration gate is complete. No subsystem result is asserted by this initial seed.
