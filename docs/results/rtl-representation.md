# RTL representation migration

Representation-only scope, recorded before RTL edits. Baseline is clean
`fb3cd3fd7e2c73379617f11a82c8418e1a590d24` (fetched `origin/main`).
The [capability table](../implementation/modern-toolchain-decisions.md) and
[P01 card](../implementation/tasks/P01-followup-representation.md) govern this
migration. P03+ production implementation and allocator/scheduler optimization
remain paused.

## Baseline and scope

| Concern | Frozen baseline / migration boundary |
| --- | --- |
| Production | FIFO, bitmap/cell/descriptor pools, AXI registers and statistics implemented; top and nine remaining APIs declaration-only |
| Layout | Packed lane zero at LSB; struct fields MSB first; 64-bit input/output metadata, raw qid 8 bits, status 45 bits, full beat 137 bits |
| Configuration | All six profiles in unchanged `verification/profiles.json`; existing scalar overrides and 25 invalid configuration checks retained |
| Ownership | Pools own bitmap/count; CSR owns config/channel holds; statistics owns counters/shadows; no new state owner |
| FIFO | Depth 2/4, registered ready, no fall-through, full-to-pop bubble, unreset payload, one clocked write and asynchronous head read |
| CSR/statistics | Independent AW/W, one read/write outstanding, stable stalled responses, read-before-write, pre-event snapshot, modulo counters and unchanged locks/errors |
| Reset/formal | Asynchronous assertion, two-edge startup constraint, arbitrary later reset/actions; existing assumptions/assertions/covers/mutations remain authoritative |
| Representation | Replace non-ANSI headers, consolidate fixed enums/records, derive widths from types, narrow unused type dependencies; preserve API names and packed boundaries |
| Inference | Compare actual memory dimensions/ports and mapped state against baseline; preserve known −0.09 ns reset-removal violation under unchanged FIFO constraints |

Historical P01/P02/P06/P07 and toolchain reports are preserved. Equivalence is
supplementary to independent contract simulation and formal checks, never a
replacement. No integrated datapath, allocator scaling, four-state simulation,
coverage closure or physical timing signoff is claimed.

## Executed checks and identities

[CI run 43210080611](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43210080611)
is PASS, including all six CSR jobs and handoff cleanup. Its PR head is
`150e48966b3d21f6cee0e42a406b28f24f4b8d80`; the actual clean tested merge SHA is
`e64d6dea9002a1d44fcc5548865b22498abfd286`. Both have Git tree
`8ddc2f5f09c4798537fa233a6262389b30b3cd3d`, verified after fetching the tested
merge object. Later task/result documentation does not imply execution on a
later SHA. The final candidate's own run is linked from [PR #8](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/8).

[The compact evidence record](rtl-representation.json) identifies each local
run's actual tested revision and dirty flag, configuration/dependency/constraint
hashes, observed tool identities, inference/mapping data, expected-negative
identities and hosted artifact IDs/digests. Earlier dirty local runs retain
that flag; no clean revision has been substituted. The local representation run
at clean `18d07c9d017334408607ebf5d5cca0c3d7df2049` passes all 57 cases,
including 42 equivalence cases. Hosted artifacts were downloaded, their SHA256s
checked against GitHub metadata, and their manifests inspected.

| Check | New result and boundary |
| --- | --- |
| Contracts | PASS, six profiles; 76 cases/profile including doctor. Both frontends reject 25 common plus eight component-specific invalid cases each; literal layouts, options, monitor declarations and 720 callback permutations pass. |
| Component simulation | PASS, FIFO depths 2/4 and pools on all six profiles; independent CSR/statistics on all six with 64-bit and reduced 8-bit counters. No integrated TM claim. |
| Frontends / heterogeneous behavior | PASS, 148 cases; current registered production plus separately identified historical candidates, six profiles, invalids and two concurrent distinct instances. |
| Production formal | PASS, E0 cell/descriptor/FIFO2/FIFO4/CSR unbounded proofs and all covers; intended population and AW/W-coupling mutations detected with named assertions/traces. No ownership-composition proof. |
| Alternate FIFO record storage | PASS, unchanged full-beat depth-2/depth-4 proofs/covers and matched actual inference/mapping. |
| Formal bridge | PASS, 49 local cases; native-baseline/current inventories, labels and property locations match; complete assumption predicates prove inclusion both ways, with startup and later-reset freedom retained. |
| Sequential equivalence / inference | PASS, 42 cases across six profiles, both FIFO depths and full/reduced statistics widths; all ports and state/memory signatures checked. Supplementary matching-state equivalence only. |
| P07 fixture | PASS, E0 seed 17/replay/19 and I0 seed 23/replay/25, small quantum, exact checker/barrier detections and I0 atomic-limit detector. Collection/replay qualification, not coverage closure. |
| Tool fixtures / repository | PASS, doctor, unit/lint rejection, genuine UVM/replay/held-data detection, counter proof/cover/mutation, synthesis/STA diagnostic rejection and DPI services. These remain fixtures. |
| FIFO mapping / timing | Mapping integrity PASS with identical measurements; reset-removal timing closure remains **FAIL**, −0.09 ns. |

