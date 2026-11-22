"""Geometry and records used to encode pool replay stimulus."""

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
