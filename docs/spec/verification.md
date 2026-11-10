# Verification plan

Use SystemVerilog/UVM with the qualified open-source simulator and UVM reference library defined in toolchain.md. Pin their versions in every run manifest. Python supplies orchestration and independent offline analyses. Drivers, sequences, monitors and scoreboards remain actual UVM components.

Required components:

- A reusable packet-stream agent instantiated actively on each input and as an output sink. Drivers implement legal ready/valid timing and permit source gaps and independent sink stalls. Monitors reconstruct actual handshaken bytes independently of driver objects.
- An active AXI4-Lite master agent, passive bus monitor and register predictor/RAL model. AW/W separation and B/R stalls are randomized independently.
- Independent packet, admission/resource and scheduling checkers, fed through monitor analysis ports. Coverage collectors remain passive.
- An assertion layer for interface stability, memory-port counts, response-credit bounds, ownership/accounting events, legal queue updates and reset behavior.
- A sequencer coordinating traffic, register accesses and reset. Cross-block scenarios are coordinated explicitly, not left to a hope that random seeds will hit them.
- A run manifest, per-test machine-readable result, waveform-on-failure and a compact first-failure artifact for AI triage.

### Independence and event ordering

The packet reference data MUST originate from input monitor handshakes. A driver saying “I sent packet X” is not evidence that the DUT accepted it. Maintain pending packet objects by input, frame ordinal and qid. Tags help debugging but are not required to be unique.

The black-box byte checker verifies the actual bytes, length, metadata, exact delivery count and per-input/per-queue order of surviving packets. The cross-input per-queue commit order is checked by an additional policy checker using the stable `commit` and `dispatch` observation points. These observations are necessary because ingress FIFO capture and internal commit are distinct; append-to-reference-queue at external EOF would impose the wrong ordering across ports.

A service-event checker maintains abstract per-input FIFO contents from external captures and checks that every `rx_service` consumes exactly the oldest captured beat. It verifies commit/status causality and eventually accounts for all buffered frames after draining. The policy model uses lists of packet objects and scalar credit counts, not copied cell IDs, pointer RAMs or the RTL free-bitmap algorithm.

At each clock, first collect a complete pre-state event batch. Evaluate admission and dequeue legality against that pre-state, then apply all deltas atomically. Do not let arbitrary ordering of UVM analysis callbacks decide whether a same-cycle release was available to admission or whether a new commit bypassed an empty queue.

The admission checker reconstructs U, free descriptors and H[q] from independently validated reservation, cell-consumption and abort-completion events. It cross-checks live CSR counters and all trace events. It must catch a DUT that reports an unjustified DROP; using the DUT's free counter as the expected answer is insufficient.

The scheduler model consumes committed packet lengths and static quanta. It checks the dispatch policy at the architectural dispatch event; checking only output EOFs cannot reconstruct exact dispatch timing under source arrivals and output stalls. The byte scoreboard separately checks that actual output follows those commitments.

Reset creates a new scoreboard epoch: abandon pre-reset expected deliveries/statuses, clear model resource state and reject any stale post-reset output. This is the specified flush policy; preservation across reset is not required.

## Requirement and directed test matrix

Every row is mandatory unless explicitly marked an experiment or a reduced-scope proof. A directed test MUST include a checker that would fail for the described violation.

