#!/usr/bin/env python3
"""Hand-derived edge witnesses and trace detector checks for queue_control."""
from argparse import ArgumentParser
from copy import deepcopy
import json
from pathlib import Path

from queue_control import Bucket, Control, Frame, PROFILES, UNIT, VARIANTS


class Witness:
    def __init__(self, profile, latency, variant):
        self.tm = Control(profile, latency, variant, trace=True)
        self.checks = []
        self.sequence = 0

    def expect(self, label, observed, expected):
        self.checks.append(dict(label=label, after_edge=self.tm.cycle - 1,
                                expected=expected, observed=observed))
        if observed != expected:
            raise AssertionError(f"{label}: expected {expected!r}, got {observed!r}")

    def frame(self, port, dest, cls=0, size=60, **overrides):
        f = Frame(port, self.sequence, dest, cls, size, **overrides)
        self.sequence += 1
        return f

    def seed(self, port, dest, cls=0, size=60, state="queued", assigned=None):
        """Install the explicitly enumerated owners in a reachable pre-edge state."""
        tm = self.tm
        f = self.frame(port, dest, cls, size)
        tm.reserve(f)
        f.state = state
        f.rx = f.beats
        if assigned is None:
            assigned = f.cells
        for _ in range(assigned):
            address = tm.cell.take(f)
            if f.tail is None:
                f.first = address
            else:
                tm.cell_next[f.tail] = address
            f.tail = address
            f.written += 1
            f.assigned += 1
        if state == "queued":
            q = f.qid
            if tm.tail[q] is None:
                tm.head[q] = f.desc
                tm.cache[q] = f.metadata()
            else:
                tm.queue_next[tm.tail[q]] = f.desc
            tm.info[f.desc] = f.metadata()
            tm.tail[q] = f.desc
            tm.depth[q] += 1
            tm.bitmap |= 1 << q
        if state == "tx":
            tm.slots[dest].append(f)
            f.times.update(dispatch=-8, eligible=-1)
            f.read_next, f.unread = f.first, f.cells
        if state == "abort":
            tm.abort[port] = f
            f.abort_next = f.first
            f.times["mark"] = tm.cycle - 1
        if state == "publishing":
            tm.publish_slot = f
            f.state = "rx"
        return f

    def prefetch(self, frame, count):
        tm = self.tm
        for _ in range(count):
            index = frame.cells - frame.unread
            addr = frame.read_next
            frame.ready.append((index, addr))
            tm.prefetch[frame.egress] += 1
            frame.unread -= 1
            frame.read_next = tm.cell_next[addr]

    def offer_heads(self, *frames):
        for f in frames:
            self.tm.capture[f.port].append((f, 1))

    def step(self, ready=None):
        self.tm.step(ready=ready)
        return self.tm.events


def lanes(events, name, field):
    return [item.get(field) for item in events.get(name, ())]


def publication(w, depth):
    tm = w.tm
    old = [w.seed(0, 0) for _ in range(depth)]
    others = [w.seed(port, port) for port in range(1, tm.ports)]
    b = w.seed(0, 0, state="publishing")
    selected = [f.desc for f in old[:1] + others]
    event = w.step()
    w.expect("pre-edge dispatch IDs", lanes(event, "dispatch", "desc"), selected)
    w.expect("one publish", lanes(event, "publication", "desc"), [b.desc])
    w.expect("merged head/tail/bitmap", [tm.head[0], tm.tail[0], tm.bitmap],
             [old[1].desc if depth == 2 else b.desc, b.desc, 1])
    expected = old[1].desc if depth == 2 else b.desc
    w.expect("next edge sees registered head", lanes(w.step(), "dispatch", "desc"), [expected])
    if depth == 2:
        w.expect("append follows old successor", [tm.head[0], tm.tail[0]], [b.desc, b.desc])
    return dict(early_publication=(event, selected)) if depth == 0 else {}


