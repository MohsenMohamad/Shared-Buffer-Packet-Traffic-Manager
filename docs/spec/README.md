# Specification index

The single-egress contracts describe the checked-in components and their
verification scope. The planned multi-egress traffic manager has its own
behavior contract and [implementation path](../implementation/plan.md#multi-egress-migration-and-gates).
MUST denotes a release requirement, SHOULD a preferred implementation, and MAY
an extension. Measured results identify the specific run and its scope.

| Document | Applies to | Authority |
| --- | --- | --- |
| [Multi-egress traffic manager](multi-egress-traffic-manager.md) | Multi-egress design | Behavior, event ordering, profiles and performance target |
| [Multi-egress interfaces](multi-egress-interfaces.md) | Multi-egress design | Public types, packet and cell ports, edge observations and CSR map |
| [architecture.md](architecture.md) | Single-egress design | Scope, profiles, block boundaries and performance targets |
| [module-contracts.md](module-contracts.md) | Single-egress design | G1 module APIs, update ownership, portable types and monitor batching |
| [interfaces.md](interfaces.md) | Single-egress design | Clock/reset, packet/control ports and event observation |
| [buffer-management.md](buffer-management.md) | Single-egress design | Admission, reservations, ownership, storage and cleanup |
| [queues-and-scheduling.md](queues-and-scheduling.md) | Single-egress design | Queue linearization, DRR and transmission |
| [registers.md](registers.md) | Single-egress design | Configuration lifecycle, register map and statistics |
| [verification.md](verification.md) | Single-egress design | UVM architecture, independent checking, test matrix and coverage |
| [formal.md](formal.md) | Single-egress design | Property families, assumptions, covers and proof scope |
| [implementation.md](implementation.md) | Single-egress design | Lint, synthesis, constraints and timing/area comparisons |
| [reset-timing.md](reset-timing.md) | Single-egress design | Reset timing policy and evidence boundary for the existing sources |
| [acceptance.md](acceptance.md) | Single-egress design | Integration and release gates |
| [toolchain.md](toolchain.md) | Shared workflow | Open-source dependencies and capability qualification |
| [automation.md](automation.md) | Shared workflow | Commands, run manifests, CI and evidence retention |
| [triage.md](triage.md) | Shared workflow | Regression evidence and diagnostic report flow |
| [references.md](references.md) | Shared workflow | Supporting protocol, algorithm and tool references |

The implementation plan and task cards organize work. Resolve contract
conflicts and record material changes with their reasons and affected tests
before implementing dependent behavior.
