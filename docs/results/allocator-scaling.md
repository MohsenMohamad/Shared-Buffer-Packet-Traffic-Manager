# Production allocator scaling

**Investigate alternatives under the original criteria.** The actual 1024-cell
allocator has a 23.93948 ns bitmap-to-ID selection arrival and −16.03948 ns
worst max slack under the exploratory 10 ns conditions. I0 data timing has
positive slack, but its constrained asynchronous reset removal misses the local
analysis target. No allocator or production API is changed. P03 remains paused;
P08 still owns measurement through the actual receive/admission consumer.

All eight mapped points and sixteen STA analyses have **valid measurement
evidence**, separately from timing closure, which is **FAIL** at every point
because of reset removal (and F0 cell selection/setup). These are single-corner,
ideal-clock, pre-layout results, without wire parasitics or a consumer timing
bound. F0 screening establishes no new F0 acceptance requirement.

## Definition and tested sources

The [experiment definition](../../experiments/allocator-scaling/README.md),
constraints, matrix, mapping script and numeric decision rules were committed
and pushed first at `2beb248978ceb5d26a509f91aa13f0811bbe46f9`.
The accepted measurements target clean
`5d977514412e2af902c3e48faec827af859cf03f`, following the separately pushed
startpoint-query correction. There were **no criteria amendments**. Both commits
descend from fetched `origin/main` `410a174`.

The first run was rejected: OpenSTA warning 1554 identified Q/QN outputs as
invalid `group_path -from` objects, leaving selection empty. The correction uses
register clock pins and enumerates internal names before JSON/Verilog emission,
so fanout and timing identify the same cells. It changes neither thresholds,
IO constraints, exceptions nor logic. Original failed evidence is retained and
excluded from accepted timing numbers. All eight original/corrected maps have
identical area, cell histograms, state and buffer counts, independently checked.

[The durable JSON](allocator-scaling.json) records exact source/lock/definition/
library digests, tool identities, per-point measurements, mapped-to-RTL state
aliases, original/rejected run identities, actual tested revisions/dirty flags,
commands and artifact hashes. Production RTL, formal properties, benches and
historical reports/JSON are unchanged. A later documentation or CI commit is not
the local tested SHA.

## Matched conditions and included logic

Every point reads the registered production synthesis sources using qualified
Yosys 0.70+post/Slang, then selects the real cell or descriptor wrapper and its
bitmap kernel. The pinned bundled ABC maps sequential/combinational logic to
Nangate45 typical, 1.10 V / 25 °C, with BUF_X1 drive and 10 fF load. OpenSTA
3.2.0 passes the runtime source-identity check. Exact commits and Liberty
SHA256 are in the definition and durable JSON.

The [mapping template](../../experiments/allocator-scaling/mapping.ys.in) uses
flat `synth -noabc`, `dffunmap`, `dfflibmap`, constrained Liberty ABC and
`check -assert`, without an ABC delay-target override or inference prepasses.
All four output buses/signals stay live. All action inputs are independent;
there is no selected-ID loopback, tied-off return, assumed-valid action or
encoder surrogate. State matches **capacity + count width + sticky error** at
every point; no internal unmapped cells or latches remain.

Area includes bitmap/count/error flops, selection, allocation validation,
return lookup/validation, descriptor duplicate handling, merged updates and
buffers. It excludes payload, FIFO, metadata/link/info arrays, reservation
accounting, observation logic and consumers outside these wrappers. Cell area
uses the library's µm² convention; it is not placement/core area.

The [SDC](../../experiments/allocator-scaling/timing.sdc) fixes an ideal 10 ns
clock, 0.10 ns uncertainty, min/max IO delays 0.2/2 ns including reset, and 10 fF
on **each output bit**. Primary `slew` mode uses 0.05 ns nonclock input slew;
`drive` sensitivity uses library BUF_X1/Z. Both use the identical mapped netlist.
There are no false/multicycle paths, reset exceptions, wire parasitics or CTS.

