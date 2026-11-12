# Toolchain inventory and qualification

The selected combination is qualified for the documented simulation, formal,
mapping and timing capabilities. Exact commits, archive digests, build inputs
and transitive dependencies are owned by `tools/dependencies.json` and
`tools/packages.lock.json`. Setup must reproduce those identities; normal checks
must not fetch mutable upstream branches.

| Role | Selected dependency |
| --- | --- |
| Simulation and lint | Verilator 5.054 |
| Verification library | Accellera UVM 2020.3.2 |
| Synthesis and formal elaboration | Yosys 0.70+post with integrated Slang and its pinned ABC |
| Formal orchestration and solver | SymbiYosys 0.71 and Z3 5.4.1 |
| Static timing | OpenSTA 3.2.0 |
| Source-build dependencies | CMake 4.4.5, SWIG 4.5.1, Eigen 5.0.1, CUDD 3.0.0, Click 8.5.1 |
| Reference cell library | Checksum-locked Nangate45 typical Liberty |

Setup builds in `.tools/install`, extracts build/Tcl/zlib packages into
`.tools/sysroot`, and keeps dependency sources and licenses under `.deps`.
The host must satisfy the recorded glibc, Python and C++ runtime compatibility.
Compiler language support is checked by compilation/execution; cache identity
includes the actual compiler and runtime. OpenSTA runtime source identity is
checked independently of the enclosing checkout's Git metadata.

## Acceptance and scope

Validate source/archive integrity, installed identities, runtime dependencies,
cache compatibility and doctor before executing consumers. Qualify successful
and unsatisfiable randomization, replay, UVM analysis/RAL/coverage, explicit
formal inputs, assertion/cover/negative results, memory inference, library
mapping and max/min timing with focused executable checks.

The [capability table](toolchain-capabilities.md) defines the accepted design
recipes. The [qualification report](../results/modern-toolchain.md) retains
executed commands, identities and results. Its fixed reference-library timing
is pre-layout evidence: no routed parasitics, multi-corner closure, variation or
noise claim follows from the presence of a timing API.

Changes to dependencies require explicit qualification of affected capabilities.
A capability fixture never substitutes for production-module verification.
