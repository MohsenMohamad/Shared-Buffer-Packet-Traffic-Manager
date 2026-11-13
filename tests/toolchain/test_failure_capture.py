"""Real temporary Git repositories exercise failure evidence and reconstruction."""
from concurrent.futures import ThreadPoolExecutor
import contextlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
import evidence
import failure_capture


class FailureCaptureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'repo'
        self.root.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        (self.root / '.gitignore').write_text('.build/\n')
        (self.root / 'rtl.sv').write_text('module a; endmodule\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'Fixture baseline')
        self.addCleanup(patch.stopall)
        patch.object(evidence, 'ROOT', self.root).start()

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, stderr=subprocess.PIPE)

    def case(self, name='failure', seed=23):
        run = evidence.Run(self.root / '.build' / name, 'E0')
        return evidence.Case(run, name, seed)

    def finish(self, case, status='FAIL'):
        with contextlib.redirect_stdout(io.StringIO()):
            result = case.finish(status, 'Expected fixture failure')
        return result

    def record(self, case):
        path = self.root / case.data['failure_capture']
        return path, json.loads(path.read_text())

    def test_failed_source_patch_reconstructs_staged_unstaged_and_untracked(self):
        (self.root / 'rtl.sv').write_text('module broken; endmodule\n')
        self.git('add', 'rtl.sv')
        (self.root / '.gitignore').write_text('.build/\n*.vcd\n')
        (self.root / 'new.sv').write_text('module new_block; endmodule\n')
        (self.root / 'input.bin').write_bytes(b'\0\xffpayload')
        case = self.case()
        case.data['parameters'] = {'N_Q': 2}
        step = case.execute([sys.executable, '-c',
                             'import sys; print("bad byte"); print("detail",file=sys.stderr); sys.exit(1)'])
        # A later successful trace/replay cannot erase the first failing log.
        case.execute([sys.executable, '-c', 'print("replay")'])
        self.assertFalse(self.finish(case))
        path, record = self.record(case)
        self.assertEqual(record['seed'], 23)
        self.assertEqual(record['parameters'], {'N_Q': 2})
        self.assertEqual(record['steps'][0]['returncode'], 1)
        self.assertEqual(record['steps'][0]['cwd'], str(self.root))
        self.assertIn('bad byte', record['log_tails'][0]['stdout']['text'])
        self.assertIn('detail', record['log_tails'][0]['stderr']['text'])
        self.assertEqual(record['changed_since_run_start'], [])
        replay = self.root.parent / 'replay'
        subprocess.run(['git', 'clone', '-q', str(self.root), str(replay)], check=True)
        subprocess.run(['git', 'apply', '--binary', str(path.parent / record['source_patch'])],
                       cwd=replay, check=True)
        for name in ('rtl.sv', '.gitignore', 'new.sv', 'input.bin'):
            self.assertEqual((replay / name).read_bytes(), (self.root / name).read_bytes())
        shutil.rmtree(case.path)
        self.assertIn('bad byte', json.loads(path.read_text())['log_tails'][0]['stdout']['text'])

    def test_all_unexpected_case_statuses_capture_but_passing_negative_does_not(self):
        for status in ('FAIL', 'TIMEOUT', 'INCONCLUSIVE', 'TOOL_ERROR', 'UNSUPPORTED'):
            case = self.case(status)
            self.assertFalse(self.finish(case, status))
            self.assertEqual(self.record(case)[1]['result'], status)
        positive = self.case('expected-mutation-detected')
        positive.execute([sys.executable, '-c', 'raise SystemExit(1)'])
        self.assertTrue(self.finish(positive, 'PASS'))
        self.assertNotIn('failure_capture', positive.data)
        self.assertEqual(len(list((self.root / failure_capture.CAPTURE_PATH).glob('*.json'))), 5)

    def test_previous_captures_never_reenter_source_patches(self):
        (self.root / 'rtl.sv').write_text('broken\n')
        patches = []
        for name in ('first', 'second'):
            case = self.case(name)
            self.finish(case)
            path, record = self.record(case)
            patches.append((path.parent / record['source_patch']).read_bytes())
        self.assertEqual(patches[0], patches[1])
        self.assertNotIn(b'verification/failures', patches[1])

    def test_clean_source_records_revision_without_patch(self):
        case = self.case()
        self.finish(case)
        _, record = self.record(case)
        self.assertFalse(record['dirty'])
        self.assertIsNone(record['source_patch'])
        self.assertEqual(record['source_revision'], self.git('rev-parse', 'HEAD').decode().strip())

    def test_changed_or_added_source_after_run_start_is_explicit(self):
        case = self.case()
        (self.root / 'rtl.sv').write_text('changed\n')
        (self.root / 'late.sv').write_text('new after run\n')
        self.finish(case)
        self.assertEqual(set(self.record(case)[1]['changed_since_run_start']), {'rtl.sv', 'late.sv'})

    def test_capture_io_failure_preserves_original_failure_and_manifest(self):
        case = self.case()
        with patch.object(failure_capture, 'capture_failure', side_effect=OSError('disk full')):
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertFalse(self.finish(case))
        manifest = json.loads((case.path / 'manifest.json').read_text())
        self.assertEqual(manifest['result'], 'FAIL')
        self.assertEqual(manifest['first_failure'], 'Expected fixture failure')
        self.assertIn('disk full', manifest['failure_capture_error'])

    def test_git_capture_error_is_not_silently_a_clean_snapshot(self):
        case = self.case()
        with patch.object(failure_capture, 'snapshot', side_effect=RuntimeError('git failed')):
            self.finish(case)
        self.assertIn('git failed', self.record(case)[1]['source_capture_error'])

    def test_large_and_missing_logs_are_bounded_and_labeled(self):
        log = self.root / '.build/huge.log'
        log.parent.mkdir()
        log.write_text('x' * 200000)
        tail = failure_capture.log_tail(log)
        self.assertTrue(tail['truncated'])
        self.assertLessEqual(len(tail['text']), 8192)
        self.assertIn('unavailable', failure_capture.log_tail(log.with_name('missing')))

    def test_concurrent_captures_have_distinct_names(self):
        data = {'test': 'same/test', 'result': 'TIMEOUT', 'first_failure': 'fixture', 'steps': []}
        with ThreadPoolExecutor(max_workers=4) as pool:
            paths = list(pool.map(lambda _: failure_capture.capture_failure(data, self.root, self.root), range(4)))
        self.assertEqual(len(set(paths)), 4)
        for name in paths:
            self.assertEqual(json.loads((self.root / name).read_text())['result'], 'TIMEOUT')


if __name__ == '__main__':
    unittest.main()
