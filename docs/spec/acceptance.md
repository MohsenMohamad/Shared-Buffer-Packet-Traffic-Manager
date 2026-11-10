# Acceptance gates

| Gate | Evidence |
|---|---|
| G0 Toolchain | Qualified UVM/randomization/SVA/coverage smoke; actual proof/cover and expected failing mutation; mapped synthesis and STA smoke |
| G1 Contracts | Profiles, external ports, internal module contracts and independent model interfaces fixed and checked |
| G2 Components | FIFO/pools, descriptor queues, scheduler, memory/TX and register slave have meaningful local tests |
| G3 Vertical path | Real UVM path through the actual shared store; partial final bytes and output stalls checked |
| G4 Concurrency | All inputs/queues, simultaneous resource changes, malformed cleanup, pressure and resets exercised |
| G5 Verification | Requirement matrix accounted for; reviewed coverage; selected unbounded safety proofs and reachable covers with documented scope |
| G6 Measurements | Matched traffic/policy and implementation comparisons with reproducible manifests |
| G7 Release | Working CI, reusable components, diagnostic examples, current documentation and no unexplained failures |

A gate's evidence identifies its exact source revision and configuration. The repository starts with specifications and capability-test sources; all subsystem gates start pending. Tests or properties not executed are reported individually with a reason. Source implementation alone is not execution evidence.

The primary UVM path is a required executable gate. If the pinned open-source simulator lacks a construct, first preserve the requirement through a supported, equivalent implementation and qualify it. Isolate an irreducible simulator-specific check as portable SV plus a minimal reproducer, expected result and an UNSUPPORTED/NOT_RUN record. Continue independent work. Such a record is not a passing result; report the resulting validation boundary explicitly. Never replace the required UVM environment with a Python-only bench.

Four-state/X propagation and simulator-specific semantic checks may remain unexecuted when the available engine cannot represent them. Maintain those cases separately from executed two-state safety/data tests. Selected functional formal claims remain required under the formal plan. No full-chip, physical signoff or silicon power claim is part of acceptance.