def exchange(w):
    tm = w.tm
    old = w.seed(0, 0, state="publishing")
    nxt = w.seed(0, 0, state="rx", assigned=0)
    last = w.seed(1, 0, state="rx", assigned=0)
    tm.stage[0].append((nxt, -1))
    tm.stage[1].append((last, -1))
    for publish, write, select in ((old, nxt, []), (nxt, last, [old.desc]), (last, None, [nxt.desc])):
        event = w.step()
        w.expect("consecutive slot publication", lanes(event, "publication", "desc"), [publish.desc])
        w.expect("consecutive final write", lanes(event, "write", "frame"), [write.identity] if write else [])
        w.expect("publication exchange pre-edge bind", lanes(event, "dispatch", "desc"), select)
    w.expect("third frame remains queued", [tm.head[0], tm.tail[0], tm.bitmap], [last.desc, last.desc, 1])
    return {}


def descriptor_prefix(w, wait):
    tm = w.tm
    f = w.seed(0, 0, state="tx")
    w.prefetch(f, 1)
    f.tx = 7
    for _ in range(tm.profile.descriptors - 2):
        w.seed(0, 0, cls=1)
    tm.wait = wait
    tm.cursors["admit"] = 1
    offers = [w.frame(p, p, cls=2) for p in range(tm.ports)]
    w.offer_heads(*offers)
    event = w.step()
    old_id = tm.profile.descriptors - 1
    w.expect("rotation starts at ingress one", lanes(event, "admission", "frame"),
             [f.identity for f in offers[1:] + offers[:1]])
    w.expect("only old free ID", lanes(event, "admission", "desc"), [old_id] + [None] * (tm.ports - 1))
    w.expect("temporary old-credit outcome", lanes(event, "admission", "result"),
             ["GRANT"] + ["WAIT" if wait else "DROP"] * (tm.ports - 1))
    w.expect("returned old owner", lanes(event, "desc_return", "desc"), [f.desc])
    w.expect("descriptor returned into next state", tm.desc.free, 1 << f.desc)
    w.expect("WAIT retains input FIFO heads", [len(c) for c in tm.capture],
             [int(wait and p != 1) for p in range(tm.ports)])
    if not wait:
        w.expect("DROP services all considered headers", lanes(event, "service", "beat"), [1] * tm.ports)
        discard = offers[0]
        for beat in range(2, 9):
            tm.capture[0].append((discard, beat))
            w.step()
        w.offer_heads(w.frame(0, 0, cls=2))
    follow = w.step()
    granted = [a["desc"] for a in follow["admission"] if a["result"] == "GRANT"]
    w.expect("reuse on a subsequent edge", granted, [f.desc])
    if wait:
        return dict(return_bypass=(event, old_id, f.desc))
    return {}


def all_returns(w):
    tm = w.tm
    tx = [w.seed(port, port, state="tx") for port in range(tm.ports)]
    for f in tx:
        w.prefetch(f, 1)
        f.tx = 7
    abort = w.seed(tm.ports - 1, 0, cls=1, size=65, state="abort", assigned=1)
    writing = w.seed(0, 0, cls=3, state="rx", assigned=0)
    tm.stage[0].append((writing, -1))
    offers = [w.frame(p, p, cls=2) for p in range(tm.ports - 1)]
    w.offer_heads(*offers)
    before_u = tm.credit
    event = w.step()
    owners = [f.identity for f in tx] + [abort.identity]
    w.expect("all retirement and cleanup lanes", lanes(event, "cell_return", "lane"), list(range(tm.ports + 1)))
    w.expect("cell owners on all lanes", lanes(event, "cell_return", "frame"), owners)
    w.expect("descriptor owners on all lanes", lanes(event, "desc_return", "frame"), owners)
    w.expect("returned physical IDs", lanes(event, "cell_return", "cell"), list(range(tm.ports + 1)))
    w.expect("returned descriptor IDs", lanes(event, "desc_return", "desc"), list(range(tm.ports + 1)))
    w.expect("materialization uses old free cell", lanes(event, "write", "cell"), [tm.ports + 1])
    w.expect("U retains every return", tm.credit, before_u + tm.ports + 2 - len(offers))
    h = [0] * tm.queues
    h[writing.qid] = 1
    for f in offers:
        h[f.qid] = 1
    w.expect("merged H by queue", tm.h, h)
    w.expect("assigned after simultaneous retirement and materialization", len(tm.cell.owner), 1)
    return dict(lost_cleanup=(event, owners))


