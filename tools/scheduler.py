"""Production scheduler regression with existing UVM packet policy components."""
import os
from pathlib import Path
import re
from evidence import Case, ROOT, IGNORED, output, sha
from registry import profile, sources, fingerprint
from foundation import run_result


def scheduler_coverage(path, mode):
    points, bins, holes = {}, {}, []
    for line in path.read_text().splitlines():
        match = re.fullmatch(r"C '(.*)' (\d+)", line)
        if not match:
            continue
        fields = dict(part.split('\x02', 1) for part in match[1].split('\x01') if '\x02' in part)
        count = int(match[2])
        if fields.get('f', '').endswith('/rtl/scheduler/tm_drr.sv'):
            point = points.setdefault(fields['t'], dict(hit=0, total=0))
            point['total'] += 1
            point['hit'] += int(count>0)
            if count==0:
                holes.append(dict(kind=fields['t'], line=fields.get('l'), expression=fields.get('o')))
        if fields.get('t')=='covergroup' and 'policy_cg.' in fields.get('h', ''):
            name = fields['h'].split('policy_cg.')[1]
            if name in bins:
                raise ValueError('Duplicate scheduler functional bin: '+name)
            bins[name] = count
    expected = {'update_kind.'+name for name in ('none','singleton','longer','different')}
    expected |= {point+'.auto_'+str(value) for point in ('tx_busy','activated') for value in (0,1)}
    expected |= {'fit.'+name for name in ('insufficient','equal','surplus')}
    expected |= {'replacement_busy.<'+kind+',auto_'+str(busy)+'>'
                 for kind in ('none','singleton','longer','different') for busy in (0,1)}
    expected |= {'reactivation_fit.<auto_'+str(active)+','+relation+'>'
                 for active in (0,1) for relation in ('insufficient','equal','surplus')}
    excluded = {'replacement_busy.<'+kind+',auto_1>': 'Dispatch collisions require free pre-state TX'
                for kind in ('singleton','longer','different')}
    if mode==0:
        excluded.update({name: 'Byte credit is absent in packet RR' for name in expected if name.startswith('reactivation_fit.')})
        excluded.update({'fit.'+name: 'Byte credit is absent in packet RR'
                         for name in ('insufficient','equal','surplus')})
    if set(bins)!=expected or not points.get('line', {}).get('hit'):
        raise ValueError('Missing scheduler code or functional coverage dimensions')
    missing = [name for name in expected-excluded.keys() if bins[name]<=0]
    if missing:
        raise ValueError('Mandatory scheduler bins not hit: '+', '.join(sorted(missing)))
    return dict(owned_points=points, unhit=holes, functional_bins=bins, exclusions=excluded,
                mandatory_hit=len(expected-excluded.keys()), mandatory_total=len(expected-excluded.keys()))


def schedule_checker_probes(run, args, binary, seed):
    probes = [(None, 'TM_SCHEDULE_PASS'), ('BYPASS','SCHEDULE_GRANT'),
              ('CREDIT','SCHEDULE_GRANT'), ('MISSING','SCHEDULE_TIMING'),
              ('HEAD','SCHEDULE_HEAD'), ('BUSY','SCHEDULE_GRANT')]
    for mutation, detector in probes:
        case = Case(run, 'scheduler-checker-'+(mutation.lower() if mutation else 'positive'), seed)
        command = [str(binary), f'+verilator+seed+{seed}', '+UVM_NO_RELNOTES', '+UVM_TESTNAME=tm_schedule_test']
        if mutation:
            command += ['+MUT_SCHED_'+mutation, '+TRACE']
        step = case.execute(command, timeout=args.timeout, cwd=case.path)
        if mutation:
            fatals = re.findall(r'UVM_FATAL[^\n]*\[([^]]+)\]', output(step))
            wave = case.path/'wave.vcd'
            ok = (step['result']!='TIMEOUT' and step['returncode'] not in (0,None) and
                  fatals==[detector] and wave.is_file() and wave.stat().st_size>0)
            case.data['artifacts']['waveform']=str(wave)
            case.finish('PASS' if ok else 'FAIL', None if ok else 'Intended policy/timing probe detection missing',
                        expected='SEEDED_DEFECT_DETECTION', detector=detector, observed_fatals=fatals)
        else:
            case.finish(*run_result(step, detector))


