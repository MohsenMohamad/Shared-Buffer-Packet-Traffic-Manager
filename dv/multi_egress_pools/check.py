"""Check sealed monitor output and write replayable coverage observations."""

from collections import Counter
from copy import deepcopy
from dataclasses import asdict
import hashlib
import re

from abi import Layout
from coverage_plan import BOUNDARIES, SOURCES, boundary, source
from oracle import PoolOracle, Violation, require


def coordinates(batch, before, profile):
    return (
        (len(batch.desc_returns), len(batch.grants),
         boundary(before.descriptor_free, profile.descriptors),
         source(batch.desc_returns, profile.ports)),
        (len(batch.cell_returns), int(batch.write is not None),
         boundary(before.physical_free, profile.cells),
         source(batch.cell_returns, profile.ports)),
    )


def activity(batch):
    return any((batch.grants, batch.write, batch.publication, batch.dispatches,
                batch.services, batch.aborts, batch.cleanup, batch.cell_returns, batch.desc_returns))


def masks(events):
    return sum(1 << lane for lane in events)


def witness(label, edge):
    batch, pre, post, reused, reset_live, all_rows, raw, layout = edge
    ports = layout.ports
    if label.startswith(("descriptor:", "cell:")):
        kind, returns, grants, old_free, origin = label.split(":")
        expected = (int(returns), int(grants), old_free, origin)
        return expected == coordinates(batch, pre, edge.profile)[int(kind == "cell")]
    if label in ("descriptor-empty-return", "descriptor-one-prefix", "descriptor-two-prefix"):
        number = ("descriptor-empty-return", "descriptor-one-prefix", "descriptor-two-prefix").index(label)
        return pre.descriptor_free == len(batch.grants) == number and len(batch.desc_returns) == 1
    if label == "descriptor-next-edge":
        return pre.descriptor_free == 1 and len(batch.grants) == 1 and bool(reused[1])
    if label == "credit-next-edge":
        return all_rows and all_rows[-1][1].unreserved == 0 and pre.unreserved == 1 and post.unreserved == 0
    if label == "cell-one-exchange":
        return (pre.physical_free == post.physical_free == 1 and batch.write is not None
                and len(batch.cell_returns) == 1)
    if label == "cell-next-edge":
        return (pre.physical_free == 1 and batch.write is not None and len(all_rows) >= 2
                and batch.write.address in {address for _, address in all_rows[-2][0].cell_returns.values()})
    if label == "reserved-write-zero-U":
        return pre.unreserved == 0 and pre.reserved_free > 0 and batch.write is not None
    if label == "full-return":
        return len(batch.desc_returns) == len(batch.cell_returns) == ports + 1
    if label == "highest-return":
        return set(batch.desc_returns) == set(batch.cell_returns) == {ports - 1}
    if label == "sparse-cleanup":
        return set(batch.desc_returns) == set(batch.cell_returns) == {ports - 1, ports}
    if label in ("full-grant-same-q", "full-grant-different-q"):
        count = 1 if label.endswith("same-q") else ports
        return (len(batch.grants) == ports and len({g.owner.qid for g in batch.grants}) == count
                and all(len(events) == ports for events in (batch.desc_returns, batch.cell_returns))
                and batch.write is not None)
    if label == "grant-and-abort":
        return len(batch.grants) == 1 and batch.grants[0].owner in {owner for owner, _ in batch.aborts.values()}
    if label == "zero-cell-cleanup":
        return batch.cleanup is not None and batch.cleanup.done and ports not in batch.cell_returns
    if label == "mark-with-staged-write":
        return batch.write is not None and batch.write.owner in {owner for owner, _ in batch.aborts.values()}
    if label == "nonfinal-abort-reclaim":
        return (batch.cleanup is not None and not batch.cleanup.done
                and post.physical_free == pre.physical_free + 1
                and post.reserved_free == pre.reserved_free + 1
                and post.unreserved == pre.unreserved and post.queue_credit == pre.queue_credit)
    if label == "active-abort-reset":
        return not batch.present and pre.assigned > 0 and pre.reserved_free > 0 and reset_live
    if label == "epoch-reused-cell-desc-tag":
        return any(any(old.address == address and old.owner.descriptor == owner.descriptor
                       and old.owner.tag == owner.tag and old.owner.epoch != owner.epoch
                       for old in reset_live)
                   for owner, address in batch.cell_returns.values())
    if label == "bound-without-final":
        return pre == post and not batch.desc_returns and all_rows[-1][0].dispatches
    if label == "repeated-tag-shared-queue":
        grants = [g.owner for sample, _ in all_rows for g in sample.grants]
        return any(first.tag == second.tag and first.qid == second.qid and first.frame != second.frame
                   for first in grants for second in grants)
    if label == "zero-and-highest-IDs":
        return (any(g.owner.descriptor == 0 for sample, _ in all_rows for g in sample.grants)
                and any(sample.write is not None and sample.write.address == 0 for sample, _ in all_rows)
                and any(owner.descriptor == edge.profile.descriptors - 1 for owner in batch.desc_returns.values())
                and any(address == edge.profile.cells - 1 for _, address in batch.cell_returns.values()))
    if label == "absent-fields":
        return raw != layout.encode(batch)
    if label == "exact-drain":
        return post.physical_free == edge.profile.cells and post.descriptor_free == edge.profile.descriptors
    raise ValueError(f"Unknown directed trigger {label}")


