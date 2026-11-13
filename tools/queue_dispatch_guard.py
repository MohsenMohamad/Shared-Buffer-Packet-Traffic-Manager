"""Production wrong-descriptor diagnostics, isolated from legal-operation DV."""
import json
from pathlib import Path
import re
from evidence import Case, ROOT, IGNORED, completed, output, sha
from registry import profile, sources, fingerprint

DETECTOR = 'QUEUE_DV_WRONG_DESC_ERROR'
MUTATION_SITE = 'dispatch.desc==heads[dispatch.qid*DESC_ID_W +: DESC_ID_W]'


def mutation_outcome(step, text, wave):
    if step['result']=='TIMEOUT':
        return 'TIMEOUT', step['first_failure']
    if IGNORED.search(text):
        return 'UNSUPPORTED', 'Required construct ignored'
    named_failure = any('Assertion failed' in line and re.search(r'\b'+re.escape(DETECTOR)+r'\b', line)
                        for line in text.splitlines())
    detected = (step['returncode'] not in (None,0) and named_failure and
                'QUEUE_DV_WRONG_DESC_INJECT' in text and wave.is_file() and wave.stat().st_size>0)
    return ('PASS',None) if detected else ('FAIL','Missing intended '+DETECTOR+' assertion and trace')


def inspect_coverage(path, queues):
    data=json.loads(path.read_text())
    bins=data['bins']
    expected={(q,d,k,p) for q in range(queues) for d in range(2) for k in range(3) for p in range(3)}
    keys={(b['qid'],b['depth'],b['wrong_kind'],b['publication']) for b in bins}
    if len(bins)!=len(expected) or keys!=expected:
        raise ValueError('Missing or duplicate dispatch-guard coverage bins')
    for b in bins:
        wanted=0 if b['depth']==0 and b['wrong_kind']==2 else 1
        if b['hits']!=wanted:
            raise ValueError('Required rejection scenario missing or impossible case hit')
    if data['rejected']!=15*queues or data['sticky_checks']!=30*queues or data['resets']!=30*queues:
        raise ValueError('Wrong-descriptor/sticky/reset counters incomplete')
    return data


def queue_dispatch_guard(run, args):
    registered=sources('queues-dispatch-guard')
    modes=('native','wide','mutation') if args.profile=='E0' else ('native','wide')
    for mode in modes:
        case=Case(run,'queues-dispatch-guard-'+mode)
        parameters=profile(args.profile)
        if mode=='wide':
            parameters.update(DESC_ID_W=(parameters['N_DESC']-1).bit_length()+1,
                              DESC_COUNT_W=parameters['N_DESC'].bit_length()+1)
        case.data.update(parameters=parameters,source_set='queues-dispatch-guard',
                         registered_source_digests=fingerprint('queues-dispatch-guard'),
                         stimulus='Directed deterministic API events; seed-independent',
                         scope='Wrong in-range descriptor on nonempty production queue; sticky error, rejected dequeue, independent publication, links and reset. No scheduler or integrated ownership qualification.')
        paths=[]
        for path in registered['sources']:
            source=ROOT/path
            if mode=='mutation' and path=='rtl/queue/tm_queue_ctrl.sv':
                text=source.read_text()
                if text.count(MUTATION_SITE)!=1:
                    raise ValueError('Descriptor-match mutation site missing or ambiguous')
                mutant=case.path/source.name
                mutant.write_text(text.replace(MUTATION_SITE,"1'b1"))
                source=mutant
                case.data.update(mutation='Remove dispatch descriptor-match guard',
                                 intended_detector=DETECTOR,mutant_sha256=sha(mutant))
                case.data['artifacts']['mutant']=str(mutant)
            paths.append(str(source))
        binary=case.path/'obj/Vqueues_dispatch_guard_tb'
        argv=['verilator','--binary','--timing','--assert','--coverage','--trace-vcd',
              '--timescale','1ns/1ps','--build-jobs',str(args.jobs),'--top-module',
              'queues_dispatch_guard_tb','--Mdir',str(binary.parent)]
        argv+=['-I'+str(ROOT/p) for p in registered['include_dirs']]
        argv+=[f'-G{k}={v}' for k,v in parameters.items()]
        argv+=[str(ROOT/'dv/unit/queues_independent.vlt'),*paths]
        build=case.execute(argv,timeout=args.build_timeout)
        result,reason=completed(build,'')
        if result!='PASS' or not binary.is_file():
            case.finish(result if result!='PASS' else 'TOOL_ERROR',reason or 'Missing executable')
            continue
        command=[str(binary)]+(['+TRACE'] if mode=='mutation' else [])
        step=case.execute(command,timeout=args.timeout,cwd=case.path)
        wave=case.path/'wave.vcd'
        if mode=='mutation':
            result,reason=mutation_outcome(step,output(step),wave)
            case.data['artifacts']['counterexample']=str(wave)
            case.finish(result,reason,expected='INTENDED_WRONG_DESCRIPTOR_COUNTEREXAMPLE',
                        observed_detector=DETECTOR if result=='PASS' else None)
            continue
        result,reason=completed(step,'TM_QUEUE_DISPATCH_GUARD_PASS')
        if step['result']!='TIMEOUT' and re.search(r'Assertion failed.*QUEUE_DV_',output(step)):
            result,reason='FAIL','Production queue dispatch diagnostic failed'
        if result=='PASS':
            try:
                case.data['coverage']=inspect_coverage(case.path/'dispatch-guard-coverage.json',parameters['N_Q'])
            except (OSError,ValueError,KeyError) as error:
                result,reason='FAIL',str(error)
        if result!='PASS' and step['result']!='TIMEOUT':
            case.execute(command+['+TRACE'],timeout=args.timeout,cwd=case.path)
            case.data['artifacts']['counterexample']=str(wave)
        for name in ('dispatch-guard-coverage.json','coverage.dat'):
            artifact=case.path/name
            if artifact.is_file():
                case.data['artifacts'][name]=dict(path=str(artifact),sha256=sha(artifact))
        case.finish(result,reason)