def four_grants(w):
    # Cleanup and a new header on its own ingress cannot coincide. This row
    # uses all TX lanes plus all admission lanes in a separate legal batch.
    tm = w.tm
    tx = [w.seed(port, port, state="tx") for port in range(tm.ports)]
    for f in tx:
        w.prefetch(f, 1)
        f.tx = 7
    writing = w.seed(0, 0, cls=1, state="rx", assigned=0)
    tm.stage[0].append((writing, -1))
    offers = [w.frame(p, p, cls=2, size=65) for p in range(tm.ports)]
    w.offer_heads(*offers)
    tm.cursors["admit"] = tm.ports - 1
    before_u = tm.credit
    event = w.step()
    w.expect("every prefix grant gets a distinct old-free descriptor",
             lanes(event, "admission", "desc"), list(range(tm.ports + 1, 2 * tm.ports + 1)))
    w.expect("simultaneous TX descriptor returns", lanes(event, "desc_return", "desc"), list(range(tm.ports)))
    w.expect("rotated full prefix", lanes(event, "admission", "frame"),
             [f.identity for f in offers[-1:] + offers[:-1]])
    w.expect("U merged with full prefix and independent write", tm.credit, before_u - tm.ports)
    held = [0] * tm.queues
    held[writing.qid] = 1
    for f in offers:
        held[f.qid] = 2
    w.expect("per-queue merged credit", tm.h, held)
    return {}


