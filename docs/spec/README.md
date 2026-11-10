# Specification index

Version 1.1. Normative hardware and verification contracts.

MUST denotes a release requirement, SHOULD a preferred implementation, and MAY an extension.
Performance values are acceptance targets until backed by an identified run.

| Document | Authority |
|---|---|
| [architecture.md](architecture.md) | Scope, profiles, block boundaries and performance targets |
| [interfaces.md](interfaces.md) | Clock/reset, packet/control ports and event observation |
| [buffer-management.md](buffer-management.md) | Admission, reservations, ownership, storage and cleanup |
| [queues-and-scheduling.md](queues-and-scheduling.md) | Queue linearization, DRR and transmission |
| [registers.md](registers.md) | Configuration lifecycle, register map and statistics |
| [verification.md](verification.md) | UVM architecture, independent checking, test matrix and coverage |
| [formal.md](formal.md) | Property families, assumptions, covers and proof scope |
| [implementation.md](implementation.md) | Lint, synthesis, constraints and timing/area comparisons |
| [toolchain.md](toolchain.md) | Open-source dependencies and capability qualification |
| [automation.md](automation.md) | Commands, run manifests, CI and evidence retention |
| [triage.md](triage.md) | Regression evidence and diagnostic report flow |
| [acceptance.md](acceptance.md) | Integration and release gates |
| [references.md](references.md) | Supporting protocol, algorithm and tool references |

Read the contract relevant to the current change. The implementation plan and task cards organize work; they cannot silently override these contracts. Record a material contract change with its reason, affected requirements and tests. Resolve conflicting requirements before implementing dependent behavior.
