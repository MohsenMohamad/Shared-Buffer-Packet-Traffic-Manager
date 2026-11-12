# 0008: Retire completed migration scaffolding

## Decision

The selected Slang toolchain is the sole executable frontend. Completed migration
comparisons no longer run in ordinary CI or require historical source objects.
This supersedes the ongoing comparison/adapter requirements of decisions 0006
and 0007; their accepted tool versions and RTL representation remain unchanged.

| Component | Disposition | Reason |
|---|---|---|
| Native/Slang bridge, historical harness miters | Remove | Migration is complete; production properties are the current acceptance |
| Old/current representation runner, registry and Git staging | Remove | Do not freeze implementation to a historical design |
| Disposable production-copy generators and native-only diagnostics | Remove | No current production consumer |
| Storage/CSR generated-input adapters | Replace with committed input ports | Execute the accepted harness directly |
| Three bridge/representation/mapping CI jobs | Remove | No live migration obligation |
| Current Slang parse/elaboration/synthesis feature fixtures | Keep | Qualify language constructs actually used |
| Current record-memory proof/cover and inference checks | Keep | Check complete-word semantics and memory shape |
| F01 explicit-witness proof/cover and missing-stability negative | Keep | Guard current arbitrary-input semantics |
| Uniform symbolic source/header/include guard | Keep, remove exceptions | Prevent unsupported symbolic declarations in any production harness |
| Production storage/CSR/queue prove/cover/mutations | Keep | Check current hardware contracts and intended defect detection |
| UVM, DPI, synthesis/STA and allocator characterization | Keep | Independent current-stack capabilities |

The two converted harness files are byte-identical to the previous adapter's
output. Their assumptions, assertions, covers, reset behavior and mutation sites
are unchanged. Harness-source generation is removed from production execution.

Removed check names are `capability-bridge`, `capability-representation-formal`
and `capability-fifo-mapping`. If configured as required in branch protection,
remove those entries. Keep existing production and retained capability checks.
