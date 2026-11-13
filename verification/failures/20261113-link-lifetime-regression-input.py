from pathlib import Path
import sys
sys.path.insert(0,str(Path.cwd()/'dv/memory_tx'))
from oracle import Profile,Violation
from qualification import replay
from traces import Trace
p=Profile();t=Trace(p);t.reset()
first=t.store(35,salt=23,chain=[5,1,9]);t.send(first);t.drain()
second=t.store(35,salt=177,chain=[5,1,9]);start=len(t.samples)
t.send(second);t.drain()
for sample in t.samples[start:]:sample['actions'].pop('query',None)
try:replay(t.samples,p)
except Violation as error:
    if error.detector!='link_capture':raise
    print('LINK_LIFETIME_PROBE_PASS')
else:raise AssertionError('LINK_LIFETIME_PROBE_MISSED: stale link capture crossed descriptor/cell reuse')
