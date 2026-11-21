#!/usr/bin/env python3
"""Finite edge-level experiment for the published multi-egress control paths."""
from argparse import ArgumentParser
from collections import Counter, deque
from dataclasses import dataclass, field
import json
from pathlib import Path
import random

from multi_egress_feasibility import MIX, WARMUP, WINDOW, ceil_div

RESULTS = ("BAD_ROUTE", "BAD_LENGTH", "QUEUE_LIMIT", "NO_DESCRIPTOR", "NO_CELLS",
           "FRAME_ERROR", "COMMITTED")
RANDOM_LENGTHS = (60, 64, 65, 72, 129, 1536)
SMALL_MIX = (60, 65, 192, 64, 129, 190, 61, 113)
CASES = {
    "balanced": (60, 65, 1536, 0),
    "independent": (0,),
    "stall": (0,),
    "incast-drop": (60, 1536),
    "incast-wait": (60,),
    "returns": (60,),
    "cleanup": (65,),
}
VARIANTS = ("direct", "cached", "registered-request")
UNIT = 1 << 16


@dataclass(frozen=True)
class Profile:
    ports: int
    cells: int
    descriptors: int
    maximum: int


PROFILES = {"primary": Profile(4, 1024, 256, 1536), "small": Profile(2, 16, 8, 192)}


@dataclass(eq=False)
class Frame:
    port: int
    sequence: int
    egress: int
    cls: int
    length: int
    malformed_at: int = 0
    wire_length: int = 0
    rx: int = 0
    tx: int = 0
    desc: int | None = None
    state: str = "input"
    first: int | None = None
    tail: int | None = None
    written: int = 0
    assigned: int = 0
    credit: int = 0
    read_next: int | None = None
    unread: int = 0
    abort_next: int | None = None
    outcome: str = ""
    ready: deque = field(default_factory=deque)
    times: dict = field(default_factory=dict)
    ecn: int = 0
    mark: bool = False

    @property
    def identity(self):
        return [self.port, self.sequence]

    @property
    def qid(self):
        return 4 * self.egress + self.cls

    @property
    def beats(self):
        return ceil_div(self.length, 8)

    @property
    def offered_beats(self):
        return ceil_div(self.wire_length or self.length, 8)

    @property
    def cells(self):
        return ceil_div(self.length, 64)

    def metadata(self):
        return Head(self.desc, self.first, self.cells, self.length, self.port,
                    self.sequence, self.ecn, self.mark)


@dataclass(frozen=True)
class Head:
    desc: int
    first: int
    cells: int
    length: int
    ingress: int
    sequence: int
    ecn: int
    mark: bool


@dataclass
class Bucket:
    balance: int
    refill: int
    capacity: int

    def fits(self, length):
        return self.balance >= length * UNIT

    def advance(self, debit):
        assert self.fits(debit)
        self.balance = min(self.capacity, self.balance - debit * UNIT + self.refill)


class Pool:
    def __init__(self, capacity):
        self.capacity = capacity
        self.free = (1 << capacity) - 1
        self.owner = {}

    def take(self, frame, address=None):
        assert self.free, "pool exhausted"
        if address is None:
            address = (self.free & -self.free).bit_length() - 1
        flag = 1 << address
        assert self.free & flag, "allocated ID was not pre-edge free"
        self.free ^= flag
        self.owner[address] = frame
        return address

    def give(self, address, frame):
        assert self.owner.get(address) is frame, "return owner mismatch"
        del self.owner[address]
        self.free |= 1 << address


