"""Replayable signal/action fixtures. No oracle state is used to create pressure."""
from copy import deepcopy
import random


def idle_output():
    return dict(valid=False,ready=False,data=0,keep=0,last=False,user=0)


class Trace:
    def __init__(self, profile, seed=17):
        self.p=profile; self.rng=random.Random(seed)
        self.samples=[]; self.epoch=0; self.resetting=False
        self.ram={}; self.responses={}; self.cycle=0; self.descriptors={}

    def edge(self, actions=None, out=None, reset=False):
        a=deepcopy(actions or {})
        if 'info' in a:self.descriptors[a['info']['desc']]=deepcopy(a['info'])
        for event in ('commit','dispatch'):
            if event in a:a[event+'_info']=deepcopy(self.descriptors[a[event]])
        if self.cycle in self.responses:
            a['response']={'data':self.responses.pop(self.cycle)}
        if 'read' in a:
            self.responses[self.cycle+self.p.latency]=self.ram[a['read']]
        if 'write' in a:
            self.ram[a['write']['addr']]=a['write']['data']
        if reset and not self.resetting: self.epoch+=1
        self.samples.append(dict(epoch=self.epoch,cycle=self.cycle,reset=reset,
                                 actions=a,out=deepcopy(out or idle_output())))
        self.resetting=reset;self.cycle+=1

    def reset(self):
        self.edge(reset=True);self.edge(reset=True);self.edge()

    def store(self, length, desc=0, tag=7, salt=0, chain=None):
        count=(length+self.p.cell_bytes-1)//self.p.cell_bytes
        if chain is None:
            chain=list(range(self.p.cells));self.rng.shuffle(chain);chain=chain[:count]
        raw=bytes((salt+37*j+11*(j//self.p.cell_bytes)+3)&255 for j in range(length))
        info=dict(desc=desc,length=length,qid=desc%self.p.queues,source=desc%self.p.sources,tag=tag)
        words=[]
        for i in range((length+7)//8):
            cell=chain[(i*8)//self.p.cell_bytes]
            addr=cell*(self.p.cell_bytes//8)+i%(self.p.cell_bytes//8)
            data=int.from_bytes(raw[i*8:i*8+8].ljust(8,bytes([self.rng.randrange(256)])),'little')
            a={'write':{'addr':addr,'data':data}}
            if i%(self.p.cell_bytes//8)==0:
                a['allocate']={'cell':cell,'desc':desc}
                if i: a['link']={'cell':chain[i//(self.p.cell_bytes//8)-1],'next':cell}
            if i==0:
                a['reserve']=info;a['info']=info|{'head':chain[0],'ncell':count}
            if i==(length+7)//8-1: a['commit']=desc
            words.append((addr,data));self.edge(a)
        return dict(info=info,raw=raw,chain=chain,words=words)

    def send(self, packet, mode='pressure', stop=None):
        self.edge({'dispatch':packet['info']['desc']})
        return self.continue_send(packet, mode, stop)

    def continue_send(self, packet, mode='pressure', stop=None, state=None):
        state=state or dict(issued=0,retired=0,available=[],held=None,age=0,stalled=set())
        words=packet['words'];n=len(words)
        for _ in range(n*20+self.p.depth*10+100):
            i,t=state['issued'],state['retired']
            if t==n: return state
            age=state['age'];state['age']+=1
            # Returned response becomes output on a later edge, never fall-through.
            visible=[x for x in state['available'] if x[0]<self.cycle]
            valid=bool(visible)
            ready=age>=self.p.depth+self.p.latency+3
            if mode=='random' and ready: ready=self.rng.randrange(4)!=0
            if isinstance(mode,tuple) and ready:
                pattern_age=age-(self.p.depth+self.p.latency+3)
                ready=bool(mode[1]&(1<<(pattern_age%4))) if pattern_age<12 else True
            final_cell=(t+1)%(self.p.cell_bytes//8)==0 or t+1==n
            # Deliberately hold each boundary for two edges, including final output.
            if not isinstance(mode,tuple) and valid and final_cell and (t,0) not in state['stalled']:
                ready=False;state['stalled'].add((t,0))
            elif not isinstance(mode,tuple) and valid and final_cell and (t,1) not in state['stalled']:
                ready=False;state['stalled'].add((t,1))
            out=idle_output();out['ready']=ready
            a={}
            if valid:
                data=words[t][1]; remaining=len(packet['raw'])-t*8
                out.update(valid=True,data=data,keep=(1<<min(8,remaining))-1,last=t+1==n,
                           user=packet['info']['qid']|len(packet['raw'])<<8|packet['info']['tag']<<24|packet['info']['source']<<40)
            transfer=valid and ready
            if transfer:
                if final_cell: a['free']=packet['chain'][t*8//self.p.cell_bytes]
                if t+1==n: a['done']=packet['info']['desc']
            # Issue from the independent number of issued-minus-retired beats.
            if i<n and i-t-int(transfer)<self.p.depth:
                a['read']=words[i][0]
                state['available'].append((self.cycle+self.p.latency,i))
                state['issued']+=1
            cell_index=min(t*8//self.p.cell_bytes,len(packet['chain'])-1)
            if cell_index+1<len(packet['chain']):
                a['query']={'cell':packet['chain'][cell_index],'next':packet['chain'][cell_index+1]}
            self.edge(a,out)
            if transfer:
                state['available']=[x for x in state['available'] if x[1]!=t]
                state['retired']+=1
            if stop and stop(self.samples[-1],state): return state
        raise RuntimeError('Fixture progress exhausted')

    def drain(self):
        for _ in range(self.p.latency+2):self.edge()


def legal_trace(profile, seed=17):
    trace=Trace(profile,seed);trace.reset()
    lengths=list(dict.fromkeys([1,7,8,9,profile.cell_bytes-1,profile.cell_bytes,
                               profile.cell_bytes+1,profile.max_length-1,profile.max_length]+list(range(1,9))))
    lengths += [trace.rng.randint(1,profile.max_length) for _ in range(12)]
    for ordinal,length in enumerate(lengths):
        packet=trace.store(length,tag=7,salt=ordinal*29)
        trace.send(packet,'random' if ordinal>=len(lengths)-12 else 'pressure')
        trace.drain()
    return trace.samples


def reset_traces(profile, seed=17):
    traces={}
    for phase in ('dispatch','pending','full','partial','cell_hold','packet_hold'):
        trace=Trace(profile,seed);trace.reset()
        packet=trace.store(profile.max_length,salt=19)
        def stop(sample,state):
            out=sample['out'];a=sample['actions']
            return ((phase=='pending' and 'read' in a) or
                    (phase=='full' and state['issued']-state['retired']==profile.depth and all(due<trace.cycle for due,_ in state['available'])) or
                    (phase=='partial' and state['retired']==1) or
                    (phase=='cell_hold' and out['valid'] and not out['ready'] and
                     not out['last'] and (state['retired']+1)%(profile.cell_bytes//8)==0) or
                    (phase=='packet_hold' and out['valid'] and out['last'] and not out['ready']))
        if phase=='dispatch':trace.edge({'dispatch':0})
        else:trace.send(packet,stop=stop)
        trace.reset()
        # Reuse exact IDs and tags; old array values remain physically present.
        fresh=trace.store(profile.max_length,salt=177,chain=packet['chain'])
        trace.send(fresh);trace.drain()
        traces[phase]=trace.samples
    return traces


def atomic_overlap_trace(profile, seed=17):
    trace=Trace(profile,seed);trace.reset()
    old=trace.store(1,desc=0,salt=23,chain=[5])
    trace.send(old,stop=lambda sample,state:sample['out']['valid'] and not sample['out']['ready'])
    # A separate observed store and the final external transfer share one edge.
    other=Trace(profile,seed+1);new=other.store(1,desc=1,salt=71,chain=[1])
    actions=deepcopy(other.samples[0]['actions']);actions.update(free=5,done=0)
    out=deepcopy(trace.samples[-1]['out']);out['ready']=True
    trace.edge(actions,out)
    # Returned ID becomes legal on the following edge, with distinct new bytes.
    reused=trace.store(1,desc=0,salt=193,chain=[5])
    trace.send(new);trace.send(reused);trace.drain()
    return trace.samples


def reused_link_trace(profile,seed=17):
    trace=Trace(profile,seed);trace.reset()
    length=min(profile.max_length,2*profile.cell_bytes+3)
    chain=[5,1,9][:(length+profile.cell_bytes-1)//profile.cell_bytes]
    first=trace.store(length,desc=0,tag=7,salt=23,chain=chain)
    trace.send(first);trace.drain()
    second=trace.store(length,desc=0,tag=7,salt=177,chain=chain)
    second_start=len(trace.samples);trace.send(second);trace.drain()
    return trace.samples,second_start
