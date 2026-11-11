"""Guard CI concurrency, handoff lifetime and the producer/consumer boundary."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.workflow = (ROOT / '.github/workflows/toolchain.yml').read_text()
        section = self.workflow.split('\njobs:\n', 1)[1]
        self.jobs = dict(re.findall(
            r'^  ([a-z][\w-]*):\n(.*?)(?=^  [a-z][\w-]*:\n|\Z)', section, re.M | re.S))

    def test_prs_share_a_group_but_every_main_manual_run_and_attempt_is_independent(self):
        group = re.search(r'^  group: (.+)$', self.workflow, re.M).group(1)
        # Read the formats from the actual expression. A shared ref-based group
        # or different argument list fails this contract, not just sample cases.
        match = re.fullmatch(
            r"ci-\$\{\{ github.event_name == 'pull_request' && "
            r"format\('([^']+)', github.event.pull_request.number\) \|\| "
            r"format\('([^']+)', github.run_id, github.run_attempt\) \}\}", group)
        self.assertIsNotNone(match)
        pr_format, run_format = match.groups()
        def key(event, run_id, attempt=1, pr=6):
            return 'ci-' + (pr_format.format(pr) if event == 'pull_request'
                            else run_format.format(run_id, attempt))
        self.assertEqual(key('pull_request', 100), key('pull_request', 101))
        self.assertNotEqual(key('pull_request', 100), key('pull_request', 101, pr=7))
        # Three main runs cover active + older pending + newly queued work.
        independent = [key('push', run_id) for run_id in (100, 101, 102)]
        independent += [key('workflow_dispatch', run_id) for run_id in (103, 104)]
        independent += [key('push', 100, attempt=2)]
        self.assertEqual(len(independent), len(set(independent)))
        self.assertRegex(self.workflow,
                         r"cancel-in-progress: \$\{\{ github.event_name == 'pull_request' \}\}")

    def test_cleanup_waits_for_all_consumers_even_if_they_fail(self):
        consumers = {name for name, body in self.jobs.items()
                     if re.search(r'^    needs: prepare$', body, re.M)}
        self.assertEqual(consumers, {'capability', 'contracts', 'storage', 'csr', 'foundation'})
        cleanup = self.jobs['cleanup-handoff']
        dependencies = re.search(r'^    needs: \[([^]]+)\]$', cleanup, re.M).group(1)
        self.assertEqual({name.strip() for name in dependencies.split(',')},
                         consumers | {'prepare'})
        self.assertRegex(cleanup, r'if: \$\{\{ always\(\) \}\}')
        self.assertIn('      actions: write', cleanup)
        self.assertEqual(len(re.findall(r'^\s+actions: write$', self.workflow, re.M)), 1)
        self.assertIn('needs.prepare.outputs.artifact-id', cleanup)
        self.assertIn('GITHUB_RUN_ATTEMPT', cleanup)

    def test_only_handoff_retention_is_shortened_and_cancellation_fallback_is_announced(self):
        prepare = self.jobs['prepare']
        handoff = re.search(r'      - name: Transfer prepared installation\n(.*?)'
                            r'(?=      - name:|\Z)', prepare, re.S).group(1)
        self.assertIn('id: handoff', handoff)
        self.assertIn('retention-days: 1\n', handoff)
        self.assertIn('steps.handoff.outputs.artifact-id', prepare)
        self.assertLess(prepare.index('Record handoff retention fallback'),
                        prepare.index('Transfer prepared installation'))
        self.assertIn('retention-days: 14', prepare)
        for name in ('contracts', 'csr', 'storage', 'uvm-foundation'):
            workflow = (ROOT / '.github/workflows' / (name + '.yml')).read_text()
            self.assertIn('retention-days: 14', workflow)

    def test_each_consumer_runs_current_validation_and_cannot_build_on_a_miss(self):
        bodies = [self.jobs['capability']]
        for name in ('contracts', 'csr', 'storage', 'uvm-foundation'):
            bodies.append((ROOT / '.github/workflows' / (name + '.yml')).read_text())
        for body in bodies:
            self.assertIn('python3 tools/toolchain_cache.py validate', body)
            self.assertIn('tar --zstd -xpf', body)
            self.assertNotIn('make setup', body)
            self.assertNotIn('toolchain_cache.py prepare', body)

    def test_exact_restore_is_identified_and_save_requires_success(self):
        prepare = self.jobs['prepare']
        self.assertIn('--restored-key', prepare)
        self.assertIn('steps.cache.outputs.cache-matched-key', prepare)
        save = re.search(r'      - name: Save only a complete validated installation\n(.*?)'
                         r'(?=      - name:|\Z)', prepare, re.S).group(1)
        self.assertIn("success() && steps.cache.outputs.cache-hit != 'true'", save)
        setup = re.search(r'      - name: Validate restored installation or build once on a cold miss\n'
                          r'(.*?)(?=      - name:|\Z)', prepare, re.S).group(1)
        self.assertNotIn('continue-on-error', setup)


if __name__ == '__main__':
    unittest.main()
