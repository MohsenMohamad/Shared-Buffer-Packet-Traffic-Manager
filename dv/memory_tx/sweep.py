"""Bounded sink patterns applied through sampled transactions, never model edits."""
from collections import Counter
from dataclasses import replace
from traces import Trace


def sweep(profile,replay,seed=17):
    configurations=[]
    for latency in (1,2):
        for depth in (4,8):
            for cell_bytes in (16,32,64):
                p=replace(profile,latency=latency,depth=depth,cell_bytes=cell_bytes,
                          max_length=min(profile.max_length,profile.cells*cell_bytes))
                counts=Counter()
                for mask in range(16):
                    t=Trace(p,seed+mask);t.reset()
                    length=min(p.max_length,max(cell_bytes+1,(depth+latency+3)*8))
                    packet=t.store(length,salt=mask*13)
                    t.send(packet,mode=('pattern',mask));t.drain()
                    result=replay(t.samples,p,['complete','exact_full'])
                    counts.update(result['bins'])
                for name in ('full_arrival','full_stall','full_exchange'):
                    if counts[name]==0:raise AssertionError('sweep_missing_bin: '+name+str(p))
                configurations.append(dict(latency=latency,depth=depth,cell_bytes=cell_bytes,
                                           masks=16,observed_bins=dict(counts)))
    return configurations
