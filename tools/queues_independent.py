"""Independent passive queue API/ownership qualification on merged production RTL."""
import json
from pathlib import Path
from evidence import Case, ROOT, completed, output, sha
from registry import profile, sources, fingerprint


def queues_independent(run, args):
    params = profile(args.profile)
    # A second legal width configuration exercises unused ID encodings/guarded widths.
    for widths in ('native', 'wide', 'empty'):
        case = Case(run, 'queues-independent-'+widths, (args.seed or [17])[0])
        registered = sources('queues-independent')
        selected = dict(params)
        if widths == 'wide':
            selected.update(DESC_ID_W=(params['N_DESC']-1).bit_length()+1,
                            DESC_COUNT_W=params['N_DESC'].bit_length()+1)
        case.data.update(parameters=selected, source_set='queues-independent',
                         registered_source_digests=fingerprint('queues-independent'),
                         scope='Independent passive API FIFO/descriptor ownership; real queue/link/pool RTL, no payload/TX implementation')
        top = 'queues_empty_tb' if widths=='empty' else 'queues_independent_tb'
        binary = case.path/('obj/V'+top)
        argv = ['verilator', '--binary', '--timing', '--assert', '--coverage', '--trace-vcd',
                '--timescale', '1ns/1ps', '--build-jobs', str(args.jobs), '--top-module',
                top, '--Mdir', str(binary.parent)]
        argv += ['-I'+str(ROOT/p) for p in registered['include_dirs']]
        argv += [f'-G{k}={v}' for k,v in selected.items()]
        argv += [str(ROOT/'dv/unit/queues_independent.vlt')]
        argv += [str(ROOT/p) for p in registered['sources']]
        build = case.execute(argv, timeout=args.build_timeout)
        result, why = completed(build, '')
        if result != 'PASS' or not binary.is_file():
            case.finish(result if result != 'PASS' else 'TOOL_ERROR', why or 'Missing executable')
            continue
        command = [str(binary), '+SEED='+str(case.data['seed'])]
        step = case.execute(command, timeout=args.timeout, cwd=case.path)
        result, why = completed(step, 'TM_QUEUE_DV_EMPTY_PASS' if widths=='empty' else 'TM_QUEUE_DV_PASS')
        if 'QUEUE_DV_' in output(step) and result != 'PASS' and step['result'] != 'TIMEOUT':
            result, why = 'FAIL', 'Independent API monitor failed'
        if widths=='empty':
            case.finish(result, why)
            continue
        if result == 'PASS':
            coverage = case.path/'queue-coverage.json'
            data = json.loads(coverage.read_text())
            mandatory = [b for b in data['bins'] if not (b['pre_count']==0 and b['event'] in (1,3))]
            if len(mandatory) != params['N_Q']*10 or any(b['hits']<=0 for b in mandatory):
                result, why = 'FAIL', 'Missing mandatory transition bin'
            case.data['coverage'] = data
            report = case.execute(['verilator_coverage', '--report', 'summary', str(case.path/'coverage.dat')], timeout=args.timeout)
            if report['result'] != 'PASS':
                result, why = report['result'], report['first_failure']
        else:
            rerun = case.execute(command+['+TRACE'], timeout=args.timeout, cwd=case.path)
            case.data['artifacts']['rerun'] = rerun
        case.data['artifacts'].update(coverage=str(case.path/'coverage.dat'),
                                     functional_coverage=str(case.path/'queue-coverage.json'),
                                     events=str(case.path/'api-events.jsonl'))
        for name in ('coverage', 'functional_coverage'):
            path=case.data['artifacts'].get(name)
            if path and Path(path).is_file():
                case.data['artifacts'][name+'_sha256']=sha(path)
        case.finish(result, why)
