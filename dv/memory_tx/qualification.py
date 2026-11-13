"""Model qualification and labeled trace fault checks, independent of RTL."""
import argparse
from collections import Counter
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
from oracle import Oracle, Profile, Violation, require
from traces import legal_trace, reset_traces, atomic_overlap_trace, reused_link_trace
from ledger import Ledger
from sweep import sweep
from hand_checks import qualify_hand, metamorphic


BASELINE_BINS=['exact_full','full_stall','full_arrival','full_exchange','atomic_commit',
              'cell_final_hold','packet_final_hold','link_query','complete']+[f'keep_{i}' for i in range(1,9)]

def baseline_bins(profile):
    return BASELINE_BINS+['maximum_descriptor']+[f'source_{p}' for p in range(profile.sources)]+[f'qid_{q}' for q in range(profile.queues)]


def replay(samples, profile, required=(), disabled=(), finish=True):
    oracle=Oracle(profile,disabled)
    ledger=Ledger(profile)
    for sample in samples:
        oracle.step(sample)
        if not disabled:ledger.observe(sample,oracle)
    return oracle.finish(required) if finish else oracle


def qualify(profile, seed):
    samples=legal_trace(profile,seed)
    required=baseline_bins(profile)
    report=replay(samples,profile,required)
    report['trace_sha256']=hashlib.sha256(json.dumps(samples,sort_keys=True).encode()).hexdigest()
    resets={name:replay(trace,profile,['reset','complete']) for name,trace in reset_traces(profile,seed).items()}
    report['hand_witnesses']=qualify_hand(replay)
    report['bounded_sweep']=sweep(profile,replay,seed)
    report['metamorphic']=metamorphic(samples,profile,replay)
    report['reset_phases']=resets
    report['atomic_overlap']=replay(atomic_overlap_trace(profile,seed),profile,['atomic_store_retire'])
    negatives={}
    def negative(name, detector, mutate, *, finish=False):
        trace=deepcopy(samples); end=mutate(trace)
        trace=trace if end is None else trace[:end+1]
        try: replay(trace,profile,finish=finish)
        except Violation as error:
            require(error.detector==detector,'selftest_wrong_detector',f'{name}: {error}')
        else: raise AssertionError('selftest_missing_detection: '+name)
        # Removal must be killed by this self-test, before a later unrelated alarm.
        if end is not None:
            try: replay(trace,profile,disabled=[detector],finish=False)
            except Violation as error:raise AssertionError('selftest_removal_wrong_alarm: '+name+': '+str(error)) from error
            negatives[name]={'detector':detector,'detector_removal':'KILLED_BY_'+name}
        else: negatives[name]={'detector':detector}
    def edit_first(predicate, change):
        def mutate(trace):
            for i,s in enumerate(trace):
                if predicate(s): change(s);return i
            raise AssertionError('missing fault trigger')
        return mutate
    has=lambda key:lambda s:key in s['actions']
    action=lambda key:lambda s:s['actions'].pop(key)
    for key,detector in [('info','metadata_info'),('commit_info','metadata_commit'),('dispatch_info','metadata_dispatch')]:
        negative('wrong_'+key,detector,edit_first(has(key),lambda s,k=key:s['actions'][k].update(tag=s['actions'][k]['tag']^1)))
    negative('missing_info_write','metadata_info_presence',edit_first(lambda s:'info' in s['actions'] and 'commit' not in s['actions'],action('info')))
    negative('missing_response','response_presence',edit_first(has('response'),action('response')))
    negative('wrong_response','response_data',edit_first(has('response'),lambda s:s['actions']['response'].update(data=s['actions']['response']['data']^1)))
    negative('extra_response','response_presence',edit_first(lambda s:not s['reset'] and s['cycle']>3 and not s['actions'],lambda s:s['actions'].update(response={'data':0})))
    for key,detector in [('keep','output_keep'),('last','output_last'),('user','output_user'),('data','output_data')]:
        def mutate_output(trace,key=key):
            for i,s in enumerate(trace):
                if s['out']['valid'] and s['out']['ready'] and not (trace[i-1]['out']['valid'] and not trace[i-1]['out']['ready']):
                    s['out'][key]^=1;return i
            raise AssertionError('no unheld transfer')
        negative('wrong_output_'+key,detector,mutate_output)
    negative('missing_cell_return','cell_completion_presence',edit_first(has('free'),action('free')))
    negative('wrong_cell_return','cell_completion_id',edit_first(has('free'),lambda s:s['actions'].update(free=(s['actions']['free']+1)%profile.cells)))
    negative('missing_done','descriptor_completion_presence',edit_first(has('done'),action('done')))
    negative('wrong_done','descriptor_completion_id',edit_first(has('done'),lambda s:s['actions'].update(done=1)))
    negative('duplicate_done','descriptor_completion_presence',edit_first(lambda s:not s['reset'] and s['cycle']>3 and not s['actions'],lambda s:s['actions'].update(done=0)))
    negative('duplicate_free','cell_completion_presence',edit_first(lambda s:not s['reset'] and s['cycle']>3 and not s['actions'],lambda s:s['actions'].update(free=0)))
    negative('wrong_link','metadata_next',edit_first(has('query'),lambda s:s['actions']['query'].update(next=(s['actions']['query']['next']+1)%profile.cells)))
    # Held fields corrupt on a successor to a genuine held-valid sample.
    def late_response(trace):
        for i,s in enumerate(trace):
            if 'response' in s['actions']:
                response=s['actions'].pop('response');trace[i+1]['actions']['response']=response;return i
        raise AssertionError('no response')
    negative('late_response','response_presence',late_response)
    negative('duplicate_response','response_presence',edit_first(lambda s:not s['reset'] and s['cycle']>3 and not s['actions'],lambda s:s['actions'].update(response={'data':0})))
    negative('early_cell_return','cell_completion_presence',edit_first(lambda s:s['out']['valid'] and not s['out']['ready'],lambda s:s['actions'].update(free=0)))
    def omit_queries(trace):
        for i,s in enumerate(trace):
            s['actions'].pop('query',None)
            if 'free' in s['actions'] and 'done' not in s['actions']:return i
        raise AssertionError('no interior cell retirement')
    negative('missing_link_capture','link_capture',omit_queries)
    def overissue(trace):
        occupied=0
        for i,s in enumerate(trace):
            if s['reset']:occupied=0;continue
            transfer=s['out']['valid'] and s['out']['ready']
            if occupied==profile.depth and not transfer:
                for later in trace[i+1:]:
                    if 'done' in later['actions']:break
                    if 'read' in later['actions']:
                        s['actions']['read']=later['actions']['read'];return i
            occupied+=int('read' in s['actions'])-int(transfer)
        raise AssertionError('no exact-capacity trigger')
    negative('overissue','read_credit',overissue)
    for key in ('valid','data','keep','last','user'):
        def mutate(trace,key=key):
            for i in range(1,len(trace)):
                prev=trace[i-1]['out']
                if prev['valid'] and not prev['ready']:
                    trace[i]['out'][key]^=1;return i
            raise AssertionError('no hold')
        # Other semantic checks would also reject the corruption after removing hold.
        trace=deepcopy(samples);end=mutate(trace)
        try:replay(trace[:end+1],profile,finish=False)
        except Violation as error:require(error.detector=='held_output','selftest_wrong_detector',str(error))
        else:raise AssertionError('missing held detector')
        negatives['held_'+key]={'detector':'held_output'}
    # Missing final transaction cannot quietly pass shutdown.
    end=next(i for i,s in enumerate(samples) if 'done' in s['actions'])
    for name,trace,detector in [('missing_final_output',samples[:end],'shutdown_ownership'),
                               ('missing_completion_leak',samples[:end],'shutdown_ownership')]:
        try:replay(trace,profile)
        except Violation as error:require(error.detector==detector,'selftest_wrong_detector',str(error))
        else:raise AssertionError(name)
        negatives[name]={'detector':detector}
    # Direct equations are separate arithmetic witnesses, not model-state edits.
    equations=[]
    for depth in (4,8):
        for B in range(depth+1):
            for O in range(3):
                for R in (0,1):
                    for I in (0,1):
                        for T in (0,1):
                            if B+O>depth or R>O or T>B:continue
                            post_B=B+R-T;post_O=O+I-R
                            legal=B+O+I-T<=depth
                            require((post_B+post_O<=depth)==legal,'equation_witness')
                            require((post_B+post_O+1<=depth)!=legal or I==0 or T==0 or B+O!=depth,
                                    'wrong_delta_witness')
                            equations.append([depth,B,O,R,I,T,post_B,post_O,legal])
    # Environment rejection is separate from a DUT guarantee detector.
    environment={}
    for name,field,value,detector in [('latency','latency',3,'parameter_latency'),('depth','depth',2,'parameter_depth'),
                                      ('cell','cell_bytes',8,'parameter_cell'),('length','max_length',1537,'parameter_length')]:
        from dataclasses import asdict
        values=asdict(profile);values[field]=value
        try:Profile(**values)
        except Violation as error:require(error.detector==detector,'environment_wrong_detector')
        else:raise AssertionError('unsupported configuration passed')
        environment[name]=detector
    trace=deepcopy(atomic_overlap_trace(profile,seed))
    overlap=next(i for i,s in enumerate(trace) if 'done' in s['actions'] and 'reserve' in s['actions'])
    # Reusing the just-returned cell on the same edge is illegal even though a return occurs.
    trace[overlap]['actions']['allocate']['cell']=trace[overlap]['actions']['free']
    try:replay(trace[:overlap+1],profile,finish=False)
    except Violation as error:require(error.detector=='environment_cell_reuse','environment_wrong_detector',str(error))
    else:raise AssertionError('same-edge reuse accepted')
    environment['same_edge_return_reuse']='environment_cell_reuse'
    short_reset=deepcopy(samples);short_reset.pop(1)
    for i,s in enumerate(short_reset):s['cycle']=i
    try:replay(short_reset,profile)
    except Violation as error:require(error.detector=='environment_reset_width','environment_wrong_detector',str(error))
    else:raise AssertionError('short reset accepted')
    environment['short_reset']='environment_reset_width'
    uninitialized=deepcopy(next(s for s in samples if 'reserve' in s['actions']))
    uninitialized.update(epoch=0,cycle=0)
    try:replay([uninitialized],profile)
    except Violation as error:require(error.detector=='environment_uninitialized','environment_wrong_detector',str(error))
    else:raise AssertionError('work before initialization accepted')
    environment['uninitialized']='environment_uninitialized'
    try:replay([],profile)
    except Violation as error:require(error.detector=='shutdown_initialization','empty_wrong_detector')
    else:raise AssertionError('empty oracle replay passed')
    negatives['empty_trace']={'detector':'shutdown_initialization'}

    for name,edit,detector in [('missing_sample',lambda t:t.pop(5),'sample_cycle'),
                               ('duplicate_sample',lambda t:t.insert(5,deepcopy(t[4])),'sample_cycle'),
                               ('mixed_epoch',lambda t:t[5].update(epoch=t[5]['epoch']+1),'sample_epoch')]:
        trace=deepcopy(samples);edit(trace)
        try:replay(trace,profile)
        except Violation as error:require(error.detector==detector,'sample_wrong_detector',str(error))
        else:raise AssertionError(name)
        negatives[name]={'detector':detector}
    try:replay(samples,profile,['absent_required_trigger'])
    except Violation as error:require(error.detector=='required_bin','required_bin_wrong_detector')
    else:raise AssertionError('unhit required bin passed')
    negatives['absent_required_trigger']={'detector':'required_bin'}

    reused,second_start=reused_link_trace(profile,seed)
    report['link_lifetime_baseline']=replay(reused,profile,['complete','link_query'])
    for sample in reused[second_start:]:sample['actions'].pop('query',None)
    try:replay(reused,profile)
    except Violation as error:require(error.detector=='link_capture','lifetime_wrong_detector',str(error))
    else:raise AssertionError('selftest_missing_detection: reused_link_missing_capture')
    negatives['reused_link_missing_capture']={'detector':'link_capture'}
    report.update(negatives=negatives,environment_rejections=environment,equation_combinations=len(equations))
    return report,samples


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--seed',type=int,default=17)
    parser.add_argument('--profile-json',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    profile=Profile(**json.loads(args.profile_json.read_text()))
    report,samples=qualify(profile,args.seed)
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/'qualification.json').write_text(json.dumps(report,indent=2)+'\n')
    (args.output/'samples.jsonl').write_text(''.join(json.dumps(s)+'\n' for s in samples))
    print('TM_MEMORY_TX_ORACLE_PASS '+report['trace_sha256'])

if __name__=='__main__':main()