| ID | Test or requirement | Required evidence and important boundary |
|---|---|---|
| IF-01 | Stream handshake | Every captured beat obeys valid/ready; no output changes while stalled. Independently vary input valid and output ready. |
| IF-02 | Input FIFOs | Fill, empty, simultaneous push/pop, full-to-pop recovery and depth 2/4. Verify registered ready and absence of combinational top input-to-output paths by structure/timing review. |
| IF-03 | Metadata | Every source and qid; duplicate tags; changing non-SOP user metadata; preservation of meaningful fields and zeroed output reserved bits. |
| LEN-01 | Length sweep | 1, 7, 8, 9, CELL_BYTES−1, CELL_BYTES, CELL_BYTES+1, MAX−1 and MAX. Compare all valid bytes and final keep. |
| LEN-02 | Multi-cell data | Distinct per-byte patterns across cell and word boundaries; no corruption or missing final partial cell. |
| LEN-03 | Single-beat commit | New head cell and descriptor fields must bypass correctly when admission and EOF service coincide. |
| ADM-01 | Basic admission | Empty pool, valid header, exact reservation and one descriptor. All selected policies/reasons match the specification. |
| ADM-02 | Cell-credit boundary | U=n, U=n−1 and same-cycle release. Admission uses pre-cycle U, not optimistic reclaimed resources. |
| ADM-03 | Descriptor exhaustion | Exhaust descriptors with short packets before cells; release descriptor at packet EOF, not queue dispatch. |
| ADM-04 | Queue limits | H[q]+n exactly at and one above limit; include receiving, queued, TX and aborted ownership in H[q]. |
| ADM-05 | DROP mode | Reject for each resource reason, drain to TLAST, emit one disposition, allocate no resources to a rejected header. |
| ADM-06 | WAIT mode | Hold a temporarily unserviceable head while other eligible inputs progress; resume after resources become available. A packet larger than its static queue cap is rejected rather than waiting forever. Document per-input HOL behavior. |
| ADM-07 | Reason priority | Make two or more predicates fail simultaneously and check the specified priority. |
| ADM-08 | Multi-input headers | Capture SOPs simultaneously on four interfaces; service/reserve in internal RR order without overbooking. |
| MEM-01 | Physical uniqueness | Live cells have unique owners; no free cell is also allocated; double-free detection cannot inflate capacity. |
| MEM-02 | Reservation equations | Check A+F=N, F=U+R and U+sum(H)=N each event batch, including multiple releases. |
| MEM-03 | Read/write ports | No more than one payload read and one payload write per cycle; no physical word collision. |
| MEM-04 | Output read credits | Buffered+outstanding responses never exceed FIFO capacity; long stalls start immediately after read bursts. Run read latency 1 and 2. |
| MEM-05 | Cell retirement | Free a cell exactly on its final accepted output beat; capture its next link before reuse. Force rapid reuse of just-returned cells. |
| MEM-06 | Descriptor returns | Coincident TX completion, abort completion and new admission; two set bits and one clear bit are merged correctly. |
| Q-01 | Basic FIFO order | Several packets per queue from different inputs; expected order follows internal valid commit, not external SOP order. |
| Q-02 | Last dequeue plus enqueue | Queue has exactly one descriptor; concurrent dequeue/enqueue must leave the new descriptor at head and tail. |
| Q-03 | Longer queue race | Concurrent enqueue/dequeue at count>1; next links, tail and count all agree with the abstract list. |
| Q-04 | Different queue updates | Enqueue one queue while dispatching another; no state update is lost or applied to the wrong queue. |
| Q-05 | Empty dequeue | Empty queue cannot dispatch, including a concurrent first commit; next-cycle visibility is explicit. |
| Q-06 | Input completion order | A short packet on one input commits before an earlier-started long packet on another input; preserve the resulting queue commit order. |
| SCH-01 | Eligible grants | No dispatch from an empty queue; descriptor/length belong to its head; no double dispatch. |
| SCH-02 | Credit discipline | Add quantum once per visit, debit packet bytes once per dispatch, freeze during TX stalls and avoid counter wrap. |
| SCH-03 | Small quantum | A large packet eventually becomes eligible after several visits; credit carries rather than resets while backlogged. |
| SCH-04 | Empty/reactivation | Deficit resets on true empty transition; same-cycle enqueue/dequeue uses merged count; later arrival cannot inherit idle credit. |
| SCH-05 | Mixed packet sizes | Saturated 64/1536-byte flows with equal and unequal quanta; compare delivered bytes, not packet counts. |
| SCH-06 | Progress | Under explicit progressing-sink assumptions, continuously backlogged queues obtain service; no lost activation. No unconditional latency claim under infinite external stalls. |
| FMT-01 | Bad headers | Invalid qid encodings and zero/oversize declared lengths; no resource allocation. |
| FMT-02 | Bad keep | Sparse/empty keep, partial nonfinal beat and wrong final mask; no partial packet reaches output. Include a first-beat error with zero allocated cells and deferred descriptor return. |
| FMT-03 | Early TLAST | Abort and reclaim an admitted packet at each representative word/cell boundary. |
| FMT-04 | Missing/late TLAST | Detect error at the expected final beat, stop writes, drain to a later TLAST; unrelated inputs progress. |
| FMT-05 | Abort concurrency | Several input aborts while normal output cells return; bounded ports, no starvation of cleanup under allowed traffic. |
| FMT-06 | Complete cleanup | After valid streams stop and bad frames drain, all cells/descriptors return and IDLE becomes true. |
| RST-01 | Reset state | RUN=0, all valid outputs low, empty queues and full pools; packet-memory contents need not be zero. |
| RST-02 | Reset in flight | Reset during RX reservation, commit/dispatch race, sink stall, outstanding RAM responses, abort cleanup and AXI-Lite responses. No stale new-epoch output. |
| CSR-01 | Register map | Reset values, capabilities, all implemented qids, unmapped/misaligned accesses and RO/WO semantics. |
| CSR-02 | Independent AW/W | AW before W, W before AW, same cycle, and long separation. No coupled-channel assumption. |
| CSR-03 | Bus backpressure | BREADY/RREADY stalls, read/write overlap, no lost response, one-outstanding transaction limits. |
| CSR-04 | Write strobes | Each byte lane, zero strobes, merged-value range checks and rejected atomic updates. |
| CSR-05 | Configuration lock | Busy disable and running configuration writes reject without changing behavior. Reconfiguration after legitimate drain succeeds. |
| CSR-06 | Statistics | Snapshot coherence, low/high read order, pre-update capture, live/shadow separation, clear restrictions and reset. |
| PAR-01 | Parameter matrix | F0/F1/I0/I1/E0/E1; counters/indices at minimum sizes; invalid elaborations rejected. |
| PERF-01 | Throughput | Saturated large packets against one-read/one-write ceiling; identify scan, metadata and boundary bubbles. |
| PERF-02 | Fairness | Complete-round/visit service accounting; distinguish dispatched from delivered bytes at finite endpoints. |
| PERF-03 | Shared capacity | Equal-capacity shared/fixed admission models; hot, uniform and adversarial queue usage. |
| PERF-04 | Implementation trade-off | Two mapped memory/pipeline configurations, same library/PVT/load conditions, functional latency accounted for. |
| AI-01 | Triage integration | Actual regression failure invokes the utility and produces a reviewable report tied to seed/config/revision; evidence and final outcome are preserved. |



