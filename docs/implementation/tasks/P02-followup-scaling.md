# P02 follow-up: Production allocator scaling

## Objective and prerequisites

Characterize the actual integrated P02 allocator now, completing this follow-up before P08. Dependencies: [P02](P02-storage-primitives.md). Preserve the allocator and production APIs during this investigation; propose any replacement as separate reviewed work.

## Execution sequence

1. Inspect the real cell/descriptor wrappers and bitmap selection kernel. Use production source lists and capacities including 1024, with representative smaller capacities and actual return-lane/ID widths. A surrogate priority encoder cannot qualify this study.
2. Commit and push the experiment definition **before** running experiments: exact source selection, capacity matrix, pinned tools and Liberty/library/PVT, clock and timing budget, uncertainty, explicit input/output delays, transition and output loads, synthesis options, path groups and legitimate exceptions. Define area/timing/fanout decision criteria and constraint coverage checks in that commit.
3. Distinguish exploratory timing conditions from an agreed F0 acceptance requirement. No exploratory clock establishes a new acceptance target. State which criteria prompt investigation and which, if any, are agreed blocking requirements.
4. Run mapped synthesis/STA on the actual production allocator. Record cell area, selection-path timing, overall worst path, relevant fanout/buffering and unconstrained paths at each capacity, with exact revisions, commands, digests and tool/library versions.
5. Commit results in a subsequent commit referencing the already-pushed definition. Record any criteria changes in separate commits with rationale; retain the original definition and distinguish original versus revised comparisons.
6. Separate standalone allocator results from timing through consumers. Schedule an actual production receive/admission consumer-path recheck during [P08](P08-receive-admission.md), including 1024 cells under identified constraints; standalone slack cannot establish consumer closure.
7. Propose focused investigations if results justify them, such as selection structure or pipelining trade-offs with contract consequences. Do not automatically replace the allocator or change allocation semantics/APIs.

## Required checks and completion

Deliver a durable experiment definition and subsequent results report with compact measurements, reproduction commands and artifact references. Review constraint coverage, area, selection and worst-path timing, fanout, limitations and proposed investigations. Complete the standalone study before P08; P08 owns the consumer-path recheck. No post-layout or full-TM timing claim follows from this study.
