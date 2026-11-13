"""Observed-write memory/TX specification model; no implementation imports."""
from __future__ import annotations
from collections import Counter, deque
from copy import deepcopy
from dataclasses import dataclass, field


class Violation(AssertionError):
    def __init__(self, detector, detail=''):
        self.detector = detector
        super().__init__(f'{detector}: {detail}')


def require(condition, detector, detail=''):
    if not condition:
        raise Violation(detector, detail)


@dataclass(frozen=True)
class Profile:
    latency: int = 1
    depth: int = 4
    cell_bytes: int = 16
    cells: int = 16
    descriptors: int = 8
    max_length: int = 128
    queues: int = 2
    sources: int = 1

    def __post_init__(self):
        require(self.latency in (1, 2), 'parameter_latency')
        require(self.depth >= self.latency + 2, 'parameter_depth')
        require(self.cell_bytes in (16, 32, 64), 'parameter_cell')
        require(16 <= self.cells <= 1024 and self.cells & (self.cells-1) == 0,
                'parameter_cells')
        require(8 <= self.descriptors <= 256 and self.descriptors & (self.descriptors-1) == 0,
                'parameter_descriptors')
        require(64 <= self.max_length <= min(1536, self.cells*self.cell_bytes),
                'parameter_length')
        require(self.queues in (2, 4, 8, 16) and self.sources in (1, 2, 4), 'parameter_lanes')


@dataclass
class Packet:
    ordinal: int
    info: dict
    cells: list = field(default_factory=list)
    state: str = 'RX'
    image: bytes = b''
    read_index: int = 0
    output_index: int = 0
    written: set = field(default_factory=set)


