"""Contract tests for false passes, process bounds and evidence retention."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from evidence import Run, completed, execute, output
from run import assertion_result, inspect_coverage, unit
from setup_toolchain import fetch
from runner_fixture import isolated_runner_repository


def process_stopped(pid):
    """A vanished /proc entry and an unreaped zombie are both stopped."""
    try:
        return Path(f'/proc/{pid}/stat').read_text().split()[2] == 'Z'
    except (FileNotFoundError, ProcessLookupError):
        # The kernel can remove the process before opening or during the read.
        return True


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name)

    def process(self, code, timeout=5):
        return execute([sys.executable, '-c', code], self.path, 'process', timeout)

    def test_nonzero_even_with_pass_marker(self):
        step = self.process('print("DONE"); raise SystemExit(3)')
        self.assertEqual(completed(step, 'DONE')[0], 'TOOL_ERROR')

    def test_zero_without_completion_marker(self):
        self.assertEqual(completed(self.process('pass'), 'DONE')[0], 'FAIL')

    def test_missing_tool(self):
        step = execute([str(self.path / 'missing')], self.path, 'missing', 1)
        self.assertEqual(step['result'], 'TOOL_ERROR')
        self.assertTrue(Path(step['stderr']).read_text())

    def test_ignored_constraint_cannot_pass(self):
        step = self.process('print("%Warning-CONSTRAINTIGN: ignored\\nDONE")')
        self.assertEqual(completed(step, 'DONE')[0], 'UNSUPPORTED')

    def test_uvm_error_overrides_completion_marker(self):
        for text in ('UVM_ERROR @ 123: failed', 'UVM_FATAL : 1'):
            step = self.process('print(' + repr(text + '\nDONE') + ')')
            self.assertEqual(completed(step, 'DONE')[0], 'FAIL')
        step = self.process('print("UVM_ERROR : 0\\nUVM_FATAL : 0\\nDONE")')
        self.assertEqual(completed(step, 'DONE')[0], 'PASS')

    def test_executed_functional_failure_differs_from_tool_error(self):
        step = self.process('print("UVM_FATAL @ 123: failed"); raise SystemExit(1)')
        self.assertEqual(completed(step, 'DONE')[0], 'FAIL')
        step = self.process('print("syntax error"); raise SystemExit(1)')
        self.assertEqual(completed(step, 'DONE')[0], 'TOOL_ERROR')

    def test_negative_assertion_requires_executed_assertion_and_wave(self):
        wave = self.path / 'wave.vcd'
        step = self.process('print("syntax error"); raise SystemExit(1)')
        self.assertEqual(assertion_result(step, wave)[0], 'FAIL')
        step = self.process('print("TM_CAP_STABILITY_FAIL"); raise SystemExit(1)')
        self.assertEqual(assertion_result(step, wave)[0], 'FAIL')
        wave.write_text('$enddefinitions $end\n')
        self.assertEqual(assertion_result(step, wave)[0], 'PASS')

    def test_stdout_stderr_are_separate(self):
        step = self.process('import sys; print("out"); print("err", file=sys.stderr)')
        self.assertEqual(Path(step['stdout']).read_text(), 'out\n')
        self.assertEqual(Path(step['stderr']).read_text(), 'err\n')

    def test_timeout_kills_descendant(self):
        pidfile = self.path / 'child.pid'
        code = ('import subprocess,time,pathlib; '
                'p=subprocess.Popen(["sleep","30"]); '
                f'pathlib.Path({str(pidfile)!r}).write_text(str(p.pid)); time.sleep(30)')
        # Include interpreter startup under a busy cloud CPU quota. The test
        # still requires a spawned child and verifies it cannot survive timeout.
        step = self.process(code, timeout=5)
        self.assertEqual(step['result'], 'TIMEOUT')
        self.assertEqual(step['returncode'], -signal.SIGKILL)
        self.assertTrue(pidfile.is_file(), 'Timeout fixture did not start its child within five seconds')
        pid = int(pidfile.read_text())
        # An unreaped zombie is stopped; it cannot continue compiling or solving.
        for _ in range(20):
            if process_stopped(pid):
                break
            time.sleep(0.01)
        else:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                return  # The process exited between the last read and cleanup.
            self.fail('Child survived process-group timeout')

    def test_timeout_proc_read_handles_disappearance_without_hiding_live_children(self):
        for error in (FileNotFoundError, ProcessLookupError):
            with self.subTest(error=error), patch.object(Path, 'read_text', side_effect=error):
                self.assertTrue(process_stopped(123))
        for state in ('S', 'R', 'Z'):
            with self.subTest(state=state), patch.object(Path, 'read_text', return_value=f'123 (sleep) {state}'):
                self.assertEqual(process_stopped(123), state == 'Z')
        with patch.object(Path, 'read_text', side_effect=PermissionError):
            with self.assertRaises(PermissionError):
                process_stopped(123)

    def test_empty_run_cannot_pass(self):
        run = Run(self.path / 'empty')
        self.assertNotEqual(run.finish(), 0)
        self.assertEqual(json.loads((run.path / 'summary.json').read_text())['result'], 'TOOL_ERROR')

    def test_actual_empty_unittest_discovery_cannot_pass(self):
        from types import SimpleNamespace
        tests = self.path / 'empty-tests'
        tests.mkdir()
        run = Run(self.path / 'empty-unit-run')
        with patch('run.FIXTURES', tests), patch('failure_capture.capture_failure',
                                               return_value='fixture-only.json'):
            unit(run, SimpleNamespace(timeout=10))
        self.assertIn(run.cases[0].data['result'], ('FAIL', 'TOOL_ERROR'))
        self.assertIn('Ran 0 tests', output(run.cases[0].data['steps'][0]))

    def test_cli_rejects_empty_unknown_and_unimplemented(self):
        checkout = isolated_runner_repository(self.path / 'checkout', ROOT)
        for args, expected in [(['ci', '--test', ''], 'TOOL_ERROR'),
                               (['ci', '--test', 'missing'], 'TOOL_ERROR'),
                               (['coverage'], 'TOOL_ERROR'),
                               (['uvm', '--seed', '17'], 'TOOL_ERROR'),
                               (['ci', '--jobs', '0'], 'TOOL_ERROR')]:
            path = self.path / str(len(list(self.path.iterdir())))
            result = subprocess.run([sys.executable, str(checkout / 'tools/run.py'), *args,
                                     '--output', str(path)], capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            summary, = path.glob('*/summary.json')
            self.assertEqual(json.loads(summary.read_text())['result'], expected)

    def test_empty_or_code_only_coverage_cannot_pass(self):
        path = self.path / 'coverage.dat'
        for text in ('', "C '\x01t\x02line\x01f\x02/x/tests/toolchain/uvm_smoke.sv' 10\n"):
            path.write_text(text)
            with self.assertRaises(ValueError):
                inspect_coverage(path)

    def test_corrupt_cached_dependency_is_rejected_without_network(self):
        path = self.path / 'archive'
        path.write_text('corrupt')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            fetch({'sha256': '0' * 64}, path)


if __name__ == '__main__':
    unittest.main()

class TimingDiagnosticsTests(unittest.TestCase):
    def test_numbered_and_unnumbered_errors_override_complete_reports(self):
        from run import sta_result
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            stdout, stderr = directory/'out', directory/'err'
            good = 'TM_STA_MAX_BEGIN\nStartpoint: x\nEndpoint: y\nslack 1\nTM_STA_MIN_BEGIN\nStartpoint: x\nEndpoint: y\nslack 1\nTM_STA_DONE\n'
            stderr.write_text('')
            step = dict(result='PASS', returncode=0, stdout=str(stdout), stderr=str(stderr))
            stdout.write_text(good)
            self.assertEqual(sta_result(step)[0], 'PASS')
            for diagnostic in ('Error: missing library', 'Error 102: bad constraint', 'Warning 1234: unconstrained endpoint'):
                stdout.write_text(diagnostic+'\n'+good)
                self.assertEqual(sta_result(step)[0], 'FAIL')
            for text in (good+'TM_STA_DONE\n', good.replace('Endpoint: y',''), good.replace('TM_STA_MAX_BEGIN','')):
                stdout.write_text(text)
                self.assertEqual(sta_result(step)[0], 'FAIL')
