# Specification index

The v1.1 one-egress contracts describe the checked-in components and their
verification scope. The v2 target has a separate behavior contract and an
[implementation path](../implementation/plan.md#v2-migration-and-gates).
MUST denotes a release requirement, SHOULD a preferred implementation, and MAY
an extension. Measured results identify the specific run and its scope.

| Document | Applies to | Authority |
| --- | --- | --- |
| [4×4 target contract](tm-v2-4x4.md) | v2 | Behavior, event ordering, profiles and performance target |
| [architecture.md](architecture.md) | v1.1 | Scope, profiles, block boundaries and performance targets |
| [module-contracts.md](module-contracts.md) | v1.1 | G1 module APIs, update ownership, portable types and monitor batching |
| [interfaces.md](interfaces.md) | v1.1 | Clock/reset, packet/control ports and event observation |
| [buffer-management.md](buffer-management.md) | v1.1 | Admission, reservations, ownership, storage and cleanup |
| [queues-and-scheduling.md](queues-and-scheduling.md) | v1.1 | Queue linearization, DRR and transmission |
| [registers.md](registers.md) | v1.1 | Configuration lifecycle, register map and statistics |
| [verification.md](verification.md) | v1.1 | UVM architecture, independent checking, test matrix and coverage |
| [formal.md](formal.md) | v1.1 | Property families, assumptions, covers and proof scope |
| [implementation.md](implementation.md) | v1.1 | Lint, synthesis, constraints and timing/area comparisons |
| [reset-timing.md](reset-timing.md) | v1.1 | Reset timing policy and evidence boundary for the existing sources |
| [acceptance.md](acceptance.md) | v1.1 | Integration and release gates |
| [toolchain.md](toolchain.md) | Shared workflow | Open-source dependencies and capability qualification |
| [automation.md](automation.md) | Shared workflow | Commands, run manifests, CI and evidence retention; registered hardware cases are v1.1 |
| [triage.md](triage.md) | Shared workflow | Regression evidence and diagnostic report flow |
| [references.md](references.md) | Shared background | Supporting protocol, algorithm and tool references |

The implementation plan and task cards organize work. Resolve contract
conflicts and record material changes with their reasons and affected tests
before implementing dependent behavior.
