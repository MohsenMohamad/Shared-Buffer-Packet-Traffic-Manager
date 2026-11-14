"""Live public-edge driver and frozen-checker adapter for the production DUT."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import random
import select
import subprocess
import time

from adapter import encode_actions, decode_actions
from oracle import Oracle, Profile, Violation, require
from ledger import Ledger


class Live:
    def __init__(self, binary, profile, seed, directory):
        self.p, self.seed, self.path = profile, seed, Path(directory)
        self.path.mkdir(parents=True, exist_ok=True)
        self.rng = random.Random(seed)
        self.oracle, self.ledger = Oracle(profile), Ledger(profile)
        self.inputs = (self.path/'stimulus.txt').open('w')
        self.raw = (self.path/'server.stdout').open('w')
        self.errors = (self.path/'server.stderr').open('w')
        self.samples = (self.path/'samples.jsonl').open('w')
        self.process = subprocess.Popen([str(Path(binary).resolve())], cwd=self.path,
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=self.errors, text=True, bufsize=1)
        self.cycle, self.epoch, self.was_reset = -1, 0, False
        self.info, self.links, self.queue_links = {}, {}, {}
        self.bins, self.crosses, self.reset_hits = Counter(), Counter(), Counter()
        self.free_edges, self.previous, self.last = {}, None, None
        self.reset_cells = set()
        self.dispatch_cycle, self.first_valid, self.last_transfer = None, False, None
        self.ready_run = True
        self.seen_tags = set()
        self.hold_run = 0
        self.expected_public = {}
        self.performance = []
        self.started = time.monotonic()

    def line(self):
        require(bool(select.select([self.process.stdout], [], [], 15)[0]), 'adapter_timeout')
        line = self.process.stdout.readline()
        self.raw.write(line); self.raw.flush()
        require(line.startswith('TM_EDGE '), 'adapter_protocol', line.strip())
        return [int(value, 16) for value in line.split()[1:]]

    def edge(self, actions=None, *, reset=False, ready=True, queue_write=None):
        actions = actions or {}
        heads = [self.rng.choice(list(self.info)) if self.info else 0 for _ in range(self.p.queues)]
        if 'commit' in actions: heads[0] = actions['commit']
        if 'dispatch' in actions: heads[0] = actions['dispatch']
        abort = self.rng.randrange(self.p.cells)
        query = self.rng.randrange(self.p.descriptors)
        qv, qi, qn = (1, *queue_write) if queue_write else (0, 0, 0)
        row = [int(not reset), int(ready), encode_actions(actions),
               sum(d << (32*q) for q, d in enumerate(heads)), abort, qv, qi, qn, query, 0]
        text = ' '.join(f'{v:x}' for v in row)+'\n'
        self.inputs.write(text); self.inputs.flush()
        self.process.stdin.write(text); self.process.stdin.flush()
        values = self.line()
        packed, valid, data, keep, last, user, dispatch_ready, idle, infos, abort_next, queue_next = values
        observed = decode_actions(packed)
        self.cycle += 1
        if reset and not self.was_reset: self.epoch += 1
        sample = dict(epoch=self.epoch, cycle=self.cycle, reset=reset, actions=observed,
                      out=dict(valid=bool(valid), ready=bool(ready), data=data, keep=keep,
                               last=bool(last), user=user))
        self.samples.write(json.dumps(sample, sort_keys=True)+'\n'); self.samples.flush()
        self.last = sample
        # Metadata expectations use only pre-edge observed writes, including all muxes.
        for q, desc in enumerate(heads):
            if desc in self.info:
                bits = (infos >> (q*192)) & ((1<<192)-1)
                actual = dict(zip(('source','tag','qid','length','ncell','head'),
                                  [(bits >> (32*i)) & 0xffffffff for i in range(6)]))
                expected = {k:v for k,v in self.info[desc].items() if k != 'desc'}
                require(actual == expected, 'metadata_head_mux', f'q={q} desc={desc} expected={expected} observed={actual}')
                self.bins['metadata_head_'+str(q)] += 1
        if abort in self.links:
            require(abort_next == self.links[abort], 'metadata_abort_mux')
            self.bins['metadata_abort_mux'] += 1
        if query in self.queue_links:
            require(queue_next == self.queue_links[query], 'metadata_queue_mux')
            self.bins['metadata_queue_mux'] += 1
        if queue_write: self.queue_links[qi] = qn
        B, O = len(self.oracle.buffered), len(self.oracle.pending)
        self.observe(sample, B, O)
        if 'info' in observed: self.info[observed['info']['desc']] = observed['info'].copy()
        if 'link' in observed: self.links[observed['link']['cell']] = observed['link']['next']
        self.expected_public = dict(response=dict(valid=bool(self.oracle.physical_reads and
                                          self.oracle.physical_reads[0]['due']==self.cycle)))
        if self.expected_public['response']['valid']:
            self.expected_public['response']['data'] = self.oracle.physical_reads[0]['data']
        if self.oracle.active is not None:
            packet = self.oracle.packets[self.oracle.active]
            chunk = packet.image[packet.output_index*8:packet.output_index*8+8]
            meta = packet.info
            self.expected_public['output_when_valid'] = dict(data=int.from_bytes(chunk,'little'),
                keep=(1<<len(chunk))-1,last=packet.output_index*8+8>=len(packet.image),
                user=meta['qid'] | meta['length']<<8 | meta['tag']<<24 | meta['source']<<40)
            if packet.read_index*8>=len(packet.image) and 'query' in observed:
                require(observed['query']['cell']==packet.cells[-1], 'tail_traversal')
                self.bins['tail_not_traversed'] += 1
        if self.was_reset and not reset:
            require(not sample['out']['valid'], 'reset_release_output')
        self.oracle.step(sample)
        self.ledger.observe(sample, self.oracle)
        self.was_reset, self.previous = reset, sample
        return sample, bool(dispatch_ready), bool(idle)

    def observe(self, s, B, O):
        a, out = s['actions'], s['out']
        fire = out['valid'] and out['ready']
        self.crosses[f'L{self.p.latency}/D{self.p.depth}/B{B}/O{O}/I{int("read" in a)}/R{int("response" in a)}/T{int(fire)}/X{int(s["reset"])}'] += 1
        if s['reset']:
            if 'response' in a: self.bins['stale_physical_response'] += 1
            if not self.was_reset:
                self.reset_cells = set(self.oracle.owners)
                prev = self.previous
                if prev and 'dispatch' in prev['actions']: self.reset_hits['dispatch'] += 1
                if O: self.reset_hits['pending'] += 1
                if B == self.p.depth: self.reset_hits['full'] += 1
                if self.oracle.active is not None:
                    packet = self.oracle.packets[self.oracle.active]
                    index = packet.output_index
                    if index % (self.p.cell_bytes//8): self.reset_hits['partial'] += 1
                    if self.oracle.held:
                        if self.oracle.held['last']: self.reset_hits['packet-final'] += 1
                        elif (index+1) % (self.p.cell_bytes//8) == 0: self.reset_hits['cell-final'] += 1
            self.dispatch_cycle, self.last_transfer = None, None
            self.free_edges.clear()
            return
        if 'dispatch' in a:
            meta = a['dispatch_info']
            length = meta['length']
            for name,value in [('word_minus',7),('word',8),('word_plus',9),
                               ('cell_minus',self.p.cell_bytes-1),('cell',self.p.cell_bytes),
                               ('cell_plus',self.p.cell_bytes+1),('max_minus',self.p.max_length-1),('max',self.p.max_length)]:
                if length==value: self.bins['length_'+name] += 1
            self.bins['multi_cell' if meta['ncell']>1 else 'single_cell'] += 1
            packet = self.oracle.packets[a['dispatch']]
            if any(right != left+1 for left,right in zip(packet.cells,packet.cells[1:])):
                self.bins['fragmented_chain'] += 1
            if meta['tag'] in self.seen_tags: self.bins['duplicate_tag'] += 1
            self.seen_tags.add(meta['tag'])
            self.dispatch_cycle, self.first_valid, self.last_transfer = self.cycle, False, None
            self.ready_run = True
        if self.dispatch_cycle is not None:
            self.ready_run &= out['ready']
            if out['valid'] and not self.first_valid:
                delay = self.cycle-self.dispatch_cycle
                self.performance.append(dict(dispatch=self.dispatch_cycle, first_valid=delay,
                                             ready_since_dispatch=self.ready_run))
                if self.ready_run: require(delay <= self.p.latency+4, 'first_valid_bound', str(delay))
                self.first_valid = True
            if self.ready_run and self.first_valid and self.last_transfer is not None:
                require(out['valid'], 'cell_boundary_bubble', f'cycle={self.cycle}')
                self.bins['ready_contiguous'] += 1
            if fire: self.last_transfer = self.cycle
            if 'done' in a: self.dispatch_cycle = None
        if self.previous and 'read' in self.previous['actions'] and not out['ready']:
            self.bins['stall_after_issue'] += 1
        if 'response' in a and not out['ready']: self.bins['stalled_response'] += 1
        if out['valid'] and out['keep'] != 255: self.bins['ignored_lanes'] += 1
        self.hold_run = self.hold_run+1 if out['valid'] and not out['ready'] else 0
        if self.hold_run>=5: self.bins['long_output_hold'] += 1
        if 'read' in a and 'write' in a:
            require(a['read'] != a['write']['addr'], 'environment_ram_collision')
            self.bins['simultaneous_1r1w'] += 1
        if 'allocate' in a:
            cell = a['allocate']['cell']
            if self.free_edges.get(cell) == self.cycle-1: self.bins['earliest_cell_reuse'] += 1
            if cell in self.free_edges and self.free_edges[cell]<self.cycle-1: self.bins['delayed_legal_reuse'] += 1
            if cell in self.reset_cells: self.bins['reset_id_reuse'] += 1
        if 'write' in a and a['write']['addr']//(self.p.cell_bytes//8) in self.reset_cells:
            if self.oracle.memory.get(a['write']['addr']) != a['write']['data']: self.bins['distinctive_reset_payload'] += 1
        if 'write' in a and a['write']['addr']//(self.p.cell_bytes//8) in self.free_edges:
            self.bins['rewritten_returned_payload'] += 1
        if 'link' in a and a['link']['cell'] in self.free_edges:
            old = self.links.get(a['link']['cell'])
            if old is not None and old != a['link']['next']: self.bins['altered_returned_link'] += 1
        if 'free' in a: self.free_edges[a['free']] = self.cycle

    def reset(self):
        self.edge(reset=True, ready=False)
        self.edge(reset=True, ready=False)
        self.edge(ready=False)  # Published first release/initialization edge.
        self.edge(ready=False)

    def packet(self, length, ordinal, chain=None, desc=None):
        count = (length+self.p.cell_bytes-1)//self.p.cell_bytes
        if chain is None: chain = self.rng.sample(range(self.p.cells), count)
        desc = self.p.descriptors-1 if desc is None else desc
        info = dict(desc=desc, length=length, qid=ordinal % self.p.queues,
                    tag=7, source=ordinal % self.p.sources, head=chain[0], ncell=count)
        # All lanes get distinctive bytes; unused final lanes remain deliberately nonzero.
        words = [sum(((ordinal*73+j*29+lane*17+self.seed) % 256) << (8*lane)
                     for lane in range(8)) for j in range((length+7)//8)]
        return dict(info=info, chain=chain, words=words)

    def load_steps(self, packet):
        info, chain, words = packet['info'], packet['chain'], packet['words']
        desc, cw = info['desc'], self.p.cell_bytes//8
        for i, word in enumerate(words):
            cell = chain[i//cw]
            a = {'write': dict(addr=cell*cw+i%cw, data=word)}
            if i % cw == 0:
                a['allocate'] = dict(cell=cell, desc=desc)
                if i == 0:
                    a['reserve'] = {k:v for k,v in info.items() if k not in ('head','ncell')}
                    a['info'] = info.copy()
                else: a['link'] = dict(cell=chain[i//cw-1], next=cell)
            if len(words)==1:
                a['commit']=desc; a['commit_info']=info.copy()
            yield a
        if len(words)>1: yield dict(commit=desc)

    def load(self, packet):
        for a in self.load_steps(packet): self.edge(a)
        self.edge()

    def dispatch(self, packet):
        info = packet['info']
        s, available, _ = self.edge(dict(dispatch=info['desc'], dispatch_info=info.copy()))
        require(available, 'environment_dispatch_busy')
        require('dispatch' in s['actions'], 'adapter_dispatch_sample')

    def drain(self, packet, *, mode='holds', reset_at=None, background=None):
        index, held, initial_stall = 0, Counter(), 0
        count, cw = len(packet['words']), self.p.cell_bytes//8
        background_steps = None
        for _ in range(10000+count*30):
            # Trigger resets only after the required public condition was observed.
            if reset_at and self.last:
                a, out = self.last['actions'], self.last['out']
                conditions = dict(dispatch='dispatch' in a, pending=bool(self.oracle.pending),
                                  full=len(self.oracle.buffered)==self.p.depth,
                                  partial=index>0 and index%cw != 0,
                                  **{'cell-final':out['valid'] and not out['ready'] and
                                     not out['last'] and (index+1)%cw==0,
                                     'packet-final':out['valid'] and not out['ready'] and out['last']})
                if conditions[reset_at]:
                    self.reset(); return False, background_steps is not None
            ready = True
            if mode != 'ready':
                if initial_stall < self.p.depth+self.p.latency+5:
                    ready = False; initial_stall += 1
                elif mode!='pressure' and ((index+1)%cw==0 or index+1==count):
                    if held[index] < 5:
                        ready = False
                        if self.last and self.last['out']['valid']: held[index] += 1
                elif mode == 'random': ready = self.rng.randrange(4) != 0
            actions = None
            if background is not None and background_steps is None:
                if 'returned' not in background and self.last and 'free' in self.last['actions']:
                    background['returned'] = self.last['actions']['free']
                    background['due'] = self.cycle+1+background.get('delay',0)
                if 'due' in background and self.cycle+1>=background['due']:
                    spare = self.rng.choice([c for c in range(self.p.cells) if c not in packet['chain']])
                    background['packet'] = self.packet(self.p.cell_bytes+3, 991, [background['returned'],spare], 0)
                    background_steps = iter(self.load_steps(background['packet']))
            if background_steps is not None:
                actions = next(background_steps, None)
            s, _, _ = self.edge(actions, ready=ready)
            if s['out']['valid'] and s['out']['ready']: index += 1
            if 'done' in s['actions']:
                require(index==count, 'driver_incomplete_packet')
                if background_steps is not None:
                    for a in background_steps: self.edge(a)
                    self.edge()
                return True, background_steps is not None
        raise Violation('missing_final_output_or_completion', f'desc={packet["info"]["desc"]} accepted={index}/{count}')

    def run(self):
        self.reset()
        # Independent descriptor-next mux test. Owner/queue behavior is outside this array API.
        for d in range(self.p.descriptors): self.edge(queue_write=(d,(d*7+3)%self.p.descriptors))
        lengths = list(range(1,10))+[self.p.cell_bytes-1,self.p.cell_bytes,self.p.cell_bytes+1,
                                    self.p.max_length-1,self.p.max_length]
        lengths += [self.rng.randint(1,self.p.max_length) for _ in range(max(18,self.p.queues))]
        for ordinal, length in enumerate(lengths):
            packet = self.packet(length, ordinal, desc=(self.p.descriptors-1 if ordinal==0 else ordinal%self.p.descriptors))
            self.load(packet); self.dispatch(packet)
            self.drain(packet, mode='ready' if ordinal%3==0 else 'random' if ordinal%3==1 else 'holds')
            self.edge()
        # Deterministic full-credit exchange witness, independent of random sink choices.
        pressure = self.packet(self.p.max_length, 222)
        self.load(pressure); self.dispatch(pressure); self.drain(pressure,mode='pressure')
        self.edge()
        # Exact capacity, per-cell/final holds, immediate legal reuse and altered old payload/links.
        for delay in (0,self.rng.randint(1,7)):
            packet = self.packet(self.p.max_length, 333)
            self.load(packet); self.dispatch(packet)
            background = {'delay':delay}
            _, triggered = self.drain(packet, background=background)
            require(triggered, 'required_reuse_trigger')
            self.dispatch(background['packet']); self.drain(background['packet'])
            self.edge()
        for phase in ('dispatch','pending','full','partial','cell-final','packet-final'):
            packet = self.packet(self.p.max_length, 444)
            self.load(packet); self.dispatch(packet)
            completed, _ = self.drain(packet, reset_at=phase)
            require(not completed, 'required_reset_trigger', phase)
            restart = self.packet(self.p.cell_bytes+7, 555, packet['chain'][:2], packet['info']['desc'])
            self.load(restart); self.dispatch(restart); self.drain(restart)
            self.edge()
        for _ in range(self.p.latency+3): self.edge()
        required = ['complete','atomic_commit','exact_full','full_arrival','full_stall','full_exchange',
                    'cell_final_hold','packet_final_hold','link_query','maximum_descriptor']
        required += [f'keep_{i}' for i in range(1,9)]
        required += [f'source_{i}' for i in range(self.p.sources)]+[f'qid_{i}' for i in range(self.p.queues)]
        report = self.oracle.finish(required)
        for name in ('stall_after_issue','stalled_response','earliest_cell_reuse',
                     'simultaneous_1r1w','rewritten_returned_payload','ready_contiguous',
                     'metadata_abort_mux','metadata_queue_mux','altered_returned_link','tail_not_traversed',
                     'single_cell','multi_cell','fragmented_chain','duplicate_tag','ignored_lanes','long_output_hold',
                     'delayed_legal_reuse','stale_physical_response','reset_id_reuse','distinctive_reset_payload',
                     'length_word_minus','length_word','length_word_plus','length_cell_minus','length_cell',
                     'length_cell_plus','length_max_minus','length_max'):
            require(self.bins[name]>0, 'required_dut_bin', name)
        for q in range(self.p.queues): require(self.bins['metadata_head_'+str(q)]>0,'required_metadata_port',str(q))
        for phase in ('dispatch','pending','full','partial','cell-final','packet-final'):
            require(self.reset_hits[phase]>0, 'required_reset_bin', phase)
        report.update(dut_bins=dict(self.bins), reset_crosses=dict(self.reset_hits),
                      occupancy_crosses=dict(self.crosses), performance=self.performance)
        return report

    def close(self):
        self.process.stdin.close()
        try:
            rest = self.process.stdout.read()
            self.raw.write(rest)
            code = self.process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            self.process.kill(); code = self.process.wait(); rest = ''
        self.raw.close(); self.errors.close(); self.samples.close(); self.inputs.close()
        return code, rest


def ram_probe(binary, p, seed, directory):
    raw = Live(binary,p,seed,directory)
    memory, pending, responses = {}, {}, []
    cycle = -1
    counter = Counter()
    rng = random.Random(seed)
    def edge(*, reset=False, write=None, read=None):
        nonlocal cycle
        cycle += 1
        actions = {}
        if write: actions['write'] = dict(addr=write[0],data=write[1])
        if read is not None: actions['read'] = read
        row = [int(not reset),0,encode_actions(actions),0,0,0,0,0,0,1]
        line = ' '.join(f'{v:x}' for v in row)+'\n'
        raw.inputs.write(line);raw.inputs.flush()
        raw.process.stdin.write(line);raw.process.stdin.flush()
        values = raw.line();actual = decode_actions(values[0])
        sample = dict(cycle=cycle,reset=reset,actions=actual,output_valid=bool(values[1]))
        raw.samples.write(json.dumps(sample,sort_keys=True)+'\n');raw.samples.flush()
        raw.last = sample
        due = pending.pop(cycle,None)
        require(('response' in actual)==(due is not None),'response_presence',f'RAM cycle={cycle}')
        if due is not None:
            require(actual['response']['data']==due,'response_data',f'RAM cycle={cycle} expected={due} observed={actual["response"]}')
            responses.append(due);counter['responses']+=1
            if reset:counter['response_during_reset']+=1
        require(not values[1],'reset_output' if reset else 'idle_output')
        if read is not None:
            require(read in memory,'environment_unwritten_ram_probe')
            require(not write or write[0]!=read,'environment_ram_collision')
            pending[cycle+p.latency] = memory[read];counter['reads']+=1
        if write:
            memory[write[0]]=write[1];counter['writes']+=1
            if read is not None:counter['simultaneous_1r1w']+=1
    error = None
    try:
        edge(reset=True);edge(reset=True);edge()
        words = p.cells*p.cell_bytes//8
        addresses = sorted({0,1,p.cell_bytes//8-1,p.cell_bytes//8,p.cell_bytes//8+1,words-2,words-1})
        for i,addr in enumerate(addresses):
            data = [0,(1<<64)-1,0x0123456789abcdef,0xfedcba9876543210][i%4] ^ rng.getrandbits(64)
            edge(write=(addr,data))
        for i,addr in enumerate(addresses):
            other = addresses[(i+1)%len(addresses)]
            edge(read=addr,write=(other,rng.getrandbits(64)))
        edge(read=addresses[0])
        edge(reset=True);edge(reset=True);edge() # Contents and pending physical responses survive.
        for addr in addresses:edge(read=addr)
        for _ in range(p.latency+2):edge()
        require(not pending,'shutdown_transactions')
        require(counter['reads']==counter['responses'] and counter['response_during_reset']>0 and counter['simultaneous_1r1w']>0,'required_ram_component_bins')
    except (Violation,OSError,ValueError) as failure:
        error = dict(detector=getattr(failure,'detector','adapter_error'),detail=str(failure),phase='ram-component',sample=raw.last)
    code,tail=raw.close()
    if error or code!=0 or 'TM_SERVER_DONE' not in tail:
        error = error or dict(detector='adapter_exit',phase='ram-component')
        error['server_returncode']=code
        (Path(directory).parent/'violation.json').write_text(json.dumps(error,indent=2)+'\n')
        print('TM_MEMORY_TX_DUT_FAIL '+json.dumps(error))
        raise SystemExit(1)
    return dict(counts=dict(counter),response_data_sha256=hashlib.sha256(json.dumps(responses).encode()).hexdigest(),
                sampled_edges=cycle+1,readback_after_reset=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', required=True, type=Path)
    parser.add_argument('--profile-json', required=True, type=Path)
    parser.add_argument('--seed', type=int, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--tx-only', action='store_true')
    args = parser.parse_args()
    profile = Profile(**json.loads(args.profile_json.read_text()))
    ram_result = None if args.tx_only else ram_probe(args.binary, profile, args.seed, args.output/'ram-probe')
    live = Live(args.binary, profile, args.seed, args.output)
    error, report = None, None
    try: report = live.run()
    except (Violation, OSError, ValueError, BrokenPipeError) as failure:
        error = dict(detector=getattr(failure,'detector','adapter_error'), detail=str(failure),
                     sample=live.last, seed=args.seed, expected_interface=live.expected_public,
                     public_stimulus=(live.path/'stimulus.txt').read_text().splitlines()[-1:])
        (args.output/'violation.json').write_text(json.dumps(error, indent=2)+'\n')
    code, tail = live.close()
    if error:
        error['server_returncode']=code
        (args.output/'violation.json').write_text(json.dumps(error,indent=2)+'\n')
    if error or code != 0 or 'TM_SERVER_DONE' not in tail:
        print('TM_MEMORY_TX_DUT_FAIL '+json.dumps(error or dict(detector='adapter_exit',returncode=code)))
        return 1
    report.update(ram_component=ram_result, seed=args.seed, elapsed_seconds=time.monotonic()-live.started,
                  stimulus_sha256=hashlib.sha256((args.output/'stimulus.txt').read_bytes()).hexdigest(),
                  sample_sha256=hashlib.sha256((args.output/'samples.jsonl').read_bytes()).hexdigest())
    (args.output/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print('TM_MEMORY_TX_DUT_PASS')
    return 0


if __name__ == '__main__': raise SystemExit(main())
