# Implementation plan

Task cards define assignments; [specifications](../spec/README.md) define behavior.
Use the committed working/documentation rules and the actual current source tree.
Completion of a fixture or local proof does not close an integrated gate.

## Integrated baseline and remaining entry condition

At `c32b3f1b79ac3412532e0564e038983aa2862112`, PRs #1-#10 integrate P00/P01/P02/
P06/P07, shared CI/evidence work, modern toolchain qualification, the RTL
representation migration, allocator characterization and the P07 stimulus/checker
follow-up. These stabilization implementation steps are complete. Their original
tested revisions and scopes remain in the linked reports. The main run
[43264681095](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43264681095)
completed successfully. This statement records that hosted result, not a new local run.

P03 is the next new hardware stage after [F01](tasks/F01-formal-symbols.md) closes
fixed-symbol formal semantics. [R01](tasks/R01-reset-timing.md) owns reset
constraint interpretation before new allocator/P08 studies. [A01](tasks/A01-allocator-selection.md)
owns measured allocator alternatives and a reviewed disposition before P08.
[C01](tasks/C01-ci-economy.md) reduces hosted iteration cost and is useful early;
it does not block queue implementation.

## Dependencies and owners

| Work | Assignment | Entry / current state |
| --- | --- | --- |
| P00/P01/P02/P06/P07 | Toolchain, contracts, storage, CSR and bench foundation | Integrated with component/fixture boundaries |
| Stabilization | [Toolchain refresh](tasks/P00-followup-modern-toolchain.md), [representation](tasks/P01-followup-representation.md), [scaling](tasks/P02-followup-scaling.md), [stimulus](tasks/P07-followup-stimulus.md) | Integrated; consume results, do not recreate |
| C01 | [CI iteration economy](tasks/C01-ci-economy.md) | Early maintenance; preserve all full suites |
| F01 | [Formal symbolic inputs](tasks/F01-formal-symbols.md) | Before P03 and new harnesses |
| P03 | [Descriptor queues](tasks/P03-queues.md) | P02 + F01 |
| P04 | [DRR and packet RR](tasks/P04-scheduler.md) | P03 |
| P05 | [Finite-port memory and TX](tasks/P05-memory-tx.md) | P03 |
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

A practical serial route is C01/F01, P03, P04, P05, R01, A01, P08, P09, P10,
P11A, P11B, P11C, P12, P13, P14. C01 and independent analysis can run alongside
hardware work when shared file ownership is explicit. P04/P05, P11A/P11B and
P12/P13 remain possible independent waves; serial work is simpler by default.

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
Do not flatten current types to satisfy the historical native frontend or assume
that richer design syntax implies full temporal-SVA/four-state support.

Use F01's explicit-input recipe in new formal harnesses. Legacy bridge results
retain their narrower scope. UVM agents, passive models, constrained packet
objects and RAL already exist; extend them onto real RTL without another bench
or runner. Frontdoor/no-DPI remains a valid tested choice; use qualified DPI
only for a concrete need, not to replace external checking.

## Implementation and decision checkpoints

P03/P04/P05/P08 add their component simulation, assertions and local production
proofs as they implement the hardware. P09 wires the real top and bench;
P10 establishes concurrency across F0/F1/I0/I1/E0/E1. P11 closes composition and
coverage rather than deferring all verification until the end.

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

The current runner/registries are authoritative for commands that exist. Future
cards register their own named suite (`queues`, `scheduler`, `memory-tx`, `receive`,
`vertical`, `concurrency`) and production-proof families. Keep capability fixture
commands and functional single-seed replay semantics distinct. Empty, unknown,
duplicate or missing required selections fail rather than silently passing.

P11C owns compatible saved coverage databases and reviewed exclusions. P12 owns
`benchmark`, `synthesis` and `sta`; P13 owns triage hooks through the same runner.
P14 reconciles all 52 obligations with actual current source and results.
Keep the requirement registry tied to executed scope; fixture/component results
must not be promoted to full-subsystem PASS.

Review exact base/head revisions and integrate prerequisites before dependent
tasks. Retain criteria-before-results and cleanup-before-new-functionality commits
through merge commits where their order is evidence. Keep bulk logs/waves/netlists
in artifacts and compact durable results/commands in Git. Reuse valid unchanged
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
