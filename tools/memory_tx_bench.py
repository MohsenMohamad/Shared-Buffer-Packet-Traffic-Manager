"""Compile and qualify public-action replay with P07 passive UVM monitors."""
from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
from evidence import Case, ROOT, IGNORED, completed, output, sha
from registry import sources, fingerprint, profile
from memory_tx import parameters


def bench(run,args):
    sys.path.insert(0,str(ROOT/'dv/memory_tx'))
    from oracle import Profile, Violation, require
    from qualification import replay, BASELINE_BINS
    from traces import legal_trace, reset_traces, atomic_overlap_trace, reused_link_trace, Trace
    from adapter import write_replay, read_observed
    p=Profile(**parameters(args));seed=(args.seed or [17])[0]
    run.scope='P07/UVM passive-edge memory/TX replay preparation; no DUT execution'
    registered=sources('memory-tx-preparation')
    build=Case(run,'memory-tx-bench-build',seed)
    build.data.update(parameters=parameters(args),source_set='memory-tx-preparation',
                      registered_source_digests=fingerprint('memory-tx-preparation'))
    params=profile(args.profile)
    params.update(CELL_ID_W=max(1,(p.cells-1).bit_length()),CELL_COUNT_W=p.cells.bit_length(),
                  DESC_ID_W=max(1,(p.descriptors-1).bit_length()),DESC_COUNT_W=p.descriptors.bit_length(),
                  DEFICIT_W=(4096+p.max_length-1).bit_length())
    config=build.path/'tm_bench_config.svh'
    config.write_text(''.join(f'parameter int {k}={v};\n' for k,v in params.items()))
    uvm_src=Path(os.environ.get('UVM_HOME',str(ROOT/'.deps/src/uvm')))/'src'
    binary=build.path/'obj/Vmemory_tx_replay_top'
    argv=['verilator','--binary','--timing','--assert','--coverage','--trace-vcd',
          '--timescale','1ns/1ps','+define+UVM_NO_DPI','+define+TM_MEMORY_TX_PREPARATION',
          '--build-jobs',str(args.jobs),'--output-groups','4','--output-split','20000',
          '--output-split-cfuncs','500','-CFLAGS','-O0','-I'+str(uvm_src),'-I'+str(build.path)]
    argv+=['-I'+str(ROOT/path) for path in registered['include_dirs']]
    argv+=[str(uvm_src/'uvm_pkg.sv')]+[str(ROOT/path) for path in registered['sources']]
    argv+=['--top-module','memory_tx_replay_top','--Mdir',str(binary.parent)]
    reuse=getattr(args,'preparation_build_manifest',None)
    if reuse is not None:
        try:
            origin=validate_build_reuse(reuse,build.data,argv,build.path,params)
            binary.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(origin['binary'],binary)
            build.data.update(build_origin='QUALIFIED_COMPILED_BENCH_REUSE',reuse=origin,
                              generated_config_sha256=sha(config),binary_sha256=sha(binary))
            status,reason='PASS',None
        except (OSError,ValueError,KeyError) as error:status,reason='FAIL',str(error)
    else:
        step=build.execute(argv,timeout=args.build_timeout)
        status,reason=step['result'],step['first_failure']
        if IGNORED.search(output(step)):status,reason='UNSUPPORTED','Required SV construct ignored'
        if status=='PASS' and not binary.is_file():status,reason='TOOL_ERROR','Missing replay executable'
        if status=='PASS':build.data.update(binary_sha256=sha(binary),generated_config_sha256=sha(config))
    build.finish(status,reason)
    if status!='PASS':return
    cases=[('legal',legal_trace(p,seed),None,None),('atomic-overlap',atomic_overlap_trace(p,seed),None,None)]
    alternate=[(seed+13)%(2**31-1)+1,(seed+35)%(2**31-1)+1]
    cases += [('random-'+str(value),legal_trace(p,value),None,None) for value in alternate]
    cases += [('replay-'+str(seed),legal_trace(p,seed),None,None)]
    cases += [('reset-'+name,trace,None,None) for name,trace in reset_traces(p,seed).items()]
    baseline=cases[0][1]
    # These are labeled corrupt electrical/action fixtures, never production RTL.
    for fault in ('wrong-response','missing-response','wrong-output','missing-done','missing-free','missing-final'):
        trace=deepcopy(baseline)
        if fault=='missing-final':
            end=next(i for i,s in enumerate(trace) if 'done' in s['actions'])
            trace=trace[:end]
            detector='shutdown_ownership'
        else:
            for i,s in enumerate(trace):
                a=s['actions']
                if fault=='wrong-response' and 'response' in a:
                    a['response']['data']^=1;detector='response_data';break
                if fault=='missing-response' and 'response' in a:
                    del a['response'];detector='response_presence';break
                if fault=='wrong-output' and s['out']['valid'] and s['out']['ready'] and not (trace[i-1]['out']['valid'] and not trace[i-1]['out']['ready']):
                    s['out']['data']^=1;detector='output_data';break
                if fault=='missing-done' and 'done' in a:
                    del a['done'];detector='descriptor_completion_presence';break
                if fault=='missing-free' and 'free' in a:
                    del a['free'];detector='cell_completion_presence';break
        cases.append((fault,trace,None,detector))
    reused,second_start=reused_link_trace(p,seed)
    cases.append(('link-lifetime-legal',deepcopy(reused),None,None))
    for sample in reused[second_start:]:sample['actions'].pop('query',None)
    cases.append(('link-lifetime-missing',reused,None,'link_capture'))
    held=deepcopy(baseline)
    for index in range(1,len(held)):
        previous=held[index-1]['out']
        if previous['valid'] and not previous['ready']:
            held[index]['out']['data']^=1;break
    cases.append(('held-data',held,'HELD_DATA','TM_STREAM_HOLD'))
    idle=Trace(p,seed);idle.reset();idle.edge();idle.edge()
    final_index=next(i for i,s in enumerate(baseline) if 'done' in s['actions'])
    pending_index=next(i for i,s in enumerate(baseline) if 'read' in s['actions'])
    cases += [('absent-trigger',idle.samples,'ABSENT_TRIGGER','MEMORY_REQUIRED_TRIGGER'),
              ('nonempty-end',baseline[:pending_index+1],'NONEMPTY_END','MEMORY_SHUTDOWN'),
              ('missing-final-sample',baseline[:final_index+1],'OMIT_FINAL_ACTION','MEMORY_SAMPLE_MISSING')]
    cases += [('collector-'+name,baseline,flag,detector) for name,flag,detector in
              [('omission','OMIT_ACTION','MEMORY_SAMPLE_MIXED'),
               ('duplicate','DUPLICATE_SAMPLE','MEMORY_SAMPLE_DUPLICATE'),
               ('mixed','MIXED_SAMPLE','MEMORY_SAMPLE_MIXED')]]
    signatures={}
    for name,samples,flag,expected in cases:
        case_seed=int(name.rsplit('-',1)[1]) if name.startswith(('random-','replay-')) else seed
        case=Case(run,'memory-tx-bench-'+name,case_seed)
        case.data.update(parameters=parameters(args),source_set='memory-tx-preparation',
                         expected='LABELED_CORRUPT_REPLAY' if expected else 'LEGAL_REPLAY')
        trace=case.path/'replay.txt';write_replay(trace,samples)
        case.data['artifacts'].update(stimulus=str(trace),observed=str(case.path/'observed.jsonl'))
        command=[str(binary),'+UVM_NO_RELNOTES','+REPLAY='+str(trace),f'+verilator+seed+{case_seed}']
        if expected:command+=['+TRACE']
        if flag:command+=['+'+flag]
        step=case.execute(command,timeout=args.timeout,cwd=case.path)
        text=output(step)
        if flag:
            diagnostics=re.findall(r'UVM_FATAL[^\n]*\[([^]]+)\]',text)
            ok=step['result']!='TIMEOUT' and step['returncode'] not in (0,None) and diagnostics==[expected]
            if expected=='TM_STREAM_HOLD':
                wave=case.path/'wave.vcd'
                ok=step['result']!='TIMEOUT' and step['returncode'] not in (0,None) and 'TM_STREAM_HOLD' in text and 'Assertion failed' in text and not diagnostics and wave.is_file() and wave.stat().st_size>0
                case.data['artifacts']['waveform']=str(wave)
            case.finish('PASS' if ok else 'FAIL',None if ok else 'Intended first collector diagnostic absent',detector=expected,observed_diagnostics=diagnostics)
            continue
        result,why=completed(step,'TM_MEMORY_TX_BENCH_PASS')
        intended_sv={'response_data':'MEMORY_RESPONSE_DATA','response_presence':'MEMORY_RESPONSE_PRESENCE',
                     'shutdown_ownership':'MEMORY_SHUTDOWN'}
        sv_detection=False
        assertion_map={'response_presence':'a_response_due','descriptor_completion_presence':'a_done',
                       'cell_completion_presence':'a_cell_return'}
        assertion_detection=False
        if expected in assertion_map:
            # Only the intended immediate assertion plus a real waveform qualifies.
            named=re.findall(r'Assertion failed in [^\n:]*\.(a_[a-z_]+)',text)
            wave=case.path/'wave.vcd'
            assertion_detection=step['result']!='TIMEOUT' and step['returncode'] not in (0,None) and named==[assertion_map[expected]] and wave.is_file() and wave.stat().st_size>0
            if assertion_detection:
                result,why='PASS',None
                case.data.update(detector=expected,sv_assertion=named[0])
                case.data['artifacts']['waveform']=str(wave)

        if expected in intended_sv:
            diagnostics=re.findall(r'UVM_FATAL[^\n]*\[([^]]+)\]',text)
            sv_detection=step['result']!='TIMEOUT' and step['returncode'] not in (0,None) and diagnostics==[intended_sv[expected]]
            if sv_detection:result,why='PASS',None
        if result=='PASS':
            try:
                observed=read_observed(case.path/'observed.jsonl')
                require(observed==(samples[:len(observed)] if sv_detection or assertion_detection else samples),
                        'bench_transport','missing/changed sampled edge')
                if expected and not assertion_detection:
                    try:replay(observed,p,finish=not sv_detection or expected=='shutdown_ownership')
                    except Violation as error:require(error.detector==expected,'bench_wrong_detector',str(error))
                    else:raise ValueError('Corrupt replay passed independent checker')
                    case.data.update(detector=expected,observed_detector=expected,sv_detection=sv_detection)
                elif not expected:
                    required=BASELINE_BINS if name=='legal' or name.startswith(('random-','replay-')) else ['complete']+(['packet_final_hold'] if name!='atomic-overlap' else ['atomic_store_retire'])
                    case.data['observed_coverage']=replay(observed,p,required)
                    case.data['saved_sv_coverage']=saved_coverage(case.path/'coverage.dat')
                    case.data['artifacts']['coverage']=str(case.path/'coverage.dat')
                    signatures[name]=hashlib.sha256((case.path/'observed.jsonl').read_bytes()).hexdigest()
                case.data['sampled_edges']=len(observed)
            except (OSError,ValueError,AssertionError) as error:result,why='FAIL',str(error)
        case.finish(result,why)

    replay_case=Case(run,'memory-tx-bench-seed-replay',seed)
    names=['legal','replay-'+str(seed)]+['random-'+str(value) for value in alternate]
    ok=all(name in signatures for name in names) and signatures['legal']==signatures['replay-'+str(seed)] and len({signatures[name] for name in ['legal']+names[2:]})==3
    replay_case.finish('PASS' if ok else 'FAIL',None if ok else 'Missing, nonrepeatable or seed-independent sampled trace',
                       sampled_trace_sha256={name:signatures.get(name) for name in names})