## Area and selection measurements

Selection arrival includes launching flop clock-to-Q and all mapped logic to
`available_id`, in ns. It is not just combinational delay or integrated Fmax.
The selection numbers below are identical in both input-drive modes because
these paths launch from bitmap flops. Stages count combinational mapped cells,
excluding launching-flop CK/Q report rows.

| Profile / pool | Entries | Area, µm² | Cells / flops / buffers | Selection arrival / slack, ns | Stages |
| --- | ---: | ---: | --- | --- | ---: |
| E0 cell | 16 | 344.470 | 211 / 22 / 10 | 0.41331 / 7.48669 | 5 |
| I0 cell | 32 | 617.652 | 384 / 39 / 14 | 0.81659 / 7.08341 | 10 |
| E1 cell | 64 | 1,090.068 | 671 / 72 / 22 | 1.47682 / 6.42318 | 19 |
| F0 cell | 1024 | 20,109.334 | 11,399 / 1,036 / 600 | **23.93948 / −16.03948** | 306 |
| E0 descriptor | 8 | 284.886 | 178 / 13 / 15 | 0.25710 / 7.64290 | 3 |
| I0 descriptor | 16 | 440.496 | 306 / 22 / 24 | 0.47333 / 7.42667 | 7 |
| E1 descriptor | 32 | 740.278 | 502 / 39 / 32 | 0.70012 / 7.19988 | 10 |
| F0 descriptor | 256 | 5,128.746 | 3,750 / 266 / 274 | 5.34754 / 2.55246 | 77 |

These are actual mapped startpoints and endpoints. `pool.free_bitmap` aliases
identify the launching state behind each flop; `/Q` launches all listed paths.

| Profile / pool | Selection startpoint (RTL bit) | Selection endpoint |
| --- | --- | --- |
| E0 cell | `_402_/Q` (`free_bitmap[7]`) | `available_id[0]` |
| I0 cell | `_746_/Q` (`free_bitmap[7]`) | `available_id[3]` |
| E1 cell | `_1318_/Q` (`free_bitmap[7]`) | `available_id[5]` |
| F0 cell | `_22766_/Q` (`free_bitmap[7]`) | `available_id[8]` |
| E0 descriptor | `_339_/Q` (`free_bitmap[6]`) | `available_id[2]` |
| I0 descriptor | `_590_/Q` (`free_bitmap[9]`) | `available_id[3]` |
| E1 descriptor | `_982_/Q` (`free_bitmap[7]`) | `available_id[4]` |
| F0 descriptor | `_7468_/Q` (`free_bitmap[11]`) | `available_id[7]` |

## Overall timing and admission-facing outputs

“Worst” here means smallest constrained slack across **all** path groups,
including asynchronous recovery/removal. Primary max paths are `rst_n → available`
for E0/I0/E1 and the selection paths above for F0. Min paths are `rst_n →` the
listed flop's reset pin (removal against rising `clk`); they are not data hold
violations. The JSON retains every group's max/min endpoints, arrival and slack,
including register-to-register setup/hold and recovery/removal separately.

| Profile / pool | Worst max arrival / slack, ns (`slew`) | Removal endpoint | Worst min slack, ns (`slew` / `drive`) | Worst max slack, ns (`drive`) |
| --- | --- | --- | --- | ---: |
| E0 cell | 2.12286 / 5.77714 | `_392_/RN`, `free_count[2]` | −0.14368 / −0.09905 | 5.68682 |
| I0 cell | 2.19931 / 5.70069 | `_719_/RN`, `free_count[3]` | **−0.14368 / −0.10898** | 5.55913 |
| E1 cell | 2.13161 / 5.76839 | `_1258_/RN`, `free_count[4]` | −0.14368 / −0.13077 | 5.49141 |
| F0 cell | 23.93948 / −16.03948 | `_21742_/RN`, `free_count[8]` | −0.14368 / −0.72827 | −16.03948 |
| E0 descriptor | 2.12180 / 5.77820 | `_337_/RN`, `free_count[1]` | −0.14368 / −0.09254 | 5.72830 |
| I0 descriptor | 2.13202 / 5.76798 | `_582_/RN`, `free_count[2]` | **−0.14368 / −0.09828** | 5.68497 |
| E1 descriptor | 2.10200 / 5.79800 | `_955_/RN`, `free_count[3]` | −0.14368 / −0.10898 | 5.65584 |
| F0 descriptor | 5.34754 / 2.55246 | `_7218_/RN`, `free_count[6]` | −0.14368 / −0.24992 | 2.55246 |

