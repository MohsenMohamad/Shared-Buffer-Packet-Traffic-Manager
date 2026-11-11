"""Executable UVM foundation qualification, isolated from production TM results."""
import hashlib
import json
import os
from pathlib import Path
import re

from evidence import Case, ROOT, IGNORED, completed, output
from registry import profile, sources, fingerprint


DEFECTS = {
    'CORRUPT': 'BYTE_CORRUPTION',
    'DUPLICATE': 'BYTE_UNEXPECTED',
    'LOST': 'BYTE_LOST',
    'STATUS': 'STATUS_CAUSALITY',
    'SERVICE': 'SERVICE_DATA',
    'ADMISSION': 'ADMISSION_PREDICATE',
    'SCHEDULE': 'SCHEDULE_HEAD',
    'STALE': 'BYTE_UNEXPECTED',
    'CSR': 'CSR_RESOURCE',
}


def coverage(path):
    counts, bins = {}, {}
    for line in path.read_text().splitlines():
        match = re.fullmatch(r"C '(.*)' (\d+)", line)
        if not match:
            continue
        fields = dict(part.split('\x02', 1) for part in match[1].split('\x01') if '\x02' in part)
        if not re.search(r'(^|/)dv/',fields.get('f', '')):
            continue
        kind, count = fields.get('t'), int(match[2])
        group = counts.setdefault(kind, dict(hit=0, total=0))
        group['total'] += 1
        group['hit'] += int(count > 0)
        if kind == 'covergroup':
            bins[fields.get('h', '')] = count
    if not counts.get('line', {}).get('hit') or not counts.get('covergroup', {}).get('hit'):
        raise ValueError('Missing nonzero saved owned code and functional counters')
    for order in ('w_first', 'simultaneous', 'aw_first'):
        if not any(name.endswith('.arrival_order.'+order) and count for name, count in bins.items()):
            raise ValueError('AW/W order bin not hit: '+order)
    return dict(owned_points=counts, functional_bins=bins)


