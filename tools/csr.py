"""Production CSR/statistics UVM regression with independently driven events."""
import os
import fcntl
from pathlib import Path
import re
import shutil

from evidence import Case, ROOT, IGNORED, output, sha
from registry import profile, sources, fingerprint
from foundation import coverage, first_failure, run_result


def csr_coverage(path):
    result = coverage(path)
    cross = {name: count for name,count in result['functional_bins'].items() if '.ordering.' in name}
    if len(cross) != 12 or not all(cross.values()):
        raise ValueError('Missing AW/W order x B stall x concurrent read bins')
    owned = {}
    for line in path.read_text().splitlines():
        match = re.fullmatch(r"C '(.*)' (\d+)", line)
        if not match:
            continue
        fields = dict(part.split('\x02',1) for part in match[1].split('\x01') if '\x02' in part)
        filename = fields.get('f','')
        if '/rtl/csr/' not in filename:
            continue
        points = owned.setdefault(Path(filename).name, {})
        point = points.setdefault(fields.get('t'), dict(hit=0,total=0,unhit=[]))
        count = int(match[2])
        point['total'] += 1
        point['hit'] += int(count > 0)
        if not count:
            point['unhit'].append({key: fields[key] for key in ('l','h','o') if key in fields})
    if set(owned) != {'tm_axil_regs.sv','tm_statistics.sv'} or any(not points.get('line',{}).get('hit') for points in owned.values()):
        raise ValueError('Missing executed production CSR line coverage')
    result.update(production_points=owned, mandatory_cross=cross)
    return result


