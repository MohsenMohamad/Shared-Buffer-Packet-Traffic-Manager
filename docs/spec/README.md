# Specification index

The active design is the shared-buffer multi-egress traffic manager. The
behavior and interface contracts govern implementation. The
[implementation plan](../implementation/plan.md) defines acceptance and sequencing.

| Document | Authority |
| --- | --- |
| [Traffic manager](multi-egress-traffic-manager.md) | Profiles, framing, resource ownership, scheduling and performance |
| [Interfaces](multi-egress-interfaces.md) | Packet, memory, event and control ABI |
| [Verification](verification.md) | Test scope, independence and coverage |
| [Requirements](../../verification/requirements.json) | Requirement IDs and expected behavior |
| [Formal](formal.md) | Property families, assumptions, covers and proof scope |
| [Implementation](implementation.md) and [reset timing](reset-timing.md) | Lint, synthesis, constraints and evidence boundaries |
| [Toolchain](toolchain.md) and [automation](automation.md) | Open-source dependencies, commands and CI |
| [Triage](triage.md) and [references](references.md) | Failure diagnosis and supporting material |

For the retired design, see the [historical baseline](../results/README.md#historical-baseline).