## Functional coverage

Required coverage dimensions include source port, qid, length class, final keep width, number of cells, admission mode/reason, cell-credit boundary, descriptor boundary, queue pre-count, enqueue/dequeue coincidence, same/different queue, input gap, output stall duration, read latency/FIFO occupancy, DRR quantum/packet-size relationship, deficit state, empty/reactivation and reset phase.

Important crosses are:

| Cross | Purpose |
|---|---|
| Last-entry enqueue/dequeue × same queue × active TX | The principal linked-queue bypass hazard |
| Reservation size × U at n/n−1 × current release | Conservative admission and counter update |
| Cell boundary × output stall × read latency | Prefetch capacity and retirement correctness |
| Abort phase × TX cell return × new reservation | Physical/logical credit reconciliation |
| Head length greater/equal/less than deficit × queue reactivation | DRR control semantics |
| AW/W arrival order × B stall × concurrent read | Actual AXI4-Lite channel independence |
| Reset phase × outstanding read count × packet partial-cell status | Stale-response and cleanup hazards |

Do not generate the Cartesian product of every field. Each cross must correspond to a requirement or known risk, with impossible combinations marked as such. Fill critical bins deliberately before increasing random-seed count.

Completion requires every mandatory functional bin hit or accompanied by a reviewed, configuration-specific exclusion. Review line/branch/toggle/FSM holes in owned RTL and preserve exclusion reasons. Report coverage by type and configuration with raw databases and a readable summary. Coverage percentages do not substitute for requirement checking.



## Assertions and checker qualification

The simulation SVA layer MUST include held-valid stability on every stream/control channel, supported memory port counts, no payload read/write collision, queue/pool/credit bounds, legal commit/dispatch transitions, no output from uncommitted data, and invalidation of pending responses on reset.

Qualify the checking with selected, clearly labeled seeded defects. Useful mutations include last-head bypass removal, wrong counter delta on concurrent allocate/free, premature cell reuse, ignoring outstanding reads in credit accounting, adding DRR quantum per packet instead of per visit, a payload-byte corruption and coupling AW/W acceptance. The detector must fail for the right reason. Seeded defects must not be represented as independently discovered natural design bugs.
