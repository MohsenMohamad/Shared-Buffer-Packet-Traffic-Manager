#!/usr/bin/env python3
"""Execute native capability gates with bounded processes and explicit evidence."""
import argparse
import json
import os
from pathlib import Path
import re
import resource
import shutil
import sys
import uuid

from evidence import Case, IGNORED, ROOT, Run, completed, output, utc

FIXTURES = ROOT / 'tests/toolchain'


class InputError(ValueError):
    pass


class ManifestParser(argparse.ArgumentParser):
    def error(self, message):
        raise InputError(message)


def inspect_coverage(path):
    """Read actual saved counters, including named coverpoints and cross bins."""
    points = {}
    bins = {}
    for line in path.read_text().splitlines():
        match = re.fullmatch(r"C '(.*)' (\d+)", line)
        if not match:
            continue
        fields = dict(part.split('\x02', 1) for part in match[1].split('\x01') if '\x02' in part)
        if not fields.get('f', '').endswith('/tests/toolchain/uvm_smoke.sv'):
            continue
        kind, count = fields.get('t'), int(match[2])
        point = points.setdefault(kind, dict(hit=0, total=0))
        point['total'] += 1
        point['hit'] += int(count > 0)
        if kind == 'covergroup':
            bins[fields.get('h', '')] = count
    if not points.get('line', {}).get('hit') or not points.get('covergroup', {}).get('hit'):
        raise ValueError('Missing nonzero owned code or functional coverage')
    prefix = 'tm_cap_pkg::tm_cap_test::cg.'
    queues = [prefix + f'q.queues[{q}]' for q in range(4)]
    lengths = [prefix + 'l.' + length for length in ('short_pkt', 'mid_pkt', 'long_pkt')]
    crosses = [prefix + f'ql.<queues[{q}],{length}>' for q in range(4)
               for length in ('short_pkt', 'mid_pkt', 'long_pkt')]
    if set(bins) != set(queues + lengths + crosses):
        raise ValueError('Expected 4 queue, 3 length and 12 cross bins')
    if any(sum(bins[name] for name in group) != 64 for group in (queues, lengths, crosses)):
        raise ValueError('Saved functional counters do not account for 64 samples in each group')
    return dict(owned_code_points=points, functional_bins=bins)


def assertion_result(step, wave):
    if step['result'] == 'TIMEOUT' or step['returncode'] is None:
        return step['result'], step['first_failure']
    if step['returncode'] == 0 or 'TM_CAP_STABILITY_FAIL' not in output(step):
        return 'FAIL', 'Expected executed held-output assertion failure'
    if not wave.is_file() or wave.stat().st_size == 0:
        return 'FAIL', 'Missing assertion-failure waveform'
    return 'PASS', None


def uvm(run, args):
    build = Case(run, 'uvm-build')
    uvm_src = Path(os.environ.get('UVM_HOME', str(ROOT / '.deps/src/uvm'))) / 'src'
    argv = ['verilator', '--binary', '--timing', '--assert', '--coverage', '--trace-vcd',
            '--timescale', '1ns/1ps', '+define+UVM_NO_DPI', '--build-jobs', str(args.jobs),
            '--output-groups', '4', '--output-split', '20000', '--output-split-cfuncs', '500', '-CFLAGS', '-O0',
            '+incdir+' + str(uvm_src), str(uvm_src / 'uvm_pkg.sv'), str(FIXTURES / 'uvm_smoke.sv'),
            '--top-module', 'tm_uvm_capabilities', '--Mdir', str(build.path / 'obj')]
    step = build.execute(argv, timeout=args.build_timeout)
    status, reason = step['result'], step['first_failure']
    if IGNORED.search(output(step)):
        status, reason = 'UNSUPPORTED', 'Required constraint, assertion or coverage construct ignored'
    binary = build.path / 'obj/Vtm_uvm_capabilities'
    if status == 'PASS' and not binary.is_file():
        status, reason = 'TOOL_ERROR', 'Successful compiler did not produce executable'
    build.finish(status, reason)
    seeds = args.seed or [17, 19]
    specs = [(f'uvm-seed{seed}', seed, False) for seed in seeds]
    specs += [('uvm-replay', seeds[0], False), ('uvm-held-data-mutation', seeds[0], True)]
    digests = []
    for name, seed, mutation in specs:
        case = Case(run, name, seed)
        if status != 'PASS':
            case.finish('NOT_RUN', 'UVM compilation did not qualify')
            continue
        argv = [str(binary), '+verilator+seed+' + str(seed), '+UVM_NO_RELNOTES']
        if mutation:
            argv += ['+MUTATION_HOLD', '+TRACE']
        step = case.execute(argv, timeout=args.timeout, cwd=case.path)
        if mutation:
            result, why = assertion_result(step, case.path / 'wave.vcd')
            case.data['artifacts']['waveform'] = str(case.path / 'wave.vcd')
            case.finish(result, why, expected='ASSERTION_FAILURE')
            continue
        result, why = completed(step, 'TM_UVM_SMOKE_PASS transactions=64')
        text = output(step)
        found = re.search(r'TM_UVM_SMOKE_PASS transactions=64 digest=([0-9a-fA-F]+)', text)
        if result == 'PASS' and ('TM_CAP_UNSAT_PASS' not in text or found is None):
            result, why = 'FAIL', 'Missing unsatisfiable randomization or transaction digest marker'
        if result == 'PASS':
            digests.append(found[1])
            try:
                coverage = inspect_coverage(case.path / 'coverage.dat')
                case.data.update(coverage=coverage, transaction_digest=found[1], transactions=64)
                case.data['artifacts']['coverage'] = str(case.path / 'coverage.dat')
                report = case.execute(['verilator_coverage', '--report', 'summary',
                                       str(case.path / 'coverage.dat')], timeout=args.timeout)
                if report['result'] != 'PASS':
                    result, why = report['result'], 'Coverage report generation failed'
            except (OSError, ValueError) as error:
                result, why = 'FAIL', str(error)
        if result != 'PASS' and step['result'] != 'TIMEOUT':
            # Identical binary/profile/seed with tracing only; the original failure remains.
            rerun_path = case.path / 'failing-rerun'
            rerun_path.mkdir()
            rerun = case.execute(argv + ['+TRACE'], timeout=args.timeout, cwd=rerun_path,
                                 stem='failing-rerun')
            case.data['artifacts']['rerun'] = rerun
            case.data['artifacts']['rerun_waveform'] = str(rerun_path / 'wave.vcd')
        case.finish(result, why)
    replay = Case(run, 'uvm-seed-replay')
    ok = len(digests) == len(seeds) + 1 and digests[0] == digests[-1] and len(set(digests[:-1])) > 1
    replay.finish('PASS' if ok else 'FAIL', None if ok else 'Missing, nonrepeatable or seed-independent digests',
                  observed_digests=digests)


