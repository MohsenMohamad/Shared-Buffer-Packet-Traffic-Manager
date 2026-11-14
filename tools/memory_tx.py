"""Preparation-only memory/TX modes; never resolve production source lists."""
import json
from pathlib import Path
import sys
from evidence import Case, ROOT, completed, output
from registry import profile, sources, fingerprint


def identity_paths():
    return ['AGENTS.md','docs/spec','docs/implementation/tasks/P05-memory-tx.md',
            'rtl/include','formal/tx','dv/memory_tx','dv/agents/tm_stream_agent.svh',
            'dv/model/tm_monitor_types.svh','dv/env/tm_bench_pkg.sv',
            'tools','tests/toolchain/test_memory_tx_preparation.py','verification/profiles.json','verification/suites.json',
            'verification/sources/memory-tx-preparation.json']


def parameters(args):
    p=profile(args.profile)
    return dict(latency=p['MEM_RD_LATENCY'],depth=p['TX_FIFO_DEPTH'],cell_bytes=p['CELL_BYTES'],
                cells=p['N_CELL'],descriptors=p['N_DESC'],max_length=p['MAX_PACKET_BYTES'],
                queues=p['N_Q'],sources=p['N_RX'])


def memory_tx_oracle(run,args):
    seed=(args.seed or [17])[0]
    run.scope='Independent memory/TX preparation; production/performance/formal/DUT coverage NOT_RUN'
    case=Case(run,'memory-tx-oracle',seed)
    p=parameters(args);case.data.update(parameters=p,source_set='memory-tx-preparation')
    config=case.path/'profile.json';config.write_text(json.dumps(p))
    step=case.execute([sys.executable,ROOT/'dv/memory_tx/qualification.py',
                       '--profile-json',config,'--seed',str(seed),'--output',case.path],timeout=args.timeout)
    result,reason=completed(step,'TM_MEMORY_TX_ORACLE_PASS')
    if result=='PASS':
        case.data['qualification']=json.loads((case.path/'qualification.json').read_text())
        case.data['artifacts'].update(samples=str(case.path/'samples.jsonl'),qualification=str(case.path/'qualification.json'))
    case.finish(result,reason)
    if result=='PASS' and args.profile=='E0' and seed==17:
        parameter_probes(run,args)
        model_mutations(run,args,config,seed)
        preparation_checks(run,args)


def memory_tx_bench(run,args):
    from memory_tx_bench import bench
    bench(run,args)


def memory_tx_dut(run,args):
    from memory_tx_dut import memory_tx_dut as execute_candidate
    execute_candidate(run,args)


def parameter_probes(run,args):
    """Both pinned frontends reject the public unsupported-configuration sentinel."""
    from frontend import read_sources
    source=ROOT/'dv/memory_tx/parameters.sv'
    include=ROOT/'rtl/include'
    for frontend in ('verilator','slang'):
        case=Case(run,'memory-tx-parameters-'+frontend)
        observations=[]
        for name,params in [('valid',{}),('latency',{'MEM_RD_LATENCY':3}),
                            ('depth',{'MEM_RD_LATENCY':2,'TX_FIFO_DEPTH':3}),
                            ('cell',{'CELL_BYTES':8}),('length',{'MAX_PACKET_BYTES':1537}),
                            ('width',{'CELL_COUNT_W':1})]:
            if frontend=='verilator':
                command=['verilator','--lint-only','--top-module','memory_tx_parameters','-I'+str(include),str(source)]
                command += ['-G'+key+'='+str(value) for key,value in params.items()]
            else:
                script=case.path/(name+'.ys')
                script.write_text(read_sources([source],'memory_tx_parameters',includes=[include],params=params)+'hierarchy -check -top memory_tx_parameters\n')
                command=['yosys','-s',str(script)]
            step=case.execute(command,timeout=args.timeout,stem=name)
            valid=step['returncode']==0 if name=='valid' else step['result']!='TIMEOUT' and step['returncode'] not in (0,None) and 'TM_INVALID_CONFIGURATION' in output(step)
            observations.append(dict(name=name,qualified=valid,expected='ACCEPT' if name=='valid' else 'PARAMETER_REJECTION'))
        ok=all(row['qualified'] for row in observations)
        case.finish('PASS' if ok else 'FAIL',None if ok else 'Public parameter acceptance/rejection did not qualify',observations=observations,
                    source_set='public-parameter-probe',parameters='tm_parameters.svh defaults with named invalid overrides')


