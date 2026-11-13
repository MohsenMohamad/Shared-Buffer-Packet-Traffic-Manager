"""Saved scheduler evidence must fail closed; these are runner tests only."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from evidence import sha
from registry import profile
from scheduler import scheduler_coverage
from scheduler_coverage import inspect


class SchedulerCoverageTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.code=self.root/'coverage.dat'
        self.manifest=self.root/'manifest.json'
        self.keys={'update_kind.'+kind for kind in ('none','singleton','longer','different')}
        self.keys|={kind+'.auto_'+str(value) for kind in ('tx_busy','activated') for value in (0,1)}
        self.keys|={'fit.'+kind for kind in ('insufficient','equal','surplus')}
        self.keys|={'replacement_busy.<'+kind+',auto_'+str(busy)+'>'
                    for kind in ('none','singleton','longer','different') for busy in (0,1)}
        self.keys|={'reactivation_fit.<auto_'+str(active)+','+kind+'>'
                    for active in (0,1) for kind in ('insufficient','equal','surplus')}
        self.write_code()
        self.parameters=profile('E0')
        self.parameters.update(CELL_ID_W=4,CELL_COUNT_W=5,DESC_ID_W=3,DESC_COUNT_W=4,DEFICIT_W=13)
        self.patch=patch('scheduler_coverage.fingerprint',return_value={'model':'digest'})
        self.patch.start(); self.addCleanup(self.patch.stop)
        self.save()

    def write_code(self,missing=None,zero=None,duplicate=None):
        self.code.write_text("C '\x01f\x02/x/rtl/scheduler/tm_drr.sv\x01t\x02line\x01l\x0230' 1\n"+
            ''.join("C '\x01t\x02covergroup\x01h\x02top.policy_cg."+name+"' "+str(0 if name==zero or (name.startswith('replacement_busy.<') and 'auto_1' in name and '<none,' not in name) else 1)+'\n'
                    for name in sorted(self.keys) if name!=missing))
        if duplicate:
            with self.code.open('a') as stream:
                stream.write("C '\x01t\x02covergroup\x01h\x02top.policy_cg."+duplicate+"' 1\n")

    def save(self,mode=1):
        self.parameters['SCHED_MODE']=mode
        self.row=dict(result='PASS',profile='E0',test=f'scheduler-mode{mode}',source_set='scheduler',
                      source_revision='revision',dirty=False,parameters=dict(self.parameters),
                      registered_source_digests={'model':'digest'},
                      coverage=scheduler_coverage(self.code,mode),
                      artifacts=dict(coverage=str(self.code),coverage_sha256=sha(self.code)))
        self.manifest.write_text(json.dumps(self.row))

    def test_positive_drr_and_rr_keep_separate_exclusions(self):
        self.assertEqual(inspect(self.manifest,'E0')['coverage']['mandatory_hit'],22)
        self.save(0)
        self.assertEqual(inspect(self.manifest,'E0')['coverage']['mandatory_hit'],13)

    def test_missing_duplicate_and_unhit_functional_bins_fail(self):
        for variant in ('missing','duplicate','zero'):
            with self.subTest(variant=variant):
                self.write_code(**{variant:'fit.equal'})
                with self.assertRaises(ValueError): scheduler_coverage(self.code,1)

    def test_impossible_owned_collision_fails(self):
        self.code.write_text(self.code.read_text().replace("policy_cg.replacement_busy.<singleton,auto_1>' 0", "policy_cg.replacement_busy.<singleton,auto_1>' 1"))
        with self.assertRaises(ValueError): scheduler_coverage(self.code,1)

    def test_empty_and_code_only_fail(self):
        for text in ('',"C '\x01f\x02/x/rtl/scheduler/tm_drr.sv\x01t\x02line' 1\n"):
            self.code.write_text(text)
            with self.assertRaises(ValueError): scheduler_coverage(self.code,1)

    def test_stale_profile_parameters_source_result_and_artifacts_fail(self):
        for variant in ('profile','parameters','source','failed','mutation','artifact','summary'):
            with self.subTest(variant=variant):
                self.save()
                if variant=='profile': self.row['profile']='F0'
                elif variant=='parameters': self.row['parameters']['DEFICIT_W']=12
                elif variant=='source': self.row['registered_source_digests']={}
                elif variant=='failed': self.row['result']='FAIL'
                elif variant=='mutation': self.row['test']='scheduler-mode1-extra-quantum'
                elif variant=='artifact': self.row['artifacts']['coverage_sha256']='wrong'
                else: self.row['coverage']['mandatory_hit']=100
                self.manifest.write_text(json.dumps(self.row))
                with self.assertRaises(ValueError): inspect(self.manifest,'E0')


if __name__=='__main__': unittest.main()
