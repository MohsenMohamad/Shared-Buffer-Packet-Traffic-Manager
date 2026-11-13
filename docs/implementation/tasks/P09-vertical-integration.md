# P09: Single-flow end-to-end vertical integration

## Objective and prerequisites

Establish the first genuine input-to-output path through allocated shared cells, queue scheduling, TX and the real control plane. One active flow is a test restriction, not a reduced fake top.

Dependencies: [P04](P04-scheduler.md), [P05](P05-memory-tx.md), [P06](P06-registers.md), [P07](P07-verification-foundation.md), [P08](P08-receive-admission.md)

## Sources and work boundary

- [architecture.md](../../spec/architecture.md)
- [interfaces.md](../../spec/interfaces.md)
- [buffer-management.md](../../spec/buffer-management.md)
- [queues-and-scheduling.md](../../spec/queues-and-scheduling.md)
- [registers.md](../../spec/registers.md)
- [verification.md](../../spec/verification.md)

Also read the relevant APIs in `docs/spec/module-contracts.md`, created by P01, and inspect the integrated dependency implementations before changing their boundaries.

`rtl/tm_top.sv`, production integration/source lists, actual `dv/env/` wiring, `dv/tests/vertical/`, assertion/trace bindings and subsystem CI.

## Execution sequence

1. Compare the integrated component port lists and semantics against P01 module-contracts before wiring. Check reset, field widths, handshake events, RAM latency, return ports, array ownership, configuration/event direction and trace timing. Resolve concrete discrepancies in the affected component/API rather than inserting unchecked adapters.

2. Instantiate the real FIFOs, RX/admission/reclaimer, pools, store/metadata, queue controller, scheduler, TX and AXI4-Lite registers. Preserve the full supported profile's top-level interface. Do not replace shared storage/queues with a stand-in packet FIFO.

3. Wire the actual control/configuration, statistics and invariant-error signals. Derive IDLE from FIFO/context/queue/TX/read/ownership state; an empty committed queue alone must not permit reconfiguration.

4. Bind the P07 UVM environment to actual ports/trace events. Cross-check service, commit, status and dispatch observations with external monitor data and resource state. Remove fixture-specific assumptions from production checking.

5. Bring up reset/default register reads, enable RUN via AXI4-Lite, and send one valid single-beat packet on one input/queue. Check exact bytes/user/keep/last, disposition, counters and final ownership.

6. Extend to multi-cell and partial-final-byte packets, gaps and sink stalls. Exercise corresponding latency-one/two supported profiles. Reset during a pending read/stall and confirm no old-epoch delivery; test a malformed packet followed by resource recovery.

7. Inject a disposable output-byte corruption in the actual integration path and require the black-box scoreboard to reject it. Confirm bound SVA and coverage collectors execute rather than merely compile.

8. Register the `vertical` suite through the common regression runner and add a real subsystem smoke job to CI using that command. Retain G0 fixture jobs and the documented distinction between capability and hardware results.

## Required checks

| Area | Evidence required |
| --- | --- |
| Real path | Allocated cell writes, commit, scheduler dispatch and actual read/output with exact monitored bytes, metadata, ordering and status. |
| Control/recovery | Real CSR RUN/IDLE/statistics wiring, final full pools, malformed cleanup and reset with pending read/output stall. |
| Latencies/lengths | Single beat, multiple cells, partial final keep and read latency 1/2 in supported fully elaborated profiles. |
| Checker/CI | Actual-path corruption detection, active assertions/coverage and hosted vertical smoke on the candidate executable revision when accessible. |

## Completion

G3: an exercised genuine UVM/production-RTL vertical path, a runnable subsystem smoke entry point and correct final resource/control state. This does not yet establish all-input/all-queue concurrency.

Requirement focus: `IF-01`, `IF-03`, `LEN-01`, `LEN-02`, `LEN-03`, `Q-01`, `MEM-02`, `MEM-03`, `MEM-04`, `MEM-05`, `FMT-06`, `RST-01`, `RST-02`, `CSR-05`, `CSR-06`

## Early packet-rate measurement

Measure saturated 64-byte and 1536-byte traffic on the real path with an always-ready output to characterize internal overhead. Keep one backlogged queue for the initial vertical baseline; also run representative multi-queue traffic once that path is available, with completion required in P10. Define reset/setup, warm-up and measurement windows explicitly; record sustained backlog, delivered packets/beats, elapsed measurement cycles, packets/cycle, beats/cycle and the interpacket-gap distribution. State how packets crossing window boundaries are counted. Define an interpacket gap as the output cycles strictly between the previous packet's final transfer and the next packet's first transfer; adjacent transfers have zero gap.

Use the common [P09/P10 measurement accounting](P10-concurrency.md#packet-rate-diagnosis-and-decision) so overhead cycles are attributed once. This is early diagnosis, not P12 benchmark closure. No hard minimum-packet utilization target is agreed; do not invent one or apply the large-packet target to 64-byte traffic.

## RTL integration PR

Steps 1–3 implement actual top/control/event/ownership wiring, production source membership and separate designer smoke; coordinate APIs with DV.

## Independent DV PR and verified G3 gate

Steps 4–8, all required path/control/latency/checker/CI rows and early packet-rate checks are DV-owned. Early wiring/bench development may precede component DV merge, but G3 requires merged passing applicable component DV (including P03/P04/P05/P08 and reviewed P02/P06 qualification), then qualification of the actual merged top. Preserve all original acceptance obligations.

Follow the [separate-owner defect/fix/reverify gates](../plan.md#ownership-and-verification-gates); hardware fixes use another RTL PR.
