"""An unrelated failure or induction-only trace cannot qualify a mutation."""
from pathlib import Path
import tempfile
import unittest
from formal_scheduler import mutation_outcome


class SchedulerMutationTests(unittest.TestCase):
    def test_only_intended_basecase_assertion_and_nonempty_trace_qualify(self):
        with tempfile.TemporaryDirectory() as folder:
            wave=Path(folder)/'trace.vcd'
            step=dict(result='TOOL_ERROR',returncode=1)
            text='engine_0.basecase: Assert failed in scheduler_formal: g_credit[0].a_credit\n'
            for variant in ('valid','unrelated','suffix','induction','crash','success','timeout','no_trace','empty_trace','wrong_status'):
                with self.subTest(variant=variant):
                    wave.write_text('counterexample')
                    message=text; process=dict(step); status='FAIL'
                    if variant=='unrelated': message=text.replace('a_credit','a_bounds')+' a_credit mentioned elsewhere'
                    elif variant=='suffix': message=text.replace('a_credit','a_credit_unrelated')
                    elif variant=='induction': message=text.replace('basecase','induction')
                    elif variant=='crash': message='frontend crashed'
                    elif variant=='success': process['returncode']=0
                    elif variant=='timeout': process['result']='TIMEOUT'
                    elif variant=='no_trace': wave.unlink()
                    elif variant=='empty_trace': wave.write_text('')
                    elif variant=='wrong_status': status='UNKNOWN'
                    result=mutation_outcome(process,status,[str(wave)],message,'a_credit')[0]
                    self.assertEqual(result=='PASS',variant=='valid')


if __name__=='__main__': unittest.main()
