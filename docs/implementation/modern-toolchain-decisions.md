# Toolchain capability and task disposition

This table assigns the representation follow-up's decisions to executable
qualification, rather than treating old frontend observations as language rules.
The executed results and exact identities are recorded in the
[qualification report](../results/modern-toolchain.md). Production RTL conversion
remains a separate PR; retain explicit open cases below.

## Capability to design

| Location / old choice | Original reason | Tested alternative / benefit and tradeoff | Disposition |
| --- | --- | --- | --- |
| `rtl/include/tm_module_ports.sv`, `rtl/common/tm_axis_rx_fifo.sv`, `rtl/csr/*.sv`: non-ANSI declarations | Module-local typedef visibility in old frontend | Production-derived ANSI vectors, fixed package ports and parameter type defaults; declarations become easier to read; width/type maintenance must still be checked | Remove obsolete header workaround in representation follow-up; all phases and production-derived behavior passed |
| `rtl/include/tm_types.svh`: repeated fixed enums/records | Old wildcard-import parsing limitation | Fixed package import and explicit qualification tested separately; one definition can serve all consumers | Remove fixed-type duplication in follow-up where useful; imports/qualified names passed; no parameterized packages |
| `rtl/include/tm_types.svh`, generator width formulas | Old `$bits(type)` rejection and parameter-dependent widths | Named localparams, `$bits(type)`, parameter-dependent records/type parameters and heterogeneous instances; reduce duplicated formulas without hiding guarded widths | Use tested type-parameter or named-width recipe in follow-up; six profiles and 25 invalid cases each passed; preserve guarded widths |
| `rtl/common/tm_axis_rx_fifo.sv`: vector memory | Old frontend misread arrays of packed structs | Independent typed-memory inference and read-latency model plus unchanged production FIFO formal; use typed storage only if useful and correctly inferred | Typed storage is accepted for follow-up: independent memory proof/cover, actual FIFO proof/cover and full-payload mapping passed; vectors remain valid for bitwise-only code |
| `docs/spec/module-contracts.md`: packed lanes | Portable old frontend and defined lane order | Unpacked ports/arrays and interfaces/modports get bounded capability tests | Capability passed parse/elaboration/synthesis and heterogeneous simulation; retain packed published ABI unless follow-up justifies improvement |
| `formal/pools/storage_formal.sv`, `formal/csr/csr_formal.sv`: anyseq internals | Native frontend symbolic-source convention | Explicit free input ports; source adapter preserves assumption/property expressions; mutual inclusion proofs compare complete assumption predicates | Retain strict free-input adapter: exact-stack inventory and mutual inclusion passed on all five configurations; native diagnostic remains |
| `formal/pools/*properties.svh`, `formal/csr/csr_properties.svh` | Immediate assertions/monitor state portable to old frontend | Check initialization, `$past`, async conversion, exact property inventory/labels, covers and seeded failures before adopting richer property syntax | Retain independent monitor semantics; no automatic SVA rewrite |
| `tools/run.py`, `tools/formal_*.py`: old diagnostic matching | Old output format | New formats must detect the same intended assertion/property with a trace; generic nonzero exit is insufficient | Retain named-property/trace requirements: production FIFO/pool/CSR seeded violations were detected; no generic failure acceptance |
| `tools/run.py`, `tools/foundation.py`, `tools/csr.py`: `UVM_NO_DPI` | Qualified frontdoor fixture baseline | UVM 2020.3.2 plus actual agents/sequences/analysis/scoreboards/frontdoor and an explicit DPI regex/HDL probe | Retain no-DPI frontdoor baseline where sufficient; reassess service-specific prohibition from actual DPI result |
| `tools/run.py`, `tools/foundation.py`, `tools/csr.py`: coverage database parsers | Exact saved counter/bin accounting | Current simulator/library databases, replay and required bins; profile/instrumentation separation | Retain required counts and rejection of missing/empty data; never substitute percentages |
| `tools/run.py`: mapping script | Earlier synthesis/ABC defaults | `synth -noabc`, explicit flop/library mapping, then Liberty ABC; require real mapped combinational/sequential cells, no internal unmapped cells | Adopt explicit script: P00 and both actual FIFO representations mapped with library cells/check-assert; no latches in generic candidates |
| `tests/toolchain/timing.sdc`, `timing.tcl` | Tiny pre-layout capability conditions | Fixed Nangate45 units are ns/fF, 1.10 V / 25 C. Explicit 10 fF load, 0.05 ns uncertainty, IO delays/slew and separate driving-cell case; compare old control under these same inputs | Correct active unit clarity; old measurements stay historical |
| `tools/run.py`: timing error parser | Older OpenSTA unnumbered diagnostics | Numbered/unnumbered errors and warnings override completion; actual bad-library/netlist/constraint/unconstrained/error-plus-marker cases | Retain stricter rejection after qualification; never accept completion alone |
| OpenSTA multi-scene/variation/noise features | Old packaged STA lacked modern analysis APIs | Current source capabilities reviewed against available data: only one typical Liberty and no routed parasitics/variation/noise models | Retain single-corner pre-layout boundary; no new measured physical claims |
| `tools/doctor.py`: GCC 14.2.0 patch check | Original observed compiler mistaken for universal requirement | Compile/execute C++20 concepts and std::format; record actual compiler/target/runtime in cache identity | Remove patch-specific rejection; preserve actual ABI/language qualification |
| `tools/packages.lock.json`: old distro bundle | Packaged Yosys/ABC/STA/solver carried unused dev dependencies | Source-built selected tools, exact transitive archives; Click runtime explicitly installed; Boost Python/filesystem/system, ffi, readline, old tool binaries removed | Remove unused packages; retain only exercised build/Tcl/zlib dependencies |

