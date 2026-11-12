"""Independent list regression against production queue/link RTL and P02 pool."""
import re
from evidence import Case, ROOT, completed, output
from registry import profile, sources, fingerprint


def queues(run, args):
    case=Case(run, 'queues', (args.seed or [17])[0])
    params=profile(args.profile)
    registered=sources('queues')
    case.data.update(parameters=params, source_set='queues', registered_source_digests=fingerprint('queues'))
    binary=case.path/'obj/Vqueues_tb'
    argv=['verilator','--binary','--timing','--assert','--trace-vcd','--timescale','1ns/1ps',
          '--build-jobs',str(args.jobs),'--top-module','queues_tb','--Mdir',str(binary.parent)]
    argv+=['-I'+str(ROOT/p) for p in registered['include_dirs']]
    argv+=[f'-G{k}={v}' for k,v in params.items()]
    argv+=[str(ROOT/p) for p in registered['sources']]
    build=case.execute(argv,timeout=args.build_timeout)
    if build['result']!='PASS' or not binary.is_file():
        case.finish(build['result'] if build['result']!='PASS' else 'TOOL_ERROR','Queue compilation failed or executable missing')
        return
    command=[str(binary),'+SEED='+str(case.data['seed'])]
    step=case.execute(command,timeout=args.timeout,cwd=case.path)
    result,why=completed(step,'TM_QUEUES_PASS')
    if step['result']!='TIMEOUT' and 'TM_QUEUES_FAIL' in output(step):
        result,why='FAIL','Queue assertion failed'
    metrics=re.search(r'TM_QUEUES_PASS (.*)',output(step))
    if metrics:
        case.data['metrics']={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',metrics[1])}
    if result!='PASS' and step['result']!='TIMEOUT':
        rerun=case.execute(command+['+TRACE'],timeout=args.timeout,cwd=case.path)
        case.data['artifacts'].update(rerun=rerun,waveform=str(case.path/'wave.vcd'))
    case.finish(result,why)
