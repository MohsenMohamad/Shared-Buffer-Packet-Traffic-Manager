# Repository layout

| Path | Responsibility |
|---|---|
| rtl/include/ | Shared production types and parameter helpers |
| rtl/common/, rtl/pools/ | Reusable FIFOs and allocators |
| rtl/rx/, rtl/admission/, rtl/reclaim/ | Ingress, reservation and cleanup control |
| rtl/queue/, rtl/scheduler/ | Descriptor queues and scheduling |
| rtl/memory/, rtl/tx/, rtl/csr/ | Storage, transmit engine and registers |
| rtl/tm_top.sv | Production integration boundary |
| dv/agents/, dv/model/, dv/env/, dv/tests/, dv/coverage/ | SV/UVM verification |
| formal/ | Property families, harnesses and proof configurations |
| tests/toolchain/ | Small language/library/solver capability fixtures |
| verification/ | Requirement/test/result mapping and schemas |
| tools/ | Setup, bounded run orchestration, reporting and triage |
| constraints/, benchmarks/ | Timing budgets and reproducible workloads |
| docs/spec/ | Normative contracts by technical topic |
| docs/implementation/ | Task dependencies and compact unfinished-work handoffs |
| docs/decisions/, docs/results/ | Durable trade-offs and curated measured evidence |
| .github/workflows/ | CI using the same repository commands |
| .deps/, .tools/, .build/, .work/ | Ignored downloads, installations, generated output and scratch |

Component tasks create their implementation directories when needed. Keep source lists separate by purpose and dependency order. Paths may be refined in P01 to preserve coherent module boundaries; do not duplicate the same implementation under multiple directory schemes.
