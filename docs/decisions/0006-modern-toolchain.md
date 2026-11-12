# Current frontend and toolchain qualification

The original packaged synthesis/solver/STA stack constrained readable production
SystemVerilog and no longer represented current upstream capability. Select the
checksum-locked source stack in `tools/dependencies.json`, including the Yosys
0.70 integrated `read_slang` frontend, Verilator 5.054, official UVM 2020.3.2,
SBY 0.71, Z3 5.4.1 and authoritative OpenSTA 3.2.0 source. Exact transitive
gitlinks, runtime/build-package dispositions and upstream verification are in
the [inventory](../implementation/modern-toolchain-plan.md).

Use `read_slang` in the real synthesis/formal registries. Retain native
`read_verilog` as a diagnostic control. Its old syntax and record-memory limits
do not impose current design prohibitions. Slang's symbolic attributes are
not equivalent to native formal symbolics: expose arbitrary harness internals
as free ports through the strict adapter, preserving expressions/property
identities and proving mutual inclusion of complete assumption predicates.
Do not replace the production DUT or weaken reset/assumptions to obtain proof.

ANSI headers, fixed shared packages, type parameters, `$bits(type)` and typed
memories are accepted recipes for the separate P01 representation follow-up.
Keep packed public lane order, finite ports and all behavior. Interface support
does not itself justify introducing an interface. Complete that follow-up before
allocator characterization; P03+ remains paused.

Current mapping explicitly performs generic synthesis without ABC, flop mapping
and Liberty ABC. Timing errors override completion markers. Measurements retain
the fixed typical Nangate45 library and explicit ns/fF constraints. One typical
library without routed parasitics or variation/noise data supports only the
reported single-corner pre-layout analysis. New OpenSTA scene/variation APIs
are capabilities to revisit when those inputs exist, not new measured results.

Installation, activation, doctor, source identity, cache identity and shared
producer/consumer validation form one contract. C++20 language/runtime probes
replace the exact compiler-patch rejection; ABI/compiler details still invalidate
the cache. Runtime OpenSTA/Slang identities must match the verified source locks,
including archive builds beneath another Git checkout.

This supersedes tool/version/frontend restrictions in decisions 0001–0005 only
where the [capability table](../implementation/modern-toolchain-decisions.md)
identifies replacement evidence. Original results remain historical facts.
The [qualification report](../results/modern-toolchain.md) records actual
execution and outstanding gates; this decision does not turn a pending check
into PASS. Production conversion and maintainer integration remain separate.