def foundation(run, args):
    seed = (args.seed or [17])[0]
    params = profile(args.profile)
    params.update(CELL_ID_W=max(1,(params['N_CELL']-1).bit_length()),
                  CELL_COUNT_W=params['N_CELL'].bit_length(),
                  DESC_ID_W=max(1,(params['N_DESC']-1).bit_length()),
                  DESC_COUNT_W=params['N_DESC'].bit_length(),
                  DEFICIT_W=(4096+params['MAX_PACKET_BYTES']-1).bit_length())
    registered = sources('uvm-foundation')
    build = Case(run, 'foundation-build', seed)
    build.data.update(scope='UVM foundation fixture only; not production TM correctness',
                      parameters=params, source_set='uvm-foundation',
                      registered_source_digests=fingerprint('uvm-foundation'))
    config = build.path / 'tm_bench_config.svh'
    config.write_text(''.join(f'parameter int {k}={v};\n' for k,v in params.items()))
    uvm_src = Path(os.environ.get('UVM_HOME', str(ROOT/'.deps/src/uvm'))) / 'src'
    binary = build.path / 'obj/Vtm_foundation_top'
    argv = ['verilator', '--binary', '--timing', '--assert', '--coverage', '--trace-vcd',
            '--timescale', '1ns/1ps', '+define+UVM_NO_DPI', '--build-jobs', str(args.jobs),
            '--output-groups', '4', '--output-split', '20000', '--output-split-cfuncs', '500',
            '-CFLAGS', '-O0', '-I'+str(uvm_src), '-I'+str(build.path)]
    argv += ['-I'+str(ROOT/p) for p in registered['include_dirs']]
    argv += [str(uvm_src/'uvm_pkg.sv')] + [str(ROOT/p) for p in registered['sources']]
    argv += ['--top-module', 'tm_foundation_top', '--Mdir', str(binary.parent)]
    step = build.execute(argv, timeout=args.build_timeout)
    result, why = step['result'], step['first_failure']
    if IGNORED.search(output(step)):
        result, why = 'UNSUPPORTED', 'Required construct ignored or unsupported'
    if result=='PASS' and not binary.is_file():
        result, why = 'TOOL_ERROR', 'No executable produced'
    build.finish(result, why)
    specs = [('positive',seed,None),('replay',seed,None),('alternate',seed%2147483645+2,None),('small-quantum',seed,None)]
    specs += [(name.lower(),seed,name) for name in DEFECTS]
    signatures=[]
    for name,case_seed,defect in specs:
        case = Case(run,'foundation-'+name,case_seed)
        case.data.update(scope='Declared behavioral fixture; expected seeded defects' if defect else 'Declared behavioral fixture; not production TM',
                         parameters=params, source_set='uvm-foundation')
        if result!='PASS':
            case.finish('NOT_RUN','Foundation compilation did not qualify')
            continue
        command=[str(binary),f'+verilator+seed+{case_seed}','+UVM_NO_RELNOTES']
        if name=='small-quantum':
            command += ['+SMALL_QUANTUM']
        if defect:
            command += ['+MUT_'+defect, '+TRACE']
        step=case.execute(command,timeout=args.timeout,cwd=case.path)
        text=output(step)
        if defect:
            # Exactly the intended first UVM fatal; compilation/crashes do not qualify.
            fatals=re.findall(r'UVM_FATAL[^\n]*\[([^]]+)\]',text)
            wave=case.path/'wave.vcd'
            ok=step['result']!='TIMEOUT' and step['returncode'] not in (0,None) and fatals==[DEFECTS[defect]] and wave.is_file() and wave.stat().st_size>0
            case.data['artifacts'].update(waveform=str(wave),transactions=str(case.path/'transactions.jsonl'))
            (case.path/'first_failure.json').write_text(json.dumps(dict(expected=DEFECTS[defect],observed=fatals,seed=case_seed,profile=args.profile,source_revision=run.provenance['source_revision']),indent=2)+'\n')
            case.data['artifacts']['first_failure']=str(case.path/'first_failure.json')
            case.finish('PASS' if ok else ('TIMEOUT' if step['result']=='TIMEOUT' else 'FAIL'),None if ok else 'Intended first checker detection/waveform missing',expected='SEEDED_DEFECT_DETECTION',detector=DEFECTS[defect],observed_fatals=fatals)
        else:
            status,reason=completed(step,'TM_FOUNDATION_PASS')
            if status=='PASS':
                try:
                    case.data['coverage']=coverage(case.path/'coverage.dat')
                    metrics=re.search(r'TM_FOUNDATION_PASS (.*)',text)
                    case.data['metrics']={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',metrics[1])}
                    if min(case.data['metrics'].values())<=0:
                        raise ValueError('Zero transaction/checker execution count')
                    if name!='small-quantum':
                        signatures.append(hashlib.sha256((case.path/'transactions.jsonl').read_bytes()).hexdigest())
                    report=case.execute(['verilator_coverage','--report','summary',str(case.path/'coverage.dat')],timeout=args.timeout)
                    if report['result']!='PASS':
                        status,reason=report['result'],'Coverage report generation failed'
                    case.data['artifacts'].update(coverage=str(case.path/'coverage.dat'),transactions=str(case.path/'transactions.jsonl'))
                except (OSError, ValueError, AttributeError) as error:
                    status,reason='FAIL',str(error)
            if status!='PASS' and step['result']!='TIMEOUT':
                rerun=case.path/'failing-rerun';rerun.mkdir()
                case.execute(command+['+TRACE'],timeout=args.timeout,cwd=rerun,stem='failing-rerun')
                case.data['artifacts']['waveform']=str(rerun/'wave.vcd')
            case.finish(status,reason)
    probes=[('barrier', 'tm_batch_test',None,'TM_BATCH_PASS')]
    probes += [('barrier-'+name.lower(),'tm_batch_test','BATCH_'+name,'BATCH_'+name)
               for name in ('DUPLICATE','MISSING','STALE')]
    if params['N_RX']>=2:
        probes += [('atomic','tm_atomic_test',None,'TM_ATOMIC_PASS'),
                   ('atomic-limit','tm_atomic_test','ATOMIC_LIMIT','ADMISSION_PREDICATE')]
    for name,test,mutation,marker in probes:
        case=Case(run,'foundation-'+name,seed)
        if result!='PASS':
            case.finish('NOT_RUN','Foundation compilation did not qualify')
            continue
        command=[str(binary),f'+verilator+seed+{seed}','+UVM_NO_RELNOTES','+UVM_TESTNAME='+test]
        if mutation:
            command += ['+MUT_'+mutation,'+TRACE']
        step=case.execute(command,timeout=args.timeout,cwd=case.path)
        if mutation:
            fatals=re.findall(r'UVM_FATAL[^\n]*\[([^]]+)\]',output(step))
            wave=case.path/'wave.vcd'
            ok=step['result']!='TIMEOUT' and step['returncode'] not in (0,None) and fatals==[marker] and wave.is_file() and wave.stat().st_size>0
            case.finish('PASS' if ok else ('TIMEOUT' if step['result']=='TIMEOUT' else 'FAIL'),None if ok else 'Expected first barrier/model detection missing',expected='SEEDED_DEFECT_DETECTION',detector=marker)
        else:
            case.finish(*completed(step,marker))
    replay=Case(run,'foundation-seed-replay',seed)
    ok=len(signatures)==3 and signatures[0]==signatures[1] and signatures[0]!=signatures[2]
    replay.finish('PASS' if ok else 'FAIL',None if ok else 'Missing, nonrepeatable or seed-independent observed trace',transaction_digests=signatures)