def formal(run, args):
    for task in ('prove', 'cover', 'mutation'):
        case = Case(run, 'formal-' + task)
        for source in ('counter.sv', 'counter.sby'):
            shutil.copyfile(FIXTURES / source, case.path / source)
        step = case.execute(['sby', '-f', '-d', str(case.path / 'engine'), 'counter.sby', task],
                            timeout=args.timeout, cwd=case.path)
        status_file = case.path / 'engine/status'
        status = status_file.read_text().split()[0] if status_file.is_file() else None
        waves = [p for p in (case.path / 'engine').rglob('*.vcd') if p.stat().st_size > 0]
        text = output(step)
        if step['result'] == 'TIMEOUT' or step['returncode'] is None:
            result, reason = step['result'], step['first_failure']
        elif task == 'mutation':
            ok = step['returncode'] != 0 and status == 'FAIL' and bool(waves) and 'Assert failed' in text
            result, reason = ('PASS', None) if ok else ('TOOL_ERROR', 'Expected assertion counterexample, not tool failure')
        else:
            ok = step['returncode'] == 0 and status == 'PASS'
            if task == 'cover':
                ok = ok and bool(waves) and 'Reached cover statement' in text
            else:
                ok = ok and 'successful proof by k-induction' in text
            result, reason = ('PASS', None) if ok else ('TOOL_ERROR', 'Missing successful proof/cover evidence')
        case.data['artifacts'].update(status=str(status_file), traces=[str(p) for p in waves])
        case.finish(result, reason, expected='COUNTEREXAMPLE' if task == 'mutation' else task.upper(),
                    engine='smtbmc z3; unbounded k-induction for prove; cover bound 20')


