# Integration status

| Area | Established evidence | Open work |
| --- | --- | --- |
| Public interfaces | Both profiles and read latencies pass declaration checks. [ABI validation](results/TM03-multi-egress-declarations.md) | Real datapath connections |
| Throughput | Cycle models meet the eight primary balanced fixed-permutation windows. Independent-length replay exposes late first-cell handoffs. [Traffic study](results/multi-egress-datapath-feasibility.md) · [Composed control replay](results/TM04-composed-timing.md) | RTL throughput and integrated traffic qualification |
| Control timing | Connected fixtures pass scoped setup, hold, slew and capacitance checks after buffer repair. [Timing study](results/TM04-composed-timing.md) | Actual ingress, payload and CSR endpoints, a fanout limit, and reset-release characterization |
| Resource pools | Independent preparation covers both geometries and required bins. Production pools pass designer smoke and scoped data timing. [Pool preparation](results/TM05-pool-dv-preparation.md) · [RTL candidate](results/TM06-pool-rtl-candidate.md) | Independent production binding, qualification and proofs |
| Integration | The public contract defines ownership, memory, scheduling and configuration. [Implementation plan](implementation/plan.md) | Remaining blocks and end-to-end integration, coverage, formal and mapped timing |

The architecture freeze remains open under [Decision 0010](decisions/0010-multi-egress-queue-control.md).
