# Registers and configuration

### Configuration lifecycle

Reset leaves RUN=0, DROP policy selected, all queue limits=N_CELL and quanta=MAX_PACKET_BYTES. Setting RUN=1 starts input acceptance after initialization. Writes to policy, limits and quanta are allowed only with RUN=0 and IDLE=1. Attempting them while running returns SLVERR with no change.

RUN may be cleared only when IDLE=1; otherwise the write returns SLVERR. To reconfigure, stop external packet generation, allow queued work to drain, observe IDLE, clear RUN, change settings and re-enable. No drain-and-clock-gate controller is implied. If external framing is broken or the sink never progresses, reset is the recovery mechanism.

IDLE means ingress FIFOs empty, no RX/drain/abort contexts, no committed queues, no TX packet/FIFO/outstanding reads, and all cells/descriptors unowned. It must not merely mean all queue counts are zero.

The internal-invariant error bit is diagnostic: it sets on a detected invalid pool return or accounting/ownership violation and clears only on reset. Verification treats any such event as a failure. Version 1 does not promise transparent recovery from an internal RTL defect or corrupted ownership state.

### Register map

All addresses are byte addresses. Unspecified bits read zero. Registers are 32-bit aligned.

| Address | Name | Access | Definition |
|---|---|---|---|
| 0x000 | ID | RO | 0x544D0100 |
| 0x004 | VERSION | RO | 0x00010000 |
| 0x008 | CAP0 | RO | [7:0] N_RX; [15:8] N_Q; [23:16] WORD_BYTES; [31:24] CELL_BYTES |
| 0x00C | CAP1 | RO | [15:0] N_CELL; [31:16] N_DESC |
| 0x010 | CTRL | RW | Bit 0 RUN; other bits ignored |
| 0x014 | STATUS | RO | Bit 0 RUN; bit 1 IDLE; bit 2 initialized; bit 3 sticky internal-invariant error |
| 0x018 | SNAPSHOT | WO | Writing bit 0 captures all statistics/high-water marks into coherent shadow registers |
| 0x01C | CLEAR_STATS | WO | Writing bit 0 clears live and shadow statistics only while disabled and idle |
| 0x020 | ADMISSION_MODE | RW | 0 DROP, 1 WAIT; other values SLVERR |
| 0x024 | FREE_CREDIT | RO | Live U |
| 0x028 | RESERVED_FREE | RO | Live R |
| 0x02C | FREE_DESC | RO | Live free descriptor count |
| 0x030 | SCHED_MODE | RO | 0 packet RR; 1 DRR |
| 0x034 | MAX_LENGTH | RO | MAX_PACKET_BYTES |
| 0x100+8k | GLOBAL_STATS[k] | RO | Low/high words of snapshot counters listed below |
| 0x400+0x40q | QUEUE[q] | Mixed | Per-queue block below; q>=N_Q returns DECERR |

Global 64-bit snapshot counters in k order are SOP_SEEN, ADMITTED_PKTS, COMMITTED_PKTS, RESOURCE_DROPS, FORMAT_DROPS, TX_PKTS, TX_BYTES, RUN_CYCLES, INPUT_STALL_CYCLES and OUTPUT_STALL_CYCLES. SOP_SEEN refers to headers serviced by the internal arbiter. Format drops count a bad header or a first format-abort detection once per packet. Input-stall cycles count a clock with at least one external input valid and not ready; they are not the sum over ports. Output stall is valid and not ready. Counters wrap modulo 2^64; there is no saturation promise.

| Queue offset | Name | Access | Meaning |
|---|---|---|---|
| 0x00 | CELL_LIMIT | RW | 1 through N_CELL; admission tests total H[q] against it |
| 0x04 | QUANTUM | RW | 64 through 4096 bytes |
| 0x08 | OWNED_CELLS | RO | Live H[q] |
| 0x0C | QUEUED_PKTS | RO | Committed descriptor-list count, excluding RX and TX |
| 0x10 | DEFICIT | RO | Live DRR deficit |
| 0x14 | HIGH_WATER | RO | Snapshot maximum H[q] |
| 0x18/1C | ADMITTED_PKTS | RO | Snapshot low/high words |
| 0x20/24 | RESOURCE_DROPS | RO | Snapshot low/high words for this valid qid |
| 0x28/2C | TX_PKTS | RO | Snapshot low/high words |
| 0x30/34 | TX_BYTES | RO | Snapshot low/high words |
| 0x38/3C | FRAME_ABORTS | RO | Snapshot low/high words for admitted malformed packets |

Snapshot captures pre-update registered state on the accepted command's execution edge. Events on that edge update the live counters afterward. Read both words from the same shadow snapshot. Live counters continue running; reads do not clear them. Reads of WO commands return zero. All high-water/statistic reads are shadow reads; resource-state reads are live.
