# Implementation plan

Task cards define assignments; [specifications](../spec/README.md) define behavior.
Use the committed working/documentation rules and the actual current source tree.
Completion of a fixture or local proof does not close an integrated gate.

## Integrated v1 baseline

At `c32b3f1b79ac3412532e0564e038983aa2862112`, PRs #1-#10 integrate P00/P01/P02/
P06/P07, shared CI/evidence work, toolchain qualification, RTL
representation, allocator characterization and the P07 stimulus/checker
follow-up. These stabilization implementation steps are complete. Their original
tested revisions and scopes remain in the linked reports. The main run
[43264681095](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43264681095)
completed successfully. This statement records that hosted result, not a new local run.

P03 RTL is merged in PR #14 and P04 RTL in PR #16. Their
[queue](../results/P03-queues.md) and [scheduler](../results/P04-scheduler.md)
reports retain their author scope. P03/P04 independent DV is integrated in PRs
#17/#18. P05 RAM/metadata/TX RTL and component qualification are integrated in
PRs #24/#26. PR #27 repaired the main-push checkout and the subsequent full main
run passed. See [status](../status.md) for the remaining qualifications and gates.
[F01](tasks/F01-formal-symbols.md) is integrated; [R01](tasks/R01-reset-timing.md)
and [A01](tasks/A01-allocator-selection.md) remain analysis inputs for the v2 path.
[C01](tasks/C01-ci-economy.md) is integrated.

## v2 migration and gates