def synth(run, args):
    case = Case(run, 'mapped-synthesis')
    liberty = ROOT / '.deps/liberty.lib'
    script = case.path / 'mapping.ys'
    netlist, stats = case.path / 'mapped.v', case.path / 'stats.json'
    script.write_text(f'read_verilog {FIXTURES}/mapping.v\nsynth -top mapping\n'
                      f'dfflibmap -liberty {liberty}\nabc -liberty {liberty}\nclean\n'
                      f'read_liberty -lib {liberty}\ncheck -assert\nwrite_verilog -noattr {netlist}\n'
                      f'tee -o {stats} stat -json -liberty {liberty}\n')
    step = case.execute(['yosys', '-s', str(script)], timeout=args.timeout)
    result, reason = step['result'], step['first_failure']
    if result == 'PASS':
        try:
            mapping = json.loads(stats.read_text())['modules']['\\mapping']
            cells = mapping['num_cells_by_type']
            if not cells or any(name.startswith('$') for name in cells) or not cells.get('DFF_X1') or not cells.get('XOR2_X1'):
                raise ValueError('Expected mapped Nangate sequential and combinational cells')
            case.data.update(mapped_cells=cells, area=mapping['area'])
        except (OSError, ValueError, KeyError) as error:
            result, reason = 'FAIL', str(error)
    case.data['artifacts'].update(netlist=str(netlist), statistics=str(stats), script=str(script))
    case.finish(result, reason)
    sta = Case(run, 'sta-max-min')
    if result != 'PASS':
        sta.finish('NOT_RUN', 'Mapped synthesis did not qualify')
        return
    os.environ.update(TM_LIBERTY=str(liberty), TM_NETLIST=str(netlist), TM_SDC=str(FIXTURES / 'timing.sdc'))
    step = sta.execute(['sta', '-exit', str(FIXTURES / 'timing.tcl')], timeout=args.timeout)
    text = output(step)
    result, reason = completed(step, 'TM_STA_DONE')
    maximum = text.split('TM_STA_MAX_BEGIN')[-1].split('TM_STA_MIN_BEGIN')[0]
    minimum = text.split('TM_STA_MIN_BEGIN')[-1].split('TM_STA_DONE')[0]
    if result == 'PASS' and (re.search(r'(?im)^\s*(?:Error|Warning):', text) or
                            any('slack' not in section or 'Startpoint:' not in section or
                                'Endpoint:' not in section for section in (maximum, minimum))):
        result, reason = 'FAIL', 'Timing errors, warnings or missing max/min constrained paths'
    sta.data['artifacts'].update(sdc=str(FIXTURES / 'timing.sdc'), liberty=str(liberty), netlist=str(netlist))
    sta.finish(result, reason, analysis='Nangate45 typical; pre-layout wire model; synthetic fixture only')


def lint(run, args):
    case = Case(run, 'lint-fixture')
    step = case.execute(['verilator', '--lint-only', '--Wall', '--top-module', 'mapping',
                         str(FIXTURES / 'mapping.v')], timeout=args.timeout)
    case.finish(step['result'], step['first_failure'])
    negative = Case(run, 'compile-error-rejection')
    broken = negative.path / 'broken.sv'
    broken.write_text('module broken(; endmodule\n')
    step = negative.execute(['verilator', '--lint-only', str(broken)], timeout=args.timeout)
    ok = step['result'] == 'TOOL_ERROR' and step['returncode'] not in (0, None) and '%Error' in output(step)
    negative.finish('PASS' if ok else 'FAIL', None if ok else 'Expected real compiler syntax rejection',
                    expected='TOOL_ERROR')


def four_state(run, args):
    case = Case(run, 'four-state-reproducer')
    step = case.execute(['verilator', '--binary', '--timing', '--assert', '--top-module',
                         'four_state', '--Mdir', str(case.path / 'obj'), '--build-jobs', str(args.jobs),
                         str(FIXTURES / 'four_state.sv')], timeout=args.build_timeout)
    if step['result'] != 'PASS':
        case.finish(step['result'], step['first_failure'])
        return
    step = case.execute([str(case.path / 'obj/Vfour_state')], timeout=args.timeout, cwd=case.path)
    if step['returncode'] not in (0, None) and 'TM_FOUR_STATE_UNSUPPORTED' in output(step):
        case.finish('UNSUPPORTED', 'Two-state simulator cannot retain X/Z; portable assertion requires four states')
    else:
        case.finish(*completed(step, 'TM_FOUR_STATE_PASS'))


def repo(run, args):
    case = Case(run, 'repository-contracts')
    case.finish(*completed(case.execute([sys.executable, str(ROOT / 'tools/check_repository.py')],
                                       timeout=args.timeout), 'Repository contracts: PASS'))


def unit(run, args):
    case = Case(run, 'runner-unit')
    step = case.execute([sys.executable, '-m', 'unittest', 'discover', '-s', str(FIXTURES), '-p', 'test_*.py', '-v'],
                        timeout=args.timeout)
    match = re.search(r'Ran (\d+) tests?', output(step))
    ok = step['result'] == 'PASS' and match and int(match[1]) > 0 and re.search(r'(?m)^OK$', output(step))
    case.finish('PASS' if ok else step['result'] if step['result'] != 'PASS' else 'FAIL',
                None if ok else 'Unit tests failed or selected zero tests')


