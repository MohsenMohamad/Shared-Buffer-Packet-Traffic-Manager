# Toolchain and frontend selection

The packaged synthesis frontend constrained production SystemVerilog
declarations and packed-record memories. Select the
checksum-locked source stack in `tools/dependencies.json`, including the Yosys
0.70 integrated `read_slang` frontend, Verilator 5.054, official UVM 2020.3.2,
SBY 0.71, Z3 5.4.1 and authoritative OpenSTA 3.2.0 source. Exact transitive
gitlinks, runtime/build-package dispositions and upstream verification are in
the [inventory](../implementation/toolchain-inventory.md).

Use `read_slang` in the real synthesis/formal registries. Retain native
`read_verilog` as a diagnostic control for syntax and packed-record memory
comparisons. For formal with Slang, expose arbitrary harness internals as free
ports through the strict adapter to preserve expressions and property identities.
Prove mutual inclusion of complete assumption predicates to account for the
different semantics of native formal symbolics and Slang's symbolic attributes.
Do not replace the production DUT or weaken reset/assumptions to obtain proof.

ANSI headers, fixed shared packages, type parameters, `$bits(type)` and typed
memories are accepted recipes for the separate P01 representation follow-up.
Keep packed public lane order, finite ports and all behavior. Interface support
does not itself justify introducing an interface. Complete that follow-up before
allocator characterization; P03+ remains paused.

The selected mapping flow performs generic synthesis without ABC, flop mapping
and Liberty ABC. Timing errors override completion markers. Measurements retain
the fixed typical Nangate45 library and explicit ns/fF constraints. One typical
library without routed parasitics or variation/noise data supports only the
reported single-corner pre-layout analysis. OpenSTA 3.2.0 scene and variation APIs
are capabilities to revisit when those inputs exist, not new measured results.

Installation, activation, doctor, source identity, cache identity and shared
producer/consumer validation form one contract. C++20 language/runtime probes
replace the exact compiler-patch rejection; ABI/compiler details still invalidate
the cache. Runtime OpenSTA/Slang identities must match the verified source locks,
including archive builds beneath another Git checkout.

This supersedes tool/version/frontend restrictions in decisions 0001–0005 only
where the [capability table](../implementation/toolchain-capabilities.md)
identifies replacement evidence. Original results remain historical facts.
The [qualification report](../results/toolchain-qualification.md) records actual
execution and outstanding gates; this decision does not turn a pending check
into PASS. Production conversion and maintainer integration remain separate.
