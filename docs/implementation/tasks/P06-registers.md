# P06: AXI4-Lite configuration and coherent statistics

## Objective and prerequisites

Implement the control plane and its event/statistics interface without depending on a CPU platform or a fully integrated packet datapath.

Dependencies: [P01](P01-contracts.md)

## Sources and work boundary

- [interfaces.md](../../spec/interfaces.md)
- [registers.md](../../spec/registers.md)
- [verification.md](../../spec/verification.md)
- [formal.md](../../spec/formal.md)

Also read the relevant APIs in `docs/spec/module-contracts.md`, created by P01, and inspect the integrated dependency implementations before changing their boundaries.

`rtl/csr/`, register-model/tests, `formal/csr/` and CSR-suite registration.

## Execution sequence

1. Use the P01 AXI/configuration/event contracts. Implement independent AW and W holding registers with one outstanding write and one independent read. Accept either write-channel arrival order.

2. Implement the authoritative address map, capability/reset values and RO/WO/reserved behavior. Keep B/R responses stable through stalls and meet the specified bounded response-production latency.

3. Apply byte strobes before range validation. Check mapped versus unmapped/misaligned addressing and invalid queue indices before indexing arrays. Rejected merged writes leave the entire register unchanged.

4. Implement RUN, disabled/idle configuration locking and correct busy-disable rejection. Consume the whole-system IDLE input defined by P01; queue emptiness alone is not sufficient.

5. Implement live U/R/free-descriptor/H state reads and separate live/shadow statistics. Capture pre-update counters coherently on SNAPSHOT; allow the same edge's events to update live state afterward. Enforce clear restrictions and sticky invariant-error reset behavior.

6. Drive the agreed event inputs from a declared component fixture while production traffic is unavailable. Compare reads and snapshot sequences against an independent register model; use reduced counter widths for a documented rollover test, without changing the production 64-bit ABI.

7. Register the `csr` suite and production protocol-safety properties. Test independent AW/W, B/R stalls, simultaneous read/write, snapshot/event collisions, zero/partial strobes, error responses and reset with pending responses. Detect a coupled-AW/W defect.

## Required checks

| Area | Evidence required |
| --- | --- |
| Protocol | AW first, W first, same edge and long separation; B/R stalls; read/write overlap; one-outstanding and response-latency contracts. |
| Register semantics | All mapped/invalid qids, address errors, RO/WO/zero strobes, range rejection, read-before-write and reset values. |
| Lifecycle/statistics | Busy disable, configuration locks, correct fixture IDLE, coherent pre-update snapshots, live/shadow separation, rollover and sticky error. |
| Safety/checker | Production request/response assertions/properties and intended coupled-channel defect detection. |

## Completion

The CSR portion of G2 executes against a declared independent event fixture. Real datapath event wiring and whole-system IDLE are verified again in P09/P10.

Requirement focus: `CSR-01`, `CSR-02`, `CSR-03`, `CSR-04`, `CSR-05`, `CSR-06`, `RST-01`, `RST-02`

The [representation migration report](../../results/rtl-representation.md) records
the ANSI/shared-type conversion and new checks. Original behavioral acceptance
and historical evidence remain in force; no later hardware stage is started.
