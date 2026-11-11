# P07 follow-up: Readable checkers and constrained packet stimulus

## Objective and prerequisites

Extend the integrated [P07](P07-verification-foundation.md) foundation before P08 with readable independent checkers and actual constrained packet generation. Preserve production interfaces and verification independence.

## Execution sequence

1. Perform behavior-preserving readability cleanup in separate commits **before** adding generator functionality. Use descriptive names, separated statements/state transitions, manageable functions and explanations of non-obvious invariants. Preserve the checker contracts and detection strength.
2. After cleanup, rerun existing positive tests and deliberately broken fixtures. Require each defect to be detected by its intended checker with the expected violation; an unrelated assertion, crash or tool failure is insufficient. Record exact revision/seeds and outcomes before proceeding.
3. Qualify packet-level `rand` fields and constraints with the pinned simulator/UVM library. Use checked `randomize()` calls that fail clearly on unsatisfiable constraints. Constrain legal lengths, qid, data/keep/last relationships and supported profile limits at packet level; preserve monitor-derived expectations.
4. Keep explicit directed and malformed controls separate from legal-packet constraints. Malformed length, framing, keep, metadata and invalid-qid cases must remain intentionally selectable rather than accidentally excluded or accepted as legal traffic.
5. Check boundary values and constraint rejection, deterministic same-seed replay and changed-seed diversity. Save actual generated-stimulus records/digests and observed handshakes, distributions, seeds/profiles and boundary coverage; declaring fields or compiling constraints is not generated-traffic evidence.
6. Separate scheduler policy checks from baseline timing assumptions. Validate legal queue selection, ordering, deficit/quantum and service ownership independently; isolate fixture-specific dispatch latency assumptions for later production binding. Do not accept whatever grants the DUT reports as the expected policy or weaken meaningful policy checks to accommodate timing changes.

## Required checks and completion

Deliver separate cleanup and functionality commits, before/after positive and intended-negative qualifications, randomization success/failure/boundary tests, replay/diversity and actual generated-stimulus evidence. Retain duplicate tags, reset epochs, simultaneous batching and malformed controls. Fixture results remain distinct from production receive/integration evidence. Complete before [P08](P08-receive-admission.md).
