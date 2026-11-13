# P03 independent queue qualification

Independent DV is in progress on `verify/p03-queues`. This report is separate
from the unchanged [P03 designer evidence](P03-queues.md). No independent scope
is verified until the passing DV PR merges. Production RTL and embedded designer
assertions are outside this PR's edit boundary.

## Baseline and prepared environment

Fetched main/base: `1c225525ba284ce694f1b234cb12cc514b9c0aee` (P04 PR #16).
The checkout was clean. No existing task branch/PR was found. Actual prerequisite
merges in this ancestry: P02 PR #3 `b663f47de525e132f32afe621cff69ac82633478`,
P06 PR #5 `a473b8c` (CSR dependency inventory), F01 PR #13 `068e2c6`,
P03 PR #14 `eccb9fb`; implementation `f89fcfb`, delivered head `0d0b986`.
P07 PR #4 `0901ad7` and follow-up PR #10 `c32b3f1` remain integrated.
Merge metadata does not replace any historical report's tested revision.

`make doctor` passed on clean main before tool-dependent checks: versions,
OpenSTA source, C++20 and solver SAT/UNSAT. Raw summary:
`.build/runs/doctor-2026-11-13T041026.841233+0000-85e19c6a/summary.json`.
No setup, tool rebuild/install/download, stamp/lock changes or validation bypass
were performed.

The first commit changes ownership documentation only. `make repo-check` passed
(52 requirement records; no hardware evaluated), raw summary
`.build/runs/repo-2026-11-13T041251.379832+0000-3c810913/summary.json`.
`git diff --check` passed. Historical reports and functional specifications are
unchanged. Role assignments preserve every existing card's acceptance obligation.

## Specification-derived API model (before behavioral comparison)

Sources: module-contracts clock/acceptance and queue/metadata port tables,
queues-and-scheduling transition matrix, verification batching and FP-QUEUE/ORDER
in formal.md. The model is an ordered list per qid and a descriptor owner set:
FREE, RX, QUEUED(q) or TX. It is not a copy of the RTL pointer update algorithm.

At each sampled edge, collect the actual API levels. `admit.valid && admit.accept`
allocates a pre-state FREE descriptor to RX; `commit.valid` publishes an RX-owned
complete descriptor absent from all pre-state lists; legal `dispatch.valid`
removes the pre-state first list member and transfers it to TX; an observed
TX-completion return releases a pre-state TX descriptor. No action occurs in
reset. Validate all actions against pre-state before applying the batch. Return
cannot fund allocation, commit cannot fund empty dispatch, and same-edge pop
cannot fund recommit. RX allocation and publication may coincide for a single-beat
packet; the same newly allocated descriptor is the only allowed exception to
pre-state RX ownership. Stimulus must not manufacture acceptance from intention.

For each queue, accepted dispatch removes the first list item, accepted commit
appends an item, then compare count and nonempty head/tail queries. This directly
covers empty/singleton/longer and same/different-qid races; singleton replacement
leaves the new sole item. For an observed metadata read of a live non-tail item,
expected next is the following list item. Never follow stale tail contents.
A separate port checker can retain observed link writes across reset to check
pre-state read/no-clear semantics, but it cannot supply FIFO expected values.

Reset empties lists and restores owner sets; retained metadata is unowned until
reused. Exercise full queue occupancy, all descriptors held by TX after dispatch,
nonzero RX publication delay, rapid reuse and supported parameter boundaries.
Coverage records sampled events/pre-counts, not requested scenarios. Illegal empty
actions are separate diagnostic tests and never become accepted FIFO operations.

## Retained evidence audit

The author `dv/unit/queues_tb.sv` does use independent ordered lists and a passive
link checker; its event sampling is inside the driver task and admission/commit
are coupled. Retain it as designer evidence; add a separate passive API model
with independently scheduled allocation/publication/TX return and saved coverage.
The author formal harness uses ordered lists and asserted live-link invariants,
not assumed RTL-derived expected next pointers. Its local queued-ID exclusion is
sound for that scope, but does not establish RX/TX/ABORT/FREE ownership. Strengthen
that boundary and qualify fixed witnesses held across later resets. Preserve its
provenance and existing selection; independent results get separate selections.