The bridge preserves the following assertion/assumption/cover/named-property
counts respectively: cell **25/1/5/14**, descriptor **17/1/8/17**, FIFO2
**11/1/6/15**, FIFO4 **13/1/6/15**, CSR **17/7/7/24**. No assertion, assumption,
cover, startup initialization or arbitrary action stream was removed.

Each CSR counter-width run hits all **12 mandatory ordering/stall/read cross
bins** (19/19 functional bins overall), records 17 snapshots, two event
collisions, two clears and three resets with pending channels. The intended
negative identifies `CSR_AW_W_INDEPENDENCE`, with a saved trace.

| Profile | Reads / writes, each counter width | Eight-bit rollover events |
| --- | --- | ---: |
| F0/F1 | 1,195 / 1,184 | 21 |
| I0/I1 | 655 / 632 | 17 |
| E0 | 565 / 540 | 17 |
| E1 | 835 / 816 | 19 |

P07 E0 observes 52 captures/services, 11 commits, 10 deliveries and 2,324 batches;
I0 observes 121 captures/services, 15 commits, 14 deliveries and 2,576 batches.
Positive saved functional bins are **20/29** and **26/39** hit. Replay digests,
zero bins and all 12/13 intended detector identities are retained in the JSON;
partial fixture coverage is not production requirement closure.


## Integrated representation

ANSI conversion covers every published module; no `_api` name or scalar parameter
is changed. Fixed encodings/layouts are in `tm_fixed`; scoped dependent types use
non-overridable defaults before ports. The type include changes only declaration
separators between ANSI and monitor/formal scopes, avoiding mirror records and
cast bridges. Derived record widths use `$bits(type)`. The common scalar override
and validation contract remains intact. The FIFO drops all unrelated type
requirements and keeps its whole-beat vector boundary. Packed queue/port lanes
and the generic bitmap return lanes remain useful APIs.

The five implemented API bodies are token-identical to baseline after comments
and whitespace are removed; the bitmap kernel, parameter definitions, validator,
profiles, formal property includes and harness expressions are unchanged. Literal
layout checks independently verify metadata, beat/status packing and every fixed
enum encoding. Parameter rejection now also covers the statistics counter guard
and bitmap capacity/index/count/return-lane guards.

Retained adaptations are justified by current evidence: `TM_ANSI_TYPES` handles
SystemVerilog declaration separators, and the bench exports fixed names according
to package visibility rules. Neither duplicates record definitions. The explicit
free-input formal adapter remains necessary because this Slang build does not
preserve native symbolic attributes. Immediate properties retain their qualified
monitor semantics. No-DPI UVM remains the exercised frontdoor configuration;
separate DPI services are checked independently. Native controls read the
immutable baseline through Git; current production always uses the selected
Slang registry. Source-relative whitespace remains an unqualified adapter limit.

## Inference and mapping

All baseline/current/record-array FIFO runs infer one 137-bit memory, depth 2/4,
one asynchronous head read and one clocked write. Both current representations
pass the unchanged full-beat proofs/covers. Vector storage remains because no
FIFO operation interprets fields; the old struct-array frontend failure is no
longer a design restriction.

