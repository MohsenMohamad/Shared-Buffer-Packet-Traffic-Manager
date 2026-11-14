"""Execute exact-source production RAM/metadata/TX; never substitute replay PASS."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from evidence import Case, ROOT, completed, output, sha, IGNORED
from registry import profile, sources, fingerprint


RTL_PATHS = ['rtl/include/tm_fixed.sv','rtl/queue/tm_desc_links.sv',
             'rtl/memory/tm_packet_ram.sv','rtl/memory/tm_metadata.sv','rtl/tx/tm_tx.sv']
HEADERS = ['rtl/include/tm_parameters.svh','rtl/include/tm_types.svh','rtl/include/tm_validate.svh']


def candidate_identity(revision):
    revision = subprocess.check_output(['git','rev-parse','--verify',revision+'^{commit}'],cwd=ROOT,text=True).strip()
    digests = {}
    for path in RTL_PATHS+HEADERS:
        expected = subprocess.check_output(['git','show',revision+':'+path],cwd=ROOT)
        digest = hashlib.sha256(expected).hexdigest()
        if not (ROOT/path).is_file() or sha(ROOT/path) != digest:
            raise ValueError('Selected candidate source differs from combined worktree: '+path)
        digests[path] = digest
    return dict(rtl_revision=revision,rtl_source_digests=digests,
                combined_revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                combined_tree=subprocess.check_output(['git','rev-parse','HEAD^{tree}'],cwd=ROOT,text=True).strip())


def memory_tx_dut(run,args):
    revision = getattr(args,'candidate_revision',None)
    if not revision:
        Case(run,'memory-tx-candidate-selection').finish('NOT_RUN','Explicit --candidate-revision is required; no DUT executed')
        return
    identity = candidate_identity(revision)
    registered = sources('memory-tx')
    run.scope = 'Exact candidate production RAM/metadata/TX against frozen observed-write oracle; independent from replay qualification'
    seed = (args.seed or [17])[0]
    seeds = [seed,(seed+14-1)%(2**31-1)+1,(seed+36-1)%(2**31-1)+1,seed]
    public = dict(**identity,profile=args.profile,seed_schedule=seeds,configurations=[])
    for latency in (getattr(args,'memory_latency',None) or [1,2]):
        for depth in (getattr(args,'tx_depth',None) or [4,8]):
            params = profile(args.profile)
            params.update(MEM_RD_LATENCY=latency,TX_FIFO_DEPTH=depth)
            case = Case(run,f'memory-tx-build-L{latency}-D{depth}')
            case.data.update(parameters=params,source_set='memory-tx',candidate=identity,
                             registered_source_digests=fingerprint('memory-tx'))
            binary = case.path/'obj/Vmemory_tx_dut_top'
            command = ['verilator','--cc','--exe','--build','--assert','--coverage','--top-module','memory_tx_dut_top',
                       '--build-jobs',str(args.jobs),'--Mdir',str(binary.parent),'-CFLAGS','-O0']
            command += ['-I'+str(ROOT/p) for p in registered['include_dirs']]
            command += ['-G'+k+'='+str(v) for k,v in params.items()]
            command += [str(ROOT/p) for p in registered['sources']]+[str(ROOT/'dv/memory_tx/dut_server.cpp')]
            step = case.execute(command,timeout=args.build_timeout)
            result, reason = step['result'],step['first_failure']
            if IGNORED.search(output(step)): result,reason='UNSUPPORTED','Required HDL construct ignored'
            if result=='PASS' and not binary.is_file(): result,reason='TOOL_ERROR','Missing DUT executable'
            case.finish(result,reason)
            config = dict(latency=latency,depth=depth,cell_bytes=params['CELL_BYTES'],cells=params['N_CELL'],
                          descriptors=params['N_DESC'],max_length=params['MAX_PACKET_BYTES'],queues=params['N_Q'],sources=params['N_RX'])
            config_report = dict(configuration=config,build_result=result,runs=[])
            public['configurations'].append(config_report)
            if result != 'PASS': continue
            signatures = []
            for index,value in enumerate(seeds):
                case = Case(run,f'memory-tx-L{latency}-D{depth}-seed{value}-run{index}',value)
                case.data.update(parameters=config,source_set='memory-tx',candidate=identity,
                                 build_manifest=str(binary.parent.parent/'manifest.json'),binary_sha256=sha(binary))
                path = case.path/'profile.json';path.write_text(json.dumps(config))
                step = case.execute([sys.executable,ROOT/'dv/memory_tx/dut.py','--binary',binary,
                                     '--profile-json',path,'--seed',str(value),'--output',case.path],timeout=args.timeout)
                result,reason = completed(step,'TM_MEMORY_TX_DUT_PASS')
                row = dict(seed=value,replay=index==3,result=result)
                if (case.path/'violation.json').is_file():
                    row['contract_violation']=json.loads((case.path/'violation.json').read_text())
                    if step['result']!='TIMEOUT' and row['contract_violation'].get('server_returncode')==0:
                        result,reason='FAIL',row['contract_violation'].get('detail',row['contract_violation']['detector'])
                        row['result']=result
                if result=='PASS':
                    report = json.loads((case.path/'result.json').read_text())
                    case.data['observed_qualification']=report
                    row.update(counts=report['counts'],observed_bins=report['bins'],dut_bins=report['dut_bins'],
                               reset_crosses=report['reset_crosses'],sample_sha256=report['sample_sha256'])
                    signatures.append(report['sample_sha256'])
                config_report['runs'].append(row)
                case.data['artifacts'].update(public_stimulus=str(case.path/'stimulus.txt'),samples=str(case.path/'samples.jsonl'),
                                              coverage=str(case.path/'coverage.dat'),result=str(case.path/'result.json'))
                case.finish(result,reason)
            case = Case(run,f'memory-tx-L{latency}-D{depth}-seed-replay',seed)
            ok = len(signatures)==4 and signatures[0]==signatures[3] and len(set(signatures[:3]))==3
            case.finish('PASS' if ok else 'FAIL',None if ok else 'Missing, nonrepeatable or seed-independent production samples',sample_sha256=signatures)
    if args.profile=='E0' and any(c['configuration']['latency']==2 and c['configuration']['depth']==4 for c in public['configurations']):
        simulation_mutations(run,args,identity,seed)
    public['detector_qualification'] = [dict(test=c.data['test'],result=c.data.get('result'),expected=c.data.get('expected'),intended_detector=c.data.get('intended_detector'),observed_violation=c.data.get('observed_violation')) for c in run.cases if 'source-fault-' in c.data['test']]
    public['result'] = 'PASS' if public['configurations'] and all(c['build_result']=='PASS' and len(c['runs'])==4 and
                         all(r['result']=='PASS' for r in c['runs']) for c in public['configurations']) and all(c.data.get('result')=='PASS' for c in run.cases) else 'FAIL'
    (run.path/'candidate-public.json').write_text(json.dumps(public,indent=2)+'\n')
    print('P05_CANDIDATE_RESULT '+json.dumps(dict(result=public['result'],rtl_revision=identity['rtl_revision'],
                                               profile=args.profile,report=str(run.path/'candidate-public.json'))),flush=True)


def simulation_mutations(run,args,identity,seed):
    from formal_tx import MUTATIONS, mutate
    config=dict(latency=2,depth=4,cell_bytes=16,cells=16,descriptors=8,max_length=128,queues=2,sources=1)
    params=profile('E0');params.update(MEM_RD_LATENCY=2,TX_FIFO_DEPTH=4)
    detectors={'outstanding-credit':'read_credit','premature-return':'cell_completion_presence','stale-validity':'reset_output'}
    for name in ['legal-neighbor']+list(MUTATIONS):
        case=Case(run,'memory-tx-source-fault-'+name,seed)
        case.data.update(parameters=config,candidate=identity,source_set='memory-tx',
                         expected='LEGAL_NEIGHBOR' if name=='legal-neighbor' else 'SEEDED_DEFECT_DETECTION')
        paths=[]
        for path in sources('memory-tx')['sources']:
            source=ROOT/path
            if path=='rtl/tx/tm_tx.sv' and name!='legal-neighbor':
                original=source.read_text();source=case.path/'tm_tx.sv'
                source.write_text(mutate(original,name));case.data['mutant_sha256']=sha(source)
            paths.append(str(source))
        binary=case.path/'obj/Vmemory_tx_dut_top'
        argv=['verilator','--cc','--exe','--build','--assert','--coverage','+define+SYNTHESIS',
              '--top-module','memory_tx_dut_top','--build-jobs',str(args.jobs),'--Mdir',str(binary.parent),
              '-CFLAGS','-O0','-I'+str(ROOT/'rtl/include'),'-I'+str(ROOT/'dv/memory_tx')]
        argv+=['-G'+k+'='+str(v) for k,v in params.items()]+paths+[str(ROOT/'dv/memory_tx/dut_server.cpp')]
        step=case.execute(argv,timeout=args.build_timeout)
        if step['result']!='PASS':
            case.finish(step['result'],step['first_failure']);continue
        path=case.path/'profile.json';path.write_text(json.dumps(config))
        step=case.execute([sys.executable,ROOT/'dv/memory_tx/dut.py','--binary',binary,'--profile-json',path,
                           '--seed',str(seed),'--output',case.path,'--tx-only'],timeout=args.timeout)
        if name=='legal-neighbor': result,reason=completed(step,'TM_MEMORY_TX_DUT_PASS')
        else:
            violation=json.loads((case.path/'violation.json').read_text()) if (case.path/'violation.json').is_file() else {}
            detector=detectors[name]
            ok=step['result']!='TIMEOUT' and step['returncode']==1 and violation.get('detector')==detector and violation.get('server_returncode')==0
            result,reason=('PASS',None) if ok else ('FAIL','Source fault did not hit intended independent '+detector+' detector without a server crash')
            case.data.update(intended_detector=detector,observed_violation=violation)
        case.data['artifacts'].update(stimulus=str(case.path/'stimulus.txt'),samples=str(case.path/'samples.jsonl'))
        case.finish(result,reason)