def arithmetic(w, credit, wait):
    tm = w.tm
    deficit = tm.profile.cells - credit
    filler = 0
    while deficit:
        count = min(deficit, tm.profile.maximum // 64)
        # Full cells and a partial tail are both reachable queued occupancies.
        w.seed(filler % tm.ports, 0, cls=1, size=64 * count)
        filler += 1
        deficit -= count
    tm.dynamic, tm.wait = True, wait
    tm.alpha[0] = 64
    f = w.frame(0, 0, size=65)
    w.offer_heads(f)
    event = w.step()
    adm = event["admission"][0]
    w.expect("post-reservation alpha boundary", [adm["shared"], adm["threshold"], adm["excess"]],
             [credit - 2, (credit - 2) // 4, 2])
    w.expect("U evaluation", adm["result"], "GRANT" if credit == 10 else "WAIT" if wait else "DROP")
    w.expect("U/H after decision", [tm.credit, tm.h[0]], [8, 2] if credit == 10 else [9, 0])
    return {}


def prefix_queue(w, dynamic):
    tm = w.tm
    tm.dynamic = dynamic
    tm.limit[0] = 2
    if dynamic:
        # At U=10 threshold 2 after the first admission. The second would
        # leave 6 shared, floor(64*6/256)=1 against cumulative excess 4.
        available = tm.profile.cells - 10
        while available:
            count = min(available, tm.profile.maximum // 64)
            w.seed(0, 0, cls=2, size=64 * count)
            available -= count
        tm.alpha[0] = 64
    w.offer_heads(w.frame(0, 0, size=65), w.frame(1, 0, size=65))
    event = w.step()
    w.expect("same-queue prefix uses earlier reservation", lanes(event, "admission", "result"), ["GRANT", "DROP"])
    w.expect("prefix limit reason", lanes(event, "admission", "reason"), ["", "QUEUE_LIMIT"])
    w.expect("exact two-cell held credit", tm.h[0], 2)
    return {}


def bad_headers(w):
    tm = w.tm
    bad = w.frame(0, tm.ports, size=12, wire_length=60)
    malformed = w.frame(1, 0, size=65, wire_length=8)
    w.offer_heads(bad, malformed)
    event = w.step()
    w.expect("route precedes bad length", lanes(event, "admission", "reason"), ["BAD_ROUTE", ""])
    w.expect("valid header reserves then marks", lanes(event, "abort_mark", "frame"), [malformed.identity])
    w.expect("no mark-edge write, publish or cleanup", [len(event.get(k, ())) for k in ("write", "publication", "cleanup")],
             [0, 0, 0])
    event = w.step()
    w.expect("first post-mark grant can complete zero-cell abort", lanes(event, "cleanup", "released"), [2])
    w.expect("zero-cell cleanup has only descriptor return",
             [lanes(event, "cell_return", "cell"), lanes(event, "desc_return", "desc")], [[], [malformed.desc]])
    event = w.step()
    w.expect("cleanup disposition next edge", lanes(event, "disposition", "code"), ["FRAME_ERROR"])
    return {}


def concurrent_mark(w):
    tm = w.tm
    staged = w.seed(0, 0, size=65, state="rx", assigned=0)
    staged.rx, staged.malformed_at = 8, 9
    tm.capture[0].append((staged, 9))
    tm.stage[0].append((staged, -1))
    event = w.step()
    w.expect("earlier staged write finishes on marking edge", lanes(event, "write", "frame"), [staged.identity])
    w.expect("same owner marked", lanes(event, "abort_mark", "frame"), [staged.identity])
    w.expect("no marking-edge reclaim", lanes(event, "cleanup", "cell"), [])
    event = w.step()
    w.expect("cleanup returns the same physical address", lanes(event, "cell_return", "cell"), [0])
    w.expect("entire reservation released once", lanes(event, "cleanup", "released"), [2])
    return {}


def fairness(w, tx_returns=False):
    tm = w.tm
    tx = [w.seed(p, p, size=192, state="tx") for p in range(tm.ports)]
    abort = [w.seed(p, p, cls=1, size=192, state="abort", assigned=3)
             for p in range(tm.ports)]
    tm.cursors["abort"] = tm.cursors["read"] = 1
    if tx_returns:
        for f in tx:
            w.prefetch(f, 1)
            f.tx = 7
    for offset in range(3 * tm.ports):
        event = w.step([tx_returns and offset == 0] * tm.ports)
        expected = (offset + 1) % tm.ports
        if tx_returns and offset == 0:
            w.expect("all cell-final TX returns coexist with a contested abort grant",
                     lanes(event, "cell_return", "lane"), list(range(tm.ports + 1)))
        w.expect("dedicated abort RR under continuous contention", lanes(event, "cleanup", "frame"),
                 [abort[expected].identity])
        expected_read = [] if tx_returns and offset >= 2 * tm.ports else [tx[expected].identity]
        w.expect("parallel read RR under continuous contention", lanes(event, "issue", "frame"), expected_read)
        if offset >= 2 * tm.ports:
            w.expect("final cleanup bound", lanes(event, "cleanup", "done"), [True])
    w.expect("all aborts complete after ports*k edges", [f is None for f in tm.abort], [True] * tm.ports)
    return {}


def strict_binding(w, publish_on_bind):
    tm = w.tm
    active = w.seed(0, 0, size=192, state="tx")
    w.prefetch(active, 3)
    active.tx = 7
    low = w.seed(0, 0, cls=1)
    high = w.seed(1, 0, cls=0, state="publishing")
    tm.mode[0] = "strict"
    tm.port_bucket[0] = Bucket(200 * UNIT, UNIT // 2, 200 * UNIT)
    if publish_on_bind:
        tm.publish_slot = None
        # The frame is complete; its final write is registered as the first edge ends.
        tm.cell.give(high.first, high)
        high.first = high.tail = None
        high.written = high.assigned = 0
        tm.stage[1].append((high, -1))
    event = w.step()
    w.expect("17-beat pre-edge has no binding", lanes(event, "dispatch", "desc"), [])
    w.expect("no tentative debit", tm.port_bucket[0].balance, 200 * UNIT)
    w.expect("active crosses from 17 to 16", active.beats - active.tx, 16)
    w.expect("low remains at head until binding", tm.head[1], low.desc)
    chosen = low if publish_on_bind else high
    event = w.step([False] * tm.ports)
    w.expect("highest eligible pre-edge head binds", lanes(event, "dispatch", "desc"), [chosen.desc])
    w.expect("debit once before refill", tm.port_bucket[0].balance, (140 * UNIT) + UNIT // 2)
    w.expect("binding edge selector sees old high visibility", lanes(event, "publication", "desc"),
             [high.desc] if publish_on_bind else [])
    event = w.step([False] * tm.ports)
    w.expect("stalled active and successor occupy both slots", [f.desc for f in tm.slots[0]],
             [active.desc, chosen.desc])
    w.expect("no rebind while both slots are owned", lanes(event, "dispatch", "desc"), [])
    w.expect("no repeat debit", tm.port_bucket[0].balance, 141 * UNIT)
    return {}


def shaping(w, limiting, threshold, park=False):
    tm = w.tm
    f = w.seed(0, 0, size=65)
    tail = w.seed(0, 0)
    balance = 65 * UNIT if threshold else 65 * UNIT - UNIT // 4
    # Configure a legal capacity with a depleted balance.
    capacity = tm.profile.maximum * UNIT
    if limiting in ("queue", "both"):
        tm.queue_bucket[0] = Bucket(balance, UNIT // 2, capacity)
    if limiting in ("port", "both"):
        tm.port_bucket[0] = Bucket(balance, UNIT // 2, capacity)
    if park:
        tm.mode[0] = "drr"
        tm.open_visit[0] = True
        tm.deficit[0] = 100
    event = w.step()
    w.expect("old credit limits the 65-byte head", lanes(event, "dispatch", "desc"), [f.desc] if threshold else [])
    if not threshold:
        w.expect("blocked head remains owned by queue", tm.head[0], f.desc)
        if park:
            w.expect("park preserves open deficit", [tm.open_visit[0], tm.deficit[0]], [True, 100])
        event = w.step()
        w.expect("following edge sees the refill", lanes(event, "dispatch", "desc"), [f.desc])
    w.expect("only the successor remains queued", tm.head[0], tail.desc)
    if park:
        w.expect("resumed visit charges length without a second quantum", tm.deficit[0], 35)
    return {}


def full_prefetch(w, retire):
    tm = w.tm
    tm.cycle = 7
    active = w.seed(0, 0, size=192, state="tx")
    successor = w.seed(0, 0, size=257 if tm.ports == 4 else 192, state="tx")
    other = w.seed(1, 1, size=65, state="tx")
    w.prefetch(active, 3)
    w.prefetch(successor, 2)
    active.tx = 7
    landing = successor.read_next
    tm.responses.append((7, tm.epoch, successor, 2, landing))
    successor.unread -= 1
    successor.read_next = tm.cell_next[landing]
    tm.prefetch[0] += 1
    writing = w.seed(1, 1, state="rx", assigned=0)
    tm.stage[1].append((writing, 6))
    event = w.step([retire] * tm.ports)
    w.expect("cell-final waits for acceptance", active.tx, 8 if retire else 7)
    w.expect("full pre-edge port never borrows the retiring slot", lanes(event, "issue", "frame"), [other.identity])
    w.expect("coincident write uses a distinct free cell", lanes(event, "write", "cell"),
             [active.cells + successor.cells + other.cells])
    w.expect("response belongs to existing outstanding slot", lanes(event, "response", "cell"), [landing])
    w.expect("credit changes only for the accepted cell-final", tm.prefetch[0], 5 if retire else 6)
    w.expect("actual retirement lane", lanes(event, "cell_return", "lane"), [0] if retire else [])
    if retire and tm.ports == 4:
        event = w.step()
        w.expect("formerly full port can now issue its unread next cell",
                 lanes(event, "issue", "frame"), [successor.identity])
    elif tm.ports == 2:
        w.expect("small two-frame maximum is six cells, hence no seventh request", successor.unread, 0)
    return {}


def handoff(w):
    tm = w.tm
    active = w.seed(0, 0, state="tx")
    w.prefetch(active, 1)
    active.tx = 6
    nxt = w.seed(0, 0)
    first_issue = 2 if tm.variant == "registered-request" else 1
    response = first_issue + tm.latency
    eligible = response + 1
    for edge in range(eligible + 1):
        event = w.step()
        w.expect("first-cell binding edge", lanes(event, "dispatch", "desc"),
                 [nxt.desc] if edge == 0 else [])
        w.expect("first-cell issue edge", lanes(event, "issue", "frame"),
                 [nxt.identity] if edge == first_issue else [])
        w.expect("first-cell fixed response", lanes(event, "response", "frame"),
                 [nxt.identity] if edge == response else [])
        if edge in (response, eligible):
            w.expect("first beat occurs one edge after response", lanes(event, "transfer", "frame"),
                     [nxt.identity] if edge == eligible else [])
    w.expect("binding/request/issue/response/eligible/accepted",
             [nxt.times[k] for k in ("dispatch", "request", "issue", "response", "eligible", "first")],
             [0, first_issue, first_issue, response, eligible, eligible])
    return dict(early_handoff=(w.tm.trace[response]["events"], nxt.identity))


def reset_inflight(w):
    tm = w.tm
    f = w.seed(0, 0)
    w.step([False] * tm.ports)
    for _ in range(2 if tm.variant == "registered-request" else 1):
        w.step([False] * tm.ports)
    w.expect("reset with request outstanding", len(tm.responses), 1)
    saved_trace = tm.trace
    due, old_epoch, _, _, _ = tm.responses[0]
    tm.reset()
    tm.trace = saved_trace
    w.expect("restart restores owned and reserved credit", [len(tm.desc.owner), tm.credit, tm.bitmap],
             [0, tm.profile.cells, 0])
    g = w.seed(0, 0)
    w.expect("same physical IDs are legal in new epoch", [g.desc, g.first], [f.desc, f.first])
    while tm.cycle <= due:
        event = w.step()
    w.expect("stale response is observed in its old epoch",
             [lanes(event, "response", "epoch"), lanes(event, "response", "accepted")],
             [[old_epoch], [False]])
    w.expect("stale response cannot transfer to reused owner", lanes(event, "transfer", "frame"), [])
    w.expect("new epoch's prefetch credit comes only from its own issue",
             tm.prefetch[0], int("issue" in g.times))
    return {}


def check_detector(name, event, expected):
    if name == "early_publication" and lanes(event, "dispatch", "desc") != expected[0]:
        return "selected an unpublished head"
    if name == "return_bypass":
        grants = [a["desc"] for a in event["admission"] if a["result"] == "GRANT"]
        if grants != [expected[0]] or expected[1] in grants:
            return "granted a returned descriptor on the same edge"
    if name == "lost_cleanup":
        if any(lanes(event, kind, "frame") != expected[0] for kind in ("cell_return", "desc_return")):
            return "missing cell or descriptor return owner"
    if name == "early_handoff" and expected[0] in lanes(event, "transfer", "frame"):
        return "accepted a first beat on its response edge"
    return None


def detector(w, name, fixture):
    event, *expected = fixture
    baseline = check_detector(name, event, expected)
    w.expect("legal neighbor passes detector " + name, baseline, None)
    planted = deepcopy(event)
    if name == "early_publication":
        planted.setdefault("dispatch", []).insert(0, dict(desc=event["publication"][0]["desc"]))
        message = "selected an unpublished head"
    elif name == "return_bypass":
        planted["admission"][1].update(result="GRANT", desc=expected[1])
        message = "granted a returned descriptor on the same edge"
    elif name == "lost_cleanup":
        planted["cell_return"].pop()
        message = "missing cell or descriptor return owner"
    else:
        planted.setdefault("transfer", []).append(dict(frame=expected[0]))
        message = "accepted a first beat on its response edge"
    w.expect("expected negative " + name, check_detector(name, planted, expected), message)
    return dict(detector=name, expected=message, legal=event, planted=planted)


def same_queue_feedback(w):
    tm = w.tm
    old = w.seed(0, 0, state="tx")
    w.prefetch(old, 1)
    old.tx = 7
    tm.dynamic = True
    tm.minimum[0] = 2
    first = w.frame(0, 0)
    w.offer_heads(first)
    event = w.step()
    w.expect("grant and old release coincide", [lanes(event, "admission", "desc"),
                                               lanes(event, "desc_return", "desc")], [[1], [0]])
    w.expect("first edge protected and shared credit", [tm.h[0], tm.credit], [1, tm.profile.cells - 1])
    second = w.frame(1, 0)
    w.offer_heads(second)
    event = w.step()
    w.expect("next edge reuses old ID and finds restored protection",
             lanes(event, "admission", "desc"), [0])
    w.expect("second edge protected and shared credit", [tm.h[0], tm.credit], [2, tm.profile.cells - 2])
    crossing = w.frame(2 if tm.ports == 4 else 0, 0, size=65)
    if tm.ports == 2:
        for beat in range(2, first.beats + 1):
            tm.capture[0].append((first, beat))
            w.step(ready=[False] * tm.ports)
    w.offer_heads(crossing)
    event = w.step(ready=[False] * tm.ports)
    w.expect("alpha zero denies shared spill from the minimum", lanes(event, "admission", "reason"),
             ["QUEUE_LIMIT"])
    return {}


def staged_scarcity(w, wait):
    tm = w.tm
    old = w.seed(0, 0, state="tx")
    w.prefetch(old, 1)
    old.tx = 7
    for _ in range(tm.profile.descriptors - 2):
        w.seed(0, 0, cls=1)
    tm.wait = wait
    tm.cursors["admit"] = 1
    offers = [w.frame(p, p, cls=2) for p in range(tm.ports)]
    w.offer_heads(*offers)
    event = w.step(ready=[False] * tm.ports)
    w.expect("sample the rotated batch without consuming it", lanes(event, "header_sample", "frame"),
             [f.identity for f in offers[1:] + offers[:1]])
    w.expect("sample-only edge", [lanes(event, "service", "beat"), tm.desc.free],
             [[], 1 << (tm.profile.descriptors - 1)])
    event = w.step()
    w.expect("commit against sampled descriptors while returning the old owner",
             [lanes(event, "admission", "desc"), lanes(event, "desc_return", "desc")],
             [[tm.profile.descriptors - 1] + [None] * (tm.ports - 1), [0]])
    w.expect("later lanes retain their sampled reason", lanes(event, "admission", "result"),
             ["GRANT"] + ["WAIT" if wait else "DROP"] * (tm.ports - 1))
    if wait:
        w.expect("pending heads sampled using newly visible free ID",
                 len(lanes(w.step(), "header_sample", "frame")), tm.ports - 1)
        w.expect("next batch can commit returned ID", lanes(w.step(), "admission", "desc"),
                 [0] + [None] * (tm.ports - 2))
    return {}


def staged_reset_and_abort(w):
    tm = w.tm
    old = w.frame(0, 0, size=65)
    w.offer_heads(old)
    w.expect("before reset, pending sample", lanes(w.step(), "header_sample", "frame"), [old.identity])
    tm.reset()
    fresh = w.frame(0, 0, size=65, malformed_at=1)
    w.offer_heads(fresh)
    w.expect("only new epoch samples", lanes(w.step(), "header_sample", "frame"), [fresh.identity])
    event = w.step()
    w.expect("new epoch grants and aborts on commit", [lanes(event, "admission", "desc"),
                                                     lanes(event, "abort_mark", "frame")],
             [[0], [fresh.identity]])
    w.expect("cleanup releases only new reservation", lanes(w.step(), "cleanup", "released"), [2])
    w.expect("registered disposition follows cleanup", lanes(w.step(), "disposition", "code"),
             ["FRAME_ERROR"])
    return {}


STAGED_CASES = {
    "staged-descriptor-drop": lambda w: staged_scarcity(w, False),
    "staged-descriptor-wait": lambda w: staged_scarcity(w, True),
    "staged-reset-and-abort": staged_reset_and_abort,
}


CASES = {
    "publish-singleton": lambda w: publication(w, 1),
    "publish-longer": lambda w: publication(w, 2),
    "publish-empty": lambda w: publication(w, 0),
    "publish-exchange": exchange,
    "descriptor-drop": lambda w: descriptor_prefix(w, False),
    "descriptor-wait": lambda w: descriptor_prefix(w, True),
    "returns": all_returns,
    "full-prefix": four_grants,
    "same-queue-feedback": same_queue_feedback,
    "dynamic-pass": lambda w: arithmetic(w, 10, False),
    "dynamic-drop": lambda w: arithmetic(w, 9, False),
    "dynamic-wait": lambda w: arithmetic(w, 9, True),
    "dynamic-prefix": lambda w: prefix_queue(w, True),
    "static-exact-prefix": lambda w: prefix_queue(w, False),
    "bad-headers": bad_headers,
    "marked-with-write": concurrent_mark,
    "arbitration-and-cleanup-bound": fairness,
    "contended-cleanup-with-returns": lambda w: fairness(w, True),
    "strict-before-bind": lambda w: strict_binding(w, False),
    "strict-on-bind": lambda w: strict_binding(w, True),
    "old-queue-credit": lambda w: shaping(w, "queue", False),
    "old-port-credit": lambda w: shaping(w, "port", False),
    "old-dual-credit": lambda w: shaping(w, "both", False),
    "exact-dual-credit": lambda w: shaping(w, "both", True),
    "parked-visit": lambda w: shaping(w, "queue", False, True),
    "full-prefetch-hold": lambda w: full_prefetch(w, False),
    "full-prefetch-exchange": lambda w: full_prefetch(w, True),
    "handoff": handoff,
    "reset-inflight": reset_inflight,
}


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--json", type=Path, required=True)
    parser.add_argument("--case", choices=(*CASES, *STAGED_CASES))
    args = parser.parse_args()
    rows = []
    for profile_name, profile in PROFILES.items():
        for variant in (*VARIANTS, "staged-admission"):
            for latency in (1, 2):
                cases = STAGED_CASES if variant == "staged-admission" else CASES
                for name, case in cases.items():
                    if args.case and name != args.case:
                        continue
                    w = Witness(profile, latency, variant)
                    row = dict(profile=profile_name, variant=variant, latency=latency,
                               case=name, checks=w.checks, result="PASS")
                    try:
                        fixtures = case(w)
                        row["negatives"] = [detector(w, n, fixture) for n, fixture in fixtures.items()]
                    except (AssertionError, IndexError, KeyError, TypeError) as error:
                        row.update(result="FAIL", failure=str(error))
                        print(f"{profile_name}/{variant}/L{latency}/{name}: {type(error).__name__}: {error}")
                    row["trace"] = w.tm.trace
                    rows.append(row)
    if not rows:
        parser.error("no directed case selected")
    args.json.write_text(json.dumps(rows, indent=2) + "\n")
    failed = sum(row["result"] != "PASS" for row in rows)
    negatives = sum(len(row.get("negatives", ())) for row in rows)
    print(f"{len(rows) - failed}/{len(rows)} directed witnesses pass, {negatives} intended detections")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