class Oracle:
    """Consume one complete sampled edge at a time; expectations never drive stimulus."""
    def __init__(self, profile=Profile(), disabled=()):
        self.p = profile
        self.disabled = frozenset(disabled)  # Only isolated self-test detector removals.
        self.memory, self.links, self.info_array = {}, {}, {}
        self.physical_reads = deque()
        self.epoch, self.cycle, self.ordinal = 0, -1, 0
        self.in_reset, self.reset_edges, self.release_cycle = False, 0, None
        self.bins = Counter()
        self.counts = Counter()
        self._clear_control()

    def check(self, condition, detector, detail=''):
        if detector not in self.disabled:
            require(condition, detector, detail)

    def _clear_control(self):
        self.packets, self.owners = {}, {}
        self.queues = {q: deque() for q in range(self.p.queues)}
        self.active = None
        self.buffered = deque()
        self.pending = deque()
        self.captured_links = set()
        self.held = None
        self.U, self.A, self.R = self.p.cells, 0, 0
        self.H = Counter()
        self.retired_cells, self.completed = set(), set()
        self.last_counts = Counter()

    def snapshot(self):
        return deepcopy((self.memory, self.links, self.info_array, self.packets,
                         self.owners, self.U, self.A, self.R, self.H))

    def step(self, sample):
        s = deepcopy(sample)
        require(set(s) == {'epoch', 'cycle', 'reset', 'actions', 'out'}, 'sample_shape')
        require(s['cycle'] == self.cycle+1, 'sample_cycle')
        require(s['epoch'] == self.epoch + int(s['reset'] and not self.in_reset), 'sample_epoch')
        self.cycle = s['cycle']
        a, out = s['actions'], s['out']
        require(set(out) == {'valid', 'ready', 'data', 'keep', 'last', 'user'}, 'output_shape')
        require(set(a) <= {'reserve', 'allocate', 'write', 'info', 'link', 'commit',
                           'dispatch', 'read', 'response', 'query', 'free', 'done', 'commit_info', 'dispatch_info'}, 'action_shape')
        # Physical RAM is unreset. Capture its due response before control flush.
        due = self.physical_reads[0] if self.physical_reads and self.physical_reads[0]['due'] == self.cycle else None
        response = a.get('response')
        self.check(bool(response) == bool(due), 'response_presence')
        if due and response:
            self.check(response['data'] == due['data'], 'response_data')
            self.physical_reads.popleft()
        if s['reset']:
            require(not any(k != 'response' for k in a), 'environment_reset_action')
            self.check(not out['valid'], 'reset_output')
            if not self.in_reset:
                self.bins['reset'] += 1
                self.bins['reset_pending' if self.pending else 'reset_idle'] += 1
                self.bins['reset_full' if len(self.buffered)+len(self.pending)==self.p.depth else 'reset_nonfull'] += 1
                if len(self.buffered)==self.p.depth:self.bins['reset_full_fifo'] += 1
                if self.active is not None:
                    packet = self.packets[self.active]
                    idx = packet.output_index
                    if idx % (self.p.cell_bytes//8): self.bins['reset_partial_cell'] += 1
                    if self.held:
                        self.bins['reset_packet_final_hold' if self.held['last'] else 'reset_cell_final_hold' if (idx+1)%(self.p.cell_bytes//8)==0 else 'reset_beat_hold'] += 1
                self.epoch += 1
            self._clear_control()
            self.in_reset = True
            self.reset_edges += 1
            return
        if self.in_reset:
            require(self.reset_edges >= 2, 'environment_reset_width')
            self.release_cycle = self.cycle
            self.in_reset, self.reset_edges = False, 0
            require(not a and not out['valid'], 'environment_initialization')
            return
        require(self.release_cycle is not None, 'environment_uninitialized')
        if self.held is not None:
            fields = ('valid','data','keep','last','user')
            self.check(all(out[k] == self.held[k] for k in fields), 'held_output')
        self.held = deepcopy(out) if out['valid'] and not out['ready'] else None
        self.check(('info' in a)==('reserve' in a),'metadata_info_presence')
        pre_owners = dict(self.owners)
        pre_packets = set(self.packets)
        pre_queues = {q:list(v) for q,v in self.queues.items()}
        pre_U = self.U
        B, O = len(self.buffered), len(self.pending)
        transfer = bool(out['valid'] and out['ready'])
        self.counts['edges'] += 1
        self.bins[f'latency_{self.p.latency}'] += 1
        self.bins[f'depth_{self.p.depth}'] += 1
        expected_free, expected_done = None, None
        if out['valid']:
            self.check(self.active is not None and bool(self.buffered), 'output_presence')
            if self.active is not None and self.buffered:
                packet = self.packets[self.active]
                i = packet.output_index
                offset = i*8
                chunk = packet.image[offset:offset+8]
                self.check(bool(chunk), 'output_extra')
                keep = (1<<len(chunk))-1
                self.check(out['keep']==keep, 'output_keep')
                expected_last=offset+8>=len(packet.image)
                self.check(out['last']==expected_last, 'output_last')
                meta = packet.info
                user = meta['qid'] | meta['length']<<8 | meta['tag']<<24 | meta['source']<<40
                self.check(out['user']==user, 'output_user')
                for lane, byte in enumerate(chunk):
                    self.check((out['data']>>(lane*8))&255 == byte, 'output_data')
                token = self.buffered[0]
                self.check(token['desc']==self.active and token['index']==i, 'output_order')
                final_cell = (offset+8) % self.p.cell_bytes == 0 or expected_last
                if not out['ready']:
                    self.bins['packet_final_hold' if out['last'] else 'cell_final_hold' if final_cell else 'beat_hold'] += 1
                if transfer:
                    self.buffered.popleft()
                    cell = packet.cells[offset//self.p.cell_bytes]
                    if final_cell:
                        expected_free = cell
                        if not expected_last:
                            self.check((packet.ordinal, cell) in self.captured_links, 'link_capture')
                    if expected_last:
                        expected_done = self.active
                    packet.output_index += 1
                    self.counts['outputs'] += 1
                    self.counts['bytes'] += len(chunk)
                    self.bins[f'keep_{len(chunk)}'] += 1
                    self.bins[f'source_{meta["source"]}'] += 1
                    self.bins[f'qid_{meta["qid"]}'] += 1
        actual_free = a.get('free')
        self.check((actual_free is not None)==(expected_free is not None), 'cell_completion_presence')
        if actual_free is not None and expected_free is not None:
            self.check(actual_free==expected_free, 'cell_completion_id')
            self.check(expected_free in pre_owners, 'cell_completion_owner')
        self.check((a.get('done') is not None)==(expected_done is not None), 'descriptor_completion_presence')
        if a.get('done') is not None and expected_done is not None:
            self.check(a['done']==expected_done, 'descriptor_completion_id')
        if 'reserve' in a:
            r = a['reserve']; d = r['desc']; length = r['length']
            n = (length+self.p.cell_bytes-1)//self.p.cell_bytes
            require(d not in pre_packets and 0<=d<self.p.descriptors, 'environment_descriptor_reuse')
            require(1<=length<=self.p.max_length and 0<=r['qid']<self.p.queues
                    and 0<=r['source']<self.p.sources and 0<=r['tag']<65536, 'environment_header')
            require(pre_U>=n, 'environment_reservation_credit')
            self.ordinal += 1
            self.packets[d] = Packet(self.ordinal, deepcopy(r))
            self.U -= n; self.R += n; self.H[r['qid']] += n
            self.counts['reserves'] += 1
        if 'allocate' in a:
            alloc = a['allocate']; cell, d = alloc['cell'], alloc['desc']
            require(cell not in pre_owners and 0<=cell<self.p.cells, 'environment_cell_reuse')
            require(d in self.packets and self.packets[d].state=='RX', 'environment_allocate_owner')
            packet = self.packets[d]
            require(len(packet.cells)<(packet.info['length']+self.p.cell_bytes-1)//self.p.cell_bytes,
                    'environment_allocate_budget')
            packet.cells.append(cell); self.owners[cell]=d
            self.A += 1; self.R -= 1
            self.counts['allocations'] += 1
        if 'write' in a:
            w=a['write']; addr=w['addr']; cell=addr//(self.p.cell_bytes//8)
            require(cell in self.owners and self.packets[self.owners[cell]].state=='RX', 'environment_write_owner')
            require(0<=w['data']<1<<64, 'environment_write_data')
            self.memory[addr]=w['data']; self.packets[self.owners[cell]].written.add(addr)
            self.counts['writes'] += 1
        if 'info' in a:
            info=a['info']; d=info['desc']
            require('reserve' in a and d==a['reserve']['desc'], 'environment_info_writer')
            self.check(info==a['reserve'] | {'head':self.packets[d].cells[0], 'ncell':(self.packets[d].info['length']+self.p.cell_bytes-1)//self.p.cell_bytes}, 'metadata_info')
            self.info_array[d]=deepcopy(info)
        if 'link' in a:
            link=a['link']; cell,nxt=link['cell'],link['next']
            require(cell in self.owners and nxt in self.owners and self.owners[cell]==self.owners[nxt], 'environment_link_owner')
            packet=self.packets[self.owners[cell]]
            require(packet.state=='RX' and packet.cells[-2:]==[cell,nxt], 'environment_link_writer')
            self.links[cell]=nxt
        if 'commit' in a:
            d=a['commit']; require(d in self.packets and self.packets[d].state=='RX', 'environment_commit_owner')
            packet=self.packets[d]; meta=packet.info
            n=(meta['length']+self.p.cell_bytes-1)//self.p.cell_bytes
            self.check(len(packet.cells)==n and d in self.info_array, 'commit_complete')
            self.check(a.get('commit_info')==meta | {'head':packet.cells[0],'ncell':n},'metadata_commit')
            image=bytearray()
            for j in range(meta['length']):
                cell=packet.cells[j//self.p.cell_bytes]
                addr=cell*(self.p.cell_bytes//8)+(j%self.p.cell_bytes)//8
                self.check(addr in packet.written, 'commit_written')
                image.append((self.memory.get(addr,0)>>(8*(j%8)))&255)
            for left,right in zip(packet.cells,packet.cells[1:]):
                self.check(self.links.get(left)==right, 'commit_chain')
            packet.image=bytes(image); packet.state='QUEUED'
            self.queues[meta['qid']].append(d)
            self.counts['commits'] += 1
            if all(k in a for k in ('reserve','allocate','write','info')): self.bins['atomic_commit'] += 1
        if 'dispatch' in a:
            d=a['dispatch']
            require(self.active is None and not self.buffered and not self.pending, 'environment_dispatch_busy')
            require(d in pre_packets and self.packets[d].state=='QUEUED', 'environment_dispatch_owner')
            packet=self.packets[d]
            self.check(a.get('dispatch_info')==packet.info | {'head':packet.cells[0],'ncell':len(packet.cells)},'metadata_dispatch')
            q=packet.info['qid']
            require(bool(pre_queues[q]) and pre_queues[q][0]==d, 'environment_dispatch_prestate')
            self.queues[q].popleft(); self.packets[d].state='TX'; self.active=d
            self.counts['dispatches'] += 1
            if d==self.p.descriptors-1:self.bins['maximum_descriptor'] += 1
        if 'query' in a:
            q=a['query']; cell=q['cell']
            if cell in pre_owners and pre_owners[cell]==self.active:
                packet=self.packets[self.active]
                idx=packet.cells.index(cell)
                if idx+1<len(packet.cells):
                    self.check(q['next']==packet.cells[idx+1], 'metadata_next')
                    self.captured_links.add((packet.ordinal,cell))
                    self.bins['link_query'] += 1
        # Arrival cannot fund a same-edge output absent a buffered pre-state beat.
        arrival=bool(due and due['epoch']==self.epoch)
        if arrival:
            self.check(bool(self.pending) and self.pending[0]==due, 'response_order')
            if self.pending: self.pending.popleft()
            self.buffered.append(due)
            self.counts['responses'] += 1
        if 'read' in a:
            require(self.active is not None, 'environment_read_owner')
            packet=self.packets[self.active]; i=packet.read_index
            self.check(B+O+1-int(transfer)<=self.p.depth, 'read_credit')
            self.check(i*8<len(packet.image), 'read_extra')
            cell=packet.cells[min(i*8//self.p.cell_bytes,len(packet.cells)-1)]
            addr=cell*(self.p.cell_bytes//8)+i%(self.p.cell_bytes//8)
            self.check(a['read']==addr, 'read_address')
            self.check(pre_owners.get(cell)==self.active, 'read_lifetime')
            require(not ('write' in a and a['write']['addr']==a['read']), 'environment_ram_collision')
            token={'due':self.cycle+self.p.latency,'data':self.memory[a['read']],
                   'epoch':self.epoch,'desc':self.active,'index':i}
            self.physical_reads.append(token); self.pending.append(token)
            packet.read_index += 1
            self.counts['reads'] += 1
        if expected_free is not None:
            d=self.active; q=self.packets[d].info['qid']
            self.owners.pop(expected_free,None)
            self.A -= 1; self.U += 1; self.H[q] -= 1
            self.retired_cells.add((self.packets[d].ordinal,expected_free))
            self.counts['frees'] += 1
        if expected_done is not None:
            packet=self.packets[self.active]
            for cell in packet.cells:self.captured_links.discard((packet.ordinal,cell))
            self.completed.add(packet.ordinal)
            del self.packets[self.active]; self.active=None
            self.counts['done'] += 1
        self.check(len(self.buffered)==B+int(arrival)-int(transfer), 'buffer_delta')
        self.check(len(self.pending)==O+int('read' in a)-int(arrival), 'outstanding_delta')
        self.check(len(self.buffered)+len(self.pending)<=self.p.depth, 'read_credit')
        F=self.p.cells-len(self.owners)
        self.check(self.A==len(self.owners) and self.A+F==self.p.cells and
                   F==self.U+self.R and self.p.cells==self.U+sum(self.H.values()) and
                   min(self.A,self.U,self.R,*self.H.values())>=0, 'resource_equations')
        if B+O==self.p.depth:
            self.bins['exact_full'] += 1
            if not transfer: self.bins['full_stall'] += 1
            if arrival: self.bins['full_arrival'] += 1
            if arrival and transfer and 'read' in a: self.bins['full_exchange'] += 1
        if a.get('done') is not None: self.bins['complete'] += 1
        if all(k in a for k in ('reserve','allocate','write','commit','free','done')):
            self.bins['atomic_store_retire'] += 1
        if 'free' in a: self.bins['cell_retire'] += 1
        if 'reserve' in a and a['reserve']['tag']==7: self.bins['duplicate_tag_candidate'] += 1

    def finish(self, required=()):
        self.check(self.cycle>=0 and self.release_cycle is not None,'shutdown_initialization')
        self.check(not self.in_reset, 'shutdown_reset')
        self.check(not self.packets and not self.owners and self.active is None and
                   not any(self.queues.values()), 'shutdown_ownership')
        self.check(not self.pending and not self.buffered and not self.physical_reads,
                   'shutdown_transactions')
        self.check(self.held is None, 'shutdown_held')
        self.check(self.U==self.p.cells and self.A==self.R==0 and not any(self.H.values()),
                   'shutdown_resources')
        for name in required:
            self.check(self.bins[name]>0, 'required_bin', name)
        return {'counts':dict(self.counts),'bins':dict(self.bins)}