def csr(run, args):
    seed = (args.seed or [17])[0]
    params = profile(args.profile)
    params.update(CELL_ID_W=max(1, (params['N_CELL']-1).bit_length()),
                  CELL_COUNT_W=params['N_CELL'].bit_length(),
                  DESC_ID_W=max(1, (params['N_DESC']-1).bit_length()),
                  DESC_COUNT_W=params['N_DESC'].bit_length(),
                  DEFICIT_W=(4096+params['MAX_PACKET_BYTES']-1).bit_length())
    registered = sources('csr')
    for width, mutation in ((64, False), (8, False), (64, True)):
        label = 'coupled-channel' if mutation else f'counter{width}'
        build = Case(run, 'csr-build-'+label, seed)
        build.data.update(parameters=params, counter_width=width, source_set='csr',
                          registered_source_digests=fingerprint('csr'),
                          scope='Production CSR/statistics; independent event and busy-context fixture')
        # Reuse compiler objects during a focused edit/test loop. Each case
        # retains its own config, immutable executable and exact source digests.
        cache = ROOT/'.build/csr-objects'/f'{args.profile}-{label}'
        cache.mkdir(parents=True, exist_ok=True)
        lock = (cache/'build.lock').open('a')
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            lock.close()
            raise ValueError('CSR object directory already in use: '+str(cache)) from error
        for name, content in {
            'tm_bench_config.svh': ''.join(f'parameter int {k}={v};\n' for k,v in params.items())+f'parameter int CSR_COUNTER_W={width};\n',
            'tm_csr_params.svh': ','.join(f'.{k}({k})' for k in params),
        }.items():
            (build.path/name).write_text(content)
            if not (cache/name).is_file() or (cache/name).read_text() != content:
                (cache/name).write_text(content)
        paths = [ROOT/p for p in registered['sources']]
        if mutation:
            original = ROOT/'rtl/csr/tm_axil_regs.sv'
            text = original.read_text()
            target = 'bus_rsp.awready = rst_n && !have_aw && !bvalid;'
            if text.count(target) != 1:
                raise ValueError('Coupled-channel mutation site missing or ambiguous')
            mutant = build.path/'tm_axil_regs.sv'
            mutant.write_text(text.replace(target, target[:-1]+' && bus_req.wvalid;'))
            paths = [mutant if p == original else p for p in paths]
            build.data.update(mutation='AWREADY requires WVALID; independently delayed W source', mutant_sha256=sha(mutant))
        uvm = Path(os.environ['UVM_HOME'])/'src'
        compiled = cache/'obj/Vtm_csr_top'
        binary = build.path/'Vtm_csr_top'
        argv = ['verilator', '--binary', '--timing', '--assert', '--coverage', '--trace-vcd',
                '--timescale', '1ns/1ps', '+define+UVM_NO_DPI', '--build-jobs', str(args.jobs),
                '--output-groups', '4', '--output-split', '20000', '--output-split-cfuncs', '500',
                '-CFLAGS', '-O0', '-I'+str(uvm), '-I'+str(cache)]
        argv += ['-I'+str(ROOT/p) for p in registered['include_dirs']]
        argv += [str(uvm/'uvm_pkg.sv')] + list(map(str, paths))
        argv += ['--top-module', 'tm_csr_top', '--Mdir', str(compiled.parent)]
        step = build.execute(argv, timeout=args.build_timeout)
        result, why = step['result'], step['first_failure']
        if IGNORED.search(output(step)):
            result, why = 'UNSUPPORTED', 'Required construct ignored or unsupported'
        if result == 'PASS' and not compiled.is_file():
            result, why = 'TOOL_ERROR', 'No CSR executable produced'
        if result == 'PASS':
            shutil.copy2(compiled, binary)
            build.data['artifacts'].update(binary=str(binary), binary_sha256=sha(binary))
        lock.close()
        build.finish(result, why)
        case = Case(run, 'csr-'+label, seed)
        case.data.update(counter_width=width, parameters=params, source_set='csr')
        if result != 'PASS':
            case.finish('NOT_RUN', 'CSR compilation did not qualify')
            continue
        command = [str(binary), f'+verilator+seed+{seed}', '+UVM_NO_RELNOTES']
        if mutation:
            command += ['+TRACE']
        step = case.execute(command, timeout=args.timeout, cwd=case.path)
        if mutation:
            fatals = re.findall(r'UVM_FATAL[^\n]*\[([^]]+)\]', output(step))
            wave = case.path/'wave.vcd'
            ok = step['result'] != 'TIMEOUT' and step['returncode'] not in (0, None) and fatals == ['CSR_AW_W_INDEPENDENCE'] and wave.is_file() and wave.stat().st_size > 0
            first_failure(case, step, 'CSR_AW_W_INDEPENDENCE')
            case.data['artifacts']['waveform'] = str(wave)
            case.finish('PASS' if ok else 'FAIL', None if ok else 'Intended independence detector missing',
                        expected='SEEDED_DEFECT_DETECTION', observed_fatals=fatals)
        else:
            result, why = run_result(step, 'TM_CSR_PASS')
            if result == 'PASS':
                try:
                    case.data['coverage'] = csr_coverage(case.path/'coverage.dat')
                    metrics = re.search(r'TM_CSR_PASS (.*)', output(step))
                    case.data['metrics'] = {k: int(v) for k,v in re.findall(r'(\w+)=(\d+)', metrics[1])}
                    if width < 64 and case.data['metrics'].get('rollovers', 0) == 0:
                        raise ValueError('Reduced counter rollover not observed')
                    case.data['artifacts'].update(coverage=str(case.path/'coverage.dat'), transactions=str(case.path/'transactions.jsonl'))
                except (OSError, ValueError, AttributeError) as error:
                    result, why = 'FAIL', str(error)
            if result != 'PASS' and step['result'] != 'TIMEOUT':
                first_failure(case, step)
                rerun = case.path/'failing-rerun'
                rerun.mkdir()
                case.execute(command+['+TRACE'], timeout=args.timeout, cwd=rerun, stem='failing-rerun')
                case.data['artifacts']['waveform'] = str(rerun/'wave.vcd')
            case.finish(result, why)