class Control:
    def __init__(self, profile, latency=1, variant="direct", trace=False):
        self.profile = profile
        self.ports = profile.ports
        self.queues = self.ports * 4
        self.latency = latency
        self.variant = variant
        self.record = trace
        self.reset()

    def reset(self):
        # The model cancels response validity on reset. Stale array data is unreachable.
        self.cycle = 0
        self.desc = Pool(self.profile.descriptors)
        self.cell = Pool(self.profile.cells)
        self.credit = self.profile.cells
        self.h = [0] * self.queues
        self.minimum = [0] * self.queues
        self.alpha = [0] * self.queues
        self.limit = [self.profile.cells] * self.queues
        self.dynamic = self.wait = False
        self.head = [None] * self.queues
        self.tail = [None] * self.queues
        self.bitmap = 0
        self.depth = [0] * self.queues
        self.cache = [None] * self.queues
        self.info = [None] * self.profile.descriptors
        self.queue_next = [None] * self.profile.descriptors
        self.cell_next = [None] * self.profile.cells
        self.capture = [deque() for _ in range(self.ports)]
        self.stage = [deque() for _ in range(self.ports)]
        self.assembly = [0] * self.ports
        self.status = [deque() for _ in range(self.ports)]
        self.abort = [None] * self.ports
        self.publish_slot = None
        self.slots = [deque() for _ in range(self.ports)]
        self.prefetch = [0] * self.ports
        self.responses = deque()
        self.cursors = dict.fromkeys(("read", "write", "abort", "admit"), 0)
        self.q_cursor = [0] * self.ports
        self.mode = ["rr"] * self.ports
        self.strict = [0] * self.ports
        self.open_visit = [False] * self.queues
        self.deficit = [0] * self.queues
        self.quantum = [self.profile.maximum] * self.queues
        self.queue_bucket = [None] * self.queues
        self.port_bucket = [None] * self.ports
        self.ecn_threshold = [None] * self.queues
        self.read_since = [None] * self.ports
        self.last_transfer = [None] * self.ports
        self.previous_final = [None] * self.ports
        self.events = {}
        self.trace = []
        self.peaks = Counter()

    def emit(self, kind, frame, **fields):
        if self.record:
            self.events.setdefault(kind, []).append(dict(frame=frame.identity, **fields))

    def rotating(self, lane):
        return ((self.cursors[lane] + i) % self.ports for i in range(self.ports))

    def move(self, lane, port):
        self.cursors[lane] = (port + 1) % self.ports

    def queue_test(self, qid, n, credit, held, protected):
        if not self.dynamic:
            return held + n <= self.limit[qid], {}
        minimum = self.minimum[qid]
        excess = max(0, held - minimum)
        next_excess = max(0, held + n - minimum)
        spill = next_excess - excess
        shared = credit - protected - spill
        threshold = self.alpha[qid] * max(0, shared) // 256
        return (spill == 0 or shared >= 0 and next_excess <= threshold,
                dict(shared=shared, threshold=threshold, excess=next_excess))

    def decide(self, f, protected):
        if not (0 <= f.egress < self.ports and 0 <= f.cls < 4):
            return "BAD_ROUTE", {}
        if not 60 <= f.length <= self.profile.maximum:
            return "BAD_LENGTH", {}
        if not self.queue_test(f.qid, f.cells, self.profile.cells, 0, sum(self.minimum))[0]:
            return "QUEUE_LIMIT", {"permanent": True}
        if not self.desc.free:
            return "NO_DESCRIPTOR", {}
        if f.cells > self.credit:
            return "NO_CELLS", {}
        fits, detail = self.queue_test(f.qid, f.cells, self.credit, self.h[f.qid], protected)
        return ("" if fits else "QUEUE_LIMIT"), detail

    def reserve(self, f, address=None):
        f.desc = self.desc.take(f, address)
        f.state = "rx"
        f.credit = f.cells
        self.credit -= f.cells
        self.h[f.qid] += f.cells

    def eligible_heads(self, port):
        heads = {}
        for cls in range(4):
            qid = 4 * port + cls
            desc = self.head[qid]
            if desc is None:
                continue
            info = self.info[desc] if self.variant == "direct" else self.cache[qid]
            assert info is not None and info.desc == desc, "head metadata is stale"
            if all(bucket is None or bucket.fits(info.length)
                   for bucket in (self.port_bucket[port], self.queue_bucket[qid])):
                heads[cls] = info
        return heads

    def dispatches(self):
        selected = []
        visit_updates = []
        for port, slots in enumerate(self.slots):
            if len(slots) == 2 or slots and slots[0].beats - slots[0].tx > 16:
                continue
            eligible = self.eligible_heads(port)
            order = [(self.q_cursor[port] + offset) % 4 for offset in range(4)]
            mode = self.mode[port]
            cls = self.strict[port]
            strict = mode == "strict" and cls in eligible
            if not strict:
                cls = next((c for c in order if c in eligible), None)
            if cls is None:
                qid = 4 * port + order[0]
                if mode != "rr" and self.open_visit[qid]:
                    self.q_cursor[port] = (order[0] + 1) % 4
                continue
            qid = 4 * port + cls
            info = eligible[cls]
            if mode != "rr" and not strict:
                if not self.open_visit[qid]:
                    self.deficit[qid] += self.quantum[qid]
                    self.open_visit[qid] = True
                if self.deficit[qid] < info.length:
                    self.open_visit[qid] = False
                    self.q_cursor[port] = (cls + 1) % 4
                    continue
                self.deficit[qid] -= info.length
                visit_updates.append(qid)
            if mode == "rr":
                self.q_cursor[port] = (cls + 1) % 4
            selected.append((port, qid, info))
        return selected, visit_updates

    def read(self):
        candidates = [None] * self.ports
        for port, slots in enumerate(self.slots):
            if self.prefetch[port] < 6:
                first_unread = next((f for f in slots if f.unread), None)
                if first_unread and self.cycle >= first_unread.times["dispatch"] + (
                    2 if self.variant == "registered-request" else 1
                ):
                    candidates[port] = first_unread
            f = candidates[port]
            if f is None:
                self.read_since[port] = None
            else:
                if self.read_since[port] is None:
                    self.read_since[port] = self.cycle
                if f.unread == f.cells:
                    f.times.setdefault("request", self.cycle)
        for port in self.rotating("read"):
            f = candidates[port]
            if f is None:
                continue
            address = f.read_next
            assert self.cell.owner[address] is f
            assert f.unread > 0
            successor = self.cell_next[address] if f.unread > 1 else None
            assert successor is None or self.cell.owner[successor] is f
            index = f.cells - f.unread
            f.read_next = successor
            f.unread -= 1
            self.prefetch[port] += 1
            self.responses.append((self.cycle + self.latency, f, index, address))
            if index == 0:
                f.times["issue"] = self.cycle
            self.emit("issue", f, cell=address, index=index, next=successor)
            wait = self.cycle - self.read_since[port]
            assert wait < self.ports, "continuously eligible read exceeded RR bound"
            self.peaks["read_wait"] = max(self.peaks["read_wait"], wait)
            self.read_since[port] = None
            self.move("read", port)
            return address
        return None

    def service_ingress(self, write_port, statistics):
        protected = sum(max(0, minimum - held) for minimum, held in zip(self.minimum, self.h))
        first = None
        admits = 0
        for port in self.rotating("admit"):
            if self.status[port] and self.status[port][0].outcome:
                f = self.status[port].popleft()
                self.emit("disposition", f, code=f.outcome)
            if not self.capture[port]:
                continue
            f, beat = self.capture[port][0]
            space = (len(self.stage[port]) < 4 or self.assembly[port] or write_port == port)
            if beat == 1:
                if self.abort[port] or len(self.status[port]) >= 8 or not space:
                    continue
                reason, detail = self.decide(f, protected)
                pending = reason in ("NO_CELLS", "NO_DESCRIPTOR", "QUEUE_LIMIT") and not detail.get("permanent")
                if self.wait and pending:
                    statistics[port]["wait_" + reason] += 1
                    self.emit("admission", f, result="WAIT", reason=reason, **detail)
                    continue
                if first is None:
                    first = port
                self.status[port].append(f)
                if reason:
                    f.state = "discard"
                    self.outcome(f, reason, statistics)
                else:
                    consumed = min(f.cells, max(0, self.minimum[f.qid] - self.h[f.qid]))
                    protected -= consumed
                    self.reserve(f)
                    admits += 1
                self.emit("admission", f, result="DROP" if reason else "GRANT", reason=reason,
                          desc=f.desc, **detail)
            if f.state == "rx" and not space:
                continue
            self.capture[port].popleft()
            f.rx += 1
            assert f.rx == beat
            if f.state == "rx":
                if (beat == f.malformed_at or (beat == f.beats) != (beat == f.offered_beats)):
                    f.state = "abort"
                    self.abort[port] = f
                    f.abort_next = f.first
                    f.times["mark"] = self.cycle
                    self.assembly[port] = 0
                    self.emit("abort_mark", f, assigned=f.assigned)
                else:
                    self.assembly[port] += 1
                    if self.assembly[port] == 8 or beat == f.beats:
                        self.stage[port].append((f, self.cycle))
                        self.assembly[port] = 0
            self.emit("service", f, beat=beat, discard=f.state != "rx")
        if first is not None:
            self.move("admit", first)
        self.peaks["admissions"] = max(self.peaks["admissions"], admits)

    def outcome(self, frame, code, stats):
        assert not frame.outcome
        frame.outcome = code
        stats[frame.port][code] += 1

    def write(self, port, reading):
        if port is None:
            return
        f, staged = self.stage[port].popleft()
        address = self.cell.take(f)
        assert address != reading
        assert f.assigned < f.credit
        self.cell_next[address] = None
        if f.tail is None:
            f.first = address
            if f.state == "abort":
                f.abort_next = address
        else:
            assert self.cell.owner[f.tail] is f and f.tail != reading
            self.cell_next[f.tail] = address
        f.tail = address
        f.written += 1
        f.assigned += 1
        final = f.written == f.cells
        if final:
            assert f.state == "rx" and f.rx == f.beats and self.publish_slot is None
            self.publish_slot = f
            f.times["final_write"] = self.cycle
        self.move("write", port)
        self.peaks["write_delay"] = max(self.peaks["write_delay"], self.cycle - staged)
        self.emit("write", f, cell=address, final=final)

    def release_credit(self, f, count):
        f.credit -= count
        self.credit += count
        self.h[f.qid] -= count

    def return_cell(self, f, address, lane):
        self.cell.give(address, f)
        f.assigned -= 1
        self.cell_returns += 1
        self.emit("cell_return", f, cell=address, lane=lane)

    def return_desc(self, f, lane):
        assert f.assigned == f.credit == 0
        self.desc.give(f.desc, f)
        self.desc_returns += 1
        self.emit("desc_return", f, desc=f.desc, lane=lane)

    def retire(self, ready, stats):
        for port, slots in enumerate(self.slots):
            f = slots[0] if slots else None
            valid = bool(f and f.ready)
            stats[port]["sink_unready"] += not ready[port]
            stats[port]["tx_blocked"] += valid and not ready[port]
            if not ready[port]:
                continue
            if not valid:
                stats[port]["tx_idle"] += 1
                stats[port]["no_bound_head" if f is None else "pending_prefetch"] += 1
                continue
            index, address = f.ready[0]
            assert index == f.tx // 8 and self.cell.owner[address] is f
            if f.tx == 0:
                f.times["first"] = self.cycle
                assert self.cycle >= f.times["eligible"], "first beat before response visibility"
            amount = min(8, f.length - 8 * f.tx)
            stats[port]["tx_beats"] += 1
            stats[port]["tx_bytes"] += amount
            f.tx += 1
            self.last_transfer[port] = self.cycle
            final = f.tx == f.beats
            cell_last = f.tx % 8 == 0 or final
            self.emit("transfer", f, port=port, cell=address, beat=f.tx, bytes=amount,
                      cell_last=cell_last, final=final)
            if cell_last:
                f.ready.popleft()
                self.prefetch[port] -= 1
                self.return_cell(f, address, port)
                self.release_credit(f, 1)
            if final:
                self.return_desc(f, port)
                slots.popleft()
                f.state = "retired"
                stats[port]["tx_frames"] += 1
                stats[f.port]["delivered"] += 1
                stats[f.port]["delivered_bytes"] += f.length
                self.previous_final[port] = self.cycle

    def cleanup(self, port, stats):
        if port is None:
            return
        f = self.abort[port]
        assert self.cycle > f.times["mark"], "cleanup on marking edge"
        address = f.abort_next
        if f.assigned:
            assert address is not None and self.cell.owner[address] is f
            successor = self.cell_next[address] if f.assigned > 1 else None
            assert successor is None or self.cell.owner[successor] is f
            f.abort_next = successor
            self.return_cell(f, address, self.ports)
        done = not f.assigned
        released = f.credit if done else 0
        self.emit("cleanup", f, port=port, cell=address, done=done, released=released)
        if done:
            self.release_credit(f, released)
            self.return_desc(f, self.ports)
            self.outcome(f, "FRAME_ERROR", stats)
            f.state = "discard"
            self.abort[port] = None
        self.move("abort", port)

    def update_queues(self, published, mark, selected, visit_updates, stats):
        queue_debit = {}
        port_debit = {}
        for port, qid, info in selected:
            f = self.desc.owner[info.desc]
            assert self.head[qid] == info.desc and f.state == "queued"
            old_next = self.queue_next[info.desc] if self.depth[qid] > 1 else None
            self.head[qid] = old_next
            self.depth[qid] -= 1
            if old_next is None:
                self.tail[qid] = None
                self.bitmap &= ~(1 << qid)
                self.cache[qid] = None
            elif self.variant != "direct":
                self.cache[qid] = self.info[old_next]
            self.queue_next[info.desc] = None
            f.state = "tx"
            f.times["dispatch"] = self.cycle
            f.read_next, f.unread = info.first, info.cells
            self.slots[port].append(f)
            queue_debit[qid] = port_debit[port] = info.length
            self.emit("dispatch", f, qid=qid, desc=info.desc, old_next=old_next,
                      length=info.length, first=info.first)
        if published:
            f = published
            qid = f.qid
            f.state = "queued"
            f.times["publication"] = self.cycle
            f.mark = mark
            self.info[f.desc] = f.metadata()
            if self.tail[qid] is None:
                self.head[qid] = f.desc
                if self.variant != "direct":
                    self.cache[qid] = self.info[f.desc]
            else:
                self.queue_next[self.tail[qid]] = f.desc
            self.queue_next[f.desc] = None
            self.tail[qid] = f.desc
            self.bitmap |= 1 << qid
            self.depth[qid] += 1
            self.outcome(f, "COMMITTED", stats)
            self.emit("publication", f, desc=f.desc, qid=qid, first=f.first, mark=f.mark)
        for qid in visit_updates:
            if self.depth[qid]:
                self.q_cursor[qid // 4] = qid % 4
            else:
                self.q_cursor[qid // 4] = (qid + 1) % 4
        for qid in range(self.queues):
            if not self.depth[qid]:
                self.deficit[qid] = 0
                self.open_visit[qid] = False
            bucket = self.queue_bucket[qid]
            if bucket:
                bucket.advance(queue_debit.get(qid, 0))
        for port, bucket in enumerate(self.port_bucket):
            if bucket:
                bucket.advance(port_debit.get(port, 0))

    def response(self):
        if self.responses and self.responses[0][0] == self.cycle:
            _, f, index, address = self.responses.popleft()
            assert self.cell.owner[address] is f and f.state == "tx"
            f.ready.append((index, address))
            if index == 0:
                f.times.update(response=self.cycle, eligible=self.cycle + 1)
                assert f.times["issue"] + self.latency == self.cycle
            self.emit("response", f, cell=address, index=index, visible=self.cycle + 1)

    def audit(self):
        assigned = len(self.cell.owner)
        reserved = sum(f.credit - f.assigned for f in self.desc.owner.values())
        assert self.profile.cells == assigned + self.credit + reserved == self.credit + sum(self.h)
        assert self.cell.free.bit_count() + assigned == self.profile.cells
        assert self.desc.free.bit_count() + len(self.desc.owner) == self.profile.descriptors
        assert all(0 <= f.assigned <= f.credit for f in self.desc.owner.values())
        assert sum(f.assigned for f in self.desc.owner.values()) == assigned
        assert 0 <= self.credit <= self.profile.cells and min(self.h) >= 0
        assert sum(self.prefetch) == len(self.responses) + sum(
            len(f.ready) for slots in self.slots for f in slots)
        assert max(self.prefetch) <= 6 and min(self.prefetch) >= 0
        assert self.bitmap == sum(1 << qid for qid, head in enumerate(self.head) if head is not None)
        assert all(bool(n) == (h is not None) == (t is not None)
                   for n, h, t in zip(self.depth, self.head, self.tail))
        if self.record:
            physical = Counter(self.cell.owner.values())
            held = Counter()
            for address, f in self.desc.owner.items():
                assert f.desc == address and f.assigned == physical[f]
                held[f.qid] += f.credit
            assert self.h == [held[qid] for qid in range(self.queues)]
            for qid, head in enumerate(self.head):
                for index in range(self.depth[qid]):
                    f = self.desc.owner[head]
                    assert f.qid == qid and f.state == "queued"
                    if index == self.depth[qid] - 1:
                        assert head == self.tail[qid]
                    head = self.queue_next[head]
                assert head is None
        return assigned

    def step(self, offers=None, ready=None, stats=None):
        if offers is None:
            offers = [None] * self.ports
        if ready is None:
            ready = [True] * self.ports
        if stats is None:
            stats = [Counter() for _ in range(self.ports)]
        self.events = {}
        self.desc_returns = self.cell_returns = 0
        capture_space = [len(fifo) < 2 for fifo in self.capture]
        write_port = next((p for p in self.rotating("write") if self.stage[p]), None)
        abort_port = next((p for p in self.rotating("abort") if self.abort[p]), None)
        published = self.publish_slot
        self.publish_slot = None
        mark = False
        if published:
            threshold = self.ecn_threshold[published.qid]
            mark = threshold is not None and self.h[published.qid] >= threshold and published.ecn in (1, 2)
        selected, visit_updates = self.dispatches()
        reading = self.read()
        self.service_ingress(write_port, stats)
        self.write(write_port, reading)
        for port, abort in enumerate(self.abort):
            if abort:
                self.stage[port] = deque(item for item in self.stage[port] if item[0] is not abort)
        self.retire(ready, stats)
        tx_returns = self.cell_returns
        self.cleanup(abort_port, stats)
        self.update_queues(published, mark, selected, visit_updates, stats)
        self.response()
        accepted = []
        for port, offer in enumerate(offers):
            if offer is None or not capture_space[port]:
                stats[port]["rx_stall"] += offer is not None
                accepted.append(False)
                continue
            f, beat = offer
            self.capture[port].append(offer)
            stats[port]["rx_beats"] += 1
            amount = min(8, (f.wire_length or f.length) - 8 * (beat - 1))
            stats[port]["rx_bytes"] += amount - (beat == f.malformed_at)
            if beat == f.offered_beats:
                stats[port]["rx_frames"] += 1
            accepted.append(True)
        assigned = self.audit()
        staging = [len(self.stage[p]) + bool(self.assembly[p]) for p in range(self.ports)]
        assert max(staging) <= 4 and max(map(len, self.slots)) <= 2
        assert max(map(len, self.capture)) <= 2 and max(map(len, self.status)) <= 8
        peaks = dict(staging=max(staging), prefetch=max(self.prefetch), responses=len(self.responses),
                     descriptors=len(self.desc.owner), physical=assigned,
                     reserved_credit=self.profile.cells - self.credit, queue_depth=max(self.depth),
                     dispatch=len(selected), cell_returns=self.cell_returns, tx_cell_returns=tx_returns,
                     desc_returns=self.desc_returns, aborts=sum(f is not None for f in self.abort))
        if self.cell_returns > tx_returns:
            peaks["cleanup_with_tx"] = tx_returns
        for key, value in peaks.items():
            self.peaks[key] = max(self.peaks[key], value)
        if self.record:
            self.trace.append(dict(edge=self.cycle, events=self.events, head=self.head.copy(),
                                   tail=self.tail.copy(), bitmap=self.bitmap, U=self.credit,
                                   H=self.h.copy(), D=self.desc.free.bit_count(),
                                   physical=assigned, prefetch=self.prefetch.copy()))
        self.cycle += 1
        return accepted

    def idle(self):
        return not (self.desc.owner or any(self.capture) or any(self.status) or self.responses
                    or any(self.stage) or self.publish_slot or any(self.abort) or any(self.slots))


def replay(profile_name, latency, variant, scenario, length):
    profile = PROFILES[profile_name]
    tm = Control(profile, latency, variant)
    tm.wait = scenario == "incast-wait"
    ports = profile.ports
    source = [None] * ports
    offer_index = [1] * ports
    sequences = [0] * ports
    rng = [random.Random(104729 + port) for port in range(ports)]
    window = [Counter() for _ in range(ports)]
    outside = [Counter() for _ in range(ports)]
    misses = [[] for _ in range(ports)]
    next_frames = [[] for _ in range(ports)]
    barrier = scenario == "returns"
    for edge in range(WARMUP + WINDOW + 16 * profile.cells + 256):
        measuring = WARMUP <= edge < WARMUP + WINDOW
        stats = window if measuring else outside
        for port in range(ports):
            if source[port] is not None or edge >= WARMUP + WINDOW:
                continue
            index = sequences[port]
            sequences[port] += 1
            mix = MIX if profile_name == "primary" else SMALL_MIX
            if scenario == "independent":
                choices = RANDOM_LENGTHS if profile_name == "primary" else RANDOM_LENGTHS[:-1] + (192,)
                size = rng[port].choice(choices)
            else:
                size = length or mix[index % len(mix)]
            dest = 0 if scenario.startswith("incast") else (port + 1) % ports
            cls = port if scenario.startswith("incast") else 0
            malformed = 0
            if scenario == "cleanup" and port < 2 and index % 8 == 0:
                size = profile.maximum
                malformed = 130 if profile_name == "primary" else 18
            f = Frame(port, index, dest, cls, size, malformed)
            source[port] = f
            if scenario == "independent":
                next_frames[dest].append(f)
        ready = [True] * ports
        if scenario == "stall":
            ready[0] = not 32 <= edge % 256 < 64
        if barrier:
            at_final = [bool(slots and slots[0].ready and slots[0].tx + 1 == slots[0].beats)
                        for slots in tm.slots]
            if edge >= 64 and all(at_final):
                barrier = False
            else:
                ready = [not final for final in at_final]
        if measuring and scenario == "independent":
            for port, slots in enumerate(tm.slots):
                if ready[port] and not (slots and slots[0].ready):
                    f = slots[0] if slots else None
                    misses[port].append((edge, tm.previous_final[port], f))
        offers = [(f, offer_index[p]) if f else None for p, f in enumerate(source)]
        accepted = tm.step(offers, ready, stats)
        for port, ok in enumerate(accepted):
            if not ok:
                continue
            f = source[port]
            if offer_index[port] == f.offered_beats:
                source[port] = None
                offer_index[port] = 1
            else:
                offer_index[port] += 1
        if edge >= WARMUP + WINDOW and not any(source) and tm.idle():
            break
    else:
        raise AssertionError("workload did not drain")
    totals = [a + b for a, b in zip(window, outside)]
    for stats in totals:
        assert stats["rx_frames"] == sum(stats[key] for key in RESULTS)
        assert stats["COMMITTED"] == stats["delivered"]
    assert sum(p["tx_bytes"] for p in totals) == sum(p["delivered_bytes"] for p in totals)
    assert not tm.bitmap and tm.credit == profile.cells
    for stats in totals:
        if stats["rx_frames"] == stats["delivered"]:
            assert stats["rx_bytes"] == stats["delivered_bytes"]
    diagnostics = []
    for port, entries in enumerate(misses):
        for idle, prior, f in entries:
            if f is None:
                f = next((frame for frame in next_frames[port]
                          if frame.times.get("first", -1) > idle), None)
            event = dict(egress=port, idle=idle, predecessor_final=prior)
            if f is not None:
                event.update(frame=f.identity, length=f.length, **f.times)
            diagnostics.append(event)
    gate = (all(p["rx_beats"] == p["tx_beats"] == WINDOW for p in window)
            and all(p["rx_frames"] == p["delivered"] for p in totals))
    keys = ("rx_beats", "rx_bytes", "rx_frames", "rx_stall",
            "tx_beats", "tx_bytes", "tx_frames", "tx_idle", "tx_blocked", "sink_unready",
            "no_bound_head", "pending_prefetch", "delivered", "delivered_bytes", *RESULTS)
    vector = lambda rows: {key: [row[key] for row in rows] for key in keys}
    return dict(profile=profile_name, latency=latency, variant=variant, scenario=scenario,
                length=length or "mix", gate=gate, window=vector(window), drain=vector(totals),
                peaks=dict(tm.peaks), misses=diagnostics, last_edge=edge,
                ownership=dict(credit=tm.credit, reserved=0, assigned=len(tm.cell.owner),
                               free_descriptors=tm.desc.free.bit_count()),
                wait={key: [row[key] for row in totals] for key in
                      ("wait_NO_DESCRIPTOR", "wait_NO_CELLS", "wait_QUEUE_LIMIT")})


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=PROFILES, default="primary")
    parser.add_argument("--variant", choices=VARIANTS, default="direct")
    parser.add_argument("--case", choices=("all", *CASES), default="all")
    parser.add_argument("--latency", type=int, choices=(1, 2))
    parser.add_argument("--json", type=Path)
    parser.add_argument("--expect-gate", action="store_true")
    args = parser.parse_args()
    profile = PROFILES[args.profile]
    results = []
    for latency in (args.latency,) if args.latency else (1, 2):
        for scenario, lengths in CASES.items():
            if args.case not in ("all", scenario):
                continue
            for length in lengths:
                value = min(length, profile.maximum)
                result = replay(args.profile, latency, args.variant, scenario, value)
                results.append(result)
                w = result["window"]
                print(f"{scenario} {value or 'mix'} L={latency}: "
                      f"rx={w['rx_beats']} tx={w['tx_beats']} idle={w['tx_idle']} "
                      f"{'PASS' if result['gate'] else 'MISS'}", flush=True)
    if args.json:
        args.json.write_text(json.dumps(results, indent=2) + "\n")
    if args.expect_gate:
        balanced = [result for result in results if result["scenario"] == "balanced"]
        if not balanced or not all(r["gate"] for r in balanced):
            raise SystemExit(1)


if __name__ == "__main__":
    main()