The 4×4 work starts at the Step 1 merge
`cf08ec7ee9b742540786376d2052987f08ca42a5` (PR #28). The
[v2 target contract](../spec/tm-v2-4x4.md) selects one shared 512-bit read and
one shared 512-bit write per cycle with independent ingress staging and egress
prefetch. Its [cycle study](../results/tm-v2-feasibility.md) passes the balanced
target at modeled latencies of one and two cycles. Queue/control realization
and independent hardware acceptance are open.

| Baseline component or work | v2 disposition and required evidence |
| --- | --- |
| P01 / P02 / P07 | Reuse qualified frontend idioms, eligible elastic FIFOs and scalar ownership kernels, plus UVM agents, passive sampling and runner infrastructure after the relevant ownership/provenance review. Publish new versioned v2 types and declarations. Independently requalify integration and any widened resource updates. |
| P03 queues | Preserve FIFO-by-publication and the sole-entry replacement rule. Change to one global publish plus concurrent egress pops, merged active bitmaps, and pre-edge successor visibility. Qualify same/different-queue collisions and four-way dispatch independently. |
| P04 scheduler | Reuse byte-DRR arithmetic and packet-RR policy where applicable. Per-egress lookahead, strict priority, parked shaping visits, dual token buckets and new binding semantics require separate RTL and independent qualification. |
| P05 memory/TX | Reuse fixed-latency response tagging and acceptance-based retirement principles. Replace word service and single TX context with 512-bit cells, four readers sharing one issue lane, per-egress credits and successors, and new metadata port budgets. Qualify both latencies, stall/reset epochs, late handoff and simultaneous returns. Keep the tested v1 [P05 scope](../results/P05-candidate-qualification.md). |
| P06 registers | Reuse the qualified AW/W hold and response logic where compatible. New v2 routing, controls, snapshots and concurrent counter updates need versioned CSR declarations, independent bus/policy checks, and real datapath composition. The [v1 CSR report](../results/P06-registers.md) retains its original scope. |
| P08 ingress/admission/cleanup | The pending v1 one-beat arbiter and its admission/reclaim implementation are superseded for the active path. Prepare v2 tests from the new framing, prefix-ordered atomic reservations, α arithmetic, independent drain and dedicated cleanup service. Qualify capacity and concurrent return behavior with the actual v2 consumer. |
| R01 reset timing | Carry forward the constraints method and evidence history. Establish v2 clock, I/O, reset assertion/release and recovery/removal path treatment with setup and hold before comparing new structures. Retain the v1 negative removal observations. |
| A01 allocator | Keep the v1 1,024-cell selection-risk characterization. Compare any-valid-free-ID structures against v2's four-vector descriptor reserve, one cell allocation and up to five returns without same-edge returned-ID reuse. Measure representative small and primary-size logic through the real reservation/reclaim consumer after R01. |
| P09–P14 one-egress work | Superseded on the active v2 path. Carry forward the vertical integration, concurrency, proof, coverage, mapped timing, diagnostics and audit objectives through the v2 gates below. Historical cards and results retain their version and provenance. |

### Next assignment and queue/control prerequisite

The next scoped assignment publishes versioned stream, event-batch, memory,
profile and CSR declarations, including the status and snapshot interfaces.
It checks elaboration and layout at both profiles without producing datapath
RTL. Independent DV then prepares and freezes expectations from those
declarations and the v2 contract under the
[root role policy](../../AGENTS.md#separate-rtl-and-independent-dv-ownership).
Queue/control analysis may use those declarations and the feasibility study.
Production RTL and independent DV retain separate owners, branches and PRs.

**Queue/control feasibility is a prerequisite for freezing the dependent v2
queue, allocator and datapath microarchitecture.** Demonstrate a finite
organization for one publication per edge, four pre-edge scheduler selections
and dispatches, simultaneous enqueue/pop with active-bitmap maintenance, and
the specified descriptor and cell return vectors including cleanup. Include
actual link/head read muxes or equivalent head caching, concurrent counter
deltas, and four prefix-ordered admission decisions with distinct pre-state
descriptor IDs. Work through same-queue updates, full/empty exchanges, and
concurrent admissions with a reclamation burst. Show bounded abort and read
service under their stated assumptions. Use a cycle-accurate prototype or
equivalent edge-level analysis including real metadata latency. Characterize
representative mapped queue, admission and allocation paths at small and
primary control sizes under R01 constraints. If the concrete design needs
extra stages, re-run the balanced target with those stages and document an
accepted change to buffering, scheduling or memory organization before
committing dependent RTL. Keep the primary capacity and throughput workload.

### v2 integration and release acceptance

- **SV/UVM.** Independently score bytes, framing, metadata, order and
  dispositions from passive ingress/egress/control monitors. Cross-check
  ordered trace batches and credit deltas against observed handshakes and a
  separately derived policy model. Qualify omission/duplication/corruption
  detectors and repeated tags. Execute the base gate and separate
  mixed-destination, bounded stall, incast DROP/WAIT, shaping and ECN tests.
  For mixed destinations, rotate each source's egress each frame and check
  committed order and per-egress service without imposing the permutation
  rate. For shaping, exercise queue-only, port-only and dual limits with
  fractional refill, stalls, saturation and high-priority competition.
  Compare against binding-time byte budgets and the allowed delivery burst.
  Check zero unexplained loss, duplication or leaks and complete frame and
  resource accounting after drain. Use both latencies, at least three random
  seeds per applicable profile, and deterministic directed replay.
- **SVA and coverage.** Bind checks for stall stability, frame boundaries,
  reset epoch, old-state grants, distinct reservations/returns, fixed response
  timing, prefetch credit and binding/debit. Observe required bins for each
  port/class, every legal final keep, partial cells, length bounds, full pools,
  same-edge publish/pop/return, contested abort, late strict arrival, bucket
  comparison at threshold, all ECN codepoints and resets with pending work.
  Review critical crosses and justified exclusions against the v2 requirement
  matrix. Record checker and intended-fault detection evidence.
- **Selected formal.** Prove conservation including reserved versus assigned
  credit, unique cell/descriptor ownership and reclaim, bounded occupancy and
  outstanding responses, and per-queue FIFO order through concurrent
  publication/dispatch and reset. Require reachable collision, full-capacity
  and abort/retire/reset covers. Use the small profile or document each reduced
  kernel and its composition premises. Safety must permit arbitrary legal
  stalls. Progress bounds name arbitration, token and sink assumptions.
  Record proof mode, depth or induction, exact tool/source and any timeouts.
- **Mapped synthesis and pre-layout STA.** Map the small profile with actual
  memory and control, or characterize a real macro. Give primary-profile
  control timing, payload bits, defined RAM latency/ports and separate memory
  assumptions. Start with the v1 study's 10 ns clock, 2 ns I/O and 0.10 ns
  uncertainty using explicit min/max delays, slew/load and reset checks.
  Record library identity, PVT, constraints, setup/hold slack and constrained
  path groups. Match function and capacity for variants where possible, and
  keep memory accounting comparable.
- **Gate closure.** Establish separately qualified component scopes first,
  then independently run the integrated v2 gates at named combined RTL and
  DV sources and confirm exact merged sources. Register suites and coverage
  through the existing tooling. Retain compact replay inputs, source, commands
  and results, and preserve named v1 evidence at its recorded SHA.

## v1 dependencies and owners

| Work | Assignment | Entry / current state |
| --- | --- | --- |
| P00/P01/P02/P06/P07 | Toolchain, contracts, storage, CSR and bench foundation | Integrated with component/fixture boundaries |
| Stabilization | [Toolchain refresh](tasks/P00-followup-toolchain.md), [representation](tasks/P01-followup-representation.md), [scaling](tasks/P02-followup-scaling.md), [stimulus](tasks/P07-followup-stimulus.md) | Integrated; consume results, do not recreate |
| C01 | [CI iteration economy](tasks/C01-ci-economy.md) | Integrated; preserve all full suites |
| F01 | [Formal symbolic inputs](tasks/F01-formal-symbols.md) | Integrated; applies to every harness |
| P03 | [Descriptor queues](tasks/P03-queues.md) | RTL #14 and independent DV #17 integrated |
| P04 | [DRR and packet RR](tasks/P04-scheduler.md) | RTL #16 and independent DV #18 integrated; P09/P11B own composition |
| P05 | [Finite-port memory and TX](tasks/P05-memory-tx.md) | RTL and scoped component qualification integrated. Historical preparation independence, composition and coverage closure remain open. |
| R01 | [Reset timing convention](tasks/R01-reset-timing.md) | Before A01 measurements / P08 |
| A01 | [Allocator evaluation/disposition](tasks/A01-allocator-selection.md) | Existing characterization + R01; before P08 |
| P08 | [Receive/admission/reclaim](tasks/P08-receive-admission.md) | P02/P03/P05/P07 + A01/R01; earlier follow-ups integrated |
| P09 | [Real vertical path](tasks/P09-vertical-integration.md) | P04/P05/P06/P07/P08 |
| P10 | [Concurrency/profile regression](tasks/P10-concurrency.md) | P09; packet-rate decision before P11 |
| P11A | [Resource/queue proof closure](tasks/P11A-formal-resources.md) | P10 |
| P11B | [TX/scheduler/CSR proof closure](tasks/P11B-formal-interfaces.md) | P10 |
| P11C | [Coverage/requirement closure](tasks/P11C-coverage.md) | P10 + P11A/P11B |
| P12 | [Traffic and implementation studies](tasks/P12-measurements.md) | P11C; R01 + P08 timing inputs |
| P13 | [Checked failure diagnostics](tasks/P13-diagnostics.md) | P10; secondary to core RTL/DV |
| P14 | [Independent release audit](tasks/P14-release.md) | P12/P13 and current integrated evidence |

The historical one-egress serial route was R01, A01, P08, P09, P10,
P11A, P11B, P11C, P12, P13, P14. C01 and independent analysis can run alongside
hardware work when shared file ownership is explicit. P11A/P11B and P12/P13
remain possible independent waves; serial work is simpler by default.

## Active tool and representation contract

Use the selected source identities in `tools/dependencies.json`, not a floating
latest release. The integrated stack is Yosys 0.70+post/Slang, Verilator 5.054,
official UVM 2020.3.2, SBY 0.71, Z3 5.4.1 and authoritative OpenSTA 3.2.0 with
pinned transitive inputs. [Decision 0006](../decisions/0006-modern-toolchain.md)
and [0007](../decisions/0007-rtl-representation.md) explain qualified choices.

Use ANSI ports, `tm_fixed`, the shared dependent `localparam type` declarations,
guarded widths and registered source lists. Preserve packed public lane order
and intentional generic vector FIFO/pool boundaries. The separator macro avoids
duplicate dependent records; it is not an invitation to create a macro framework.
Qualify a useful new language/library construct once before depending on it.
Use the qualified types and declarations. Richer design syntax does not imply
full temporal-SVA/four-state support.

Use F01's explicit-input recipe in all formal harnesses. UVM agents, passive models, constrained packet
objects and RAL already exist; extend them onto real RTL without another bench
or runner. Frontdoor/no-DPI remains a valid tested choice; use qualified DPI
only for a concrete need, not to replace external checking.

## v1 implementation and decision checkpoints

P08 follows the [root preparation and qualification workflow](../../AGENTS.md#preparation-implementation-and-independent-qualification).
P03/P04/P05 RTL and component DV landed in separate PRs. P09 wires the real top
and bench. P10 establishes concurrency across F0/F1/I0/I1/E0/E1. P11 closes
composition and coverage.

R01 preserves old reset-violation evidence and establishes comparable new
constraints. A01 reviews whether lowest-pre-state-ID ordering has any functional
consumer before comparing selection structures. It may propose a reviewed
any-valid-free-ID contract with complete specification/checker updates; ownership
safety does not depend on numeric ordering. Latency/return-bypass changes remain
separate decisions. Existing tests alone are not a justification for an arbitrary
policy, and deleting a failing safety check is not a design decision.
P08 measures through the actual selected allocator consumer at I0 and 1024 cells.

P09 measures saturated 64/1536-byte packet rate early. P10 attributes each output
cycle once and records a reviewed baseline/optimization decision before P11.
There is no invented 64-byte target; the existing 1536-byte target remains.
An adopted optimization refreshes affected integration/checker/proof evidence.

P12 can be delivered in cohesive steps: traffic benchmarks, the actual matched
flat/banked memory variant, then final mapped/STA comparison. Those steps together
close P12. P13 can likewise separate offline failure collection from its real
diagnostic session/review; fixtures alone do not close AI-01. Later executable
changes refresh affected G5 evidence before P14.

## Commands and evidence ownership

The current runner and registries are authoritative for existing commands,
including `queues`, `scheduler` and `memory-tx`. Future cards register their
named suites (`receive`, `vertical`, `concurrency`) and proof families. Keep capability fixture
commands and functional single-seed replay semantics distinct. Empty, unknown,
duplicate or missing required selections fail rather than silently passing.

P11C owns compatible saved coverage databases and reviewed exclusions. P12 owns
`benchmark`, `synthesis` and `sta`; P13 owns triage hooks through the same runner.
P14 reconciles all 52 obligations with actual current source and results.
Keep the requirement registry tied to executed scope; fixture/component results
must not be promoted to full-subsystem PASS.

Review exact base/head revisions and integrate prerequisites before dependent
tasks. Retain criteria-before-results and cleanup-before-new-functionality commits
through merge commits where their order is evidence. Follow the
[durable evidence policy](../documentation.md#durable-evidence-for-new-work). Reuse valid
evidence; refresh checks affected by executable changes. The maintainer controls
merges and any release tag.

## Reviewing a recorded design restriction

A current contract is the starting point for compatible work, not proof that its
original choice was well studied. Before preserving a restrictive implementation
policy, identify the external behavior or real consumer that requires it,
distinguish architectural timing from correctness invariants, and compare a
grounded alternative when evidence warrants it. Change a contract explicitly with
its callers/checkers and verification plan; do not silently freeze convenience
choices or weaken safety to make an experiment pass. A01 is the assigned review
of numeric allocation order; this does not reopen every accepted project scope
decision without a concrete reason.

## Ownership and verification gates

The [root ownership policy](../../AGENTS.md#separate-rtl-and-independent-dv-ownership)
defines file boundaries and the shared RTL/DV workflow. This table captures
the one-egress assignments and evidence dependencies.

| Task | RTL PR | Independent DV / other PR |
| --- | --- | --- |
| P03 / P04 | Already merged #14 / #16 | Independent queue / scheduler DV integrated #17 / #18 |
| P05 | Store, metadata, TX and designer smoke integrated #24 | Component tests, FP-TX, covers and negatives integrated #26. See [status](../status.md) for remaining gates. |
| A01 | Adopted allocator candidate after coordinated policy decision | Independent safety/policy qualification; analysis owns frozen comparison and disposition |
| P08 | RX/admission/reclaim implementation + designer smoke | Framing/admission/accounting/concurrency tests and local composition proofs |
| P09 | Real top/config/event/ownership wiring | Real UVM path, binds, scoreboard qualification, coverage and subsystem CI |
| P10 / P11A / P11B / P11C | Defects handled by separate fix PRs | DV concurrency, proof composition and coverage closure |
| P12A | None | DV traffic/benchmark work (steps 1–4) |
| P12B | Real matched memory variants (step 5) | Separate DV requalification (step 6); refresh affected G5 evidence |
| P12C / R01 | None | Analysis: mapped synthesis/STA/comparison (steps 7–9) / reset constraints |
| P13 | None | Tooling/diagnostics; actual reviewed session required |
| Optional optimization | Separate scoped RTL optimization PR | Separate independent DV PR; refresh affected checks and G5 evidence |

P09's verified G3 gate consumes passing merged component DV scope, including
P03/P04/P05/P08 and applicable P02/P06 qualification. Wiring and early DV may
begin earlier but cannot claim G3. P11 closure consumes verified P09/P10 and the
reviewed packet-rate decision; an adopted optimization requires its passing DV
merge before closure. Analysis and infrastructure cannot establish these gates.

### Dependency evidence inventory

P02 implementation is complete (PR #3, merge
`b663f47de525e132f32afe621cff69ac82633478`). Its
[storage report](../results/P02-storage-primitives.md) records live-ID/FIFO models,
unbounded local proofs, covers and intended wrong-delta detections at tested
`040863d055ba5fd70b3c09f18e3c268c67d3c1ef`; later representation/toolchain
qualification and allocator characterization retain their own scopes. This is
substantial reusable dependency evidence.
Its report does not establish separate-owner independent qualification or global
RX/TX/abort composition; inventory/review of that missing qualification remains
DV work before the relevant verified integration gate.

P06 implementation is complete (PR #5); the
[CSR report](../results/P06-registers.md) records independent architectural-event
models, bus coverage, FP-CSR and intended AW/W defect detection at tested
`26bad4d0bdf52d8657b1a4cd3ea14061ab54e2cc`. Its independent model is useful evidence;
separate-owner qualification is not demonstrated by that label alone. The genuine
gaps are provenance review/independent signoff and actual datapath event/IDLE
composition in P09/P10/P11B. Existing local evidence remains reusable with those
scope boundaries.
