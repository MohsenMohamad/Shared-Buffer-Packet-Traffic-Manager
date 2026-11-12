"""False-pass guards for recorded packet/handshake qualification."""
from copy import deepcopy
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools'))
from packet_stimulus import compare_handshakes, records


class PacketEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.beat = dict(data=0x8877665544332211, keep=1, last=1, user=0x07000100)
        self.status = dict(code=0, qid=0, length=1, tag=7)
        self.inputs = {0: [self.beat]}
        self.statuses = {0: [self.status]}
        self.outputs = [self.beat]
        encoded = dict(self.beat, data=f'{self.beat["data"]:016x}', user=f'{self.beat["user"]:016x}')
        self.observed = [dict(encoded, kind='capture', source=0, epoch=1, cycle=1),
                         dict(self.status, kind='status', source=0, epoch=1, cycle=2),
                         dict(encoded, kind='output', source=0, epoch=1, cycle=3)]

    def check(self, observed):
        compare_handshakes(self.inputs, self.statuses, self.outputs, observed, 1)

    def test_complete_handshakes_and_ignored_output_lanes(self):
        self.check(self.observed)
        observed = deepcopy(self.observed)
        observed[-1]['data'] = '0000000000000011'
        self.check(observed)  # Only lane zero is valid.

    def test_missing_accepted_beats_status_or_output_fails(self):
        for index in range(3):
            with self.subTest(index=index), self.assertRaises(ValueError):
                self.check(self.observed[:index]+self.observed[index+1:])

    def test_corrupted_captured_or_delivered_payload_fails(self):
        for index in (0, 2):
            observed = deepcopy(self.observed)
            observed[index]['data'] = '8877665544332210'
            with self.subTest(index=index), self.assertRaises(ValueError):
                self.check(observed)

    def test_duplicate_or_stale_handshake_fails(self):
        for kind in range(3):
            observed = deepcopy(self.observed)
            observed.insert(kind, deepcopy(observed[kind]))
            with self.subTest(kind=kind), self.assertRaisesRegex(ValueError, 'Duplicate/stale'):
                self.check(observed)

    def test_wrong_disposition_does_not_count_as_negative_coverage(self):
        observed = deepcopy(self.observed)
        observed[1]['code'] = 6
        with self.assertRaisesRegex(ValueError, 'disposition'):
            self.check(observed)

    def test_output_metadata_and_framing_are_checked(self):
        for field, value in (('user', '0000000008000100'), ('keep', 3), ('last', 0)):
            observed = deepcopy(self.observed)
            observed[-1][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'framing/metadata'):
                self.check(observed)

    def test_invalid_monitor_source_is_not_accepted(self):
        observed = deepcopy(self.observed)
        observed[0]['source'] = 1
        with self.assertRaisesRegex(ValueError, 'Invalid observed'):
            self.check(observed)

    def test_empty_or_malformed_record_is_not_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'stimulus.jsonl'
            for text in ('', '{incomplete'):
                path.write_text(text)
                with self.subTest(text=text), self.assertRaises(ValueError):
                    records(path)


if __name__ == '__main__':
    unittest.main()