class Edge:
    def __init__(self, batch, pre, post, reused, reset_live, history, raw, layout, profile):
        self.values = batch, pre, post, reused, reset_live, history, raw, layout
        self.profile = profile

    def __iter__(self):
        return iter(self.values)


def check_trace(path, profile, *, triggers=None, detector=None, coverage=None, expected_edges=None):
    layout = Layout(profile)
    oracle = PoolOracle(profile)
    accepted_fingerprint, results_fingerprint = hashlib.sha256(), hashlib.sha256()
    features = set()
    reached, first_detection = {}, None
    trigger_edges = {}
    for label, edge in (triggers or {}).items():
        trigger_edges.setdefault(edge, []).append(label)
    activity_edges = 0
    samples = 0
    remember_identity = "repeated-tag-shared-queue" in (triggers or {})
    history, seen_writes, reset_live = [], {}, []
    for number, line in enumerate(path.open()):
        edge_text, row = line.split(maxsplit=1)
        reset_n, initialized, origin, batch, observed = layout.read_row(row)
        prior_desc = None
        if not reset_n and oracle.epoch is not None:
            reset_live = list(seen_writes.values())
            had_abort = any(frame.phase == "ABORT" for frame in oracle.frames.values())
            if not had_abort:
                reset_live = []
            seen_writes.clear()
        if detector == "STALE_OWNER" and batch.cell_returns and any(
                owner.epoch != batch.epoch for owner, _ in batch.cell_returns.values()):
            prior_desc = deepcopy(oracle.frames), dict(oracle.cells)
        try:
            before, after, reclaimed = oracle.sample(int(edge_text), reset_n, initialized, batch, observed)
        except Violation as error:
            if detector != error.detector or first_detection is not None:
                raise ValueError(f"edge {number}: {error}") from error
            first_detection = {"name": error.detector, "edge": number, "detail": str(error)}
            if detector != "STALE_OWNER":
                break
            require(prior_desc == (oracle.frames, oracle.cells), "STALE_OWNER_EFFECT", number)
            continue

        raw = int(row.split()[3], 16)
        reused = ({batch.write.address} & reclaimed[0] if batch.write else set(),
                  {g.owner.descriptor for g in batch.grants} & reclaimed[1])
        if batch.write:
            seen_writes[batch.write.address] = batch.write
        for _, address in batch.cell_returns.values():
            seen_writes.pop(address, None)
        for label in trigger_edges.get(number, ()):
            require(witness(label, Edge(batch, before, after, reused, reset_live,
                                        history, raw, layout, profile)), "DIRECTED_TRIGGER", (label, number))
            reached[label] = {"edge": number, "pre": asdict(before), "post": asdict(after),
                              "grants": [asdict(g.owner) for g in batch.grants],
                              "cell_mask": masks(batch.cell_returns),
                              "descriptor_mask": masks(batch.desc_returns),
                              "cell_write": asdict(batch.write) if batch.write else None,
                              "cleanup": asdict(batch.cleanup) if batch.cleanup else None}
        history.append((batch, before))
        if len(history) > 2 and not remember_identity:
            history.pop(0)

        if reset_n and initialized:
            desc, cell = coordinates(batch, before, profile)
            if coverage is not None:
                coverage.write(" ".join(str(value) for value in (
                    *desc[:2], BOUNDARIES.index(desc[2]), SOURCES.index(desc[3]),
                    *cell[:2], BOUNDARIES.index(cell[2]), SOURCES.index(cell[3]))) + "\n")
            samples += 1
            if origin == 1 and activity(batch):
                activity_edges += 1
                for name, items in (("descriptor", desc), ("cell", cell)):
                    features.add(f"{name}-{items[2]}")
                if batch.grants and batch.desc_returns:
                    features.add("grant-and-return")
                if batch.write and batch.cell_returns:
                    features.add("write-and-return")
                if "mixed" in (desc[3], cell[3]):
                    features.add("mixed-source")
                if len(batch.grants) > 1:
                    features.add("same-q" if len({g.owner.qid for g in batch.grants}) == 1 else "different-q")
                if any(reused):
                    features.add("next-edge-reuse")
        if origin == 1 and not reset_n and before.descriptor_free < profile.descriptors:
            features.add("reset-with-ownership")
        accepted_fingerprint.update(f"{number} {int(reset_n)} {layout.encode(batch):x}\n".encode())
        results_fingerprint.update(f"{after}\n".encode())

    if expected_edges is not None and (detector is None or detector == "STALE_OWNER"):
        require(oracle.edge + 1 == expected_edges, "MONITOR_EDGE_COUNT", (oracle.edge + 1, expected_edges))
    if detector is None or detector in ("STALE_OWNER", "DRAIN_OWNERSHIP"):
        try:
            oracle.drained()
        except Violation as error:
            if detector != "DRAIN_OWNERSHIP" or error.detector != detector:
                raise
            first_detection = {"name": error.detector, "edge": oracle.edge, "detail": str(error)}
    if detector:
        require(first_detection is not None, "MUTATION_NOT_DETECTED", detector)
        if detector == "STALE_OWNER":
            require(oracle.edge > first_detection["edge"], "STALE_REPLAY_NEIGHBOR", oracle.edge)
    require(reached.keys() == (triggers or {}).keys(), "MISSING_TRIGGERS", set(triggers or {}) - reached.keys())
    require(samples > 0, "EMPTY_OBSERVATION", path)
    return {
        "edges": oracle.edge + 1, "samples": samples, "random_activity_edges": activity_edges,
        "features": sorted(features), "accepted_sha256": accepted_fingerprint.hexdigest(),
        "result_sha256": results_fingerprint.hexdigest(), "triggers": reached,
        "detected": first_detection,
    }


CROSS_BIN = re.compile(
    r"::(descriptor_cross|cell_cross)\.combinations\.<count\[(\d+)\],"
    r"count\[(\d+)\],bucket\[(\d+)\],origin\[(\d+)\]>")


def coverage_counts(path):
    """Read only the named native covergroup crosses from the saved database."""
    hits = {"descriptor": Counter(), "cell": Counter()}
    for line in path.open():
        if not line.startswith("C ") or "\x01t\x02covergroup" not in line:
            continue
        encoded, count = line.rsplit(" ", 1)
        fields = dict(item.split("\x02", 1) for item in encoded.split("\x01") if "\x02" in item)
        match = CROSS_BIN.search(fields.get("h", ""))
        if match is None:
            continue
        kind, returned, allocated, free, src = match.groups()
        hits[kind.removesuffix("_cross")][int(returned), int(allocated),
                                         BOUNDARIES[int(free)], SOURCES[int(src)]] += int(count)
    require(all(any(kind.values()) for kind in hits.values()), "EMPTY_NATIVE_COVERAGE", path)
    return hits