def saved_coverage(path):
    bins={};points={}
    for line in path.read_text().splitlines():
        match=re.fullmatch(r"C '(.*)' (\d+)",line)
        if not match:continue
        fields=dict(part.split('\x02',1) for part in match[1].split('\x01') if '\x02' in part)
        if not fields.get('f','').endswith('/dv/memory_tx/replay.sv'):continue
        kind,count=fields.get('t'),int(match[2])
        group=points.setdefault(kind,dict(hit=0,total=0));group['total']+=1;group['hit']+=int(count>0)
        if kind=='covergroup':bins[fields['h']]=count
    if not points.get('line',{}).get('hit') or not points.get('covergroup',{}).get('hit'):
        raise ValueError('Missing saved nonzero bench code/covergroup counters')
    for point in ('issue','response','output_transfer','output_hold','cell_return','descriptor_done'):
        if not any(name.endswith('.'+point+'.auto_1') and count>0 for name,count in bins.items()):
            raise ValueError('Missing observed SV trigger bin: '+point)
    return dict(bench_points=points,functional_bins=bins,scope='Replay bench only; DUT coverage NOT_RUN')


def validate_build_reuse(path,current,argv,current_path,params):
    path=Path(path).resolve();old=json.loads(path.read_text())
    if old.get('result')!='PASS' or old.get('test')!='memory-tx-bench-build' or old.get('source_set')!='memory-tx-preparation':
        raise ValueError('Only an explicit passing preparation build may be reused')
    for key in ('parameters','registered_source_digests','tool_versions','dependency_digests'):
        if old.get(key)!=current.get(key):raise ValueError('Preparation build identity mismatch: '+key)
    steps=old.get('steps',[])
    if len(steps)!=1 or steps[0].get('returncode')!=0:
        raise ValueError('Preparation reuse requires the original successful compiler manifest')
    command=steps[0]['argv']
    normalize=lambda values,directory:[str(value).replace(str(directory),'<BUILD>') for value in values]
    if normalize(command,path.parent)!=normalize(argv,current_path):
        raise ValueError('Preparation compiler command changed')
    config=path.parent/'tm_bench_config.svh'
    expected=''.join(f'parameter int {key}={value};\n' for key,value in params.items())
    if config.read_text()!=expected:raise ValueError('Preparation generated config changed')
    binary=path.parent/'obj/Vmemory_tx_replay_top'
    digest=sha(binary)
    if old.get('binary_sha256') is not None and old['binary_sha256']!=digest:
        raise ValueError('Preparation binary hash changed')
    return dict(manifest=str(path),manifest_sha256=sha(path),binary=str(binary),binary_sha256=digest,
                compiled_source_revision=old['source_revision'],compiled_dirty=old['dirty'],
                validation='Exact registered HDL/package/header, configuration, dependency, compiler argv and tool identities match; Python checking executes current source')
