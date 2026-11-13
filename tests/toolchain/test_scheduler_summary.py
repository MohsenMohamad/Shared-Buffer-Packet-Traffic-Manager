"""Compact exports preserve actual statuses and accept relative run roots."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from scheduler_summary import collect


class SchedulerSummaryTests(unittest.TestCase):
    def test_relative_root_preserves_failure_and_source_identity(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); run=root/'regression-run'; case=run/'scheduler-mode1';case.mkdir(parents=True)
            manifest=case/'manifest.json'
            data=dict(test='scheduler-mode1',result='FAIL',first_failure='intentional test fixture',seed=17,
                      profile='E0',source_revision='revision',dirty=False,dependency_digests={'pins':'hash'},
                      constraint_digests={},registered_source_digests={'model':'hash'},
                      tool_versions={'python':'Python version','verilator':'Verilator version'},artifacts={'coverage_sha256':'digest'})
            manifest.write_text(json.dumps(data))
            (run/'summary.json').write_text(json.dumps(dict(result='FAIL',cases=[dict(manifest=str(manifest))])))
            result=collect(Path(os.path.relpath(root,Path.cwd())))
            self.assertEqual(result['cases'][0]['result'],'FAIL')
            self.assertEqual(result['cases'][0]['raw_case'],'regression-run/scheduler-mode1/manifest.json')
            self.assertEqual(result['provenance']['revision']['tools']['verilator'],'Verilator version')

    def test_empty_export_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(ValueError): collect(Path(folder))


if __name__=='__main__': unittest.main()
