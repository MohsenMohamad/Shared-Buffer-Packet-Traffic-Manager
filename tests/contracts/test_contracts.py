"""Executable G1 boundary examples; no functional component result is inferred."""
import hashlib
import itertools
import json
import os
from pathlib import Path
import random
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'dv/model'), str(ROOT / 'tools')]
from events import (PacketKey, Packet, Admission, CellRelease, AbortDone, PolicyEvents,
                    StreamSample, BusSample, Collector, CycleBatch, PolicyState)
from registry import profile, sources, selection

IDLE = StreamSample(False, False, None)


def state():
    # Six assigned cells, four reserved-free; no optimistic admission bypass.
    return PolicyState(16, 8, 16, 128, (16, 16), 6, 4, 6, 1, [8, 2], [[], []])


def batch(policy):
    return CycleBatch(0, 7, False, (IDLE,), IDLE, BusSample(), (), policy)


class EventTests(unittest.TestCase):
    def collect(self, policy, order):
        samples = dict(reset=False, rx0=IDLE, output=IDLE, bus=BusSample(), status=(), policy=policy)
        collector = Collector(1)
        for source in order:
            collector.submit(0, 7, source, samples[source])
        return collector.seal(0, 7)

    def orders(self):
        # Exhaustive monitor permutations, with replayable randomized traversal.
        orders = list(itertools.permutations(('reset','rx0','output','bus','status','policy')))
        random.Random(int(os.environ.get('TM_CONTRACT_SEED', '17'))).shuffle(orders)
        digest = hashlib.sha256(repr(orders).encode()).hexdigest()
        self.assertEqual(len(orders),720)
        print('TM_BATCH_ORDERS seed=' + os.environ.get('TM_CONTRACT_SEED','17') + ' digest=' + digest)
        return orders

    def test_reserve_release_two_descriptor_returns_are_atomic(self):
        e = PolicyEvents(admission=Admission(PacketKey(0,0,2),0,32,True,'COMMITTED'),
                         materialize=1, release=CellRelease(1),
                         abort_done=AbortDone(0,4), tx_done=True)
        expected = state()
        expected.apply(batch(e))
        self.assertEqual((expected.u, expected.r, expected.a, expected.d, expected.h),
                         (9,1,6,2,[6,1]))
        for order in self.orders():
            model = state()
            model.apply(self.collect(e, order))
            self.assertEqual(model, expected)

    def test_release_cannot_fund_prestate_admission(self):
        e = PolicyEvents(admission=Admission(PacketKey(0,0,2),0,112,False,'NO_CELLS'),
                         release=CellRelease(1),tx_done=True)
        for order in self.orders():
            model = state()
            model.apply(self.collect(e, order))
            self.assertEqual((model.u,model.d),(7,2))
        wrong = PolicyEvents(admission=Admission(PacketKey(0,0,2),0,112,True,'COMMITTED'),
                             release=CellRelease(1))
        before = state()
        with self.assertRaisesRegex(ValueError,'pre-state'):
            before.apply(batch(wrong))
        self.assertEqual(before,state())  # failed validation made no partial update

    def test_last_pop_and_push_preserve_new_packet(self):
        old = Packet(PacketKey(0,0,0),0,16,5,b'a'*16)
        new = Packet(PacketKey(0,0,1),0,16,5,b'b'*16)  # duplicate tag is intentional
        e = PolicyEvents(commit=new, dispatch=(0,old.key))
        for order in self.orders():
            model=state(); model.queues[0]=[old]
            model.apply(self.collect(e,order))
            self.assertEqual(model.queues[0],[new])

    def test_commit_cannot_bypass_empty_dispatch(self):
        new = Packet(PacketKey(0,0,0),0,16,5,b'a'*16)
        for order in self.orders():
            model=state()
            with self.assertRaisesRegex(ValueError,'pre-state head'):
                model.apply(self.collect(PolicyEvents(commit=new,dispatch=(0,new.key)),order))
            self.assertEqual(model,state())

    def test_barrier_rejects_incomplete_duplicate_stale_and_unknown(self):
        c=Collector(1)
        c.submit(0,0,'reset',False)
        for args in [(0,0,'reset',False),(0,0,'invented',False),(0,1,'rx0',IDLE)]:
            with self.assertRaises(ValueError): c.submit(*args)
        with self.assertRaises(ValueError): c.seal(0,0)
        for source,sample in dict(rx0=IDLE,output=IDLE,bus=BusSample(),status=(),policy=PolicyEvents()).items():
            c.submit(0,0,source,sample)
        c.seal(0,0)
        with self.assertRaises(ValueError): c.submit(0,0,'reset',False)
        c.submit(1,0,'reset',True)  # new epoch may restart cycle numbering

    def test_reset_flushes_policy_epoch(self):
        model=state()
        model.apply(CycleBatch(1,0,True,(IDLE,),IDLE,BusSample(),(),PolicyEvents()))
        self.assertEqual((model.u,model.r,model.a,model.d,model.h,model.queues),
                         (16,0,0,8,[0,0],[[],[]]))

    def test_rejected_delta_is_atomic(self):
        model=state()
        with self.assertRaises(ValueError): model.apply(batch(PolicyEvents(abort_done=AbortDone(0,8))))
        self.assertEqual(model,state())


