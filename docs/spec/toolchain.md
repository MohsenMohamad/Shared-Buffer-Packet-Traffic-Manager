# Open-source toolchain

All required build and verification workflows use command-line open-source tools and execute on a Linux x86-64 cloud workspace. No hardware server, proprietary simulator, FPGA board, GPU, GUI or container daemon is required.

| Purpose | Tool and qualification |
|---|---|
| SV/UVM simulation and RTL lint | Verilator 5.054 candidate baseline, pinned source; use timing, assertions and coverage explicitly |
| UVM library | Accellera UVM 2020.3.1 pinned source; this version is explicitly supported by the simulator project |
| Constrained randomization | Z3; qualify successful and unsatisfiable randomization and seed replay |
| Functional formal | SymbiYosys + Yosys + Z3, mutually qualified pinned versions |
| Standard-cell mapping | Yosys + ABC, explicit Liberty library and mapping constraints |
| Static timing | OpenSTA, Liberty/netlist/SDC inputs, max/min reports |
| Orchestration | Python 3.11+, Bash, Make; C++20-capable compiler for generated simulation code |

`tools/dependencies.json` records initial source pins. P00 installs the tools, records the exact qualified versions and adds reproducible setup/doctor commands. Qualify the toolchain as a combination, not a list of installed executables. Use source builds or compatible pinned distributions; do not copy a binary built for a newer libc into an older base image.

## Capability tests

The initial UVM smoke exercises class construction, factory registration, virtual-interface configuration, constrained randomization, a timed transaction path, functional covergroups/crosses and a held-output SVA. The negative build intentionally violates held-output stability and must fail at that assertion. Compilation failure does not qualify the negative test.

Extend focused capability tests when introducing sequencer/driver APIs, analysis ports, RAL, covergroup features or temporal syntax beyond the already qualified subset. Preserve upstream sources and notices; avoid modifying the reference UVM library as the first workaround. Document the reason and patch provenance if a dependency patch becomes necessary.

The initial unmodified UVM library uses its supported `UVM_NO_DPI` configuration. Agents use interface transactions and frontdoor register accesses; HDL backdoor access, DPI polling and DPI regular-expression services are outside this baseline. This setting does not remove UVM classes, constrained randomization, scoreboards, SVA or functional coverage. A future DPI/backdoor path requires its own qualification and dependency configuration.

Verilator supports modern UVM but does not implement every SystemVerilog semantic or assertion feature. It is primarily a two-state simulator. Do not claim X/Z propagation coverage from it. Treat ignored constraint/coverage/assertion constructs as errors for owned code; do not use black-box-unsupported simulation options or silently disable assertions. Narrow external-library warnings require a documented waiver.

`--coverage` instruments supported code/functional coverage. Explicitly write and collect the resulting database and inspect its nonzero point/bin counts. A printed coverage percentage without a saved database is insufficient. Build a tiny harness with the actual coverage options before assuming collection works.

Formal code uses the supported free frontend, with monitor-state translations where concurrent SVA is unavailable. Keep an explicit property mapping between simulation and formal. Equivalence, bounded checking and unbounded proof retain separate statuses.

## Dependency handling

Download pinned external sources to ignored `.deps/` and build to ignored `.tools/` or `.build/`. Keep downloads, executables and Liberty files out of Git. Record archive digests or commits, compiler versions and tool versions. A normal lint/test command does not fetch mutable upstream branches. A separate setup command prepares dependencies while network access is available.

Use the public Nangate45 reference Liberty pinned in dependencies.json for the initial implementation study. It is a reference analysis platform. Include actual payload storage in the small mapped profiles and state every abstraction used for larger profiles.

Upstream references: [Verilator support tracking](https://github.com/verilator/verilator/issues/1538), [release history](https://verilator.org/guide/latest/changes.html), [language support](https://verilator.org/guide/latest/languages.html), [coverage](https://verilator.org/guide/latest/simulating.html), [UVM reference library](https://github.com/accellera-official/uvm-core), [SBY](https://yosyshq.readthedocs.io/projects/sby/en/stable/), [Yosys](https://yosyshq.readthedocs.io/projects/yosys/en/latest/), [OpenSTA](https://github.com/The-OpenROAD-Project/OpenSTA).
