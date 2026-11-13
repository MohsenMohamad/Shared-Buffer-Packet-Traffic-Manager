"""Hand-calculated passive traces, not a production memory/TX campaign."""
import unittest

from dv.model.memory_tx import Beat, Edge, Info, MemoryTxModel, Violation


class Trace:
    """A tiny fixed-latency RAM environment, separate from the passive oracle.

    Samples requests/writes; deliberately retains RAM and responses across reset.
    Output levels and resource events always come from the explicit trace.
    """
    def __init__(self, latency=1, depth=4):
        self.model = MemoryTxModel(latency=latency, depth=depth)
        self.latency = latency
        self.clock = -1
        self.words = {}
        self.responses = {}
        self.tick(reset=True)
        self.tick(reset=True)
        self.tick()

    def tick(self, **signals):
        self.clock += 1
        response = self.responses.pop(self.clock, None)
        signals.setdefault('response', response)
        edge = Edge(**signals)
        self.model.step(edge)
        if edge.read is not None:
            self.responses[self.clock + self.latency] = self.words[edge.read]
        if edge.write:
            self.words[edge.write[0]] = edge.write[1]

    def load(self, desc, info, cells, words):
        self.tick(reserve=(desc, info))
        for cell in cells:
            self.tick(allocate=(desc, cell))
        for left, right in zip(cells, cells[1:]):
            self.tick(link_write=(left, right))
        for ordinal, data in enumerate(words):
            cell_index, offset = divmod(ordinal, 2)
            self.tick(write=(cells[cell_index] * 2 + offset, data))
        self.tick(commit=desc)

    def dispatch(self, desc, info):
        self.tick(dispatch=(desc, info))

    def complete(self, desc, cell, data, info, keep=255):
        self.tick(output=Beat(data, keep, True, info.user), ready=True,
                  cell_return=(desc, cell), desc_return=desc, done=desc)