## Task and guidance audit

| Card / guidance | Change | Reason / preserved obligation |
| --- | --- | --- |
| P00 | Explicit refresh follow-up and precommitted inventory/criteria | Authorized upgrades requalify the combination; historical G0 fixture result remains accurate |
| P00 refresh | New focused card | Cold/restore/error/hosted acceptance and actual production frontend bridge |
| P01 | Representation follow-up owns conversion | Existing API ownership, six profiles and invalid elaboration checks remain mandatory |
| P01 representation | New focused card before allocator study | Consume executable accepted recipe; no algorithm or published behavior change |
| P02 | Follow-up ordering updated | Existing storage correctness evidence preserved; characterize the converted actual production source |
| P02 scaling | Depends on P01 representation | Precommitted capacity/constraint matrix and real consumer-path recheck remain |
| P03 | Unchanged, paused | Linked-list collision/pre-state ownership/order obligations are independent of richer syntax |
| P04 | Unchanged, paused | DRR visit/credit/freeze policy and packet-RR comparison are unchanged |
| P05 | Unchanged, paused | Finite ports, one/two-cycle responses, credits/retirement and real banked comparison remain |
| P06 | Unchanged hardware card | Frontdoor, atomic rejected writes and coherent pre-event snapshots requalified; no event-wiring claim |
| P07 | Service restriction clarified by capability table | Actual agents/models/negative detection/coverage still required; no-DPI frontdoor is a chosen tested configuration |
| P07 stimulus | Unchanged prerequisite before P08 | Readability first, constrained legal packets plus explicit malformed controls, replay and independent policy checking |
| P08 | Both P02 and P07 follow-ups retained | Representation precedes scaling transitively; actual allocator receive/admission consumer path still measured |
| P09 | Unchanged | Real vertical integration and early 64/1536-byte packet-rate accounting remain |
| P10 | Unchanged | Concurrent profile/seed checks and pre-P11 baseline/optimization decision remain |
| P11A | Unchanged | Unbounded production resource/ownership/FIFO order and caller-assumption closure remain |
| P11B | Unchanged | TX/DRR/AXI safety and separately scoped fair progress remain |
| P11C | Unchanged | Actual compatible coverage databases and reviewed exclusions; P09/P10 measurements before closure |
| P12 | Unchanged | Equal-capacity physical variants and full benchmark/mapped timing study remain; no fixture substitution |
| P13 / P14 | Unchanged | Checked diagnostic integration and exact final integrated-source release audit remain |
| Root and nested AGENTS | No obsolete pin-specific prohibition found | Preserve independence, scoped lint waivers, exact evidence and production formal targets |
| Toolchain / formal / implementation / module contracts / automation specs | Update operational frontend/ABI/bridge guidance after qualification | Behavioral contracts and verification strength remain authoritative |
| Status / plan | Add refresh and representation ordering | P03+ pause and all later integration boundaries remain explicit |
| Decisions 0001–0005 | Preserve records; add supersession links for tool/representation observations | Historical reasons remain facts; new evidence has its own identity |

No downloadable launch pack is changed. Capability acceptance alone does not
justify adding interfaces, abstractions or algorithms to the traffic manager.
