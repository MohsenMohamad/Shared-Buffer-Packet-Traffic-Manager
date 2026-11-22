"""Resource expectations derived from the multi-egress behavior contract."""

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Profile:
    ports: int
    cells: int
    descriptors: int
    max_length: int

    @property
    def queues(self):
        return 4 * self.ports


PROFILES = {
    "primary": Profile(4, 1024, 256, 1536),
    "small": Profile(2, 16, 8, 192),
}


class Violation(ValueError):
    def __init__(self, detector, detail):
        self.detector = detector
        super().__init__(f"{detector}: {detail}")


def require(condition, detector, detail):
    if not condition:
        raise Violation(detector, detail)


@dataclass(frozen=True)
class Owner:
    epoch: int
    ingress: int
    sequence: int
    qid: int
    descriptor: int
    tag: int

    @property
    def frame(self):
        return self.epoch, self.ingress, self.sequence


@dataclass(frozen=True)
class Counts:
    physical_free: int
    unreserved: int
    reserved_free: int
    assigned: int
    descriptor_free: int
    queue_credit: tuple[int, ...]


@dataclass(frozen=True)
class Grant:
    owner: Owner
    length: int
    cells: int


@dataclass(frozen=True)
class Write:
    owner: Owner
    address: int
    index: int
    final: bool


@dataclass(frozen=True)
class Publication:
    owner: Owner
    head: int
    cells: int
    length: int


@dataclass(frozen=True)
class Service:
    owner: Owner
    address: int
    cell_last: bool
    frame_last: bool


@dataclass(frozen=True)
class Cleanup:
    owner: Owner
    done: bool
    released: int


@dataclass
class Batch:
    epoch: int
    present: bool = True
    grants: list[Grant] = field(default_factory=list)
    write: Write | None = None
    publication: Publication | None = None
    dispatches: dict[int, tuple[Owner, int]] = field(default_factory=dict)
    services: dict[int, Service] = field(default_factory=dict)
    aborts: dict[int, tuple[Owner, int]] = field(default_factory=dict)
    cleanup: Cleanup | None = None
    cell_returns: dict[int, tuple[Owner, int]] = field(default_factory=dict)
    desc_returns: dict[int, Owner] = field(default_factory=dict)


@dataclass
class Frame:
    owner: Owner
    length: int
    outstanding: int
    phase: str = "RX"
    phase_edge: int = 0
    cells: dict[int, int] = field(default_factory=dict)
    writes: int = 0

    @property
    def budget(self):
        return (self.length + 63) // 64


