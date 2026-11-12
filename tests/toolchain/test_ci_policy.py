"""Qualify event requests, complete-diff classification and truthful summaries."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from ci_policy import REQUIRED, complete_paths, decision, qualification
from check_light import syntax, units
import toolchain_cache as cache


class PolicyTests(unittest.TestCase):
    def event(self, action='synchronize', draft=False, labels=()):
        return dict(action=action, pull_request=dict(draft=draft,
                    labels=[dict(name=label) for label in labels],
                    base=dict(sha='a' * 40), head=dict(sha='b' * 40)))

    def test_event_path_truth_table(self):
        cases = (
            ('draft code push', 'pull_request', self.event(draft=True), ['rtl/tm.sv'], True, False),
            ('ready code push', 'pull_request', self.event(), ['rtl/tm.sv'], True, True),
            ('prose push', 'pull_request', self.event(), ['README.md'], True, False),
            ('normative doc push', 'pull_request', self.event(), ['docs/spec/automation.md'], True, True),
            ('ready docs event', 'pull_request', self.event('ready_for_review', True), ['README.md'], True, True),
            ('persistent full-ci draft', 'pull_request', self.event(draft=True, labels=['full-ci']), ['README.md'], True, True),
            ('full-ci draft docs label', 'pull_request', dict(self.event('labeled', True), label=dict(name='full-ci')), ['README.md'], True, True),
            ('unrelated label', 'pull_request', dict(self.event('labeled', labels=['full-ci']), label=dict(name='bug')), ['rtl/tm.sv'], True, False),
            ('main', 'push', {}, None, False, True),
            ('manual', 'workflow_dispatch', {}, None, False, True),
            ('truncated file list', 'pull_request', self.event(), ['README.md'], False, True),
            ('empty file list', 'pull_request', self.event(), [], True, True),
        )
        for name, event_name, event, paths, complete, expected in cases:
            with self.subTest(name=name):
                self.assertEqual(decision(event_name, event, paths, complete)[0], expected)
        for action in ('opened', 'reopened'):
            self.assertTrue(decision('pull_request', self.event(action), ['tools/run.py'], True)[0])

    def test_unknown_and_normative_paths_are_substantive(self):
        for path in ('AGENTS.md', 'tools/AGENTS.md', 'docs/documentation.md', 'docs/spec/README.md',
                     'docs/implementation/tasks/C01-ci-economy.md', 'verification/sources/production.json',
                     'docs/results/new.md', 'tools/setup_toolchain.py', 'tools/run.py',
                     '.github/workflows/toolchain.yml', 'new-file.md', 'README.md/child'):
            with self.subTest(path=path):
                self.assertTrue(decision('pull_request', self.event(), [path], True)[0])

    def test_git_uses_complete_base_to_head_not_final_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, text=True).strip()
            git('init', '-q')
            git('config', 'user.name', 'Fixture')
            git('config', 'user.email', 'fixture@example.invalid')
            (root / 'README.md').write_text('base')
            git('add', '.'); git('commit', '-qm', 'base')
            base = git('rev-parse', 'HEAD')
            (root / 'code.py').write_text('pass')
            git('add', '.'); git('commit', '-qm', 'substantive')
            (root / 'README.md').write_text('last commit is prose')
            git('add', '.'); git('commit', '-qm', 'prose')
            event = self.event()
            event['pull_request']['base']['sha'] = base
            event['pull_request']['head']['sha'] = git('rev-parse', 'HEAD')
            paths = complete_paths(event, root)
            self.assertEqual(set(paths), {'README.md', 'code.py'})
            self.assertTrue(decision('pull_request', event, paths, True)[0])

    def test_incomplete_diff_is_never_a_cosmetic_classification(self):
        for data in (b'', b'README.md', b'\xff\0'):
            with patch('ci_policy.subprocess.check_output', return_value=data):
                with self.assertRaises(ValueError):
                    complete_paths(self.event(), ROOT)
        with patch('ci_policy.subprocess.check_output', side_effect=subprocess.TimeoutExpired('git', 60)):
            with self.assertRaises(subprocess.TimeoutExpired):
                complete_paths(self.event(), ROOT)

    def needs(self, full='true'):
        needs = {job: dict(result='success') for job in REQUIRED}
        needs['policy']['outputs'] = dict(full=full)
        if full == 'false':
            for job in REQUIRED[2:]:
                needs[job]['result'] = 'skipped'
        return needs

    def test_summary_requires_all_requested_jobs(self):
        self.assertTrue(qualification(self.needs())[0])
        for job in REQUIRED:
            for result in ('failure', 'cancelled', 'skipped', None):
                needs = self.needs()
                needs[job]['result'] = result
                self.assertFalse(qualification(needs)[0], (job, result))
            needs = self.needs()
            del needs[job]
            self.assertFalse(qualification(needs)[0], job)
        for outputs in ({}, dict(full=''), dict(full='unknown')):
            needs = self.needs()
            needs['policy']['outputs'] = outputs
            self.assertFalse(qualification(needs)[0])

    def test_summary_reports_intentional_skip_without_hardware_pass(self):
        ok, message = qualification(self.needs('false'))
        self.assertTrue(ok)
        self.assertIn('NOT_REQUESTED', message)
        self.assertNotIn('PASS', message)
        needs = self.needs('false')
        needs['prepare']['result'] = 'failure'
        self.assertFalse(qualification(needs)[0])

    def test_cleanup_guard_runs_after_consumer_failure_but_not_skipped_prepare(self):
        workflow = (ROOT / '.github/workflows/toolchain.yml').read_text()
        cleanup = workflow.split('  cleanup-handoff:\n')[1].split('  full-ci-summary:')[0]
        self.assertIn("if: ${{ always() && needs.prepare.result != 'skipped' }}", cleanup)
        for prepare, consumer, expected in (
            ('skipped', 'skipped', False), ('success', 'failure', True),
            ('success', 'cancelled', True), ('failure', 'skipped', True),
            ('cancelled', 'skipped', True)):
            with self.subTest(prepare=prepare, consumer=consumer):
                # always() is true irrespective of failed/cancelled dependencies.
                self.assertEqual(True and prepare != 'skipped', expected)

    def test_workflow_connects_policy_and_light_jobs_without_path_filters(self):
        workflow = (ROOT / '.github/workflows/toolchain.yml').read_text()
        self.assertIn('types: [opened, synchronize, reopened, ready_for_review, labeled]', workflow)
        self.assertNotIn('paths-ignore:', workflow)
        self.assertNotIn('paths:', workflow)
        self.assertNotIn('pull_request_target', workflow)
        self.assertIn("group: ${{ github.event.action == 'labeled' && github.event.label.name != 'full-ci' && format('label-{0}-', github.run_id) || '' }}ci-", workflow)
        self.assertIn("needs: policy\n    if: ${{ needs.policy.outputs.full == 'true' }}", workflow)
        self.assertIn('fetch-depth: 0', workflow.split('  policy:')[1].split('  prepare:')[0])
        self.assertIn('needs: [repository, policy, prepare, capability, contracts, storage, csr, foundation]', workflow)
        self.assertIn('CI_SUMMARY_NEEDS: ${{ toJSON(needs) }}', workflow)
        light = (ROOT / '.github/workflows/repository.yml').read_text()
        self.assertIn('python3 tools/check_repository.py', light)
        self.assertIn('python3 tools/check_light.py', light)
        for forbidden in ('doctor', 'make lint', 'prepare', 'native-prerequisites', 'verilator'):
            self.assertNotIn(forbidden, light)

    def test_light_rejects_missing_and_empty_selections(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for target in (root / 'missing', root):
                with self.assertRaisesRegex(ValueError, 'selection'):
                    units(target)
            for paths in (b'', b'missing.py\0'):
                with patch('check_light.subprocess.check_output', return_value=paths):
                    with self.assertRaises((ValueError, OSError)):
                        syntax(root)

    def test_missing_install_is_actionable_and_never_calls_doctor(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(cache, 'checked_step') as step:
            with self.assertRaisesRegex(ValueError, 'receive and unpack the producer handoff'):
                cache.validate({}, Path(directory))
            step.assert_not_called()


if __name__ == '__main__':
    unittest.main()
