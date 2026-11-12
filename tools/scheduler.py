"""Production scheduler regression with existing UVM packet policy components."""
import json
import os
from pathlib import Path
import re
from evidence import Case, ROOT, IGNORED, output, sha
from registry import profile, sources, fingerprint
from foundation import run_result


def scheduler(run, args):
    params = profile(args.profile)
    registered = sources('scheduler')
    seed = (args.seed or [17])[0]
    for mode in (1, 0):
        build = Case(run, f'scheduler-mode{mode}-build', seed)
        parameters = dict(params, SCHED_MODE=mode)
        parameters.update(CELL_ID_W=max(1,(params['N_CELL']-1).bit_length()),
                          CELL_COUNT_W=params['N_CELL'].bit_length(),
                          DESC_ID_W=max(1,(params['N_DESC']-1).bit_length()),
                          DESC_COUNT_W=params['N_DESC'].bit_length(),
                          DEFICIT_W=(4096+params['MAX_PACKET_BYTES']-1).bit_length())
        build.data.update(parameters=parameters, source_set='scheduler', registered_source_digests=fingerprint('scheduler'))
        config = build.path/'tm_bench_config.svh'
        config.write_text(''.join(f'parameter int {k}={v};\n' for k,v in parameters.items()))
        uvm = Path(os.environ['UVM_HOME'])/'src'
        binary = build.path/'obj/Vtm_scheduler_top'
        argv = ['verilator', '--binary', '--timing', '--assert', '--coverage', '--trace-vcd',
                '--timescale', '1ns/1ps', '+define+UVM_NO_DPI', '--build-jobs', str(args.jobs),
                '--output-groups', '4', '--output-split', '20000', '--output-split-cfuncs', '500',
                '-CFLAGS', '-O0', '-I'+str(uvm), '-I'+str(build.path)]
        argv += ['-I'+str(ROOT/p) for p in registered['include_dirs']]
        argv += [str(uvm/'uvm_pkg.sv')] + [str(ROOT/p) for p in registered['sources']]
        argv += ['--top-module', 'tm_scheduler_top', '--Mdir', str(binary.parent)]
        step = build.execute(argv, timeout=args.build_timeout)
        result, why = step['result'], step['first_failure']
        if IGNORED.search(output(step)):
            result, why = 'UNSUPPORTED', 'Required construct ignored'
        if result=='PASS' and not binary.is_file():
            result, why = 'TOOL_ERROR', 'Missing executable'
        build.finish(result, why)
        case = Case(run, f'scheduler-mode{mode}', seed)
        case.data.update(parameters=parameters, source_set='scheduler')
        if result!='PASS':
            case.finish('NOT_RUN', 'Build did not qualify')
            continue
        command = [str(binary), f'+verilator+seed+{seed}', '+UVM_NO_RELNOTES']
        step = case.execute(command, timeout=args.timeout, cwd=case.path)
        status, reason = run_result(step, f'TM_SCHEDULER_PASS mode={mode}')
        if status=='PASS':
            metrics = re.search(r'TM_SCHEDULER_PASS (.*)', output(step))
            case.data['metrics'] = {k:int(v) for k,v in re.findall(r'(\w+)=(\d+)', metrics[1])}
            coverage = case.path/'coverage.dat'
            if not coverage.is_file() or not coverage.stat().st_size:
                status, reason = 'FAIL', 'Missing saved coverage'
            else:
                case.data['artifacts']['coverage'] = str(coverage)
                report = case.execute(['verilator_coverage','--report','summary',str(coverage)],timeout=args.timeout)
                if report['result']!='PASS':
                    status, reason = report['result'], 'Coverage report failed'
        if status!='PASS' and step['result']!='TIMEOUT':
            rerun=case.path/'failing-rerun'; rerun.mkdir()
            case.execute(command+['+TRACE'],timeout=args.timeout,cwd=rerun)
            case.data['artifacts']['waveform']=str(rerun/'wave.vcd')
        case.finish(status, reason)
