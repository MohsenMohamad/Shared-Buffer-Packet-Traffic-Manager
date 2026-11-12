# P03 descriptor queues

The production queue controller and reusable descriptor-link child implement
pre-state publication/dispatch and merged same/different-qid updates. The queue
component tests pass all six production profiles. FP-QUEUE and FP-ORDER are
proved unboundedly at two queues/eight descriptors on the actual controller and
link RTL. The last-entry mutation fails the intended named ordering assertion.
These are component results; ownership callers and the packet path remain
composition obligations.

The [compact evidence](P03-queues.json) records actual tested base revision,
dirty source hashes, configurations, tool/lock identities, commands, run names,
metrics, engine statuses and cover steps. Tests start from current origin/main
`068e2c6` on `feat/descriptor-queues`; dirty executions retain their actual input
hashes instead of claiming execution on a later commit. Raw manifests, separate
stdout/stderr, staged configurations and counterexample/cover waves remain in
ignored `.build/runs/` artifacts. No hosted execution, synthesis or timing result
is claimed.

## Implementation and ownership

`tm_queue_ctrl_api` owns only head/tail/count. Both operations use pre-state
eligibility and one combined next-state assignment; concurrent publication cannot
fund an empty dispatch. Empty/mismatched dispatch and out-of-range or overflowing
publication set the sticky invariant error and are ignored as queue actions.
Caller violations do not define a general recovery protocol.

At count one, simultaneous dispatch/commit retains the old descriptor on the
accepted dispatch record and installs the new descriptor as head and tail.
It issues no link write and never traverses the old final link. At longer counts,
pop follows the actual old-head link and push writes the old tail once. Different
qids both update. Queries remain registered pre-state arrays until the edge.

`tm_desc_links` owns the only descriptor-next array in each queue verification
assembly. It has one edge-triggered write and one combinational pre-state read,
with no reset or write-through. Live head/tail/count validity bounds traversal;
unused and final-entry links remain stale. P05 must reuse this exact production
child once in the metadata wrapper, retaining the controller as the sole
head/tail/count writer. The full wrapper is still a declaration.

The actual P02 `tm_desc_pool_api` has allocation from `admit` and distinct
`tx_return`/`abort_return` lanes. The queue has no return output. Simulation
instantiates this pool: a full pool stays exhausted while every queued descriptor
moves to modeled TX ownership; only a later TX-completion return frees an ID.
A same-edge return cannot fund allocation/publication. This is a local boundary
check with modeled TX completion, not implementation of TX or an integrated FIFO.

## Executed checks

| Check | Result and scope |
| --- | --- |
| F01 prerequisite | Qualified explicit-input recipe rerun passes all 28 cases at widths 1/4; existing integrated bridge scope retained from F01. |
| Queue simulation | F0/F1/I0/I1/E0/E1 pass with more than 12,000 sampled cycles each. F0/I0/E1 use seed 23; F1/I1/E0 use seed 17. |
| Width matrix | QID widths 1/2/3/4 and descriptor-count widths 4/5/6/9; current ANSI records with guarded widths, no native record flattening. |
| FIFO/count proof | FP-QUEUE/FP-ORDER pass unbounded k-induction on actual controller/link RTL; N_Q=2, N_DESC=8, IDs 3 bits, counts 4 bits. |
| Reachability | Last-pop/push, longer replacement, two qids, full occupancy, empty attempt plus commit, active reset collision and post-reset publication reached. No guided-cover restrictions. |
| Seeded defect | Replacing the singleton bypass with the stale old link produces a real `g_order[q].a_order` counterexample; expected detection passes. |
| Contracts and tooling | E0 contract elaboration/independent batching, lint capability route, Python/JSON/shell checks, 73 toolchain unit tests, repository/link checks and whitespace checks pass. Lint's fixture route is not production queue lint evidence; queue builds enable simulator assertions and warning errors. |

