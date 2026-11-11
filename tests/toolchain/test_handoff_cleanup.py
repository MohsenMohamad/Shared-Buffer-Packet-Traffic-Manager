"""Bound handoff deletion to one run/attempt and expose retention fallbacks."""
from contextlib import redirect_stdout
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import cleanup_toolchain_artifact as handoff


class CleanupTests(unittest.TestCase):
    def metadata(self, **changes):
        return dict(id=99, name='toolchain-42-2', workflow_run={'id': 42}, **changes)

    def clean(self, artifact_id='99', token='fixture-token'):
        return handoff.cleanup('owner/repo', '42', '2', artifact_id, token)

    def test_only_selected_handoff_is_deleted(self):
        with patch.object(handoff, 'api_request', side_effect=[self.metadata(), None]) as api:
            report = self.clean()
        self.assertEqual(report['status'], 'deleted')
        self.assertEqual(api.call_args_list[0].args,
                         ('GET', '/repos/owner/repo/actions/artifacts/99', 'fixture-token'))
        self.assertEqual(api.call_args_list[1].args,
                         ('DELETE', '/repos/owner/repo/actions/artifacts/99', 'fixture-token'))
        self.assertEqual(api.call_count, 2)

    def test_other_runs_attempts_ids_and_diagnostics_are_never_deleted(self):
        for metadata in (
            dict(id=100, name='toolchain-42-2', workflow_run={'id': 42}),
            dict(id=99, name='toolchain-42-1', workflow_run={'id': 42}),
            dict(id=99, name='toolchain-41-2', workflow_run={'id': 41}),
            dict(id=99, name='preparation-42-2', workflow_run={'id': 42}),
            dict(id=99, name='toolchain-uvm-sha', workflow_run={'id': 42}),
            dict(id=99, name='toolchain-42-2', workflow_run=None),
        ):
            with self.subTest(metadata=metadata), patch.object(handoff, 'api_request',
                                                              return_value=metadata) as api:
                report = self.clean()
                self.assertEqual(report['status'], 'retention-fallback')
                self.assertEqual(api.call_count, 1)
                self.assertEqual(api.call_args.args[0], 'GET')

    def test_permission_and_network_failures_are_visible_fallbacks(self):
        for failure in (HTTPError('https://api.github.com', 403, 'Forbidden', {}, None),
                        URLError('connection unavailable')):
            with self.subTest(failure=failure), patch.object(handoff, 'api_request',
                                                            side_effect=failure) as api:
                report = self.clean()
                self.assertEqual(report['status'], 'retention-fallback')
                self.assertEqual(api.call_count, 1)
                console = io.StringIO()
                with redirect_stdout(console), patch.dict(os.environ, {
                    'GITHUB_OUTPUT': '', 'GITHUB_STEP_SUMMARY': ''
                }):
                    handoff.publish(report)
                self.assertIn('::warning::', console.getvalue())
                self.assertIn('one day', console.getvalue())
                self.assertNotIn('fixture-token', console.getvalue())

    def test_delete_failure_does_not_claim_cleanup(self):
        failure = HTTPError('https://api.github.com', 403, 'Forbidden', {}, None)
        with patch.object(handoff, 'api_request', side_effect=[self.metadata(), failure]):
            self.assertEqual(self.clean()['status'], 'retention-fallback')

    def test_missing_producer_output_or_token_never_calls_delete(self):
        with patch.object(handoff, 'api_request') as api:
            self.assertEqual(self.clean(artifact_id='')['status'], 'not-selected')
            self.assertEqual(self.clean(token='')['status'], 'retention-fallback')
            api.assert_not_called()

    def test_invalid_selectors_never_reach_api(self):
        with patch.object(handoff, 'api_request') as api:
            report = handoff.cleanup('owner/repo/other', '42', '2', '99', 'token')
            self.assertEqual(report['status'], 'retention-fallback')
            self.assertEqual(self.clean(artifact_id='../100')['status'], 'retention-fallback')
            api.assert_not_called()

    def test_already_absent_is_an_idempotent_noop(self):
        with patch.object(handoff, 'api_request', side_effect=HTTPError(
                'https://api.github.com', 404, 'Not Found', {}, None)) as api:
            self.assertEqual(self.clean()['status'], 'already-absent')
            self.assertEqual(api.call_count, 1)

    def test_summary_and_output_record_fallback(self):
        with tempfile.TemporaryDirectory() as temporary:
            summary, output = (Path(temporary) / name for name in ('summary', 'output'))
            with patch.dict(os.environ, {'GITHUB_OUTPUT': str(output),
                                         'GITHUB_STEP_SUMMARY': str(summary)}):
                with redirect_stdout(io.StringIO()):
                    handoff.publish(dict(status='retention-fallback', artifact_id='99',
                                         artifact_name='toolchain-42-2', reason='HTTP 403'))
            self.assertEqual(output.read_text(), 'status=retention-fallback\n')
            self.assertIn('one day', summary.read_text())


if __name__ == '__main__':
    unittest.main()
