"""Whole-command checks kept outside the light suite to avoid recursive discovery."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/toolchain'))
from runner_fixture import isolated_runner_repository


def capture_inventory():
    folder = ROOT / 'verification/failures'
    return {str(p.relative_to(folder)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in folder.rglob('*') if p.is_file()}


class CaptureIsolationTests(unittest.TestCase):
    def test_check_light_leaves_real_capture_directory_unchanged(self):
        before = capture_inventory()
        result = subprocess.run([sys.executable, str(ROOT / 'tools/check_light.py')],
                                cwd=ROOT, capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(capture_inventory(), before,
                         'Light self-tests created or modified real failure records')

    def test_failed_real_check_with_external_output_still_captures(self):
        before = capture_inventory()
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            checkout = isolated_runner_repository(directory / 'checkout', ROOT)
            # Fail an actual repository check, not a mocked capture or Case.finish.
            requirements = checkout / 'verification/requirements.json'
            data = json.loads(requirements.read_text())
            data['requirements'][0]['status'] = 'INVALID-FIXTURE-STATUS'
            requirements.write_text(json.dumps(data))
            output = directory / 'outside-output'
            self.assertFalse(output.is_relative_to(checkout))
            result = subprocess.run([sys.executable, str(checkout / 'tools/run.py'),
                                     'repo', '--output', str(output)], cwd=checkout,
                                    capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            record, = (checkout / 'verification/failures').glob('*.json')
            saved = json.loads(record.read_text())
            self.assertEqual(saved['test'], 'repository-contracts')
            self.assertEqual(saved['result'], 'TOOL_ERROR')
            self.assertTrue(Path(saved['run_directory']).is_relative_to(output))
            self.assertIn('invalid requirement status', saved['log_tails'][0]['stderr']['text'])
            self.assertIn('INVALID-FIXTURE-STATUS',
                          (record.parent / saved['source_patch']).read_text())
        self.assertEqual(capture_inventory(), before)


if __name__ == '__main__':
    unittest.main()