| Depth | Payload bits | Mapped cells, all three representations | Area, library units | Clock max/min slack | Reset recovery/removal |
| --- | ---: | ---: | ---: | --- | --- |
| 2 | 274 | 710 | 2,053.520 | 7.87 / 0.04 ns | 8.99 / **−0.09 ns** |
| 4 | 548 | 1,543 | 4,343.248 | 7.47 / 0.04 ns | 8.99 / **−0.09 ns** |

Inference and mapping are separate reads of the same source. An exploratory
combined script ran extra `proc`/`memory_collect` passes before `synth`, changing
the depth-4 result to 1,545 cells / 4,342.184 for all three representations.
Resetting the design after inference and rereading before the unchanged mapping
recipe restores the historical result for all three. This isolates a flow-order
effect rather than an RTL representation difference; the final comparison checks
identical cell histograms, area and memory-port signatures.

Constraints are unchanged: typical Nangate45 1.10 V / 25 °C, ns/fF, ideal 10 ns
clock, 0.05 ns uncertainty, 0.2/1 ns min/max IO delays including reset, 0.05 ns
input slew and 10 fF loads. No timing exception hides reset. Mapping integrity
passes; **timing closure remains FAIL** because of reset removal. This is neither
allocator characterization nor physical signoff.

Generic inference matches baseline for all 42 implemented-module/profile cases,
with no latches. FIFO payload memory is separate from the following generic
state-bit counts; these are pre-mapping signatures, not physical area estimates.

| Profiles | FIFO control, depth 2 / 4 | Cell pool | Descriptor pool | CSR | Statistics, counter 64 / 8 |
| --- | ---: | ---: | ---: | ---: | ---: |
| F0/F1 | 5 / 8 | 1,036 | 266 | 528 | 11,872 / 6,832 |
| I0/I1 | 5 / 8 | 39 | 22 | 220 | 3,888 / 2,208 |
| E0 | 5 / 8 | 22 | 13 | 180 | 2,580 / 1,460 |
| E1 | 5 / 8 | 72 | 39 | 304 | 6,512 / 3,712 |

Equivalence uses all ports, corresponding state and the complete payload, with
bounded forward structural matching, direct SAT and temporal induction for any
remaining points. It requires matching state correspondence; it does not prove
that independently arbitrary unreset memories begin equal. Independent FIFO
order/reset and CSR protocol/statistics contracts remain necessary. Neither
induction correspondence nor a passing miter establishes the specification.

## Reproduction

Use the checked-out locks, `make setup JOBS=2` when installation is needed, then
activate and run doctor. The immutable baseline object must be present; CI checks
out full history for comparison jobs. Do not substitute the historical external
installation for the repository selection.

```sh
export CXX=g++-14
source .tools/activate.sh
make doctor
make repo-check
make test-unit
make frontends
make bridge RUN_ARGS='--timeout 900'
make formal-rtl RUN_ARGS='--timeout 900'
make representation-formal RUN_ARGS='--timeout 900'
make fifo-mapping
make ci RUN_ARGS='--test repo --test unit --test lint --test uvm --test formal --test synth --test uvm-dpi'
for profile in F0 F1 I0 I1 E0 E1; do
  make regression RUN_ARGS="--profile $profile --test contracts --test pools --seed 17"
  make regression RUN_ARGS="--profile $profile --test csr --seed 17"
done
make regression RUN_ARGS='--profile E0 --test uvm-foundation --seed 17'
make regression RUN_ARGS='--profile I0 --test uvm-foundation --seed 23'
```

Raw manifests under `.build/runs/` contain exact argv, separate stdout/stderr,
configuration/source hashes, property identities, traces and coverage databases.
Hosted result artifacts retain these for 14 days; the toolchain transfer has its
separate cleanup/one-day fallback. Reproduce expired artifacts from the tested
revision, its locks, baseline Git object and the commands above. Historical
P01/P02/P06/P07/toolchain reports and their JSON have not been rewritten.

## Remaining boundaries

Production top and nine other APIs remain declarations. P03+, allocator scaling,
scheduler optimization, integrated traffic/ownership composition and coverage
closure remain outside this migration. Existing reduced formal dimensions,
clock-boundary asynchronous-reset modeling and two-state simulation boundaries
are unchanged. Unreset invalid payload equality is not an initialization claim.
Native richer-type parsing and source-relative whitespace are not qualified
production routes. The known reset-removal violation remains visible; there is
no physical, multi-corner, routed-parasitic or signoff claim.