At F0 cell capacity, `available` is also slow: `_22766_/Q → available` arrives
at **23.91619 ns**, slack **−16.01619 ns**. Allocation/count update feedback from
that bitmap flop to `_22775_/D` arrives at **24.35943 ns**, setup slack
**−14.49976 ns**. This separates worst slack from longest arrival: the output
has the smaller required time. `free_count` remains a short registered output
(0.13196 ns max arrival). Descriptor F0 `available` arrives at 5.31446 ns;
its internal worst register path arrives at 5.90283 ns, slack 3.95489 ns.

## Coverage, fanout and harness review

All accepted analyses pass `check_setup -verbose`: no missing input/output
delays, unclocked registers, loops, generated-clock errors or unconstrained
endpoints. Every live output bit has both min and max paths. Constrained flop
and output-bit counts match mapped state/ports; errors/warnings or empty reports
cannot pass the parser. Named path groups retain selection, availability, count,
ordinary clocked checks and asynchronous checks. The rejected first attempt and
four evidence-rejection unit tests demonstrate that completion is insufficient.

Direct sink-pin fanout peaks at **10** for data nets at every point after ABC
buffering, passing the 64-pin screen. Clock sinks equal the flop counts in the
area table; clocks are ideal. Reset sink counts for E0/I0/E1/F0 are
**24/40/75/1,038** (cell) and **14/23/40/267** (descriptor), including propagated
buffer/inverter reset nets in the review. Both F0 reset roots miss the 256-pin
screen. The F0 cell's 600 buffers do not remove the serial priority dependency.

The primary ideal-slew reset model is optimistic about driving this reset load.
With BUF_X1, F0 cell reset sees **1,414.35461 fF**, slew **3.23030 ns** against
0.19853 ns, and capacitance slack **−1,353.70093 fF**. Descriptor F0 reset sees
365.44641 fF / 0.83672 ns; E1 cell reset also violates slew/capacitance in drive
mode. Primary F0 internal capacitance violations remain visible too:
`_12990_/ZN` (cell) and `_5629_/ZN` (descriptor), slack −3.06964/−1.84047 fF.
These diagnostics are recorded measurements, not hidden constraint errors or
physical closure. No library extrapolation at an overloaded reset is a silicon
prediction.

Unused API payload fields disappear naturally: F0 cell uses 11/19 allocation
bits and 11/24 return bits; descriptor uses 10/67 admission bits and all nine
bits of each return. Those live bits are precisely the valid/accept and relevant
ID fields. No input ID is substituted by selected ID. Outputs have one specified
external load per bit, while real consumers may add fanout and logic. There is
no claim that the isolated available ID/count/availability loads model admission.

## Criteria applied and follow-up evaluation

| Original criterion | Result | Disposition |
| --- | --- | --- |
| Mapping / coverage integrity | PASS: 8 maps, 16 timing analyses | Valid standalone evidence, not timing closure. |
| I0 setup/hold/recovery/removal >= 0 ns in both modes | **MISS**: removal negative in both pools/modes | Investigate reset release/drive constraints and implementation with the actual integration reset contract; preserve the violation. |
| F0 selection <= 6 ns in both modes | **MISS**: cell 23.93948 ns; descriptor 5.34754 ns passes | Investigate selection alternatives; this is an exploratory screen, not F0 acceptance. |
| Area/entry <= 2× same pool at I0 | PASS at all points | F0 ratios 1.017428 cell / 0.727695 descriptor; no area-driven replacement finding. |
| Data <= 64 / reset <= 256 sink pins | Data PASS; F0 reset **MISS** in both pools | Evaluate reset buffering/physical distribution; low data fanout does not establish short logic depth. |

