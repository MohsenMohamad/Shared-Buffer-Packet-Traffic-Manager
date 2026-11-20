#!/usr/bin/env python3
"""Deterministic cycle and credit study for the multi-egress datapath using packet RR."""

from argparse import ArgumentParser
from collections import Counter, deque
from dataclasses import dataclass, field
from fractions import Fraction

PORTS = 4
CELLS = 1024
DESCRIPTORS = 256
WARMUP = 2048
WINDOW = 9216
MIX = (60, 65, 1536, 64, 129, 1518, 61, 513)


def ceil_div(value, unit):
    return (value + unit - 1) // unit


@dataclass
class Frame:
    source: int
    egress: int
    traffic_class: int
    length: int
    malformed_at: int = 0
    rx: int = 0
    writes: int = 0
    issued: int = 0
    tx: int = 0
    resident: int = 0
    admitted: bool = False
    discard: bool = False
    drained: bool = False
    disposition: str = ""
    ready_cells: deque = field(default_factory=deque)

    @property
    def beats(self):
        return ceil_div(self.length, 8)

    @property
    def cells(self):
        return ceil_div(self.length, 64)


class Study:
    def __init__(self, scenario, length, latency, assembly, prefetch):
        self.scenario = scenario
        self.length = length
        self.latency = latency
        self.assembly = assembly
        self.prefetch = prefetch
        self.inputs = [deque() for _ in range(PORTS)]
        self.staged = [deque() for _ in range(PORTS)]
        self.dispositions = [deque() for _ in range(PORTS)]
        self.aborts = [None] * PORTS
        self.queues = [[deque() for _ in range(4)] for _ in range(PORTS)]
        self.output = [deque() for _ in range(PORTS)]
        self.source = [None] * PORTS
        self.source_beat = [0] * PORTS
        self.sequence = [0] * PORTS
        self.assembly_beats = [0] * PORTS
        self.q_cursor = [0] * PORTS
        self.pending = deque()
        self.publish = None
        self.cursors = dict.fromkeys(("read", "write", "abort", "admit"), 0)
        self.free = CELLS
        self.physically_free = CELLS
        self.desc_free = DESCRIPTORS
        self.reserved = 0
        self.prefetch_used = [0] * PORTS
        self.totals = [Counter() for _ in range(PORTS)]
        self.frame_counts = [Counter() for _ in range(PORTS)]
        self.peaks = Counter()
        self.read_waits = [None] * PORTS
        self.last_transfer = [None] * PORTS
        self.release_barrier = scenario == "returns"

    def rotating(self, service):
        start = self.cursors[service]
        return ((start + offset) % PORTS for offset in range(PORTS))

    def move(self, service, port):
        self.cursors[service] = (port + 1) % PORTS

    def make_frame(self, port):
        index = self.sequence[port]
        self.sequence[port] += 1
        offset = port if self.scenario == "phased" else 0
        length = self.length or MIX[(index + offset) % len(MIX)]
        egress = 0 if self.scenario.startswith("incast") else (port + 1) % PORTS
        if self.scenario == "cleanup":
            # Two long abortions compete with valid traffic and repeated returns.
            if port < 2 and index % 8 == 0:
                return Frame(port, egress, 0, 1536, 130)
        traffic_class = port if self.scenario.startswith("incast") else 0
        return Frame(port, egress, traffic_class, length)

    def choose_dispatches(self):
        selected = []
        for port, slots in enumerate(self.output):
            if len(slots) == 2 or (slots and slots[0].beats - slots[0].tx > 16):
                continue
            for offset in range(4):
                traffic_class = (self.q_cursor[port] + offset) % 4
                queue = self.queues[port][traffic_class]
                if queue:
                    selected.append((port, traffic_class, queue.popleft()))
                    self.q_cursor[port] = (traffic_class + 1) % 4
                    break
        return selected

    def choose_reads(self, cycle):
        candidates = [None] * PORTS
        for port, slots in enumerate(self.output):
            if self.prefetch_used[port] < self.prefetch:
                candidates[port] = next((frame for frame in slots
                                         if frame.issued < frame.cells), None)
        for port in range(PORTS):
            if candidates[port] is None:
                self.read_waits[port] = None
            elif self.read_waits[port] is None:
                self.read_waits[port] = cycle
        for port in self.rotating("read"):
            frame = candidates[port]
            if frame is not None:
                self.pending.append((cycle + self.latency, frame, frame.issued))
                frame.issued += 1
                self.prefetch_used[port] += 1
                self.peaks["read_delay"] = max(
                    self.peaks["read_delay"], cycle - self.read_waits[port]
                )
                self.read_waits[port] = None
                self.move("read", port)
                break

    def step(self, cycle):
        measuring = WARMUP <= cycle < WARMUP + WINDOW
        offered = cycle < WARMUP + WINDOW
        # Decide from pre-edge queues, staging, credits and output slots.
        dispatches = self.choose_dispatches()
        ready_writes = sum(bool(staged) for staged in self.staged)
        published, self.publish = self.publish, None
        write_port = next((p for p in self.rotating("write") if self.staged[p]), None)
        abort_port = next((p for p in self.rotating("abort") if self.aborts[p]), None)
        capture_space = [len(fifo) < 2 for fifo in self.inputs]
        if self.release_barrier and cycle >= 64 and all(
            slots and slots[0].ready_cells and slots[0].tx + 1 == slots[0].beats
            for slots in self.output
        ):
            self.release_barrier = False
        self.choose_reads(cycle)
        ingress_space = [
            len(self.staged[p]) + bool(self.assembly_beats[p]) < self.assembly
            or bool(self.assembly_beats[p]) or write_port == p
            for p in range(PORTS)
        ]

        # RX service and any prefix-ordered, bundled reservation consume old credit.
        drops = admits = 0
        first_decision = None
        for port in self.rotating("admit"):
            statuses = self.dispositions[port]
            if statuses and statuses[0].disposition:
                statuses.popleft()
            fifo = self.inputs[port]
            if not fifo:
                continue
            frame = fifo[0]
            if frame.rx == 0:
                if self.aborts[port] or not ingress_space[port] or len(statuses) == 8:
                    continue
                if frame.cells > self.free or self.desc_free == 0:
                    if self.scenario == "incast-wait":
                        continue
                    frame.discard = True
                    drops += 1
                    frame.disposition = "drop"
                    self.frame_counts[port]["drop"] += 1
                    if measuring:
                        reason = "desc_drops" if self.desc_free == 0 else "cell_drops"
                        self.totals[port][reason] += 1
                else:
                    self.free -= frame.cells
                    self.reserved += frame.cells
                    self.desc_free -= 1
                    frame.admitted = True
                    admits += 1
                statuses.append(frame)
                if first_decision is None:
                    first_decision = port
            if not frame.discard and not ingress_space[port]:
                continue
            fifo.popleft()
            frame.rx += 1
            if frame.admitted and frame.rx == frame.malformed_at:
                frame.discard = True
                self.aborts[port] = frame
                self.assembly_beats[port] = 0
                if measuring:
                    self.totals[port]["aborted"] += 1
            if not frame.discard:
                self.assembly_beats[port] += 1
                if self.assembly_beats[port] == 8 or frame.rx == frame.beats:
                    self.staged[port].append((frame, cycle))
                    self.assembly_beats[port] = 0
            frame.drained = frame.rx == frame.beats
        if first_decision is not None:
            self.move("admit", first_decision)

        if write_port is not None:
            frame, staged_at = self.staged[write_port].popleft()
            self.peaks["write_delay"] = max(self.peaks["write_delay"], cycle - staged_at)
            assert self.physically_free > 0 and self.reserved > 0
            self.physically_free -= 1
            self.reserved -= 1
            frame.resident += 1
            frame.writes += 1
            if frame.writes == frame.cells:
                assert frame.drained and not frame.discard
                self.publish = frame
            self.move("write", write_port)
        for port, abort in enumerate(self.aborts):
            if abort:
                self.staged[port] = deque(item for item in self.staged[port] if item[0] is not abort)

        # Retire only cells whose last valid beat transfers on this edge.
        returns = desc_returns = 0
        for port, slots in enumerate(self.output):
            stats = self.totals[port]
            ready = not (self.scenario == "stall" and port == 0 and 32 <= cycle % 256 < 64)
            frame = slots[0] if slots else None
            if self.release_barrier and frame and frame.tx + 1 == frame.beats:
                ready = False
            if measuring:
                stats["sink_stall"] += not ready
            if frame is None or not frame.ready_cells or not ready:
                if measuring and ready:
                    stats["tx_idle"] += 1
                    stats["read_starve"] += frame is not None
                continue
            assert frame.ready_cells[0][0] == frame.tx // 8
            if frame.tx % 8 == 0 and self.last_transfer[port] is not None:
                ready_at = frame.ready_cells[0][1]
                continuous_deadline = self.last_transfer[port] + 1
                margin = continuous_deadline - ready_at
                if measuring:
                    key = ("min_interframe_margin" if frame.tx == 0
                           else "min_within_frame_margin")
                    self.peaks[key] = min(self.peaks.get(key, margin), margin)
            self.last_transfer[port] = cycle
            if measuring:
                stats["tx_beats"] += 1
                stats["tx_bytes"] += min(8, frame.length - 8 * frame.tx)
            frame.tx += 1
            if frame.tx % 8 == 0 or frame.tx == frame.beats:
                frame.ready_cells.popleft()
                self.prefetch_used[port] -= 1
                frame.resident -= 1
                returns += 1
            if frame.tx == frame.beats:
                assert frame.resident == 0
                slots.popleft()
                desc_returns += 1
                self.frame_counts[frame.source]["tx"] += 1
                if measuring:
                    stats["tx_frames"] += 1

        abort_cell_return = False
        if abort_port is not None:
            abort = self.aborts[abort_port]
            if abort.resident:
                abort_cell_return = True
                abort.resident -= 1
                self.physically_free += 1
                self.reserved += 1
            if not abort.resident:
                self.reserved -= abort.cells
                self.free += abort.cells
                desc_returns += 1
                abort.disposition = "abort"
                self.frame_counts[abort.source]["abort"] += 1
                self.aborts[abort_port] = None
            self.move("abort", abort_port)
        self.physically_free += returns
        self.free += returns
        self.desc_free += desc_returns

        for port, traffic_class, frame in dispatches:
            self.output[port].append(frame)
        if published:
            self.queues[published.egress][published.traffic_class].append(published)
            published.disposition = "commit"
            self.frame_counts[published.source]["commit"] += 1
            if measuring:
                self.totals[published.source]["commits"] += 1
        if self.pending and self.pending[0][0] == cycle:
            _, frame, cell = self.pending.popleft()
            frame.ready_cells.append((cell, cycle + 1))

        for port in range(PORTS):
            if self.source[port] is None:
                if not offered:
                    continue
                self.source[port] = self.make_frame(port)
            frame = self.source[port]
            if not capture_space[port]:
                if measuring:
                    self.totals[port]["rx_stall"] += 1
                continue
            self.inputs[port].append(frame)
            if measuring:
                stats = self.totals[port]
                stats["rx_beats"] += 1
                stats["rx_bytes"] += min(8, frame.length - 8 * self.source_beat[port])
            self.source_beat[port] += 1
            if self.source_beat[port] == frame.beats:
                self.source[port] = None
                self.source_beat[port] = 0
                self.frame_counts[port]["rx"] += 1
                if measuring:
                    self.totals[port]["rx_frames"] += 1

        assert self.free + self.reserved == self.physically_free <= CELLS
        assert min(self.free, self.reserved, self.desc_free) >= 0
        assert self.desc_free <= DESCRIPTORS
        assert all(len(fifo) <= 2 for fifo in self.inputs)
        staged = [
            len(self.staged[p]) + bool(self.assembly_beats[p]) for p in range(PORTS)
        ]
        assert max(staged) <= self.assembly
        assert max(self.prefetch_used) <= self.prefetch
        assert all(len(slots) <= 2 for slots in self.output)
        self.peaks["assembly"] = max(self.peaks["assembly"], max(staged))
        self.peaks["prefetch"] = max(self.peaks["prefetch"], max(self.prefetch_used))
        self.peaks["dispositions"] = max(self.peaks["dispositions"],
                                         max(map(len, self.dispositions)))
        self.peaks["outstanding"] = max(self.peaks["outstanding"], len(self.pending))
        self.peaks["cell_credit"] = max(self.peaks["cell_credit"], CELLS - self.free)
        self.peaks["physical"] = max(self.peaks["physical"], CELLS - self.physically_free)
        self.peaks["descriptors"] = max(self.peaks["descriptors"], DESCRIPTORS - self.desc_free)
        self.peaks["ready_writes"] = max(self.peaks["ready_writes"], ready_writes)
        self.peaks["admissions"] = max(self.peaks["admissions"], admits)
        self.peaks["drops"] = max(self.peaks["drops"], drops)
        self.peaks["dispatches"] = max(self.peaks["dispatches"], len(dispatches))
        self.peaks["tx_cell_returns"] = max(self.peaks["tx_cell_returns"], returns)
        self.peaks["desc_returns"] = max(self.peaks["desc_returns"], desc_returns)
        self.peaks["cleanup"] = max(self.peaks["cleanup"], sum(a is not None for a in self.aborts))
        if abort_cell_return:
            self.peaks["cleanup_plus_tx_returns"] = max(
                self.peaks["cleanup_plus_tx_returns"], returns
            )
        self.peaks["queue_depth"] = max(
            self.peaks["queue_depth"], max(len(q) for queues in self.queues for q in queues)
        )

    def run(self):
        for cycle in range(WARMUP + WINDOW + 2 * CELLS * 8):
            self.step(cycle)
            if cycle >= WARMUP + WINDOW and self.desc_free == DESCRIPTORS and not (
                any(self.inputs) or any(self.source) or any(self.dispositions)
            ):
                assert self.free == CELLS and not self.pending
                break
        else:
            raise AssertionError("did not drain")
        print(f"{self.scenario} length={self.length or 'mix'} L={self.latency} "
              f"A={self.assembly} P={self.prefetch}")
        keys = ("rx_beats", "tx_beats", "rx_bytes", "tx_bytes", "rx_frames", "commits",
                "tx_frames", "rx_stall", "tx_idle", "read_starve", "sink_stall",
                "desc_drops", "cell_drops", "aborted")
        print("  " + " ".join(f"{key}=" + "/".join(str(p[key]) for p in self.totals)
                              for key in keys))
        print("  " + " ".join(f"{key}={value}" for key, value in sorted(self.peaks.items())))
        for counts in self.frame_counts:
            assert counts["rx"] == counts["drop"] + counts["abort"] + counts["commit"]
            assert counts["commit"] == counts["tx"]
        print("  after drain " + " ".join(
            f"{key}=" + "/".join(str(counts[key]) for counts in self.frame_counts)
            for key in ("rx", "drop", "abort", "commit", "tx")
        ))
        return all(p["rx_beats"] == p["tx_beats"] == WINDOW
                   for p in self.totals) and all(not (c["drop"] or c["abort"])
                                               for c in self.frame_counts)


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--assembly", type=int, default=4)
    parser.add_argument("--prefetch", type=int, default=6)
    parser.add_argument("--latency", type=int, choices=(1, 2))
    parser.add_argument("--case", choices=("all", "balanced", "phased", "stall", "incast-drop",
                                          "incast-wait", "returns", "cleanup"), default="all")
    parser.add_argument("--expect-gate", action="store_true")
    options = parser.parse_args()
    if options.assembly < 1 or options.prefetch < 1:
        parser.error("assembly and prefetch depths must be positive")
    demand = [Fraction(PORTS * ceil_div(length, 64), ceil_div(length, 8))
              for length in range(60, 1537)]
    worst = max(demand)
    peak_lengths = [length for length, rate in enumerate(demand, 60) if rate == worst]
    print(f"warmup={WARMUP} window={WINDOW} max_sustained={worst} "
          f"at {peak_lengths[0]}–{peak_lengths[-1]} bytes")
    cases = {
        "balanced": (60, 65, 1536, 0),
        "phased": (0,),
        "stall": (0,),
        "incast-drop": (60, 1536),
        "incast-wait": (60,),
        "returns": (60,),
        "cleanup": (65,),
    }
    passed = True
    for latency in (options.latency,) if options.latency else (1, 2):
        for scenario, lengths in cases.items():
            if options.case not in ("all", scenario):
                continue
            for length in lengths:
                study = Study(scenario, length, latency, options.assembly, options.prefetch)
                gate = study.run()
                if scenario == "balanced":
                    passed &= gate
                if (options.assembly, options.prefetch) == (4, 6):
                    if scenario == "phased":
                        assert gate
                    if scenario == "stall":
                        assert [p["tx_beats"] for p in study.totals] == [8064] + [WINDOW] * 3
                    if scenario.startswith("incast"):
                        assert study.totals[0]["tx_beats"] == WINDOW
                        assert not any(p["tx_beats"] for p in study.totals[1:])
                    if scenario == "incast-wait":
                        assert all(not p["drop"] for p in study.frame_counts)
                        assert all(p["rx_stall"] for p in study.totals)
                    if scenario == "incast-drop":
                        cause = "desc_drops" if length == 60 else "cell_drops"
                        assert all(p[cause] and not p["rx_stall"] for p in study.totals)
                    if scenario == "returns":
                        assert study.peaks["dispatches"] == study.peaks["tx_cell_returns"] == 4
                        assert study.peaks["desc_returns"] == 4
                    if scenario == "cleanup":
                        assert study.peaks["cleanup"] == 2
                        assert study.peaks["cleanup_plus_tx_returns"] > 0
                        assert study.totals[0]["tx_beats"] == study.totals[3]["tx_beats"] == WINDOW
    if options.case in ("all", "balanced"):
        print(f"balanced gate {'PASS' if passed else 'MISS'}")
        if options.expect_gate and not passed:
            raise SystemExit(1)


if __name__ == "__main__":
    main()
