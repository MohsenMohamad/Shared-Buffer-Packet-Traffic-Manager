"""Passive, spec-derived memory/TX oracle; no RTL or retained checker imports.

Each Edge is a sealed pre-edge monitor batch. Memory responses use issue-time
snapshots; packet bytes use monitored writes. Neither stimulus packet objects
nor DUT cursors/free counts are accepted by this API.
"""
from collections import Counter, deque
from dataclasses import dataclass, field


class Violation(AssertionError):
    """A named contract detector, suitable for negative qualification."""


def require(condition, detector):
    if not condition:
        raise Violation(detector)


@dataclass(frozen=True)
class Info:
    length: int
    qid: int = 0
    tag: int = 0
    source: int = 0

    @property
    def user(self):
        return self.qid | (self.length << 8) | (self.tag << 24) | (self.source << 40)


@dataclass(frozen=True)
class Beat:
    data: int
    keep: int
    last: bool
    user: int


@dataclass(frozen=True)
class Edge:
    reset: bool = False
    reserve: tuple | None = None       # descriptor, independently sampled Info
    allocate: tuple | None = None      # descriptor, physical cell
    write: tuple | None = None         # physical word address, 64-bit data
    link_write: tuple | None = None    # previous cell, next cell
    commit: int | None = None
    dispatch: tuple | None = None      # descriptor, Info (cross-check only)
    read: int | None = None            # physical word address
    response: int | None = None        # unbackpressured data, no driver token
    output: Beat | None = None         # actual valid output levels
    ready: bool = False
    capture_next: tuple | None = None  # independently witnessed next-link capture
    cell_return: tuple | None = None   # descriptor, cell
    desc_return: int | None = None
    done: int | None = None


@dataclass
class Packet:
    info: Info
    cells: list = field(default_factory=list)
    writes: dict = field(default_factory=dict)
    payload: bytes | None = None
    phase: str = 'RX'


@dataclass(frozen=True)
class Token:
    due: int
    epoch: int
    ordinal: int
    data: int


def little_bytes(data):
    require(0 <= data < 1 << 64, 'MTX_WORD_WIDTH')
    return data.to_bytes(8, 'little')