The evidence diagnoses a long mapped priority dependency: cell selection grows
from 5 to 10 to 19 to 306 combinational stages as entries grow 16/32/64/1024.
The worst F0 path launches from bitmap bit 7 and crosses predominantly cascaded
four-input NOR/NAND/AND/OR cells. This is the source loop's accumulating `found`
dependency after this exact mapping, not proof that every bitmap selection must
have this delay. Registered count output timing does not bound `available`,
which is driven by the selector's `found` result.

A separate reviewed evaluation should first compare equivalent combinational
lowest-ID selection expressions/mapping strategies at the same capacities and
constraints, preserving all existing tests/proofs. Hierarchical or banked
selection is a candidate to measure, not the conclusion. A free list would need
to preserve lowest-ID behavior or explicitly review a contract change; a
pipeline would change the current combinational availability/action timing and
needs latency/throughput/API review. This PR implements none of these options.
Reset distribution/drive and recovery/removal need their own focused evaluation;
changing allocator structure alone does not establish reset closure.

There is no implemented production receive/admission consumer to characterize,
so no speculative consumer harness is added. P08 must recheck the **actual**
consumer at I0 and **1024 cells**, including admission predicate, resource
accounting, metadata/action fanout and allocation feedback under identified
constraints. Standalone measurements are **not a guaranteed timing bound** on
that integrated path. No post-layout, multi-corner, full-TM or power result follows.

## Functional checks and reproduction

| Check executed locally | Result / scope |
| --- | --- |
| Qualified doctor | PASS, including strict source identity, C++20 and solver probes. |
| I0/F0 `pools`, seed 17, depths 2/4 | PASS: four independent storage/ownership executions at clean `2beb248`; bench deliberately widens ID encodings to exercise invalid requests. |
| Production cell/descriptor formal at clean `5d97751` | PASS: unbounded proofs at 16 cells/8 descriptors; 5/8 covers reached; both wrong-delta mutations detected at `a_population` with saved traces. |
| Runner unit tests | PASS: 44 tests, including four new measurement-integrity rejection cases; dirty `5d97751` with only later tooling/CI metadata edits. |
| Repository contracts | PASS; document validation only. |

Proof assumptions remain reset low on the first two sampled edges, then arbitrary
reset/action inputs, with clock-boundary `async2sync` modeling. These local proofs
do not establish RX/queue/TX ownership composition, 1024-cell formal closure or
analog reset behavior. RTL and verification sources are unchanged from main.

```sh
export CXX=g++-14
source .tools/activate.sh
make allocator-scaling RUN_ARGS='--timeout 1800'
make regression RUN_ARGS='--profile I0 --test pools --seed 17'
make regression RUN_ARGS='--profile F0 --test pools --seed 17'
make formal-rtl RUN_ARGS='--test cell --test descriptor --timeout 900'
make test-unit
make repo-check
```

Use `make setup JOBS=2` only when preparing a missing installation, followed by
`make doctor`. Check out the exact tested SHA to reproduce local records; later
metadata edits do not relabel it. Generated scripts, mapped JSON/netlists,
separate stdout/stderr, proof configurations/traces and manifests are under
`.build/runs/`. The durable JSON names the original directories and hashes.
CI registers `allocator-scaling` beside existing shared-install consumers and
retains raw artifacts for 14 days under `toolchain-allocator-scaling-<tested SHA>`.
A measurement job PASS means execution/integrity PASS, not timing closure.