def scheduler(run, args):
    params = profile(args.profile)
    registered = sources('scheduler')
    seed = (args.seed or [17])[0]
    for mode, mutation in ((1, None), (0, None), (1, 'extra-quantum'), (1, 'missing-dispatch'), (0, 'missing-dispatch')):
        label = f'scheduler-mode{mode}'+('-'+mutation if mutation else '')
        build = Case(run, label+'-build', seed)
        parameters = dict(params, SCHED_MODE=mode)
        parameters.update(CELL_ID_W=max(1,(params['N_CELL']-1).bit_length()),
                          CELL_COUNT_W=params['N_CELL'].bit_length(),
                          DESC_ID_W=max(1,(params['N_DESC']-1).bit_length()),
                          DESC_COUNT_W=params['N_DESC'].bit_length(),
                          DEFICIT_W=(4096+params['MAX_PACKET_BYTES']-1).bit_length())
        build.data.update(parameters=parameters, source_set='scheduler', defines=['UVM_NO_DPI','TM_SCHEDULER_BENCH'], registered_source_digests=fingerprint('scheduler'))
        config = build.path/'tm_bench_config.svh'
        config.write_text(''.join(f'parameter int {k}={v};\n' for k,v in parameters.items()))
        uvm = Path(os.environ['UVM_HOME'])/'src'
        binary = build.path/'obj/Vtm_scheduler_top'
        argv = ['verilator', '--binary', '--timing', '--assert', '--coverage', '--trace-vcd',
                '--timescale', '1ns/1ps', '+define+UVM_NO_DPI', '+define+TM_SCHEDULER_BENCH', '--build-jobs', str(args.jobs),
                '--output-groups', '4', '--output-split', '20000', '--output-split-cfuncs', '500',
                '-CFLAGS', '-O0', '-I'+str(uvm), '-I'+str(build.path)]
        argv += ['-I'+str(ROOT/p) for p in registered['include_dirs']]
        source_paths = [ROOT/p for p in registered['sources']]
        if mutation:
            original = ROOT/'rtl/scheduler/tm_drr.sv'
            target = 'if (!visit_active)\n                    credit ='
            text = original.read_text()
            if mutation=='missing-dispatch':
                target = 'else if (tx_ready) begin'
                replacement = "else if (tx_ready && 1'b0) begin"
                count = 2
            else:
                replacement = "if (!visit_active || (tx_ready && credit >= (DEFICIT_W+1)'(selected_info.length)))\n                    credit ="
                count = 1
            if text.count(target)!=count:
                raise ValueError('Scheduler mutation site missing or ambiguous: '+mutation)
            mutant = build.path/'tm_drr.sv'
            mutant.write_text(text.replace(target,replacement))
            source_paths[source_paths.index(original)] = mutant
            build.data.update(mutation=mutation, mutant_sha256=sha(mutant))
        argv += [str(uvm/'uvm_pkg.sv')] + [str(p) for p in source_paths]
        argv += ['--top-module', 'tm_scheduler_top', '--Mdir', str(binary.parent)]
        step = build.execute(argv, timeout=args.build_timeout)
        result, why = step['result'], step['first_failure']
        if IGNORED.search(output(step)):
            result, why = 'UNSUPPORTED', 'Required construct ignored'
        if result=='PASS' and not binary.is_file():
            result, why = 'TOOL_ERROR', 'Missing executable'
        build.finish(result, why)
        case = Case(run, label, seed)
        case.data.update(parameters=parameters, source_set='scheduler', registered_source_digests=fingerprint('scheduler'))
        if result!='PASS':
            case.finish('NOT_RUN', 'Build did not qualify')
            continue
        if mode==1 and not mutation:
            schedule_checker_probes(run, args, binary, seed)
        command = [str(binary), f'+verilator+seed+{seed}', '+UVM_NO_RELNOTES', '+DETACHED_STIMULUS_PROBE']
        if mutation:
            command += ['+TRACE']
            if mutation=='extra-quantum':
                command += ['+PACKET_QUANTUM_PROBE']
        step = case.execute(command, timeout=args.timeout, cwd=case.path)
        if mutation:
            detector = 'SCHEDULE_CREDIT' if mutation=='extra-quantum' else 'SCHEDULE_TIMING'
            fatals = re.findall(r'UVM_FATAL[^\n]*\[([^]]+)\]', output(step))
            wave = case.path/'wave.vcd'
            ok = (step['result']!='TIMEOUT' and step['returncode'] not in (0,None) and
                  fatals==[detector] and wave.is_file() and wave.stat().st_size>0)
            case.data['artifacts']['waveform']=str(wave)
            case.finish('PASS' if ok else 'FAIL', None if ok else 'Intended '+detector+' detection missing',
                        expected='SEEDED_DEFECT_DETECTION', detector=detector, observed_fatals=fatals)
            continue
        status, reason = run_result(step, f'TM_SCHEDULER_PASS mode={mode}')
        if status=='PASS':
            metrics = re.search(r'TM_SCHEDULER_PASS (.*)', output(step))
            case.data['metrics'] = {k:int(v) for k,v in re.findall(r'(\w+)=(\d+)', metrics[1])}
            coverage = case.path/'coverage.dat'
            if not coverage.is_file() or not coverage.stat().st_size:
                status, reason = 'FAIL', 'Missing saved coverage'
            else:
                case.data['artifacts'].update(coverage=str(coverage), coverage_sha256=sha(coverage))
                try:
                    case.data['coverage'] = scheduler_coverage(coverage, mode)
                    case.data['finite_endpoints'] = [
                        {k:int(v) for k,v in re.findall(r'(\w+)=(\d+)', line)}
                        for line in output(step).splitlines() if '[SCHEDULER_BYTES]' in line and 'quantum0=' in line]
                    if len(case.data['finite_endpoints'])!=2:
                        raise ValueError('Missing equal/unequal quantum finite endpoints')
                except (OSError, ValueError) as error:
                    status, reason = 'FAIL', str(error)
                report = case.execute(['verilator_coverage','--report','summary',str(coverage)],timeout=args.timeout)
                if report['result']!='PASS':
                    status, reason = report['result'], 'Coverage report failed'
        if status!='PASS' and step['result']!='TIMEOUT':
            rerun=case.path/'failing-rerun'; rerun.mkdir()
            case.execute(command+['+TRACE'],timeout=args.timeout,cwd=rerun)
            case.data['artifacts']['waveform']=str(rerun/'wave.vcd')
        case.finish(status, reason)