class MemoryTxModel:
    def __init__(self, latency=1, depth=4, cell_bytes=16, ncell=16,
                 ndesc=8, max_length=128):
        require(latency in (1, 2) and depth >= latency + 2, 'MTX_CONFIGURATION')
        require(cell_bytes in (16, 32, 64), 'MTX_CONFIGURATION')
        self.latency, self.depth = latency, depth
        self.cell_bytes, self.cell_words = cell_bytes, cell_bytes // 8
        self.ncell, self.ndesc, self.max_length = ncell, ndesc, max_length
        self.ram = {}                 # deliberately survives reset
        self.pending = deque()        # physical RAM pipeline survives reset
        self.cover = Counter()
        self.cycle = -1
        self.epoch = 0
        self.reset_edges = 0
        self.in_reset = False
        self.initialized = False
        self._flush()

    def _flush(self):
        self.packets = {}
        self.owners = {}
        self.committed = deque()      # local single-queue dispatch environment
        self.active = None
        self.read_count = self.retired = 0
        self.fifo = deque()
        self.captured = set()
        self.held = None

    @property
    def outstanding(self):
        return sum(token.epoch == self.epoch for token in self.pending)

    @property
    def credits(self):
        return len(self.fifo) + self.outstanding

    def address(self, packet, ordinal):
        cell_index, word_offset = divmod(ordinal, self.cell_words)
        return packet.cells[cell_index] * self.cell_words + word_offset

    def _response(self, edge):
        due = self.pending[0] if self.pending and self.pending[0].due == self.cycle else None
        require((edge.response is not None) == (due is not None), 'MTX_RESPONSE_LATENCY')
        if due:
            require(edge.response == due.data, 'MTX_MEMORY_DATA')
            self.pending.popleft()
        return due

    def step(self, edge):
        self.cycle += 1
        due = self._response(edge)
        if edge.reset:
            require(not any((edge.reserve, edge.allocate, edge.write, edge.link_write,
                             edge.dispatch, edge.output, edge.capture_next,
                             edge.cell_return)) and edge.read is None and
                    edge.commit is None and edge.desc_return is None and edge.done is None,
                    'MTX_RESET_CONTROL')
            if not self.in_reset:
                self.epoch += 1
                self.cover['reset_pending' if self.pending or due else 'reset_idle'] += 1
            self.reset_edges += 1
            self.in_reset, self.initialized = True, False
            self._flush()
            return
        if self.in_reset:
            require(self.reset_edges >= 2, 'MTX_RESET_WIDTH')
            self.in_reset, self.reset_edges = False, 0
        if not self.initialized:
            require(edge == Edge(response=edge.response), 'MTX_INITIALIZATION')
            self.initialized = True
            return

        # All legality checks use this pre-state. Current retirement can fund a
        # read credit, but cannot fund physical reallocation until the next edge.
        packet = self.packets.get(self.active)
        occupancy = len(self.fifo)
        outstanding = self.outstanding + int(due is not None and due.epoch == self.epoch)
        fire = edge.output is not None and edge.ready
        require(occupancy + outstanding <= self.depth, 'MTX_CREDIT_BOUND')
        self.cover[f'credits_{occupancy + outstanding}'] += 1
        if occupancy + outstanding == self.depth and not edge.ready:
            self.cover['full_credit_stall'] += 1
        if due and due.epoch == self.epoch and not edge.ready:
            self.cover['pending_response_stall'] += 1
        if due and edge.read is not None and fire:
            self.cover['issue_response_retire'] += 1

        if self.held is not None:
            require(edge.output == self.held, 'MTX_STABILITY')
        expected_cell = None
        expected_done = None
        if edge.output is not None:
            require(packet is not None and self.fifo, 'MTX_OUTPUT_WITHOUT_RESPONSE')
            token = self.fifo[0]
            require(token.epoch == self.epoch and token.ordinal == self.retired,
                    'MTX_RESPONSE_ORDER')
            offset = self.retired * 8
            count = min(8, packet.info.length - offset)
            last = offset + count == packet.info.length
            require(edge.output.keep == (1 << count) - 1 and edge.output.last == last,
                    'MTX_OUTPUT_FRAMING')
            require(edge.output.user == packet.info.user, 'MTX_OUTPUT_METADATA')
            require(little_bytes(edge.output.data)[:count] == packet.payload[offset:offset + count],
                    'MTX_OUTPUT_BYTES')
            if fire:
                if (self.retired + 1) % self.cell_words == 0 or last:
                    cell_index = self.retired // self.cell_words
                    expected_cell = (self.active, packet.cells[cell_index])
                    if not last:
                        require((packet.cells[cell_index], packet.cells[cell_index + 1])
                                in self.captured, 'MTX_LINK_BEFORE_RETURN')
                if last:
                    expected_done = self.active
        require(edge.cell_return == expected_cell, 'MTX_CELL_RETIREMENT')
        require(edge.desc_return == expected_done and edge.done == expected_done,
                'MTX_COMPLETION')

        if edge.allocate:
            desc, cell = edge.allocate
            require(desc in self.packets and self.packets[desc].phase == 'RX', 'MTX_ALLOC_OWNER')
            require(0 <= cell < self.ncell and cell not in self.owners, 'MTX_CELL_REUSE')
        if edge.reserve:
            desc, info = edge.reserve
            require(0 <= desc < self.ndesc and desc not in self.packets, 'MTX_DESC_REUSE')
            require(1 <= info.length <= self.max_length and 0 <= info.qid < 256 and
                    0 <= info.tag < 65536 and 0 <= info.source < 256, 'MTX_HEADER')
        if edge.read is not None:
            require(packet is not None and packet.phase == 'TX', 'MTX_READ_OWNER')
            require(self.read_count < (packet.info.length + 7) // 8, 'MTX_READ_PAST_END')
            require(edge.read == self.address(packet, self.read_count), 'MTX_READ_ORDER')
            require(occupancy + outstanding + 1 - int(fire) <= self.depth, 'MTX_OVERISSUE')
            require(edge.write is None or edge.read != edge.write[0], 'MTX_PAYLOAD_COLLISION')
        if edge.dispatch:
            desc, info = edge.dispatch
            require(self.active is None and not self.fifo and outstanding == 0,
                    'MTX_DISPATCH_BUSY')
            require(self.committed and self.committed[0] == desc, 'MTX_DISPATCH_ORDER')
            require(self.packets[desc].info == info, 'MTX_DISPATCH_METADATA')

        # Apply the sealed batch after validating pre-state decisions.
        self.held = edge.output if edge.output is not None and not edge.ready else None
        if fire:
            self.fifo.popleft()
            self.retired += 1
            if expected_cell:
                del self.owners[expected_cell[1]]
                self.cover['cell_retired'] += 1
            if expected_done is not None:
                del self.packets[expected_done]
                self.active = None
                self.cover['packet_completed'] += 1
        if due and due.epoch == self.epoch:
            self.fifo.append(due)
        elif due:
            self.cover['old_response_discarded'] += 1
        if edge.read is not None:
            self.pending.append(Token(self.cycle + self.latency, self.epoch,
                                      self.read_count, self.ram[edge.read]))
            self.read_count += 1
        if edge.reserve:
            desc, info = edge.reserve
            self.packets[desc] = Packet(info)
        if edge.allocate:
            desc, cell = edge.allocate
            self.owners[cell] = desc
            self.packets[desc].cells.append(cell)
        if edge.write:
            addr, data = edge.write
            require(0 <= addr < self.ncell * self.cell_words, 'MTX_WRITE_ADDRESS')
            desc = self.owners.get(addr // self.cell_words)
            require(desc in self.packets and self.packets[desc].phase == 'RX', 'MTX_WRITE_OWNER')
            little_bytes(data)
            require(addr not in self.packets[desc].writes, 'MTX_DUPLICATE_WRITE')
            self.packets[desc].writes[addr] = data
            self.ram[addr] = data
        if edge.link_write:
            previous, following = edge.link_write
            desc = self.owners.get(previous)
            require(desc is not None and self.owners.get(following) == desc, 'MTX_LINK_OWNER')
            cells = self.packets[desc].cells
            require((previous, following) in list(zip(cells, cells[1:])), 'MTX_LINK_ORDER')
        if edge.commit is not None:
            committed = self.packets[edge.commit]
            require(committed.phase == 'RX' and len(committed.cells) ==
                    (committed.info.length + self.cell_bytes - 1) // self.cell_bytes,
                    'MTX_COMMIT_CELLS')
            addresses = [self.address(committed, i)
                         for i in range((committed.info.length + 7) // 8)]
            require(set(addresses) == set(committed.writes), 'MTX_COMMIT_WRITES')
            committed.payload = b''.join(little_bytes(committed.writes[a]) for a in addresses)
            committed.payload = committed.payload[:committed.info.length]
            committed.phase = 'QUEUED'
            self.committed.append(edge.commit)
        if edge.dispatch:
            self.active = self.committed.popleft()
            self.packets[self.active].phase = 'TX'
            self.read_count = self.retired = 0
            self.captured.clear()
        if edge.capture_next:
            require(packet is not None, 'MTX_LINK_CAPTURE_OWNER')
            require(edge.capture_next in list(zip(packet.cells, packet.cells[1:])),
                    'MTX_LINK_CAPTURE_VALUE')
            require(edge.capture_next[0] in self.owners, 'MTX_LINK_AFTER_REUSE')
            self.captured.add(edge.capture_next)
        require(self.credits <= self.depth, 'MTX_FIFO_OVERWRITE')

    def finish(self, required=()):
        require(not self.packets and not self.owners and not self.pending and
                not self.fifo and self.active is None and self.held is None,
                'MTX_RESOURCE_LEAK')
        for name in required:
            require(self.cover[name] > 0, 'MTX_MISSING_PRESSURE:' + name)
        return dict(self.cover)
