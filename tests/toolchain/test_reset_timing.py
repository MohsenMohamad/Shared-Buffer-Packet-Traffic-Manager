"""Guard complete separated timing evidence and explicit source envelopes."""
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from reset_timing import BASE_GROUPS, measurements
from timing_constraints import CONFIG, constraints, render


def report():
    text = 'R01_COVERAGE 4 5 5\n'
    for group in BASE_GROUPS:
        for delay in ('max', 'min'):
            asynchronous = group == 'reset_checks'
            check = 'recovery' if delay == 'max' else 'removal'
            block = ('Startpoint: rst_n\nEndpoint: ff\nPath Group: ' + ('asynchronous' if asynchronous else 'clk') + '\n'
                     ' 5.00000 ^ rst_n (in)\n 5.10000 ^ ff/RN (DFFR_X1)\n'
                     ' 5.10000 data arrival time\n' + (f' 0.10000 library {check} time\n' if asynchronous else '') +
                     ' -0.10000 slack (VIOLATED)\n')
            text += f'R01_{group}_{delay}_BEGIN\n{block}R01_{group}_{delay}_END\n'
    return text + 'R01_DONE\n'


class ResetTimingTests(unittest.TestCase):
    def setUp(self):
        self.config = json.loads(CONFIG.read_text())
        self.model = constraints(self.config, 'fifo-capability-r01', 'fall-reference-r01', 'slew')

    def test_negative_slack_is_valid_measurement_with_unresolved_source(self):
        self.model['reset_max_ns'] = 0.0  # Synthetic point release matches both port rows.
        data = measurements(report(), self.model, False)
        self.assertEqual(data['model_closure'], 'FAIL')
        self.assertEqual(data['source_closure'], 'UNRESOLVED')
        self.assertEqual(data['required_port_release_window_ns_after_rise'], [5.1, 4.9])
        self.assertFalse(data['release_window_nonempty'])

    def test_missing_removal_or_recovery_and_diagnostics_rejected(self):
        good = report()
        for bad in (good.replace('R01_reset_checks_min_END', ''),
                    good.replace('library removal time', 'library hold time'),
                    good.replace('R01_reset_checks_max_BEGIN', ''),
                    good.replace('R01_COVERAGE 4 5 5', 'R01_COVERAGE 4 5 0'),
                    'Error 123: bad SDC\n' + good, 'Warning: unconstrained\n' + good,
                    good + 'R01_DONE\n'):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                measurements(bad, self.model, False)

    def test_asynchronous_category_overlap_rejected(self):
        bad = report().replace('R01_reset_effects_min_BEGIN\nStartpoint: rst_n\nEndpoint: ff\nPath Group: clk',
                               'R01_reset_effects_min_BEGIN\nStartpoint: rst_n\nEndpoint: ff\nPath Group: asynchronous')
        with self.assertRaisesRegex(ValueError, 'Asynchronous check'):
            measurements(bad, self.model, False)

    def test_missing_bounds_reversed_and_nonfinite_models_rejected(self):
        for change in ('missing', 'reverse', 'nan', 'negative'):
            bad = deepcopy(self.config)
            reset = bad['scenarios']['fall-reference-r01']
            if change == 'missing':
                del reset['reset_min_ns']
            elif change == 'reverse':
                reset['reset_min_ns'] = 0.3
            elif change == 'nan':
                reset['reset_min_ns'] = float('nan')
            else:
                reset['reset_min_ns'] = -0.1
            with self.subTest(change=change), self.assertRaises((ValueError, KeyError)):
                constraints(bad, 'fifo-capability-r01', 'fall-reference-r01', 'slew')

    def test_all_consumers_use_same_reset_events_with_explicit_data_budgets(self):
        for study in self.config['studies']:
            text = render(constraints(self.config, study, 'fall-reference-r01', 'slew'))
            self.assertIn('set_input_delay -min -clock clk -clock_fall 0.0 $reset', text)
            self.assertIn('set_input_delay -max -clock clk -clock_fall 0.2 $reset', text)
            self.assertNotIn('false_path', text)
            self.assertIn('name != rst_n', text)


if __name__ == '__main__':
    unittest.main()
