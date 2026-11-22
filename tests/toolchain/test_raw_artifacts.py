"""Run the repository check against staged files and a complete fixture PR."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from runner_fixture import isolated_runner_repository

ROOT = Path(__file__).resolve().parents[2]


class RawArtifactTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.event = Path(directory.name) / 'event.json'
        self.checkout = isolated_runner_repository(Path(directory.name) / 'checkout', ROOT)

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.checkout, text=True).strip()

    def write(self, path, content):
        target = self.checkout / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)

    def check(self, *args):
        return subprocess.run([sys.executable, 'tools/check_repository.py', *args], cwd=self.checkout,
                              env={**os.environ, 'GITHUB_EVENT_PATH': str(self.event)},
                              capture_output=True, text=True, timeout=30)

    def check_pr(self, base):
        self.event.write_text(json.dumps({'pull_request': {'base': {'sha': base},
                                                           'head': {'sha': self.git('rev-parse', 'HEAD')}}}))
        return self.check('--pr-diff')

    def test_pr_checks_earlier_commits_and_allows_removing_old_logs(self):
        old_log = 'verification/failures/old/F0.log'
        self.write(old_log, 'old job output\n')
        self.git('add', '-f', old_log)
        self.git('commit', '-qm', 'Legacy capture')
        base = self.git('rev-parse', 'HEAD')
        self.git('rm', old_log)
        raw = 'verification/failures/p05-postmerge-checkout-43617402959/F0.log'
        self.write(raw, 'raw workflow log\n')
        self.git('add', '-f', raw)
        self.git('commit', '-qm', 'Add raw capture')
        self.write('docs/results/component.md', 'Scoped result and replay command\n')
        self.write('tests/fixtures/replay.patch', 'Reviewed reproduction input\n')
        self.write('tests/fixtures/manifest.json', '{}\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'Add durable evidence and fixture')
        result = self.check_pr(base)
        self.assertEqual(result.returncode, 1)
        self.assertIn(raw, result.stderr)
        self.assertNotIn(old_log, result.stderr)
        self.git('rm', raw)
        self.git('commit', '-qm', 'Move raw capture out of the PR diff')
        result = self.check_pr(base)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_generated_evidence_is_rejected_but_schema_and_fixtures_are_allowed(self):
        for path in ('docs/results/timing.json', 'docs/results/trace.jsonl',
                     'verification/failures/capture.patch', 'verification/pools/results.json'):
            self.write(path, '{}\n')
            self.git('add', '-f', path)
        self.write('verification/sources/pools.json', '{}\n')
        self.write('tests/fixtures/expected.json', '{}\n')
        self.git('add', 'verification/sources/pools.json', 'tests/fixtures/expected.json')
        result = self.check()
        self.assertEqual(result.returncode, 1)
        for path in ('docs/results/timing.json', 'docs/results/trace.jsonl',
                     'verification/failures/capture.patch', 'verification/pools/results.json'):
            self.assertIn(path, result.stderr)
        self.assertNotIn('verification/sources/pools.json', result.stderr)
        self.assertNotIn('tests/fixtures/expected.json', result.stderr)

    def test_local_check_rejects_force_added_run_output(self):
        raw = '.build/runs/failures/capture.json'
        self.write(raw, '{}\n')
        self.assertEqual(self.check().returncode, 0)
        self.git('add', '-f', raw)
        result = self.check()
        self.assertEqual(result.returncode, 1)
        self.assertIn(raw, result.stderr)
