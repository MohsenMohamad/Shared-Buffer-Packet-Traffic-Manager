# Repository layout

| Path | Responsibility |
|---|---|
| rtl/include/multi_egress/ | Multi-egress public types, ports and parameter helpers |
| rtl/common/, rtl/pools/ | Reusable FIFOs and allocators |
| rtl/rx/, rtl/admission/, rtl/reclaim/ | Ingress, reservation and cleanup control |
| rtl/queue/, rtl/scheduler/ | Descriptor queues and scheduling |
| rtl/memory/, rtl/tx/, rtl/csr/ | Storage, transmit engine and registers |
| rtl/ | Production component and integration sources as they land |
| dv/multi_egress_pools/ | Independent SV/UVM pool verification |
| formal/ | Property families, harnesses and proof configurations |
| tests/toolchain/ | Small language/library/solver capability fixtures |
| verification/ | Requirements, source lists and verification configuration |
| tools/ | Setup, bounded run orchestration, reporting and triage |
| constraints/, benchmarks/ | Timing budgets and reproducible workloads |
| docs/spec/ | Normative contracts by technical topic |
| docs/implementation/ | Task dependencies and compact unfinished-work handoffs |
| docs/decisions/, docs/results/ | Durable trade-offs and curated measured evidence |
| .github/workflows/ | CI using the same repository commands |
| .deps/, .tools/, .build/, .work/ | Ignored downloads, installations, generated output and scratch |

Component tasks create their implementation directories when needed. Keep source lists separate by purpose and dependency order. Preserve coherent module boundaries and avoid duplicating the same implementation under multiple directory schemes.
