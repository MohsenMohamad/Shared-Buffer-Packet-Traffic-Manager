"""P02 component execution; independent handshake and ownership models."""
import re
from evidence import Case, ROOT, completed, output
from registry import profile, sources, fingerprint


def pools(run, args):
    for depth in (2, 4):
        case = Case(run, f'pools-depth{depth}', (args.seed or [17])[0])
        params = dict(profile(args.profile), RX_FIFO_DEPTH=depth)
        # Extra encoding bit tests range checks even for power-of-two capacities.
        params.update(CELL_ID_W=params['N_CELL'].bit_length(), DESC_ID_W=params['N_DESC'].bit_length())
        registered = sources('simulation')
        case.data.update(parameters=params, source_set='simulation',
                         registered_source_digests=fingerprint('simulation'))
        binary = case.path / 'obj/Vstorage_tb'
        argv = ['verilator', '--binary', '--timing', '--assert', '--trace-vcd',
                '--timescale', '1ns/1ps', '--build-jobs', str(args.jobs),
                '--top-module', 'storage_tb', '--Mdir', str(binary.parent)]
        argv += ['-I'+str(ROOT/p) for p in registered['include_dirs']]
        argv += [f'-G{k}={v}' for k,v in params.items()]
        argv += [str(ROOT/p) for p in registered['sources']]
        build = case.execute(argv, timeout=args.build_timeout)
        if build['result'] != 'PASS' or not binary.is_file():
            case.finish(build['result'] if build['result']!='PASS' else 'TOOL_ERROR', 'Storage compilation failed or executable missing')
            continue
        command = [str(binary), '+SEED='+str(case.data['seed'])]
        step = case.execute(command, timeout=args.timeout, cwd=case.path)
        result, why = completed(step, 'TM_STORAGE_PASS')
        if step['result']!='TIMEOUT' and step['returncode'] not in (0,None) and 'TM_STORAGE_FAIL' in output(step):
            result, why = 'FAIL', 'Storage assertion failed'
        metrics=re.search(r'TM_STORAGE_PASS (.*)', output(step))
        if metrics:
            case.data['metrics']={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)', metrics[1])}
        if result != 'PASS' and step['result']!='TIMEOUT':
            rerun = case.execute(command+['+TRACE'], timeout=args.timeout, cwd=case.path)
            case.data['artifacts'].update(rerun=rerun, waveform=str(case.path/'wave.vcd'))
        case.finish(result, why)
