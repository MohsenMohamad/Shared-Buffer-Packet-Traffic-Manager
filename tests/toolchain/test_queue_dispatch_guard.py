"""Only the intended diagnostic and trace qualify the guard-removal mutation."""
import json
from pathlib import Path
import tempfile
import unittest
from queue_dispatch_guard import DETECTOR, inspect_coverage, mutation_outcome


class DispatchGuardEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.wave=Path(self.temp.name)/'wave.vcd'
        self.wave.write_text('nonempty counterexample')
        self.step=dict(result='TOOL_ERROR',returncode=-6,first_failure='Process exited -6')
        self.text='QUEUE_DV_WRONG_DESC_INJECT q=0 head=0 wrong=5\n%Fatal: Assertion failed: '+DETECTOR

    def test_intended_assertion_and_trace_qualify(self):
        self.assertEqual(mutation_outcome(self.step,self.text,self.wave),('PASS',None))

    def test_timeout_crash_wrong_assertion_success_and_empty_trace_fail(self):
        for name in ('timeout','crash','other_assertion','no_injection','success','empty_trace','missing_trace'):
            with self.subTest(name=name):
                step=dict(self.step); text=self.text
                self.wave.write_text('counterexample')
                if name=='timeout': step['result']='TIMEOUT'
                elif name=='crash': text='Segmentation fault'
                elif name=='other_assertion': text=text.replace(DETECTOR,'QUEUE_DV_WRONG_DESC_COUNT')
                elif name=='no_injection': text=text.split('\n')[1]
                elif name=='success': step.update(result='PASS',returncode=0)
                elif name=='empty_trace': self.wave.write_text('')
                else: self.wave.unlink()
                self.assertNotEqual(mutation_outcome(step,text,self.wave)[0],'PASS')

    def test_missing_duplicate_unhit_bins_and_wrong_totals_fail(self):
        data=dict(rejected=30,sticky_checks=60,resets=60,publications=116,
                  bins=[dict(qid=q,depth=d,wrong_kind=k,publication=p,hits=0 if d==0 and k==2 else 1)
                        for q in range(2) for d in range(2) for k in range(3) for p in range(3)])
        path=Path(self.temp.name)/'coverage.json'
        path.write_text(json.dumps(data))
        self.assertEqual(inspect_coverage(path,2)['rejected'],30)
        for name in ('empty','duplicate','unhit','wrong_total'):
            with self.subTest(name=name):
                mutated=json.loads(json.dumps(data))
                if name=='empty': mutated['bins']=[]
                elif name=='duplicate': mutated['bins'][1]=mutated['bins'][0]
                elif name=='unhit': mutated['bins'][0]['hits']=0
                else: mutated['rejected']=29
                path.write_text(json.dumps(mutated))
                with self.assertRaises(ValueError): inspect_coverage(path,2)


if __name__=='__main__': unittest.main()
