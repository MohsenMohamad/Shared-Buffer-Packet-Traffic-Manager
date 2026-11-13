"""Literal byte/lifetime witnesses and contract-valid metamorphic checks."""
from copy import deepcopy
from oracle import Profile, require, Violation
from traces import Trace, idle_output


def hand_trace(profile):
    # Literal C=16 fragmented chain; these values are independent of random stimulus.
    require(profile.cell_bytes==16,'hand_profile')
    t=Trace(profile);t.reset()
    info=dict(desc=0,length=35,qid=0,tag=7,source=0)
    addresses=[10,11,2,3,18]
    data=[0x0706050403020100,0x0f0e0d0c0b0a0908,0x1716151413121110,0x1f1e1d1c1b1a1918,0xaaaaaaaabb222120]
    for i,(addr,word) in enumerate(zip(addresses,data)):
        a={'write':{'addr':addr,'data':word}}
        if i==0:a.update(reserve=info,info=info|{'head':5,'ncell':3},allocate={'desc':0,'cell':5})
        if i==2:a.update(allocate={'desc':0,'cell':1},link={'cell':5,'next':1})
        if i==4:a.update(allocate={'desc':0,'cell':9},link={'cell':1,'next':9},commit=0)
        t.edge(a)
    packet=dict(info=info,chain=[5,1,9],raw=bytes(range(35)),words=list(zip(addresses,data)))
    t.send(packet);t.drain()
    return t.samples


def qualify_hand(replay):
    results=[]
    for latency in (1,2):
        for depth in (4,8):
            p=Profile(latency=latency,depth=depth)
            samples=hand_trace(p);report=replay(samples,p)
            transfers=[s for s in samples if s['out']['valid'] and s['out']['ready']]
            require([s['out']['keep'] for s in transfers]==[255,255,255,255,7],'hand_keeps')
            require([s['actions'].get('free') for s in transfers]==[None,5,None,1,9],'hand_lifetimes')
            require([s['actions'].get('done') for s in transfers]==[None,None,None,None,0],'hand_descriptor')
            raw=bytes((s['out']['data']>>(lane*8))&255 for s in transfers for lane in range(8) if s['out']['keep']&(1<<lane))
            require(raw==bytes(range(35)),'hand_bytes')
            issued=[(s['cycle'],s['actions']['read']) for s in samples if 'read' in s['actions']]
            arrived=[s['cycle'] for s in samples if 'response' in s['actions']]
            require([address for _,address in issued]==[10,11,2,3,18],'hand_read_order')
            require(arrived==[cycle+latency for cycle,_ in issued],'hand_latency')
            results.append(dict(latency=latency,depth=depth,valid_bytes=len(raw),returns=[5,1,9]))
    return results


def metamorphic(samples,profile,replay):
    renamed=deepcopy(samples)
    for s in renamed:
        for key in ('reserve','info','commit_info','dispatch_info'):
            if key in s['actions']:s['actions'][key]['tag']^=0x2345
        if s['out']['valid']:s['out']['user']^=0x2345<<24
    replay(renamed,profile)
    unused=deepcopy(samples)
    for s in unused:
        if s['out']['valid']:
            for lane in range(8):
                if not s['out']['keep']&(1<<lane):s['out']['data']^=0x5a<<(lane*8)
    replay(unused,profile)
    return {'tag_bijection':'PASS','unused_output_lanes':'PASS'}
