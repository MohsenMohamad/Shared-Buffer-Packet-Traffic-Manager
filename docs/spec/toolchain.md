# Open-source toolchain

All required build and verification workflows use command-line open-source tools and execute on a Linux x86-64 cloud workspace. No hardware server, proprietary simulator, FPGA board, GPU, GUI or container daemon is required.

| Purpose | Tool and qualification |
|---|---|
| SV/UVM simulation and RTL lint | Verilator 5.054 qualified source baseline, pinned source; use timing, assertions and coverage explicitly |
| UVM library | Accellera UVM 2020.3.2 checksum-locked official distribution |
| Constrained randomization | Z3; qualify successful and unsatisfiable randomization and seed replay |
| Functional formal | SymbiYosys + Yosys + Z3, mutually qualified pinned versions |
| Standard-cell mapping | Yosys + ABC, explicit Liberty library and mapping constraints |
| Static timing | OpenSTA, Liberty/netlist/SDC inputs, max/min reports |
| Orchestration | Python 3.11+, Bash, Make; C++20-capable compiler for generated simulation code |

`tools/dependencies.json` records exact source/archive pins. The [toolchain qualification report](../results/modern-toolchain.md) records executed qualification, and the [operational guide](../implementation/toolchain.md) defines setup/doctor/cache commands. Qualify the toolchain as a combination, not a list of installed executables. Use source builds or compatible pinned distributions; do not copy a binary built for a newer libc into an older base image.

## Capability tests

The initial UVM smoke exercises class construction, factory registration, virtual-interface configuration, constrained randomization, a timed transaction path, functional covergroups/crosses and a held-output SVA. The negative build intentionally violates held-output stability and must fail at that assertion. Compilation failure does not qualify the negative test.

Extend focused capability tests when introducing sequencer/driver APIs, analysis ports, RAL, covergroup features or temporal syntax beyond the already qualified subset. Preserve upstream sources and notices; avoid modifying the reference UVM library as the first workaround. Document the reason and patch provenance if a dependency patch becomes necessary.

The production frontdoor baseline uses the unmodified library with `UVM_NO_DPI`. Agents use interface transactions and frontdoor register accesses. The refresh separately qualifies DPI positive/negative regular expressions and HDL path/read/deposit with explicit visibility of the probed variable. Those services are available; the no-DPI frontdoor setting remains a sufficient chosen configuration. A production backdoor path must register its visibility and service-specific checks. Force/release, polling and four-state backdoor semantics are not qualified by this probe. No UVM sources or warnings are suppressed for the DPI test.

Verilator supports UVM but does not implement every SystemVerilog semantic or assertion feature. It is primarily a two-state simulator. Do not claim X/Z propagation coverage from it. Treat ignored constraint/coverage/assertion constructs as errors for owned code; do not use black-box-unsupported simulation options or silently disable assertions. Narrow external-library warnings require a documented waiver.

`--coverage` instruments supported code/functional coverage. Explicitly write and collect the resulting database and inspect its nonzero point/bin counts. A printed coverage percentage without a saved database is insufficient. Build a tiny harness with the actual coverage options before assuming collection works.

Formal and synthesis use the registered `read_slang` frontend in Yosys 0.70. All formal harnesses use the [qualified explicit-input recipe](formal.md#selected-frontend-and-arbitrary-inputs), without adapters or source-policy exceptions. Symbolic attributes must not silently become X constants. Preserve monitor-state translations where concurrent SVA is unavailable. Keep an explicit property mapping between simulation and formal. Equivalence, bounded checking and unbounded proof retain separate statuses.

## Dependency handling

Download pinned external sources to ignored `.deps/` and build to ignored `.tools/` or `.build/`. Keep downloads, executables and Liberty files out of Git. Record archive digests or commits, compiler versions and tool versions. A normal lint/test command does not fetch mutable upstream branches. A separate setup command prepares dependencies while network access is available.

Use the public Nangate45 reference Liberty pinned in dependencies.json for the initial implementation study. It is a reference analysis platform. Include actual payload storage in the small mapped profiles and state every abstraction used for larger profiles.

Upstream references: [Verilator support tracking](https://github.com/verilator/verilator/issues/1538), [release history](https://verilator.org/guide/latest/changes.html), [language support](https://verilator.org/guide/latest/languages.html), [coverage](https://verilator.org/guide/latest/simulating.html), [UVM reference library](https://github.com/accellera-official/uvm-core), [SBY](https://yosyshq.readthedocs.io/projects/sby/en/stable/), [Yosys](https://yosyshq.readthedocs.io/projects/yosys/en/latest/), [OpenSTA](https://github.com/parallaxsw/OpenSTA).
