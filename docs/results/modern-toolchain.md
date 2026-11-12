# Modern toolchain qualification

The selected source stack passes toolchain qualification and applicable merged
component/fixture checks. `read_slang` is selected in the real synthesis/formal
runners. Richer production-derived representations pass elaboration, behavior,
formal and mapping checks in disposable copies. Production RTL conversion remains
the next PR; these results establish neither integrated TM behavior nor physical
signoff.

The FIFO comparison retains a **−0.09 ns asynchronous reset-removal violation**
under the stated reset constraints. Successful STA execution is recorded separately
from timing closure. Four-state simulation and Slang's native-style symbolic
attributes/functions remain unsupported.

## Sources and evidence

Starting `origin/main` was `66f6d0d730238709e2a11faab221f24dc5a81ee9`.
Inventory/failure criteria were committed first at `e09e28a`.
[PR #7](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/7)
contains this refresh; integration remains with the maintainer. Historical
P00/P01/P02/P06/P07 reports and production `rtl/`, `formal/` and `dv/` are unchanged.

[The durable JSON](modern-toolchain.json) records actual tested SHAs/dirty flags,
commands, profiles/seeds, dependency/constraint hashes, source fingerprints, tool
identities, configurations, outcomes, negative identities, coverage/replay data,
property inventories and timing measurements. Apply each run's source overrides
to its baseline catalog to reconstruct behavioral file hashes; null means a file
was absent. Configuration references deduplicate identical dictionaries. Bulky
logs, generated sources, databases, netlists and traces remain build/CI artifacts.

Local P01/P02/UVM/production-formal cases record dirty base `22563dc`; the final
bridge records dirty base `6e694a5`; later cases retain their own recorded bases.
They are not relabeled as execution on a later documentation commit. Earlier
component runs precede the OpenSTA metadata fix and do not establish its runtime
source identity. The coherent cold build and complete hosted rerun at clean head
`6e694a5439272fb49183697b41178ac077530f6e` include the strict source check.
Current synthesis/FIFO timing cases also pass that check. Final-head CI is linked
in the PR checks and description.

The supplied audit at
[`a48286d`](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/tree/a48286d51b9dd195b18388e9ee3c70c8403ccc0b/tests/investigations/rtl-frontend-probes)
is supplemented by independent memory, signed-width, heterogeneous, interface,
symbolic-input, assumption-inclusion, timing-error and DPI cases. The old-control
rerun preserves original source/input hashes. Its unchanged `named_widths`
fixture passes unbounded proof/cover and detects its intended mutation; ten old
synthesis outcomes match, five accepted and five rejected.

## Selected installation

| Component | Selected identity |
| --- | --- |
| Yosys | 0.70+post, `28ba3cb926fe376fa05ebfc1b921747d011d4557` |
| Integrated frontend | sv-elab `9dcee13ea3862347e1715dc51f63e9f845cdd222`, slang `545f88b2ed3a2d20325fbd17413af177a6bca72f`; runtime revisions checked |
| ABC | Yosys gitlink `6c5104934c90eb3cdef9ea063318f7588908a185`; source-built, Liberty mapping exercised |
| Simulation/library | Verilator 5.054 `bbb60a403932a9f695cb6ff001ceb73de6ad9234`; unmodified official UVM 2020.3.2 distribution |
| Formal | SBY 0.71 `79fc9eddca5e33a28cc2f2cd19c9825efd9a7255`; Z3 5.4.1 build `145c0c51570a357cc558ce898ce77573ba9d4fbf` |
| Timing | Authoritative OpenSTA 3.2.0 `c7f04667369f1f7bfeb9eebb381fd8c63267bb21`; runtime `sta::git_sha1` checked |
| Build/runtime inputs | CMake 4.4.5, SWIG 4.5.1, CUDD 3.0.0, Eigen 5.0.1, Click 8.5.1; selected Tcl 8.6.16/zlib and reduced build-package set |
| Host | Linux x86-64, glibc ≥2.39; executed C++20 concepts/`std::format`; GCC 14.2.0 observed, exact compiler patch not required |

The [inventory](../implementation/modern-toolchain-plan.md) records reasons,
transitive gitlinks/download SHA256s and every old package's disposition. The
[dependency](../../tools/dependencies.json) and
[package](../../tools/packages.lock.json) locks define normal setup inputs.
The published Yosys release's integrated combination is selected; newer standalone
sv-elab/slang is not substituted without qualification. Upstream licenses remain
with the sources/installations.

Cold preparation in an empty local checkout passes in about 48 minutes with two
jobs. Repeat setup verifies archives and reuses the install. Sealed exact restore
passes current doctor without setup. Actual payload tests reject changed bytes,
modes, symlinks, deletion, incomplete installation and compiler/path/Python/libc
identity mismatches; restoration passes. Forty runner/cache tests additionally
cover recipe/flag/runtime invalidation, interrupted builds, current-validator
execution, transfer permissions and stale CMake objects. Cache generation is v3.
The old `/workspace/toolchain` installation is preserved.

## Frontend comparison

P/E/S means parsing, RTLIL elaboration and completed generic synthesis. Native
parsing is deferred AST parsing; Slang's AST-only phase also performs semantic
compilation. A parse success is not equivalent between them and does not establish
synthesis or correct behavior.

| Representation/case | Old native 0.52 | Current native 0.70 | Selected Slang |
| --- | --- | --- | --- |
| Baseline non-ANSI, ANSI vectors, explicit package scope, minimal/named widths | P/E/S accepted | P/E/S accepted | P/E/S accepted |
| Wildcard package import, inline parameter-dependent records, type parameters, `$bits(type)` | Rejected | Rejected | P/E/S accepted |
| Invalid typedef forward reference | Rejected before accepted elaboration | Rejected before accepted elaboration | Intended before-declaration diagnostic in all phases |
| Unpacked port/array example | Rejected | Rejected | P/E/S accepted |
| Interface/modport example | Deferred parse accepted; E/S rejected | Deferred parse accepted; E/S rejected | P/E/S accepted |
| Four-word packed-record memory | P/E/S complete, zero inferred memories; no semantic acceptance | P/E complete; structure check fails and independent formal counterexample | P/E/S accepted; correct inference, unbounded proof and covers |

Native diagnostic commands deliberately return nonzero; their `TOOL_ERROR`/`FAIL`
statuses remain in the JSON. Native forward-reference cases do not receive credit
for Slang's precise diagnostic: an earlier unsupported construct can block it.
The frozen old audit supplies its complete synthesis comparison; the separate
native replay adds parse/elaboration and independent minimized synthesis cases.

Both accepted recipes (`type_parameter`, `named_widths`) elaborate all six
profiles and reject 25 invalid variants each. Three production-derived forms
execute with two heterogeneous instances. The independent feature test checks
16 reads from two differently typed memories, one/two-cycle read latency,
nine-bit signed addition of eight-bit operands, unpacked lanes and a modport.
Inferred memories have widths 10/16, depth four, one read and one clocked write
port; before `memory_dff`, read registers are separate from asynchronous memory
read ports. Generic candidates contain no latches.

## Formal preservation and merged stages

| Executed check | Result and boundary |
| --- | --- |
| P00 fixtures | Genuine UVM, SAT/UNSAT randomization, saved coverage, replay, intended held-output SVA detection/waveform; unbounded counter proof, wrap cover and mutation |
| P01 | Six profiles/options/monitor declarations; 25 invalid variants rejected by both tools per profile; 720 callback permutations; E0 replay/alternate seed |
| P02 simulation | Six profiles, FIFO depths 2/4, independent actual FIFO/pool checks |
| Production formal | Cell capacity 16, descriptor capacity 8/two returns, FIFO depth 2/4/full 137-bit beats, reduced real CSR: unbounded proofs/all covers; wrong-credit and AW/W-coupling mutations detected |
| Formal bridge | Five configurations preserve counts, labels and property source lines; complete assumption predicates prove mutual inclusion both ways |
| Richer representation | Disposable type-parameter/record-memory FIFO depth 2/4 and CSR pass unchanged proof/cover; CSR mutation remains detected |
| P06 | E0/F0 seed 17 hosted, E0 seed 17 local; 64-bit counters and 8-bit rollover, all 12 mandatory AW/W/backpressure cross bins, coupled-channel detector |
| P07 fixture | E0 seeds 17/replay/19, I0 23/replay/25; agents/sequences/analysis/RAL/models/scoreboards, small quantum, nine checker defects, duplicate/missing/stale barriers and I0 atomic-limit detector |
| DPI services | Positive/negative regex and HDL path/read/deposit pass; unmodified UVM, target-only visibility |
| Four-state reproducer | **UNSUPPORTED**, executed; no X/Z propagation claim |

The bridge retains arbitrary streams, initialization, two-edge startup reset,
arbitrary later resets, `$past`, asynchronous reset conversion and every property/
assumption expression. CSR startup/past/control equalities are **proved**, not
assumed. Native symbolic attributes create symbolic cells; this Slang build lowers
them to X and rejects function forms. Its minimized attribute case fails the
intended `a_constant` assertion with a trace. Explicit arbitrary input ports are
the qualified bridge. The native record-memory counterexample and selected
frontend's complete-word proof prevent elaboration alone from qualifying memory.

| Configuration | Assertions | Assumptions | Covers | Preserved named properties |
| --- | ---: | ---: | ---: | ---: |
| Cell | 25 | 1 | 5 | 14 |
| Descriptor | 17 | 1 | 8 | 17 |
| FIFO depth 2 | 11 | 1 | 6 | 15 |
| FIFO depth 4 | 13 | 1 | 6 | 15 |
| CSR | 17 | 7 | 7 | 24 |

P00 seed 17/replay digest is `69a1b1d1`; seed 19 is `a72dedbf`, 64 transactions
each. Seed-17 saved coverage has 19 functional bins, 17 hit; queue/length/cross
groups each account for exactly 64 samples. P07 E0 has 52 captures/services,
11 commits, 10 deliveries, 2,324 batches; I0 has 121 captures/services, 15 commits,
14 deliveries, 2,576 batches. Saved functional bins are 20/29 and 26/39 hit.
These qualify collection/checkers, not coverage closure. Full replay/bin data
are in the JSON; cross-version random-stream equality is not required.

P06 E0 records 565 reads/540 writes, F0 1,195/1,184. Each has 17 snapshots,
two event collisions, two clears and three resets with pending channels.
Eight-bit configurations observe 17 and 21 rollover events respectively.

## Mapping and timing

Mapping uses `synth -noabc`, `dffunmap`, Liberty `dfflibmap`, Liberty ABC and
`check -assert`. P00 maps one `DFF_X1` and one `XOR2_X1`, area 6.118 library units.
Fixed Nangate45 typical Liberty SHA256 is
`8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1`:
1.10 V, 25 °C, ns/fF. Constraints: 10 ns ideal clock, 0.05 ns uncertainty,
min/max IO delays 0.2/1 ns, input slew 0.05 ns, load 10 fF; separate `BUF_X1`
driving-cell case passes. P00 max/min slack is 8.84/0.17 ns. Old STA 2.0.17 gives
the same numbers on identical new netlist/Liberty/SDC; only its unsupported
`report_units` command is omitted.

| Actual E0 FIFO, both representations | Payload bits | Cells | Area | Clock-group max/min slack | Reset recovery/removal slack |
| --- | ---: | ---: | ---: | --- | --- |
| Depth 2 | 274 | 710 | 2,053.520 | 7.87 / 0.04 ns | 8.99 / **−0.09 ns** |
| Depth 4 | 548 | 1,543 | 4,343.248 | 7.47 / 0.04 ns | 8.99 / **−0.09 ns** |

Every payload bit is mapped. The two representations have identical cell counts,
area and reported paths; this is not allocator characterization. Reset is
explicitly constrained with no false-path exception. The minimum asynchronous
path is `rst_n` to a `DFFR_X1` removal check, arrival 0.20 ns versus required
0.29 ns. `timing_closure` remains FAIL. Preserve this finding until reset timing
is justified in its implementation context.

Bad Liberty/netlist/SDC, unconstrained design and an error followed by completion
all trigger intended rejection. The last returns zero and prints completion;
numbered/unnumbered diagnostics still force failure. Unrelated crashes/nonzero
status do not qualify a negative. Runtime probes confirm `define_scene`,
`read_spef`, `set_timing_derate`, `annotate_noise_delays`, scalar POCV and quantile 3.
Source review confirms scenes replace deprecated `define_corners`; noise requires
retained SPEF coupling. With one typical library and no routed parasitics or
variation models, no MCMM/statistical/noise/physical-closure measurement is claimed.

## Hosted execution and reproduction

[Cold run 43104862084](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43104862084)
and [PR run 43104870563](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43104870563)
succeed at head `6e694a5`: one cold producer, all capability, contracts, storage,
E0/F0 CSR and P07 consumers, and cleanup. Cold preparation takes about 52 minutes.
[43153126525](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43153126525)
accepts exact warm cache without setup at checkout
`2f316490ceb681aa58b585fe69c22a888333fac9` (PR head `c5d7147`), before later push
cancellation; this establishes restore, not final-head suite acceptance.
The final candidate's required result is in the
[current PR checks](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/7/checks),
with the exact final run linked in the PR description.

Consumers receive the sealed installation and run integrity/current doctor;
they never build tools. Identity includes checkout path and ABI/compiler/recipe:
the install is not advertised as relocatable. Diagnostics retain 14 days; the
handoff is deleted after consumers, with a one-day fallback. Regenerate expired
artifacts using recorded fingerprints and commands:

```sh
make setup JOBS=2
make doctor
make ci JOBS=2
make uvm-dpi JOBS=2
for profile in F0 F1 I0 I1 E0 E1; do
  make regression RUN_ARGS="--profile $profile --test contracts --seed 17"
  make regression RUN_ARGS="--profile $profile --test pools --seed 17"
done
make formal-rtl RUN_ARGS='--timeout 900'
make regression RUN_ARGS='--profile E0 --test csr --seed 17'
make regression RUN_ARGS='--profile F0 --test csr --seed 17'
make regression RUN_ARGS='--profile E0 --test uvm-foundation --seed 17'
make regression RUN_ARGS='--profile I0 --test uvm-foundation --seed 23'
make frontends
make bridge
make representation-formal RUN_ARGS='--timeout 900'
make fifo-mapping
```

JSON records actual job/timeout options. In a separate empty checkout run
`python3 tools/toolchain_cache.py prepare --jobs 2`, repeat it, then run `validate`
for cold/restore checks. Never delete an installation while regressions use it.
Native diagnostics and four-state reproduction deliberately exit nonzero:

```sh
python3 tools/run.py frontends --frontend verilog
python3 tools/run.py four-state
python3 tests/frontends/compare_native.py --reference "$NATIVE_RUN" \
  --yosys "$OLD_YOSYS" --library-path "$OLD_RUNTIME" --output "$FRESH_CONTROL_RUN"
```

Set paths to a completed native run, the historical executable/runtime and a
fresh output directory. Replay adds parse/elaboration and minimized synthesis
without overwriting modern results. Frozen-audit old synthesis/formal commands
and input-preservation hashes are recorded separately in JSON.

The [decision table](../implementation/modern-toolchain-decisions.md) and
[P01 recipe](../implementation/tasks/P01-followup-representation.md) give executable
accepted alternatives. Whitespace in source paths remains unqualified. DPI
force/release/polling, additional concurrent formal SVA, physical timing closure
and integrated TM behavior are not established. P03+ stays paused; representation
precedes allocator characterization, and both P02/P07 follow-ups precede P08.
