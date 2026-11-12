# Implementation analysis

Use the public library recorded in the run manifest. Use an identified public reference library such as Nangate45 typical. Record source, digest, units and PVT; report results within that analysis boundary.

The production implementation experiment MUST state whether area includes payload storage, metadata, FIFOs, control and observation logic. For the small I0/I1 profiles, prefer a fully mapped payload memory so the boundary is unambiguous. For a large abstract-SRAM profile, separate logic/metadata metrics from storage bits and assumed memory latency.

Run explicit SDC setup: clock period, uncertainty, min/max input delays and slews, min/max output delays and loads. Review setup/max and hold/min paths, unconstrained endpoints and timing exceptions. Do not cut valid paths merely to make slack positive. Initial 10-ns/100-MHz conditions are a working reference point, not a guaranteed final Fmax. A typical-corner ideal-clock hold result is not post-CTS or multi-corner closure. PPA power claims are excluded unless an actual power-estimation flow and activity assumptions are added.

At least one meaningful architectural comparison must connect a diagnosed cause to a measured result: e.g. a flat versus banked/register-pipelined memory, an allocator selection structure, queue-head lookup pipeline or an active-queue scheduler optimization. Report added registers/storage, latency and throughput as well as area/slack. A result that worsens one metric can still be a valid engineering finding.

A required implementation comparison is one-stage flat versus two-stage banked/register-pipelined read structures at equal payload capacity. The banked implementation physically reads independent banks in parallel; it is not evidence that an unchanged single SRAM gained more ports. Its extra stage must be modeled by MEM_RD_LATENCY and output-response credits in integration.



Verilator RTL lint is required. Do not blanket-disable warning classes to close lint. Scope a waiver to the exact construct and document its functional reason. Keep simulation-only classes and monitors out of synthesis source lists. Use synthesizable SystemVerilog accepted by the registered pinned `read_slang` flow. Consume the [qualified representation recipes](../implementation/tasks/P01-followup-representation.md); old native-frontend syntax rejections are not current prohibitions. Qualify constructs beyond that tested subset before relying on them.

Generated netlists, timing scripts, logs and waves belong in ignored build/output directories and CI artifacts. Commit concise curated results with the source revision and commands needed to regenerate them. Never equate positive setup slack at one reference corner with physical signoff.
