"""Extended evidence validation; no simulated result is inferred from units."""
import json
from pathlib import Path
import tempfile
import unittest
from scheduler_stress import inspect_stress, intended_failure


class SchedulerStressEvidenceTests(unittest.TestCase):
    def test_named_diagnostic_trace_and_failure_required(self):
        with tempfile.TemporaryDirectory() as folder:
            wave=Path(folder)/'wave.vcd'; wave.write_text('trace')
            step=dict(result='TOOL_ERROR',returncode=-6)
            text='UVM_FATAL @ 10: [SCHED_INPUT_DONE] invalid neighbor'
            self.assertTrue(intended_failure(step,text,wave,{'SCHED_INPUT_DONE'})[0])
            for bad in ('crash','UVM_FATAL [SCHED_INPUT_CONFIG] wrong','UVM_FATAL [SCHED_INPUT_DONE_OTHER] suffix'):
                self.assertFalse(intended_failure(step,bad,wave,{'SCHED_INPUT_DONE'})[0])
            self.assertFalse(intended_failure(dict(result='TIMEOUT',returncode=-9),text,wave,{'SCHED_INPUT_DONE'})[0])
            wave.write_text('')
            self.assertFalse(intended_failure(step,text,wave,{'SCHED_INPUT_DONE'})[0])

    def test_required_bins_impossible_bins_and_random_counts_fail_closed(self):
        counters={key:1 for key in ['backlog.'+k for k in ('zero','one','multiple','all')]+['cursor.wrap','quantum.minimum','quantum.maximum','final.stall']+['quantum.'+k for k in ('less','equal','greater')]+['stall.'+k for k in ('none','short','medium','long')]+['visit.'+k for k in ('zero','one','many')]}
        allowed={(0,0),(1,0),(2,0),(2,1),(3,0),(4,1),(5,1)}
        counters.update({f'reset.{p}.{b}':int((p,b) in allowed) for p in range(6) for b in (0,1)})
        data=dict(mode=1,coverage_counts=counters,random_publications=100,random_steps=4800,progress_checks=1,reconfigurations=1,behind=1,ahead=1,completion_commits=1,skip_commits=1,reactivation_boundary=1,random_quanta=[[64,4096],[65,127],[512,1024]],random_qids=[50,50],length_choices=[10]*10)
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'coverage.json';path.write_text(json.dumps(data))
            result=inspect_stress(path,1,2)
            self.assertEqual(result['mandatory_hit'],result['mandatory_total'])
            for variant in ('missing','unhit','impossible','steps','publication','quanta','class','duplicate'):
                row=json.loads(json.dumps(data))
                if variant=='missing': del row['coverage_counts']['cursor.wrap']
                elif variant=='unhit': row['coverage_counts']['cursor.wrap']=0
                elif variant=='impossible': row['coverage_counts']['reset.0.1']=1
                elif variant=='steps': row['random_steps']=0
                elif variant=='publication': row['random_publications']=101
                elif variant=='quanta': row['random_quanta']=[[64,4096]]*3
                elif variant=='class': row['length_choices']=[100]+[0]*9
                encoded=json.dumps(row)
                if variant=='duplicate': encoded=encoded.replace('"mode": 1','"mode": 1,"mode": 1')
                path.write_text(encoded)
                with self.subTest(variant=variant),self.assertRaises(ValueError): inspect_stress(path,1,2)


if __name__=='__main__': unittest.main()