class BaselineTraces(unittest.TestCase):
    def test_hand_calculated_normal_little_endian_and_unused_lanes(self):
        for latency in (1, 2):
            with self.subTest(latency=latency):
                t = Trace(latency)
                info = Info(9, qid=3, tag=0x1234, source=1)
                t.load(0, info, [3], [0x0706050403020100, 0xFFEEDDCCBBAA9908])
                self.assertEqual(t.model.packets[0].payload, bytes(range(9)))
                self.assertEqual(info.user, 0x011234000903)
                t.dispatch(0, info)
                t.tick(read=6)
                t.tick(read=7)
                if latency == 2:
                    t.tick()
                t.tick(output=Beat(0x0706050403020100, 255, False, info.user), ready=True)
                # Only lane 0 is meaningful; the other seven differ from RAM.
                t.complete(0, 3, 0xA5A5A5A5A5A5A508, info, keep=1)
                t.model.finish(['packet_completed', 'cell_retired'])

    def test_hand_calculated_cell_boundary_and_earliest_legal_reuse(self):
        for latency in (1, 2):
            with self.subTest(latency=latency):
                t = Trace(latency)
                info = Info(17, tag=7)
                t.load(0, info, [3, 1], [0x0706050403020100,
                                       0x0F0E0D0C0B0A0908, 0x9999999999999910])
                self.assertEqual(t.model.packets[0].payload, bytes(range(17)))
                t.dispatch(0, info)
                t.tick(read=6, capture_next=(3, 1))
                t.tick(read=7)
                if latency == 2:
                    t.tick(read=2)
                else:
                    t.tick(read=2, output=Beat(0x0706050403020100, 255, False, info.user), ready=True)
                if latency == 2:
                    t.tick(output=Beat(0x0706050403020100, 255, False, info.user), ready=True)
                boundary = Beat(0x0F0E0D0C0B0A0908, 255, False, info.user)
                for _ in range(4):
                    t.tick(output=boundary)  # prefetch progressed; ownership has not
                    self.assertEqual(t.model.owners[3], 0)
                next_info = Info(8, tag=7)  # deliberately duplicate tag
                t.tick(output=boundary, reserve=(1, next_info))
                t.tick(output=boundary, ready=True, cell_return=(0, 3))
                # Allocate on the very next edge after return; overwrite this
                # cell before the old packet EOF. No same-edge return bypass.
                t.tick(allocate=(1, 3))
                t.tick(write=(6, 0x8786858483828180))
                t.tick(commit=1)
                final = Beat(0x1010101010101010, 1, True, info.user)
                t.tick(output=final)
                t.tick(output=final)
                t.complete(0, 1, final.data, info, keep=1)
                t.dispatch(1, next_info)
                t.tick(read=6)
                for _ in range(latency):
                    t.tick()
                t.complete(1, 3, 0x8786858483828180, next_info)
                t.model.finish(['cell_retired', 'packet_completed'])

    def test_first_full_credit_stalls_all_latency_depth_pairs(self):
        for latency in (1, 2):
            for depth in (4, 8):
                with self.subTest(latency=latency, depth=depth):
                    t = Trace(latency, depth)
                    info = Info(96)
                    # Hand formula: word i contains byte values 8*i .. 8*i+7.
                    words = [int.from_bytes(bytes(range(8*i, 8*i+8)), 'little')
                             for i in range(12)]
                    cells = list(range(6))
                    t.load(0, info, cells, words)
                    t.dispatch(0, info)
                    for i in range(depth):
                        t.tick(read=i, capture_next=(i//2, i//2+1) if i % 2 == 0 and i < 10 else None)
                    self.assertEqual(t.model.credits, depth)
                    self.assertGreater(t.model.outstanding, 0)
                    for _ in range(latency + 5):
                        t.tick()  # immediate stall following issue, across arrival
                    self.assertEqual((len(t.model.fifo), t.model.outstanding), (depth, 0))
                    # Return one slot per edge while issuing remaining requests.
                    for i in range(12):
                        final = i == 11
                        release = (0, i//2) if i % 2 or final else None
                        read = depth + i if depth + i < 12 else None
                        capture = (read//2, read//2+1) if read is not None and read % 2 == 0 and read < 10 else None
                        if final:
                            held = Beat(words[i], 255, True, info.user)
                            for _ in range(5):
                                t.tick(output=held)
                        t.tick(output=Beat(words[i], 255, final, info.user), ready=True,
                               cell_return=release, read=read, capture_next=capture,
                               desc_return=0 if final else None, done=0 if final else None)
                    t.model.finish(['full_credit_stall', 'pending_response_stall',
                                    'issue_response_retire', 'packet_completed'])

    def test_first_pending_response_reset_without_clearing_ram(self):
        for latency in (1, 2):
            with self.subTest(latency=latency):
                t = Trace(latency)
                info = Info(8, tag=9)
                t.load(0, info, [0], [0x1716151413121110])
                t.dispatch(0, info)
                t.tick(read=0)
                t.tick(reset=True)
                t.tick(reset=True)
                t.tick()  # first post-release edge initializes
                self.assertEqual(t.model.ram[0], 0x1716151413121110)
                self.assertFalse(t.model.fifo)
                self.assertEqual(t.model.credits, 0)
                # New epoch immediately after legal initialization, same IDs/tag.
                t.load(0, info, [0], [0x9796959493929190])
                t.dispatch(0, info)
                t.tick(read=0)
                for _ in range(latency):
                    t.tick()
                t.complete(0, 0, 0x9796959493929190, info)
                t.model.finish(['reset_pending', 'packet_completed'])

    def test_named_error_detectors(self):
        def active(latency=1, depth=4, length=8):
            t = Trace(latency, depth)
            info = Info(length)
            cells = list(range((length + 15)//16))
            words = [0x0706050403020100 + i for i in range((length + 7)//8)]
            t.load(0, info, cells, words)
            t.dispatch(0, info)
            return t, info

        t, info = active()
        t.tick(read=0)
        t.tick()
        with self.assertRaisesRegex(Violation, '^MTX_OUTPUT_BYTES$'):
            t.complete(0, 0, 0x0001020304050607, info)
        t, info = active()
        with self.assertRaisesRegex(Violation, '^MTX_CELL_RETIREMENT$'):
            t.tick(cell_return=(0, 0))
        t, info = active(length=64)
        for i in range(4):
            t.tick(read=i)
        with self.assertRaisesRegex(Violation, '^MTX_OVERISSUE$'):
            t.tick(read=4)
        t, info = active(latency=2)
        t.tick(read=0)
        with self.assertRaisesRegex(Violation, '^MTX_RESPONSE_LATENCY$'):
            t.tick(response=0x0706050403020100)
        t, info = active()
        t.tick(read=0)
        t.tick()
        held = Beat(0x0706050403020100, 255, True, info.user)
        t.tick(output=held)
        with self.assertRaisesRegex(Violation, '^MTX_STABILITY$'):
            t.tick(output=Beat(held.data ^ (1 << 63), 255, True, info.user))
        t, info = active()
        t.tick(read=0)
        t.tick(reset=True)
        t.tick(reset=True)
        t.tick()
        with self.assertRaisesRegex(Violation, '^MTX_OUTPUT_WITHOUT_RESPONSE$'):
            t.tick(output=held, ready=True)
        t, info = active()
        t.tick(read=0)
        with self.assertRaisesRegex(Violation, '^MTX_MEMORY_DATA$'):
            t.tick(response=0x0706050403020101)
        t, info = active()
        t.tick(read=0)
        t.tick()
        with self.assertRaisesRegex(Violation, '^MTX_OUTPUT_FRAMING$'):
            t.tick(output=Beat(0x0706050403020100, 127, True, info.user))
        t, info = active()
        t.tick(read=0)
        t.tick()
        with self.assertRaisesRegex(Violation, '^MTX_OUTPUT_METADATA$'):
            t.tick(output=Beat(0x0706050403020100, 255, True, info.user ^ 1))
        t, info = active()
        with self.assertRaisesRegex(Violation, '^MTX_RESOURCE_LEAK$'):
            t.model.finish()
        with self.assertRaisesRegex(Violation, '^MTX_MISSING_PRESSURE:full_credit_stall$'):
            Trace().model.finish(['full_credit_stall'])


if __name__ == '__main__':
    unittest.main()
