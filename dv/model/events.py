"""Independent monitor boundary and small atomic policy example, not a TM model.

P07 consumes these records in independent packet/service/policy checkers. Physical
IDs remain diagnostic trace fields and are deliberately absent from scalar policy.
"""
from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True, order=True)
class PacketKey:
    epoch: int
    source: int
    ordinal: int


@dataclass(frozen=True)
class Beat:
    data: bytes  # all eight lanes, keep selects meaningful bytes
    keep: int
    last: bool
    user: int  # includes untruncated invalid qid and reserved input bits


@dataclass(frozen=True)
class StreamSample:
    valid: bool
    ready: bool
    beat: Beat | None


@dataclass(frozen=True)
class Packet:
    key: PacketKey
    qid: int
    length: int
    tag: int
    payload: bytes  # reconstructed ONLY from external input handshakes


@dataclass(frozen=True)
class Service:
    source: int
    beat: Beat
    sop: bool


@dataclass(frozen=True)
class Admission:
    packet: PacketKey
    qid: int
    length: int
    accepted: bool
    reason: str


@dataclass(frozen=True)
class CellRelease:
    qid: int
    aborted: bool = False


@dataclass(frozen=True)
class AbortDone:
    qid: int
    reserved: int


@dataclass(frozen=True)
class PolicyEvents:
    admission: Admission | None = None
    materialize: int = 0  # 0/1, independently cross-checked from service
    release: CellRelease | None = None
    abort_done: AbortDone | None = None
    tx_done: bool = False
    commit: Packet | None = None
    dispatch: tuple[int, PacketKey] | None = None
    service: Service | None = None
    # Raw physical events/IDs are diagnostic only, not abstract queue pointers.
    trace: tuple[tuple[str, Any], ...] = ()


@dataclass(frozen=True)
class BusSample:
    # Full levels permit independent AW/W assembly, response and stall checks.
    awvalid: bool = False
    awready: bool = False
    awaddr: int = 0
    awprot: int = 0
    wvalid: bool = False
    wready: bool = False
    wdata: int = 0
    wstrb: int = 0
    bvalid: bool = False
    bready: bool = False
    bresp: int = 0
    arvalid: bool = False
    arready: bool = False
    araddr: int = 0
    arprot: int = 0
    rvalid: bool = False
    rready: bool = False
    rdata: int = 0
    rresp: int = 0


@dataclass(frozen=True)
class Status:
    source: int
    code: int
    qid: int
    length: int
    tag: int


@dataclass(frozen=True)
class CycleBatch:
    epoch: int
    cycle: int
    reset: bool
    captures: tuple[StreamSample, ...]
    output: StreamSample
    bus: BusSample
    statuses: tuple[Status, ...]
    policy: PolicyEvents


class Collector:
    """Barrier: explicit idle reports are mandatory; callbacks never update state."""
    def __init__(self, n_rx):
        self.n_rx = n_rx
        self.sources = {'reset', 'output', 'bus', 'status', 'policy'} | {
            f'rx{i}' for i in range(n_rx)}
        self.pending = {}
        self.last = None

    def submit(self, epoch, cycle, source, sample):
        key = (epoch, cycle)
        if source not in self.sources or (self.last is not None and key <= self.last):
            raise ValueError('Unknown source or stale batch')
        if self.pending and key not in self.pending:
            raise ValueError('Seal current clock before advancing')
        slot = self.pending.setdefault(key, {})
        if source in slot:
            raise ValueError('Duplicate monitor callback')
        slot[source] = sample

    def seal(self, epoch, cycle):
        key = (epoch, cycle)
        slot = self.pending.get(key, {})
        if slot.keys() != self.sources:
            raise ValueError('Incomplete clock batch')
        batch = CycleBatch(epoch, cycle, slot['reset'],
                           tuple(slot[f'rx{i}'] for i in range(self.n_rx)),
                           slot['output'], slot['bus'], tuple(slot['status']), slot['policy'])
        del self.pending[key]
        self.last = key
        return batch


@dataclass
class PolicyState:
    capacity: int
    descriptors: int
    cell_bytes: int
    max_length: int
    limits: tuple[int, ...]
    u: int
    r: int
    a: int
    d: int
    h: list[int]
    queues: list[list[Packet]] = field(default_factory=list)

    def apply(self, batch):
        """Validate against pre-state; commit all scalar/list deltas atomically.

        This example demonstrates event ordering, not scheduling, byte checking,
        trace causality or physical ownership. P07 must supply those checkers.
        """
        if batch.reset:
            self.u, self.r, self.a, self.d = self.capacity, 0, 0, self.descriptors
            self.h = [0] * len(self.limits)
            self.queues = [[] for _ in self.limits]
            return
        e = batch.policy
        n = 0
        if e.admission:
            x = e.admission
            n = (x.length + self.cell_bytes-1)//self.cell_bytes
            if not 0 <= x.qid < len(self.limits):
                reason = 'BAD_QID'
            elif not 1 <= x.length <= self.max_length:
                reason = 'BAD_LENGTH'
            elif self.h[x.qid] + n > self.limits[x.qid]:
                reason = 'QUEUE_LIMIT'
            elif self.d == 0:
                reason = 'NO_DESCRIPTOR'
            elif self.u < n:
                reason = 'NO_CELLS'
            else:
                reason = 'COMMITTED'  # accepted predicate; status COMMITTED is later
            if (x.accepted, x.reason) != (reason == 'COMMITTED', reason):
                raise ValueError('Admission disagrees with pre-state')
        queues = [list(q) for q in self.queues]
        if e.dispatch:
            q, packet = e.dispatch
            if not queues[q] or queues[q][0].key != packet:
                raise ValueError('Dispatch has no pre-state head')
            queues[q].pop(0)
        if e.commit:
            queues[e.commit.qid].append(e.commit)
        u, r, a, d, h = self.u, self.r, self.a, self.d, list(self.h)
        if e.admission and e.admission.accepted:
            u -= n; r += n; d -= 1; h[e.admission.qid] += n
        if e.materialize not in (0, 1):
            raise ValueError('More than one materialization')
        a += e.materialize; r -= e.materialize
        if e.release:
            a -= 1
            if e.release.aborted:
                r += 1
            else:
                u += 1; h[e.release.qid] -= 1
        if e.abort_done:
            x = e.abort_done
            u += x.reserved; r -= x.reserved; h[x.qid] -= x.reserved; d += 1
        d += int(e.tx_done)
        if not (0 <= d <= self.descriptors and min(u, r, a, *h) >= 0 and
                a+u+r == self.capacity and u+sum(h) == self.capacity):
            raise ValueError('Merged resource invariants failed')
        self.u, self.r, self.a, self.d, self.h, self.queues = u, r, a, d, h, queues
