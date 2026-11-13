"""Recompute lifetime and read totals from sample history, independent of deltas."""
from collections import Counter
from oracle import require


class Ledger:
    def __init__(self,profile):
        self.p=profile;self.epoch=-1;self.reservations=[];self.active=None
        self.reads=[];self.outputs=0;self.responses=0

    def observe(self,sample,model):
        if sample['reset']:
            self.reservations=[];self.active=None;self.reads=[];self.outputs=self.responses=0
            return
        a=sample['actions']
        if 'reserve' in a:
            self.reservations.append(dict(info=a['reserve'],allocations=0,beats=0,retirements=0,ended=False))
        if 'allocate' in a:
            lifetime=next(r for r in reversed(self.reservations) if r['info']['desc']==a['allocate']['desc'] and not r['ended'])
            lifetime['allocations']+=1
        if 'dispatch' in a:
            self.active=next(r for r in reversed(self.reservations) if r['info']['desc']==a['dispatch'] and not r['ended'])
        if 'read' in a:self.reads.append(sample['cycle']+self.p.latency)
        self.responses=sum(due<=sample['cycle'] for due in self.reads)
        if sample['out']['valid'] and sample['out']['ready']:
            require(self.active is not None,'ledger_output_without_dispatch')
            self.active['beats']+=1;self.outputs+=1
            length=self.active['info']['length'];consumed=min(length,self.active['beats']*8)
            # A cell retires only when all its bytes are externally consumed.
            self.active['retirements']=consumed//self.p.cell_bytes+int(consumed==length and length%self.p.cell_bytes!=0)
            if consumed==length:self.active['ended']=True;self.active=None
        budget=sum((r['info']['length']+self.p.cell_bytes-1)//self.p.cell_bytes for r in self.reservations)
        allocated=sum(r['allocations'] for r in self.reservations)
        retired=sum(r['retirements'] for r in self.reservations)
        expected_H=Counter()
        for r in self.reservations:
            expected_H[r['info']['qid']]+=(r['info']['length']+self.p.cell_bytes-1)//self.p.cell_bytes-r['retirements']
        require((model.U,model.A,model.R)==(self.p.cells-budget+retired,allocated-retired,budget-allocated),
                'ledger_resources')
        require(model.H==expected_H,'ledger_queue_credit')
        require(len(model.packets)==sum(not r['ended'] for r in self.reservations),'ledger_descriptors')
        require(len(model.pending)==len(self.reads)-self.responses and len(model.buffered)==self.responses-self.outputs,
                'ledger_transactions')