def model_mutations(run,args,config,seed):
    """Intentional model faults are isolated copies and must fail their own self-test."""
    import shutil
    import tempfile
    targets={'response_presence':'missing_response','response_data':'wrong_response',
             'output_data':'wrong_output_data','output_keep':'wrong_output_keep',
             'cell_completion_presence':'missing_cell_return','descriptor_completion_presence':'missing_done',
             'link_capture':'missing_link_capture','read_credit':'overissue'}
    for detector,test in targets.items():
        case=Case(run,'memory-tx-remove-'+detector,seed)
        directory=case.path/'isolated-model';shutil.copytree(ROOT/'dv/memory_tx',directory,ignore=shutil.ignore_patterns('__pycache__'))
        oracle=directory/'oracle.py';text=oracle.read_text()
        text=text.replace('self.disabled = frozenset(disabled)',f'self.disabled = frozenset(disabled) | {{{detector!r}}}')
        oracle.write_text(text)
        step=case.execute([sys.executable,directory/'qualification.py','--profile-json',config,'--seed',str(seed),'--output',case.path/'result'],timeout=args.timeout)
        marker='selftest_missing_detection: '+test
        ok=step['result']!='TIMEOUT' and step['returncode'] not in (0,None) and marker in output(step)
        case.finish('PASS' if ok else 'FAIL',None if ok else 'Detector removal did not fail its intended self-test',
                    expected='MODEL_DETECTOR_REMOVAL',detector=detector,selftest=test)
    for name,old,new,detector in [('credit','self.U += 1','self.U += 2','resource_equations'),
                                  ('buffer','self.buffered.append(due)','self.buffered.extend([due,due])','buffer_delta')]:
        case=Case(run,'memory-tx-wrong-model-delta-'+name,seed)
        directory=case.path/'isolated-model';shutil.copytree(ROOT/'dv/memory_tx',directory,ignore=shutil.ignore_patterns('__pycache__'))
        oracle=directory/'oracle.py';text=oracle.read_text()
        if old not in text:case.finish('FAIL','Missing intended model mutation anchor');continue
        oracle.write_text(text.replace(old,new))
        step=case.execute([sys.executable,directory/'qualification.py','--profile-json',config,'--seed',str(seed),'--output',case.path/'result'],timeout=args.timeout)
        import re
        diagnostics=re.findall(r'oracle\.Violation: ([a-z_]+):',output(step))
        ok=step['result']!='TIMEOUT' and step['returncode'] not in (0,None) and diagnostics==[detector]
        case.finish('PASS' if ok else 'FAIL',None if ok else 'Wrong model delta did not hit intended independent self-test',
                    expected='WRONG_MODEL_DELTA',detector=detector,observed_detectors=diagnostics)


def preparation_checks(run,args):
    checks=[('boundaries',[sys.executable,'-m','unittest','discover','-s','tests/toolchain','-p','test_memory_tx_preparation.py','-v']),
            ('syntax',[sys.executable,'-c',"import sys;sys.path.insert(0,'tools');import check_light;check_light.syntax()"]),
            ('repository',[sys.executable,'tools/check_repository.py'])]
    for name,command in checks:
        case=Case(run,'memory-tx-preparation-'+name)
        step=case.execute(command,timeout=args.timeout)
        case.finish(step['result'],step['first_failure'],scope='Preparation boundary and tool-independent checks only')
