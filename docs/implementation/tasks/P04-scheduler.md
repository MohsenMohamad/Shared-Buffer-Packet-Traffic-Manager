# P04: Deficit round robin and packet-RR comparison

## Objective and prerequisites

Implement the specified byte-aware visit policy, including its interaction with merged queue updates and exclusive TX ownership.

Dependencies: [P03](P03-queues.md)

## Sources and work boundary

- [queues-and-scheduling.md](../../spec/queues-and-scheduling.md)
- [verification.md](../../spec/verification.md)
- [formal.md](../../spec/formal.md)

Also read the relevant APIs in `docs/spec/module-contracts.md`, created by P01, and inspect the integrated dependency implementations before changing their boundaries.

`rtl/scheduler/`, independent scheduling model/tests, `formal/scheduler/` and scheduler-suite registration.

## Execution sequence

1. Use the P03 pre-state head/query and dispatch events. Implement cursor/visit/deficit state against the canonical DRR policy; do not base policy decisions on external input capture or output EOF alone.

2. Add one quantum on entering a nonempty visit; subtract packet bytes once at accepted dispatch. Continue an existing visit without another addition when the next head fits. Retain credit across insufficient-credit visits.

3. Use merged enqueue/dequeue count for true-empty closure. Clear credit only when genuinely empty; a singleton replaced on the dispatch edge remains nonempty. Later reactivation must not inherit idle credit.

4. Freeze scanning/credit additions while TX owns a packet. A fitting head waits for TX availability. Resume no earlier than the cycle after TX final handshake, preserving whether the visit continues.

5. Implement packet RR as the separate elaboration comparison mode. Size deficit arithmetic to hold QUANTUM_MAX+MAX_PACKET_BYTES-1 and assert/check bounds.

6. Build the dispatch-policy reference from packet lengths, queue events and visit state, not the RTL state-machine structure. Measure complete visits or include initial/final deficits and in-flight packets in finite accounting.

7. Register the `scheduler` suite. Check grant eligibility, add/debit discipline and bounds on production RTL; reach reactivation/collision cases and detect a quantum-per-packet mutation.

## Required checks

| Area | Evidence required |
| --- | --- |
| Visit arithmetic | Several packets in one visit, quantum smaller than packet, unequal quanta, maximum quantum/length and bounded credit. |
| Races | Empty/reactivation, singleton replacement, longer queue updates, TX busy/stalls and next-cycle commit visibility. |
| Policy/checker | Independent dispatch matching, packet-RR distinction, complete-visit byte equation, grant/credit properties and intended extra-quantum detection. |

## Completion

The scheduler portion of G2 implements both modes and passes independent policy checks without credit growth per stalled cycle or per packet in a continuing visit. System-level fairness measurements are completed in P12.

Requirement focus: `SCH-01`, `SCH-02`, `SCH-03`, `SCH-04`, `SCH-05`, `SCH-06`, `PERF-02`
