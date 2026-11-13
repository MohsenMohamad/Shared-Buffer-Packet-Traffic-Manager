"""Fail-closed saved independent coverage qualification; no hardware claim."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from evidence import sha
from queue_coverage import inspect


class QueueCoverageTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.code=self.root/'coverage.dat'
        self.code.write_text("C '\x01f\x02/x/rtl/queue/tm_queue_ctrl.sv\x01t\x02line\x01l\x0230' 1\n")
        self.functional=self.root/'functional.json'
        self.data={key:1 for key in ('delayed_publish','reuse','tx_retained','full','reset_active',
                    'reset_collision','read_checks','link_collision','same_singleton','same_long','different','empty_publish')}
        self.data['bins']=[dict(qid=q,pre_count=c,event=e,hits=0 if c==0 and e in (1,3) else 1)
                           for q in range(2) for c in range(3) for e in range(4)]
        self.manifest=self.root/'manifest.json'
        self.save()
        self.patch=patch('queue_coverage.fingerprint',return_value={'model':'digest'})
        self.patch.start(); self.addCleanup(self.patch.stop)

    def save(self):
        self.functional.write_text(json.dumps(self.data))
        self.row=dict(result='PASS',profile='E0',source_set='queues-independent',
                      source_revision='revision',dirty=False,parameters={'N_Q':2},
                      registered_source_digests={'model':'digest'},
                      artifacts=dict(coverage=str(self.code),functional_coverage=str(self.functional),
                                     coverage_sha256=sha(self.code),functional_coverage_sha256=sha(self.functional)))
        self.manifest.write_text(json.dumps(self.row))

    def test_valid_saved_counters_and_owned_code(self):
        self.assertEqual(inspect(self.manifest,'E0')['code']['tm_queue_ctrl.sv']['line'],dict(hit=1,total=1))

    def test_empty_duplicate_unhit_and_illegal_bins_fail(self):
        for mode in ('empty','duplicate','unhit','illegal'):
            with self.subTest(mode=mode):
                original=json.loads(json.dumps(self.data))
                if mode=='empty': self.data['bins']=[]
                elif mode=='duplicate': self.data['bins'][1]=self.data['bins'][0]
                elif mode=='unhit': self.data['bins'][0]['hits']=0
                else: self.data['bins'][1]['hits']=1
                self.save()
                with self.assertRaises(ValueError): inspect(self.manifest,'E0')
                self.data=original

    def test_stale_source_wrong_profile_failure_and_corruption_fail(self):
        for mode in ('source','profile','failed','corrupt'):
            with self.subTest(mode=mode):
                self.save()
                if mode=='source': self.row['registered_source_digests']={}
                elif mode=='profile': self.row['profile']='F0'
                elif mode=='failed': self.row['result']='FAIL'
                else: self.functional.write_text('{}')
                self.manifest.write_text(json.dumps(self.row))
                with self.assertRaises(ValueError): inspect(self.manifest,'E0')


if __name__=='__main__': unittest.main()
