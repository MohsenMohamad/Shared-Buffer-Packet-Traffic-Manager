# Toolchain capabilities and design use

Use the selected stack's qualified capabilities where they simplify the actual
design. Exact executed scope is in the [qualification report](../results/modern-toolchain.md)
and [RTL representation report](../results/rtl-representation.md).

| Area | Current recipe | Acceptance boundary |
| --- | --- | --- |
| Declarations and shared types | ANSI ports, fixed `tm_fixed` package, scoped dependent type defaults declared before use | Six profiles, invalid configurations and heterogeneous instances; preserve widths and packing |
| Width formulas | Named localparams and qualified `$bits(type)` use | Guard invalid indices/counts; no unsupported parameterized-package syntax |
| Memories | Vector or packed-record words according to actual operations | Check width/depth/ports, complete-word behavior and read latency; vector storage remains appropriate for bitwise copying |
| Published interfaces | Packed lane ABI with explicit lane order | Unpacked ports and modports are available when useful; interface changes require contract review |
| Formal inputs | Committed explicit top-level input ports | Fixed witnesses remain stable across DUT resets; uniform source guards and missing-stability negative |
| Formal properties | Independent immediate assertions and monitor state | Preserve assumptions, initialization, `$past`, property labels, reachability and named mutation detections |
| UVM | Qualified frontdoor agents, sequences, analysis, RAL and constraints | Checked randomize results, replay, independent scoreboards and saved functional coverage |
| DPI | Qualified regex and HDL path/read/deposit services | Explicit visibility; no force/release, polling or four-state claim without qualification |
| Coverage | Saved databases with required point/bin counts | Missing or empty coverage fails; printed percentages do not substitute |
| Mapping | `synth -noabc`, explicit flop mapping, Liberty ABC | Require real mapped cells, no unresolved cells and live required outputs |
| Timing | Explicit units, clock, IO delays, uncertainty, slew/drive and load | Report data and reset checks separately under R01; reject unconstrained paths and tool diagnostics |
| Timing APIs | Scene, parasitic, derate and noise APIs available | One typical Liberty without physical/variation/noise inputs supports only the stated pre-layout analysis |
| Installation | Pinned sources, isolated runtime, compatibility-validated shared cache | Actual compiler/runtime identity and executable language/ABI checks |

New tasks extend the existing production source registries, runner and evidence
path. Qualify concrete additional language/library constructs once before use.
Do not add interfaces, abstraction layers or services merely to demonstrate syntax.
Current production proofs and independent regressions define correctness;
standalone frontend fixtures establish only their stated capability.