def main(argv=None):
    parser = ManifestParser(description=__doc__)
    parser.add_argument('action')
    parser.add_argument('--profile', default=None)
    parser.add_argument('--test', action='append', help='CI gate or regression suite selection (repeatable)')
    parser.add_argument('--seed', action='append', type=int)
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--timeout', type=float, default=None)
    parser.add_argument('--build-timeout', type=float, default=1200)
    parser.add_argument('--output', type=Path, default=ROOT / '.build/runs')
    parser.add_argument('--uvm-home', type=Path, help='Compatibility override; must match locked installation')
    try:
        args = parser.parse_args(argv)
    except InputError as error:
        run = Run(ROOT / '.build/runs' / ('invalid-' + uuid.uuid4().hex))
        Case(run, 'malformed-input').finish('TOOL_ERROR', str(error))
        return run.finish()
    if args.timeout is None:
        args.timeout = 240 if args.action == 'formal-rtl' else 120
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    activation = ROOT / '.tools/environment.json'
    if activation.is_file():
        os.environ.update(json.loads(activation.read_text()))
    if args.uvm_home is not None:
        os.environ['UVM_HOME'] = str(args.uvm_home.resolve())
    action = {'test-uvm-smoke': 'uvm', 'formal-smoke': 'formal', 'synth-smoke': 'synth',
              'test-unit': 'unit', 'repo-check': 'repo'}.get(args.action, args.action)
    if args.profile is None:
        args.profile = 'E0' if action == 'formal-rtl' else 'F0' if action == 'regression' else 'toolchain'
    run = Run(args.output.resolve() / (action + '-' + utc().replace(':', '') + '-' + uuid.uuid4().hex[:8]), args.profile)
    if action == 'formal-rtl':
        from formal_storage import formal_rtl, selection as formal_selection
        run.scope = 'Local production storage invariants and reachability; no integrated TM ownership proof'
        try:
            if not 1 <= args.jobs <= 8 or not 0 < args.timeout <= 3600 or not 0 < args.build_timeout <= 3600:
                raise ValueError('jobs must be 1..8; timeouts must be >0 and <=3600 seconds')
            formal_selection(args)
            from doctor import qualify
            qualify(run)
            formal_rtl(run, args)
        except (OSError, ValueError, KeyError) as error:
            Case(run, 'formal-selection-or-suite-error').finish('TOOL_ERROR', str(error))
        return run.finish()
    if action == 'regression':
        from registry import selection
        from contracts import contracts
        from storage import pools
        run.scope = 'Selected contract/component suites; no integrated TM validation'
        try:
            selected = selection(args.profile, args.test)
            if not 1 <= args.jobs <= 8 or not 0 < args.timeout <= 3600 or not 0 < args.build_timeout <= 3600:
                raise ValueError('jobs must be 1..8; timeouts must be >0 and <=3600 seconds')
            if args.seed is not None and (len(args.seed) != 1 or not 1 <= args.seed[0] <= 2**31-1):
                raise ValueError('Regression accepts one positive 31-bit functional seed')
            from doctor import qualify
            qualify(run)
            handlers = {'contracts': contracts, 'pools': pools}
            for name in selected:
                handlers[name](run, args)
        except (OSError, ValueError, KeyError) as error:
            Case(run, 'selection-or-suite-error').finish('TOOL_ERROR', str(error))
        return run.finish()
    from doctor import qualify
    gates = dict(doctor=lambda r, a: qualify(r), repo=repo, unit=unit, lint=lint, uvm=uvm, formal=formal, synth=synth)
    selected = args.test if args.test is not None else list(gates) if action == 'ci' else [action]
    gates['four-state'] = four_state  # Explicit reproducer; outside the required two-state suite.
    error = None
    if args.profile != 'toolchain':
        error = 'Capability commands require the toolchain profile'
    if not 1 <= args.jobs <= 8 or not 0 < args.timeout <= 3600 or not 0 < args.build_timeout <= 3600:
        error = 'jobs must be 1..8; timeouts must be >0 and <=3600 seconds'
    if args.seed is not None and (len(set(args.seed)) != len(args.seed) or len(args.seed) < 2 or
                                  any(seed < 1 or seed > 2**31-1 for seed in args.seed)):
        error = 'Seed replay qualification requires at least two distinct positive 31-bit seeds'
    if args.test is not None and action != 'ci':
        error = '--test selects CI component gates; use action ci'
    if not selected or any(not name or name not in gates for name in selected) or len(set(selected)) != len(selected):
        error = 'Empty, duplicate or unknown test selection'
    if action not in (*gates, 'ci'):
        Case(run, 'unimplemented').finish('NOT_IMPLEMENTED', 'Command not implemented: ' + args.action)
    elif error:
        Case(run, 'selection').finish('TOOL_ERROR', error)
    else:
        # Version records accompany direct capability runs as well as CI. Independent
        # gates continue after failures; compilation remains prerequisite to execution.
        if 'doctor' not in selected and any(s in selected for s in ('uvm', 'formal', 'synth', 'lint', 'four-state')):
            qualify(run)
        for name in selected:
            try:
                gates[name](run, args)
            except (OSError, ValueError, KeyError) as error:
                Case(run, name + '-error').finish('TOOL_ERROR', str(error))
    return run.finish()


if __name__ == '__main__':
    sys.exit(main())