The independent simulation model stores ordered lists updated only from accepted
commit/dispatch actions and separately tracks allocated versus TX-owned IDs.
Directed cases cover each qid's transition matrix, a queue filled to N_DESC,
all descriptors held after dispatch, next-edge publication and return visibility,
and reset during concurrent actions. Random traffic exercises alternating qids,
rapid returned-ID reuse and stale link contents. A separate passive checker checks
one-write/read pre-state semantics, including a read/write-address collision;
its saved link values never supply the FIFO model's expected order. Those saved
values persist across reset, so clearing the production link array would fail.
The inspected mutation trace replaces qid 1's sole descriptor 0 with descriptor
4 while old link 0 contains 2. The mutant installs head 2, and the independent
list expects head 4; the named ordering check detects that mismatch.
Direct illegal empty dispatches, alone and with publication, check the controller's
empty guard and sticky error independently of scheduler-style request filtering.

## Proof and residual obligations

See [formal/queue/README.md](../../formal/queue/README.md) for the complete
configuration, assumptions and invariant structure. The proof uses F01's arbitrary
top-level input recipe; no fixed witness or native symbolic decoration is needed.
Independent lists determine accepted pop IDs and expected order. Every live edge
is related to the real child's link through an **asserted** representation
invariant, never an assumed favorable next pointer. Safety is unbounded;
16-sample covers establish reachability only. Reset is modeled at sampled edges,
including arbitrary later resets; recovery/removal timing is outside this result.

P11A must discharge legal RX ownership and global pre-state disjointness at
publication: commit ID/qid are in range, the descriptor is not already in **any**
queue (even if popped on the same edge), and total queued count is below capacity
when committing. Legal RX ownership additionally excludes FREE, TX and ABORT
references; the local harness does not prove those owner transitions. Payload
completion and immutable descriptor-info correctness remain caller obligations.

P04/P11A must prove dispatch is a pre-state eligible head with matching descriptor
information and unconditional TX acceptance. P05 reuses the link child and proves
TX final-beat retirement/return timing, immutable metadata and finite memory ports.
P09/P10/P11A compose reset epochs, actual pool/accounting and ownership transitions.
Commit-to-output bytes, DRR fairness and whole-system conservation are not closed
by this FIFO proof. Requirement records retain their subsystem status and add
scoped queue-component evidence for Q-01 through Q-05, MEM-01, ADM-03, reset and
parameter obligations. Q-06 ingress-completion timing remains an integration test.

## Reproduction

Use the prepared pinned installation; no dependency changes or installation are
part of these checks.

```sh
source .tools/activate.sh
make formal-symbols RUN_ARGS='--timeout 120'
make regression RUN_ARGS='--profile F0 --test queues --seed 23 --timeout 120'
make regression RUN_ARGS='--profile F1 --test queues --seed 17 --timeout 120'
make regression RUN_ARGS='--profile I0 --test queues --seed 23 --timeout 120'
make regression RUN_ARGS='--profile I1 --test queues --seed 17 --timeout 120'
make regression RUN_ARGS='--profile E0 --test queues --seed 17 --timeout 120'
make regression RUN_ARGS='--profile E1 --test queues --seed 23 --timeout 120'
make formal-rtl RUN_ARGS='--test queues --timeout 300'
make regression RUN_ARGS='--profile E0 --test contracts --seed 17 --timeout 120'
make lint
python3 tools/check_light.py
python3 tools/check_repository.py
git diff --check
```

The `queues` simulation source set, suite handler and production-proof selection
are registered through the common runner. The existing full-CI storage job runs
`pools` and `queues` across all profiles and the default production proof set now
includes `queues`. The scheduler, metadata wrapper and integrated packet FIFO
were not implemented as part of P03.

## CI registration correction

The first full hosted run ([43296011706](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43296011706))
failed in `capability-bridge`. The legacy bridge iterated the expanded production
proof registry and tried to process `queues` as an old storage harness, raising
`KeyError: defines`. The same failure was reproduced locally on `f89fcfb`.

The bridge now selects exactly its five qualified historical configurations.
All production selections, including the separate queue proof, remain registered.
A regression checks that new explicit-input proofs cannot extend the bridge and
that losing any historical configuration still fails. After the correction,
`make bridge RUN_ARGS='--timeout 900'` passes all 49 cases, including property
inventories and both assumption-inclusion directions. `python3 tools/check_light.py`
passes all 74 unit tests; repository and whitespace checks also pass. The compact
record retains the tested dirty inputs separately from the original RTL results.
Hosted qualification of the correction is pending.
