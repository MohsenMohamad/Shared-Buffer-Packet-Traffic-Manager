"""Construct legal edge trajectories independently of the passive oracle.

Filler frames reach scarcity through allocations and writes. They are queued
until drain. Only pool events and their causality are modeled here.
"""

from copy import deepcopy
from dataclasses import dataclass, field

from abi import Layout
from replay_types import Batch, Cleanup, Counts, Grant, Owner, Publication, Service, Write


@dataclass
class Intent:
    owner: Owner
    length: int
    budget: int
    addresses: list[int] = field(default_factory=list)
    phase: str = "rx"


class Stimulus:
    def __init__(self, profile):
        self.p = profile
        self.rows = []
        self.epoch = 0
        self.pending = None
        self.desc = {}
        self.busy_cells = set()
        self.sequences = [0] * profile.ports
        self.f = profile.cells
        self.u = profile.cells
        self.h = [0] * profile.queues
        self.reset()

    def counts(self):
        return Counts(self.f, self.u, self.f - self.u, self.p.cells - self.f,
                      self.p.descriptors - len(self.desc), tuple(self.h))

    def reset(self):
        self.epoch += 1
        self.pending = None
        self.desc.clear()
        self.busy_cells.clear()
        self.sequences = [0] * self.p.ports
        self.f = self.u = self.p.cells
        self.h = [0] * self.p.queues
        empty = Counts(0, 0, 0, 0, 0, (0,) * self.p.queues)
        self.rows.extend([
            (False, False, Batch(self.epoch, False), empty),
            (False, False, Batch(self.epoch, False), empty),
            (True, False, Batch(self.epoch), self.counts()),
        ])

    def edge(self, *, grants=(), write=None, dispatch=(), returns=(), aborts=(),
             cleanup=None, held=None):
        batch = Batch(self.epoch)
        if self.pending is not None:
            frame = self.pending
            batch.publication = Publication(frame.owner, frame.addresses[0], frame.budget, frame.length)
            frame.phase = "queued"
            self.pending = None
        for frame in grants:
            batch.grants.append(Grant(frame.owner, frame.length, frame.budget))
            self.desc[frame.owner.descriptor] = frame
            self.u -= frame.budget
            self.h[frame.owner.qid] += frame.budget
        for frame in dispatch:
            batch.dispatches[frame.owner.qid // 4] = (frame.owner, frame.length)
            frame.phase = "tx"
        if write is not None:
            frame, address = write
            if address is None:
                address = next(index for index in range(self.p.cells) if index not in self.busy_cells)
            index = len(frame.addresses)
            final = index + 1 == frame.budget
            batch.write = Write(frame.owner, address, index, final)
            self.busy_cells.add(address)
            frame.addresses.append(address)
            self.f -= 1
            if final:
                self.pending = frame
        for frame in aborts:
            batch.aborts[frame.owner.ingress] = (frame.owner, frame.budget)
            frame.phase = "abort"
        if held is not None:
            lane = held.owner.qid // 4
            batch.services[lane] = Service(held.owner, held.addresses[0], False, False)
        for frame in returns:
            lane = frame.owner.qid // 4
            address = self.reclaim(frame, lane, batch)
            final = not frame.addresses
            batch.services[lane] = Service(frame.owner, address, True, final)
            self.credit(frame, 1)
            if final:
                self.complete(frame, lane, batch)
        if cleanup is not None:
            lane = self.p.ports
            if cleanup.addresses:
                self.reclaim(cleanup, lane, batch)
            final = not cleanup.addresses
            released = cleanup.budget if final else 0
            batch.cleanup = Cleanup(cleanup.owner, final, released)
            if final:
                self.credit(cleanup, released)
                self.complete(cleanup, lane, batch)
        self.rows.append((True, True, batch, self.counts()))
        return len(self.rows) - 1

    def reclaim(self, frame, lane, batch):
        address = frame.addresses.pop(0)
        self.busy_cells.remove(address)
        batch.cell_returns[lane] = frame.owner, address
        self.f += 1
        return address

    def credit(self, frame, amount):
        self.h[frame.owner.qid] -= amount
        self.u += amount

    def complete(self, frame, lane, batch):
        batch.desc_returns[lane] = frame.owner
        del self.desc[frame.owner.descriptor]

    def intent(self, ingress, qid, budget, descriptor=None, avoid=()):
        if descriptor is None:
            descriptor = next(index for index in range(self.p.descriptors)
                              if index not in self.desc and index not in avoid)
        sequence = self.sequences[ingress]
        self.sequences[ingress] += 1
        return Intent(Owner(self.epoch, ingress, sequence, qid, descriptor, 7),
                      max(60, (budget - 1) * 64 + 1), budget)

    def grant_many(self, count, *, ingresses=None, qids=None, budget=1):
        ingresses = list(range(count)) if ingresses is None else list(ingresses)
        qids = [0] * count if qids is None else qids
        selected = []
        for ingress, qid in zip(ingresses, qids, strict=True):
            selected.append(self.intent(ingress, qid, budget,
                                        avoid=[f.owner.descriptor for f in selected]))
        return selected

    def provision(self, *, budget=1, written=None, ingress=0, qid=0,
                  descriptor=None, addresses=(), phase="queued"):
        frame = self.intent(ingress, qid, budget, descriptor)
        self.edge(grants=[frame])
        written = budget if written is None else written
        for index in range(written):
            self.edge(write=(frame, addresses[index] if index < len(addresses) else None))
        if phase in ("queued", "tx"):
            self.edge()
        if phase == "tx":
            self.edge(dispatch=[frame])
        elif phase == "abort":
            self.edge(aborts=[frame])
        return frame

    def fill_cells(self, free):
        while self.f > free:
            budget = min(self.f - free, self.u, self.p.max_length // 64)
            if budget < 1:
                raise ValueError("Fixture has insufficient credit to reach target physical occupancy")
            self.provision(budget=budget, ingress=1, qid=1)

    def fill_descriptors(self, free):
        while self.counts().descriptor_free > free:
            self.provision(ingress=1, qid=1)

    def drain(self):
        for frame in list(self.desc.values()):
            if frame.phase == "rx":
                while len(frame.addresses) < frame.budget:
                    self.edge(write=(frame, None))
                self.edge()
        for lane in range(self.p.ports):
            bound = [f for f in self.desc.values() if f.phase == "tx" and f.owner.qid // 4 == lane]
            for frame in bound:
                while frame.addresses:
                    self.edge(returns=[frame])
        for frame in list(self.desc.values()):
            if frame.phase == "queued":
                self.edge(dispatch=[frame])
                while frame.addresses:
                    self.edge(returns=[frame])
            elif frame.phase == "abort":
                while frame.owner.descriptor in self.desc:
                    self.edge(cleanup=frame)
        assert self.counts() == Counts(self.p.cells, self.p.cells, 0, 0, self.p.descriptors,
                                      (0,) * self.p.queues)


def cross_placements(profile, kind, capacity):
    """Find fixture placements with enough IDs for the requested actions."""
    buckets = ((0, 0), (1, 1), (2, 4), (5, capacity - 1), (capacity, capacity))
    for cleanup in (0, 1):
        for tx in range(profile.ports + 1):
            origin = 3 if cleanup and tx else 2 if cleanup else int(tx > 0)
            max_allocations = profile.ports - cleanup if kind == "descriptor" else 1
            for allocated in range(max_allocations + 1):
                needed = allocated + (cleanup if kind == "cell" else 0)
                for bucket, (low, high) in enumerate(buckets):
                    free = high if bucket == 3 and tx + cleanup == 0 else max(low, needed)
                    if free <= high and free + tx + cleanup <= capacity:
                        yield (tx + cleanup, allocated, bucket, origin), free


def crosses(profile, kind):
    """Reach every required cross using legal preparation and actual events."""
    capacity = profile.descriptors if kind == "descriptor" else profile.cells
    for coordinates, free in sorted(cross_placements(profile, kind, capacity)):
        count, allocated, old_bin, origin = coordinates
        cleanup_present = origin >= 2
        n_tx = count - int(cleanup_present)
        state = Stimulus(profile)
        transmit = [state.provision(ingress=lane, qid=4 * lane, phase="tx")
                    for lane in range(profile.ports - n_tx, profile.ports)]
        cleanup = None
        if cleanup_present:
            cleanup = state.provision(budget=2 if kind == "cell" else 1,
                                      written=1 if kind == "cell" else 0,
                                      ingress=profile.ports - 1, qid=3, phase="abort")
            # A one-cell completed RX frame cannot format-abort. Keep a second
            # reserved cell for the physical cleanup case.
        if kind == "descriptor":
            state.fill_descriptors(free)
            ingresses = list(range(profile.ports - int(cleanup_present)))
            grants = state.grant_many(allocated, ingresses=ingresses[:allocated],
                                      qids=list(range(allocated)))
            edge = state.edge(grants=grants, returns=transmit, cleanup=cleanup)
        else:
            writer = state.provision(written=0, phase="rx", ingress=0, qid=2) if allocated else None
            state.fill_cells(free)
            edge = state.edge(write=(writer, None) if writer else None, returns=transmit, cleanup=cleanup)
        state.drain()
        label = f"{kind}:{count}:{allocated}:{old_bin}:{origin}"
        yield label, state.rows, edge


@dataclass
class Witness:
    name: str
    state: Stimulus
    triggers: dict[str, int]
    negatives: dict[str, list] = field(default_factory=dict)
    random_priority: int = 1


def alter(rows, index, action, counts=None):
    rows = deepcopy(rows)
    reset_n, initialized, batch, before = rows[index]
    action(batch)
    rows[index] = reset_n, initialized, batch, before if counts is None else counts
    return rows


def descriptor_witness(profile, free):
    state = Stimulus(profile)
    returning = state.provision(phase="tx", qid=4 * (profile.ports - 1))
    old_id = returning.owner.descriptor
    state.fill_descriptors(free)
    prefix = state.grant_many(free, qids=[2] * free)
    overlap = state.edge(grants=prefix, returns=[returning])
    acquire = state.intent(0, 2, 1, descriptor=old_id)
    following = state.edge(grants=[acquire])
    state.drain()
    label = ("descriptor-empty-return", "descriptor-one-prefix", "descriptor-two-prefix")[free]
    case = Witness(label, state, {label: overlap, "descriptor-next-edge": following}, random_priority=3)
    if free == 0:
        bad = Grant(acquire.owner, acquire.length, acquire.budget)
        case.negatives["desc-return-bypass"] = alter(state.rows, overlap, lambda b: b.grants.append(bad))
    if free == 2:
        first, second = state.rows[overlap][2].grants
        owner = second.owner
        duplicate = Owner(owner.epoch, owner.ingress, owner.sequence, owner.qid,
                          first.owner.descriptor, owner.tag)
        case.negatives["descriptor-prefix-repeat"] = alter(
            state.rows, overlap, lambda b: b.grants.__setitem__(1, Grant(duplicate, second.length, 1)))
    return case


def cell_exchange(profile):
    state = Stimulus(profile)
    returning = state.provision(phase="tx", qid=4 * (profile.ports - 1), addresses=[0])
    writer = state.provision(written=0, phase="rx")
    state.fill_cells(1)
    next_desc = next(i for i in range(profile.descriptors) if i not in state.desc)
    edge = state.edge(write=(writer, None), returns=[returning])
    newcomer = state.intent(1, 2, 1, descriptor=next_desc)
    reserve = state.edge(grants=[newcomer])
    reuse = state.edge(write=(newcomer, 0))
    state.drain()

    def use_returned(batch):
        w = batch.write
        batch.write = Write(w.owner, 0, w.index, w.final)

    bad_grant = Grant(newcomer.owner, newcomer.length, newcomer.budget)
    return Witness("cell-exchange", state, {
        "cell-one-exchange": edge, "credit-next-edge": reserve,
        "cell-next-edge": reuse, "reserved-write-zero-U": edge,
    }, {
        "cell-return-bypass": alter(state.rows, edge, use_returned),
        "credit-return-bypass": alter(state.rows, edge, lambda b: b.grants.append(bad_grant)),
    }, random_priority=4)


def exhausted(profile):
    state = Stimulus(profile)
    returning = state.provision(phase="tx", qid=0)
    state.fill_cells(0)
    edge = state.edge(returns=[returning])
    new = state.intent(0, 0, 1)
    state.edge(grants=[new])
    state.edge(write=(new, 0))
    state.drain()

    def write_without_free(batch):
        batch.write = Write(new.owner, 0, 0, True)

    return Witness("cell-exhaustion", state, {}, {
        "physical-exhaustion": alter(state.rows, edge, write_without_free),
    }, random_priority=3)


def fan_in(profile):
    state = Stimulus(profile)
    ends = [state.provision(phase="tx", ingress=lane, qid=4 * lane) for lane in range(profile.ports)]
    aborting = state.provision(phase="abort", budget=2, written=1, ingress=profile.ports - 1)
    grants = state.grant_many(profile.ports - 1)
    everywhere = state.edge(grants=grants, returns=ends, cleanup=aborting)
    highest = state.provision(phase="tx", qid=4 * (profile.ports - 1))
    high = state.edge(returns=[highest])
    highest = state.provision(phase="tx", qid=4 * (profile.ports - 1))
    aborting = state.provision(phase="abort", budget=2, written=1)
    sparse = state.edge(returns=[highest], cleanup=aborting)
    state.drain()
    return Witness("return-lanes", state, {
        "full-return": everywhere, "highest-return": high, "sparse-cleanup": sparse,
    }, {
        "omit-high-lane": alter(state.rows, high, lambda b: b.cell_returns.pop(profile.ports - 1)),
        "repeat-return": alter(state.rows, high,
                               lambda b: b.cell_returns.__setitem__(0, next(iter(b.cell_returns.values())))),
    }, random_priority=4)


def grant_fan_in(profile, same):
    state = Stimulus(profile)
    ends = [state.provision(phase="tx", qid=4 * lane) for lane in range(profile.ports)]
    writer = state.provision(written=0, phase="rx", qid=1)
    qids = [1] * profile.ports if same else list(range(profile.ports))
    prefix = state.grant_many(profile.ports, qids=qids)
    edge = state.edge(grants=prefix, write=(writer, None), returns=ends)
    state.drain()
    name = "full-grant-same-q" if same else "full-grant-different-q"
    return Witness(name, state, {name: edge}, random_priority=4)


def abort_witness(profile):
    state = Stimulus(profile)
    zero = state.intent(0, 1, 2)
    first = state.edge(grants=[zero], aborts=[zero])
    complete = state.edge(cleanup=zero)
    partial = state.provision(budget=3, written=1, ingress=1, phase="rx", qid=2)
    staged = state.edge(write=(partial, None), aborts=[partial])
    reclaim = state.edge(cleanup=partial)
    state.edge(cleanup=partial)
    state.drain()
    final_only = Stimulus(profile)
    last = final_only.intent(0, 1, 1)
    final_only.edge(grants=[last], aborts=[last])
    last_edge = final_only.edge(cleanup=last)
    old_counts = final_only.rows[last_edge - 1][3]

    def omit(batch):
        batch.cleanup = None
        batch.desc_returns.clear()

    def release_early(batch):
        batch.cleanup = Cleanup(partial.owner, False, partial.budget)

    return [Witness("abort-accounting", state, {
        "grant-and-abort": first, "zero-cell-cleanup": complete,
        "mark-with-staged-write": staged, "nonfinal-abort-reclaim": reclaim,
    }, {"early-abort-credit": alter(state.rows, reclaim, release_early)}, random_priority=4),
        Witness("final-cleanup", final_only, {},
                {"omit-final-cleanup": alter(final_only.rows, last_edge, omit, old_counts)})]


def reset_witness(profile):
    state = Stimulus(profile)
    previous = state.provision(phase="tx", addresses=[0], descriptor=0)
    aborting = state.provision(phase="abort", budget=3, written=2, ingress=1)
    state.edge(cleanup=aborting)
    reset = len(state.rows)
    state.reset()
    current = state.provision(phase="tx", addresses=[0], descriptor=0)
    held = state.edge()
    state.edge(held=current)
    retire = state.edge(returns=[current])
    state.drain()

    def stale(batch):
        batch.cell_returns[0] = previous.owner, 0
        batch.desc_returns[0] = previous.owner
        batch.services[0] = Service(previous.owner, 0, True, True)

    return Witness("active-reset", state, {
        "active-abort-reset": reset, "epoch-reused-cell-desc-tag": retire,
        "bound-without-final": held,
    }, {"stale-owner": alter(state.rows, held, stale)}, random_priority=4)


def identity_witness(profile):
    state = Stimulus(profile)
    first = state.provision(qid=0, addresses=[0], descriptor=0)
    last = state.provision(qid=0, ingress=1, addresses=[profile.cells - 1],
                           descriptor=profile.descriptors - 1)
    state.edge(dispatch=[first])
    first_edge = state.edge(returns=[first])
    state.edge(dispatch=[last])
    last_edge = state.edge(returns=[last])
    state.drain()
    return Witness("identity-and-drain", state, {
        "repeated-tag-shared-queue": first_edge, "zero-and-highest-IDs": last_edge,
        "absent-fields": last_edge, "exact-drain": last_edge,
    }, {"omit-final-return": alter(state.rows, last_edge, lambda b: b.desc_returns.clear())})


def witnesses(profile):
    cases = [descriptor_witness(profile, count) for count in range(3)]
    cases += [cell_exchange(profile), exhausted(profile), fan_in(profile),
              grant_fan_in(profile, True), grant_fan_in(profile, False)]
    cases += abort_witness(profile)
    cases += [reset_witness(profile), identity_witness(profile)]
    return cases


def save_rows(path, profile, rows):
    layout = Layout(profile)
    path.write_text("".join(layout.row(*row) + "\n" for row in rows))


def save_triggers(path, triggers):
    path.write_text("".join(f"{edge} {name}\n" for name, edge in sorted(
        triggers.items(), key=lambda item: item[1])))


def generate(root, profile):
    root.mkdir(exist_ok=True)
    templates = []
    for case in witnesses(profile):
        path = root / f"{case.name}.edges"
        save_rows(path, profile, case.state.rows)
        save_triggers(root / f"{case.name}.triggers", case.triggers)
        templates.extend([path.name] * case.random_priority)
        for name, trace in case.negatives.items():
            save_rows(root / f"{name}.edges", profile, trace)
    cross_triggers = {}
    with (root / "crosses.edges").open("w") as stream:
        offset = 0
        for kind in ("descriptor", "cell"):
            for label, rows, edge in crosses(profile, kind):
                cross_triggers[label] = offset + edge
                stream.writelines(Layout(profile).row(*row) + "\n" for row in rows)
                offset += len(rows)
    save_triggers(root / "crosses.triggers", cross_triggers)
    (root / "templates.txt").write_text("\n".join(templates) + "\n")


def generate_candidate(root, profile):
    """Reuse frozen intent and replace the numeric endpoint witness with real scarcity."""
    generate(root, profile)
    state = Stimulus(profile)
    first = state.provision(qid=0)
    remaining = profile.cells - 2
    for frames in range(profile.descriptors - 2, 0, -1):
        budget = remaining // frames
        state.provision(ingress=1, qid=1, budget=budget)
        remaining -= budget
    last = state.provision(qid=0, ingress=1)
    state.edge(dispatch=[first])
    repeated_tag = state.edge(returns=[first])
    state.edge(dispatch=[last])
    inactive = state.edge()
    highest = state.edge(returns=[last])
    state.drain()
    cases = [Witness("identity-and-drain", state, {
        "repeated-tag-shared-queue": repeated_tag, "zero-and-highest-IDs": highest,
        "absent-fields": inactive, "exact-drain": len(state.rows) - 1,
    })]

    state = Stimulus(profile)
    edge = state.edge(grants=state.grant_many(profile.ports - 1))
    state.drain()
    cases.append(Witness("sparse-grants", state, {"sparse-grants": edge}))

    state = Stimulus(profile)
    returning = state.provision(phase="tx")
    first = state.provision(written=0, phase="rx", ingress=0, qid=1)
    second = state.provision(written=0, phase="rx", ingress=1, qid=1)
    state.fill_cells(2)
    state.edge(write=(first, None), returns=[returning])
    edge = state.edge(write=(second, None))
    state.drain()
    cases.append(Witness("cell-next-edge", state, {"live-cell-next-edge": edge}))

    for case in cases:
        save_rows(root / f"{case.name}.edges", profile, case.state.rows)
        save_triggers(root / f"{case.name}.triggers", case.triggers)