Compare new points only within the same mapping/library/drive-mode/IO conditions;
normalize area by entries and distinguish one versus two return lanes. Historical
P02 had no matched mapped allocator timing; historical FIFO timing used different
IO/uncertainty conditions and different logic. Neither is a numeric comparator.
Original reports and JSON remain unchanged. Regenerate expired raw artifacts
using the recorded SHA, locks, definition and commands above.

## Hosted execution reference

[PR #9](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/9)
has a passing [CI run](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43217405597)
(all 21 jobs, including handoff cleanup) and a passing [allocator characterization job](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43217405597/job/131180482259).
Its actual tested merge is `56d75b44e07e2e7f9cc429c73de5024cbcfd95e3`, with PR
head `2dda7603a60755ca3c4d359548ccfb3d7cd7e1b5`. The fetched merge object has
identical RTL, verification sources, experiment scripts/constraints, frontend and
locks to the local measured revision; the runner only adds scope metadata.
This does not replace the local tested SHA or imply execution on later metadata.

Artifact `13944132446` is **digest-verified and cross-compared: PASS**. The
GitHub connector download and independently supplied ZIP are byte-for-byte
identical, 1,805,959 bytes, and match GitHub's SHA256
`0e781af3dc9c381caad3d8435310c6da5c393156e518103c52e7dfdfc18aae91`;
ZIP CRC checks pass. Workspace HTTP clients encounter proxy CONNECT 403 at the
redirected storage host; the GitHub connector successfully retrieves the archive
and provides an available download route.

All 32 archived case statuses pass. All **eight mapping** and **sixteen timing**
measurement sets match the local records **exactly**, including area, cells,
state, buffers, ports, fanout, path endpoints/arrival/slack, electrical checks,
definition/library digests and netlist digests. Raw mapped JSON/statistics and
netlists independently reproduce their recorded measurements/digests; raw STA
stdout/stderr reparses with the strict local checker. Every allocator case names
the same clean hosted merge SHA. The JSON records the verified archive and
summary hashes, comparison scope and counts. No numbers, criteria or conclusions
changed: successful measurement reproduction does not establish timing closure.

To repeat the archive-to-local comparison, save the ZIP as
`.build/allocator-hosted/allocator.zip` and retain the original local run below
(or substitute the regenerated run directory). This reads archived data without
executing archived scripts:

```sh
python3 - <<'PYCODE'
import hashlib, json, sys, zipfile
from pathlib import Path
sys.path.insert(0, 'tools')
from allocator_scaling import timing_measurements
artifact = Path('.build/allocator-hosted/allocator.zip')
local = Path('.build/runs/allocator-scaling-2026-11-12T121457.361321+0000-1dda634d')
assert hashlib.sha256(artifact.read_bytes()).hexdigest() == '0e781af3dc9c381caad3d8435310c6da5c393156e518103c52e7dfdfc18aae91'
compared = 0
with zipfile.ZipFile(artifact) as archive:
    assert archive.testzip() is None
    for name in archive.namelist():
        if '/allocator-' not in name or not name.endswith('/manifest.json'):
            continue
        hosted = json.loads(archive.read(name))
        original = json.loads((local / Path(name).parent.name / 'manifest.json').read_text())
        assert hosted['source_revision'] == '56d75b44e07e2e7f9cc429c73de5024cbcfd95e3' and not hosted['dirty']
        for field in ('measurements', 'definition_digests', 'liberty_sha256', 'netlist_sha256'):
            assert hosted.get(field) == original.get(field), (name, field)
        parent = str(Path(name).parent)
        if Path(parent).name.startswith('allocator-sta-'):
            raw = archive.read(parent + '/sta.stdout') + archive.read(parent + '/sta.stderr')
            assert timing_measurements(raw.decode()) == hosted['measurements']
        else:
            assert hashlib.sha256(archive.read(parent + '/mapped.v')).hexdigest() == hosted['netlist_sha256']
        compared += 1
assert compared == 24
print('PASS: eight mappings and sixteen STA measurement sets match exactly')
PYCODE
```