class PoolOracle:
    def __init__(self, profile):
        self.profile = profile
        self.frames = {}
        self.cells = {}
        self.sequence = {}
        self.epochs = set()
        self.epoch = None
        self.reset_edges = 0
        self.edge = -1
        self.pending_publication = None
        self.previous_cell_returns = set()
        self.previous_desc_returns = set()

    def counts(self):
        credits = [0] * self.profile.queues
        reserved_free = 0
        for frame in self.frames.values():
            credits[frame.owner.qid] += frame.outstanding
            reserved_free += frame.outstanding - len(frame.cells)
            require(frame.outstanding >= len(frame.cells), "CONSERVATION", frame.owner)
        assigned = len(self.cells)
        unreserved = self.profile.cells - sum(credits)
        physical_free = self.profile.cells - assigned
        descriptors = self.profile.descriptors - len(self.frames)
        for address, owner in self.cells.items():
            frame = self.frames.get(owner.descriptor)
            require(frame is not None and frame.owner == owner and address in frame.cells,
                    "CELL_OWNER", (address, owner))
        require(sum(len(f.cells) for f in self.frames.values()) == assigned,
                "CONSERVATION", "frame and physical cell populations disagree")
        require(min(unreserved, reserved_free, physical_free, descriptors) >= 0
                and physical_free == unreserved + reserved_free,
                "CONSERVATION", (physical_free, unreserved, reserved_free, descriptors))
        return Counts(physical_free, unreserved, reserved_free, assigned, descriptors, tuple(credits))

    def owner(self, owner, phase, detector, old=False):
        require(owner.epoch == self.epoch, "STALE_OWNER", owner)
        frame = self.frames.get(owner.descriptor)
        require(frame is not None and frame.owner == owner and frame.phase == phase
                and (not old or frame.phase_edge < self.edge), detector, owner)
        return frame

    def sample(self, edge, reset_n, initialized, batch, observed):
        require(edge == self.edge + 1, "EDGE_SEQUENCE", edge)
        self.edge = edge
        pre = self.counts()
        prior_reclaims = self.previous_cell_returns, self.previous_desc_returns
        self.previous_cell_returns = set()
        self.previous_desc_returns = set()
        if not reset_n:
            require(not batch.present, "RESET_ACTIVITY", edge)
            self.reset_edges += 1
            self.frames.clear()
            self.cells.clear()
            self.sequence.clear()
            self.pending_publication = None
            self.epoch = None
        else:
            require(batch.present, "EDGE_PRESENT", edge)
            if self.epoch is None:
                require(self.reset_edges >= 2 and batch.epoch not in self.epochs,
                        "RESET_EPOCH", (self.reset_edges, batch.epoch))
                self.epochs.add(batch.epoch)
                self.epoch = batch.epoch
                self.reset_edges = 0
                require(not initialized, "INITIALIZE", edge)
            else:
                require(batch.epoch == self.epoch, "EDGE_EPOCH", batch.epoch)
                require(initialized, "INITIALIZE", edge)
            if initialized:
                self.apply(batch, pre)
            else:
                require(batch == Batch(batch.epoch), "INITIALIZE_ACTIVITY", edge)
        after = self.counts()
        if observed is not None:
            expected = after if reset_n else Counts(0, 0, 0, 0, 0, (0,) * self.profile.queues)
            require(observed == expected, "REPORTED_COUNTS", f"observed {observed}, expected {expected}")
        return pre, after, prior_reclaims

    def apply(self, batch, pre):
        self.check_return_owners(batch)
        self.grant(batch, pre.unreserved)
        self.publish(batch.publication)
        for lane, (owner, length) in batch.dispatches.items():
            frame = self.owner(owner, "QUEUED", "DISPATCH_PHASE", old=True)
            bound = sum(f.phase == "TX" and f.owner.qid // 4 == lane for f in self.frames.values())
            require(owner.qid // 4 == lane and length == frame.length and bound < 2,
                    "DISPATCH_LANE", (lane, owner))
            frame.phase, frame.phase_edge = "TX", self.edge
        if batch.write:
            self.materialize(batch.write, pre.physical_free)
        for lane, (owner, reserved) in batch.aborts.items():
            frame = self.owner(owner, "RX", "ABORT_PHASE")
            require(lane == owner.ingress and reserved == frame.budget and frame.writes < frame.budget,
                    "ABORT_RESERVATION", owner)
            frame.phase, frame.phase_edge = "ABORT", self.edge
        for lane in range(self.profile.ports):
            self.retire(lane, batch)
        self.cleanup(batch)

    def check_return_owners(self, batch):
        used_cells, used_desc = set(), set()
        for lane, (owner, address) in batch.cell_returns.items():
            require(owner.epoch == self.epoch, "STALE_OWNER", owner)
            require(address not in used_cells, "DUPLICATE_CELL_RETURN", (lane, address))
            require(self.cells.get(address) == owner, "CELL_OWNER", (lane, address, owner))
            used_cells.add(address)
        for lane, owner in batch.desc_returns.items():
            require(owner.epoch == self.epoch, "STALE_OWNER", owner)
            require(owner.descriptor not in used_desc, "DUPLICATE_DESC_RETURN", (lane, owner))
            frame = self.frames.get(owner.descriptor)
            require(frame is not None and frame.owner == owner, "DESC_OWNER", (lane, owner))
            used_desc.add(owner.descriptor)

    def grant(self, batch, prefix_credit):
        ingresses = set()
        for grant in batch.grants:
            owner = grant.owner
            require(owner.epoch == self.epoch, "STALE_OWNER", owner)
            require(0 <= owner.ingress < self.profile.ports and owner.ingress not in ingresses,
                    "GRANT_INGRESS", owner)
            require(batch.cleanup is None or not batch.cleanup.done
                    or owner.ingress != batch.cleanup.owner.ingress, "GRANT_CLEANUP_INGRESS", owner)
            require(0 <= owner.descriptor < self.profile.descriptors
                    and owner.descriptor not in self.frames, "DESC_PRE_FREE", owner)
            require(0 <= owner.qid < self.profile.queues and 60 <= grant.length <= self.profile.max_length
                    and grant.cells == (grant.length + 63) // 64, "GRANT_RESERVATION", grant)
            require(grant.cells <= prefix_credit, "CREDIT_PREFIX", grant)
            require(owner.sequence > self.sequence.get(owner.ingress, -1), "FRAME_IDENTITY", owner)
            self.sequence[owner.ingress] = owner.sequence
            ingresses.add(owner.ingress)
            prefix_credit -= grant.cells
            self.frames[owner.descriptor] = Frame(owner, grant.length, grant.cells, phase_edge=self.edge)

    def publish(self, publication):
        require((publication is None) == (self.pending_publication is None),
                "NEXT_EDGE_PUBLICATION", publication)
        if publication is None:
            return
        frame = self.owner(publication.owner, "RX", "PUBLICATION_OWNER", old=True)
        require(publication.owner == self.pending_publication
                and publication.cells == frame.budget
                and publication.length == frame.length
                and frame.cells.get(publication.head) == 0,
                "PUBLICATION_METADATA", publication)
        self.pending_publication = None
        frame.phase, frame.phase_edge = "QUEUED", self.edge

    def materialize(self, write, old_free):
        require(old_free > 0, "PHYSICAL_EXHAUSTION", write.address)
        require(0 <= write.address < self.profile.cells and write.address not in self.cells,
                "CELL_PRE_FREE", write.address)
        frame = self.owner(write.owner, "RX", "WRITE_OWNER", old=True)
        require(frame.outstanding > len(frame.cells), "WRITE_CREDIT", write.owner)
        require(write.index == frame.writes and write.final == (frame.writes + 1 == frame.budget),
                "WRITE_SEQUENCE", write)
        self.cells[write.address] = frame.owner
        frame.cells[write.address] = frame.writes
        frame.writes += 1
        if write.final:
            self.pending_publication = frame.owner

    def retire(self, lane, batch):
        service = batch.services.get(lane)
        cell = batch.cell_returns.get(lane)
        desc = batch.desc_returns.get(lane)
        if service is None:
            require(cell is None and desc is None, "TX_ACCEPTANCE", lane)
            return
        frame = self.owner(service.owner, "TX", "TX_PHASE", old=True)
        require(service.owner.qid // 4 == lane and service.address in frame.cells, "TX_OWNER", service)
        oldest = min(frame.cells, key=frame.cells.get)
        require(service.address == oldest and (not service.frame_last or service.cell_last),
                "TX_ORDER", service)
        require((cell == (service.owner, service.address)) if service.cell_last else cell is None,
                "TX_CELL_EVENT", (lane, service, cell))
        require((desc == service.owner) if service.frame_last else desc is None,
                "TX_DESC_EVENT", (lane, service, desc))
        if service.cell_last:
            require(service.frame_last == (frame.outstanding == 1), "TX_FINAL", service)
            self.release_cell(frame, service.address)
            frame.outstanding -= 1
        if service.frame_last:
            self.release_desc(frame)

    def cleanup(self, batch):
        lane = self.profile.ports
        cell = batch.cell_returns.get(lane)
        desc = batch.desc_returns.get(lane)
        event = batch.cleanup
        if event is None:
            require(cell is None and desc is None, "CLEANUP_SERVICE", lane)
            return
        frame = self.owner(event.owner, "ABORT", "CLEANUP_PHASE", old=True)
        if cell is not None:
            owner, address = cell
            require(owner == event.owner and address in frame.cells, "CLEANUP_OWNER", cell)
            self.release_cell(frame, address)
        require(cell is not None or event.done, "EMPTY_CLEANUP_SERVICE", event)
        if event.done:
            require(not frame.cells and event.released == frame.outstanding,
                    "CLEANUP_CREDIT", event)
            require(desc == event.owner, "CLEANUP_DESC_EVENT", event)
            self.release_desc(frame)
        else:
            require(event.released == 0 and desc is None, "EARLY_CLEANUP_CREDIT", event)

    def release_cell(self, frame, address):
        del self.cells[address]
        del frame.cells[address]
        self.previous_cell_returns.add(address)

    def release_desc(self, frame):
        descriptor = frame.owner.descriptor
        del self.frames[descriptor]
        self.previous_desc_returns.add(descriptor)

    def drained(self):
        require(not self.frames and not self.cells and self.pending_publication is None,
                "DRAIN_OWNERSHIP", (len(self.frames), len(self.cells)))
        require(self.counts() == Counts(self.profile.cells, self.profile.cells, 0, 0,
                                       self.profile.descriptors, (0,) * self.profile.queues),
                "DRAIN_COUNTS", self.counts())
