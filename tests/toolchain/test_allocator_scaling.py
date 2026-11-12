"""Reject misleading timing completion and incomplete production mapping evidence."""
from copy import deepcopy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from allocator_scaling import mapping_measurements, timing_measurements


def timing_report():
    text = 'TM_COVERAGE_DONE\n'
    for group in ('OVERALL', 'selection', 'availability', 'count'):
        for delay in ('max', 'min'):
            tag = f'TM_{group}_{delay}'
            text += (f'{tag}_BEGIN\nStartpoint: bitmap_ff\nEndpoint: available_id[0]\n'
                     f'Path Group: {group}\n 1.00000 data arrival time\n'
                     f' -0.10000 slack (VIOLATED)\n{tag}_END\n')
    return text + 'TM_CHECK_TYPES_BEGIN\nremoval -0.10000\nTM_CHECK_TYPES_END\nTM_STA_DONE\n'


class AllocatorEvidenceTests(unittest.TestCase):
    def test_negative_slack_is_valid_evidence(self):
        self.assertEqual(timing_measurements(timing_report())['selection_max']['slack_ns'], -0.1)

    def test_completion_does_not_override_numbered_or_unnumbered_diagnostics(self):
        for diagnostic in ('Error 123: bad SDC', 'Warning: unconstrained', 'Warning 1554: invalid startpoint'):
            with self.subTest(diagnostic=diagnostic), self.assertRaises(ValueError):
                timing_measurements(diagnostic + '\n' + timing_report())

    def test_empty_selection_missing_hold_and_missing_coverage_rejected(self):
        good = timing_report()
        start = good.index('TM_selection_max_BEGIN')
        end = good.index('TM_selection_max_END')
        empty = good[:start] + 'TM_selection_max_BEGIN\nNo paths found.\n' + good[end:]
        for bad in (empty, good.replace('TM_count_min_END', ''), good.replace('TM_COVERAGE_DONE', '')):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                timing_measurements(bad)

    def test_mapping_rejects_missing_state_unmapped_cell_and_dead_output(self):
        module = dict(cells={'ff': dict(type='DFFR_X1', port_directions={'D': 'input', 'Q': 'output'},
                                       connections={'D': [1], 'Q': [2]})},
                      netnames={}, ports={
                          'clk': dict(direction='input', bits=[3]),
                          'rst_n': dict(direction='input', bits=[4]),
                          **{p: dict(direction='output', bits=[2]) for p in
                             ('available_id', 'free_count', 'available', 'invariant_error')}})
        self.assertEqual(mapping_measurements(module, 1)['state_bits'], 1)
        with self.assertRaises(ValueError):
            mapping_measurements(module, 2)
        bad = deepcopy(module)
        bad['cells']['unmapped'] = dict(type='$mux')
        with self.assertRaises(ValueError):
            mapping_measurements(bad, 1)
        bad = deepcopy(module)
        bad['ports']['available_id']['bits'] = ['0']
        with self.assertRaises(ValueError):
            mapping_measurements(bad, 1)