class RegistrationTests(unittest.TestCase):
    def test_profiles_and_source_separation(self):
        self.assertEqual(profile('E0')['N_RX'],1)
        self.assertEqual(profile('F0')['N_CELL'],1024)
        self.assertEqual(profile('F1')['MEM_RD_LATENCY'],2)
        self.assertEqual(set(selection('I0',None)),{'contracts'})
        for name in ('production','synthesis'):
            self.assertTrue(all(p.startswith('rtl/') for p in sources(name)['sources']))
            self.assertNotIn('dv/model/tm_monitor_types.svh',sources(name)['headers'])
        self.assertIn('dv/model/tm_monitor_types.svh',sources('simulation')['headers'])
        self.assertIn('formal/pools/storage_formal.sv', sources('formal')['sources'])
        self.assertFalse(any('tests/toolchain' in p for p in sources('formal')['sources']))
        self.assertEqual(selection('E0', ['pools']), ['pools'])
        self.assertEqual(selection('E0', ['csr']), ['csr'])
        self.assertEqual(selection('E0', ['queues']), ['queues'])
        self.assertEqual(selection('E0', ['queues-dispatch-guard']), ['queues-dispatch-guard'])
        self.assertIn('dv/unit/queues_dispatch_guard_tb.sv', sources('queues-dispatch-guard')['sources'])
        self.assertNotIn('dv/unit/queues_dispatch_guard_tb.sv', sources('queues-independent')['sources'])
        self.assertNotIn('dv/unit/queues_dispatch_guard_tb.sv', sources('formal')['sources'])
        self.assertIn('rtl/queue/tm_queue_ctrl.sv', sources('production')['sources'])
        self.assertIn('rtl/queue/tm_desc_links.sv', sources('synthesis')['sources'])
        self.assertIn('formal/queue/queue_formal.sv', sources('formal')['sources'])
        self.assertIn('dv/unit/queues_tb.sv', sources('queues')['sources'])
        self.assertNotIn('dv/unit/queues_tb.sv', sources('formal')['sources'])
        self.assertIn('rtl/csr/tm_axil_regs.sv', sources('production')['sources'])
        self.assertIn('rtl/csr/tm_statistics.sv', sources('synthesis')['sources'])
        self.assertIn('dv/fixtures/tm_csr_fixture.sv', sources('csr')['sources'])
        self.assertNotIn('dv/fixtures/tm_csr_fixture.sv', sources('formal')['sources'])
        self.assertIn('formal/csr/csr_formal.sv', sources('formal')['sources'])

    def test_bad_selections(self):
        for name,tests in [('unknown',['contracts']),('F0',[]),('F0',['']),
                           ('F0',['unknown']),('F0',['contracts','contracts'])]:
            with self.assertRaises(ValueError): selection(name,tests)

    def test_cli_routes_single_functional_seed_and_preserves_p00(self):
        from run import main
        from evidence import Case
        def fake(run,args):
            self.assertEqual((args.profile,args.seed),('E0',[23]))
            Case(run,'registered-contracts',23).finish('PASS')
        # This is orchestration qualification, not evidence for hardware tools.
        with tempfile.TemporaryDirectory() as folder:
            with patch('doctor.qualify'), patch('contracts.contracts',side_effect=fake) as suite:
                self.assertEqual(main(['regression','--profile','E0','--test','contracts',
                                       '--seed','23','--output',folder]),0)
                suite.assert_called_once()
            for args in [('uvm','--seed','23'),('regression','--test',''),
                         ('regression','--profile','missing'),('regression','--profile',''),
                         ('regression','--test','contracts','--test','contracts'),
                         ('regression','--seed','0'),
                         ('regression','--seed','17','--seed','19')]:
                self.assertNotEqual(main([*args,'--output',folder]),0)


class StorageRoutingTests(unittest.TestCase):
    def test_production_formal_selection_is_nonempty_and_separate(self):
        from argparse import Namespace
        from formal_storage import selection as formal_selection
        specs, selected = formal_selection(Namespace(profile='E0', test=None, seed=None))
        self.assertEqual(set(selected), {'cell','descriptor','fifo2','fifo4','csr','queues','scheduler','queues-independent'})
        for profile_name, tests, seed in [('toolchain',None,None), ('E0',[],None),
                ('E0',['counter'],None), ('E0',['cell','cell'],None), ('E0',['cell'],[17])]:
            with self.assertRaises(ValueError):
                formal_selection(Namespace(profile=profile_name,test=tests,seed=seed))

    def test_routes_production_and_fixture_independently(self):
        from run import main
        from evidence import Case
        def done(run,args):
            Case(run,'executed-selector').finish('PASS')
        with tempfile.TemporaryDirectory() as folder, patch('doctor.qualify'):
            with patch('formal_storage.formal_rtl', side_effect=done) as production, patch('run.formal',side_effect=done) as fixture:
                self.assertEqual(main(['formal-rtl','--test','cell','--output',folder]),0)
                production.assert_called_once(); fixture.assert_not_called()
                self.assertEqual(main(['formal-smoke','--output',folder]),0)
                fixture.assert_called_once()
            with patch('storage.pools', side_effect=done) as storage:
                self.assertEqual(main(['regression','--profile','I0','--test','pools','--seed','17','--output',folder]),0)
                storage.assert_called_once()
            with patch('csr.csr', side_effect=done) as registers:
                self.assertEqual(main(['regression','--profile','E0','--test','csr','--seed','17','--output',folder]),0)
                registers.assert_called_once()
            with patch('queues.queues', side_effect=done) as queues:
                self.assertEqual(main(['regression','--profile','E0','--test','queues','--seed','17','--output',folder]),0)
                queues.assert_called_once()
            with patch('queue_dispatch_guard.queue_dispatch_guard', side_effect=done) as dispatch_guard:
                self.assertEqual(main(['regression','--profile','E0','--test','queues-dispatch-guard','--output',folder]),0)
                dispatch_guard.assert_called_once()

if __name__=='__main__': unittest.main()
