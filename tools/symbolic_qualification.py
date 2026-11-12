"""Small F01 assert/cover qualification on the selected pinned formal stack."""
from collections import Counter
import json
import re
import sys

from evidence import Case, ROOT, output, sha
from frontend import read_sources
from registry import sources


def outcome(step, status, text, waves, expected, labels):
    """Match engine status AND named semantics; errors cannot detect a mutation."""
    if step['result'] == 'TIMEOUT':
        return 'TIMEOUT', 'Symbolic qualification timed out'
    if status == 'UNKNOWN':
        return 'INCONCLUSIVE', 'Engine returned UNKNOWN'
    if status not in ('PASS', 'FAIL') or step['returncode'] is None:
        return 'TOOL_ERROR', 'No completed proof/cover result (frontend/engine error)'
    if expected == 'ASSERT_FAIL':
        ok = status == 'FAIL' and step['returncode'] != 0 and bool(waves) and all(
            re.search(r'Assert failed in .*\b' + re.escape(label) + r'\b', text)
            for label in labels)
    elif expected == 'UNREACHED':
        ok = status == 'FAIL' and step['returncode'] != 0 and not waves and all(
            re.search(r'Unreached cover statement .*\b' + re.escape(label) + r'\b', text)
            for label in labels) and 'Assert failed' not in text
    elif expected == 'REACHED':
        ok = status == 'PASS' and step['returncode'] == 0 and bool(waves) and all(
            re.search(r'Reached cover statement .*\b' + re.escape(label) + r'\b', text)
            for label in labels)
    elif expected == 'PROVED':
        ok = status == 'PASS' and step['returncode'] == 0 and 'successful proof by k-induction' in text
    else:
        raise ValueError('Unknown symbolic expectation: ' + expected)
    return ('PASS', None) if ok else ('FAIL', 'Missing intended ' + expected + ': ' + ', '.join(labels))


def qualify(run, args):
    if args.frontend != 'slang':
        raise ValueError('formal-symbols qualifies the registered Slang recipe with explicit native controls')
    registered = sources('formal')  # Executes the source/header policy first.
    spec = json.loads((ROOT/'verification/formal.json').read_text())['symbolic_qualification']
    if spec['handler'] != 'formal-symbols' or spec['source'] not in registered['sources'] or spec['header'] not in registered['headers']:
        raise ValueError('Unregistered symbolic qualification source/handler')
    case = Case(run, 'symbolic-source-guards')
    step = case.execute([sys.executable, '-m', 'unittest', 'discover', '-s',
                         'tests/toolchain', '-p', 'test_formal_symbols.py', '-v'], timeout=args.timeout)
    text = output(step)
    match = re.search(r'Ran (\d+) tests', text)
    ok = step['result'] == 'PASS' and match and int(match[1]) > 0 and re.search(r'(?m)^OK$', text)
    case.finish('PASS' if ok else step['result'] if step['result'] != 'PASS' else 'FAIL',
                None if ok else 'Source policy/negative classification checks failed')
    # This exact diagnostic fixture is outside production registration. A parser
    # rejection is recorded independently from an executed assertion failure.
    case = Case(run, 'symbolic-unsupported-functions')
    diagnostic = ROOT/'tests/frontends/symbolic_functions.sv'
    script = case.path/'diagnostic.ys'
    script.write_text(read_sources([diagnostic], 'symbolic_functions', frontend='slang', formal=True))
    step = case.execute(['yosys', '-Q', '-T', '-s', str(script)], timeout=args.timeout)
    text = output(step)
    ok = step['returncode'] not in (0, None) and step['result'] != 'TIMEOUT' and all(
        "unknown system name '" + name + "'" in text for name in ('$anyseq', '$anyconst'))
    case.finish('PASS' if ok else step['result'] if step['result'] == 'TIMEOUT' else 'TOOL_ERROR',
                None if ok else 'Missing exact unsupported-function frontend diagnostics',
                observed='FRONTEND_REJECTION', capability='UNSUPPORTED',
                expected='UNKNOWN_SYSTEM_ANYSEQ_AND_ANYCONST', source_sha256=sha(diagnostic))
    for width in spec['widths']:
        for variant, frontend in (('native', 'verilog'), ('decorated', 'slang'),
                                  ('recipe', 'slang'), ('missing-assumption', 'slang')):
            control = variant in ('native', 'decorated')
            source = ROOT / spec['diagnostic_control' if control else 'source']
            top = 'anyconst_control' if control else spec['top']
            for task in ('prove', 'change', 'reach'):
                # Rejected decoration has no meaningful distinct-value recipe.
                if variant == 'decorated' and task == 'reach':
                    continue
                mode = 'prove' if task == 'prove' else 'cover'
                defines = ['OMIT_STABILITY'] if variant == 'missing-assumption' else []
                defines += ['CHANGE_COVER'] if task == 'change' else ['REACH_COVERS'] if task == 'reach' else []
                if task == 'prove':
                    expected = 'ASSERT_FAIL' if variant in ('decorated', 'missing-assumption') else 'PROVED'
                    labels = ['a_constant'] if expected == 'ASSERT_FAIL' else ['a_constant', 'a_reset_constant']
                elif task == 'change':
                    expected = 'REACHED' if variant in ('decorated', 'missing-assumption') else 'UNREACHED'
                    labels = ['c_witness_change']
                else:
                    expected = 'REACHED'
                    labels = ['c_witness_zero', 'c_witness_ones', 'c_stimulus_change', 'c_later_reset']
                case = Case(run, f'symbolic-{variant}-w{width}-{task}')
                header = ROOT/spec['header']
                case.data.update(configuration=dict(spec, width=width), frontend=frontend,
                                 input_digests={str(p.relative_to(ROOT)): sha(p) for p in (source, header)},
                                 expected=expected, property_identities=labels,
                                 capability='REJECTED_SEMANTICS' if variant == 'decorated' else 'QUALIFICATION',
                                 assumptions='Two low startup samples; later reset and stimulus arbitrary; witness held after first sample only in recipe',
                                 method='unbounded k-induction' if task == 'prove' else f'bounded reachability depth {spec["depth"]}')
                config = case.path/'symbolic.sby'
                config.write_text(f'[options]\nmode {mode}\ndepth {spec["depth"]}\n[engines]\n{spec["engine"]}\n[script]\n' +
                                  read_sources([source.name], top, defines=defines, params={'W':width},
                                               frontend=frontend, formal=True) +
                                  f'prep -top {top}\nasync2sync\ndffunmap\nchformal -lower\nwrite_json ../model/symbolic_inventory.json\n[files]\n{source}\n{header}\n')
                step = case.execute(['sby', '-f', '-d', str(case.path/'engine'), str(config)], timeout=args.timeout, cwd=case.path)
                sf = case.path/'engine/status'
                status = sf.read_text().split()[0] if sf.is_file() else None
                waves = [str(p) for p in (case.path/'engine').rglob('*.vcd') if p.stat().st_size]
                result, reason = outcome(step, status, output(step), waves, expected, labels)
                inventory_file = case.path/'engine/model/symbolic_inventory.json'
                inventory = {}
                if inventory_file.is_file():
                    module = json.loads(inventory_file.read_text())['modules'][top]
                    counts = Counter(c['type'] for c in module['cells'].values())
                    inventory = {k: counts[k] for k in ('$assert', '$assume', '$cover', '$anyconst', '$anyseq')}
                    assumptions = 2 if variant == 'recipe' else 1
                    wanted = {'$assert': 2 if task == 'prove' else 0, '$assume': assumptions,
                              '$cover': 1 if task == 'change' else 4 if task == 'reach' else 0,
                              '$anyconst': 1 if variant == 'native' else 0, '$anyseq': 0}
                    ports = {'clk', 'rst_n', 'stimulus'} | (set() if control else {'witness'})
                    properties = {n for n, c in module['cells'].items() if c['type'] in ('$assert', '$cover')}
                    wanted_properties = {'a_constant', 'a_reset_constant'} if task == 'prove' else set(labels)
                    if inventory != wanted or set(module['ports']) != ports or properties != wanted_properties:
                        if result not in ('TIMEOUT', 'INCONCLUSIVE', 'TOOL_ERROR'):
                            result, reason = 'FAIL', 'Symbolic source/property inventory changed'
                elif result != 'TIMEOUT':
                    result, reason = 'TOOL_ERROR', 'Missing elaborated symbolic property inventory'
                case.finish(result, reason, engine_status=status, traces=waves, inventory=inventory,
                            observed='UNREACHED_WITHIN_DEPTH' if result == 'PASS' and expected == 'UNREACHED' else expected if result == 'PASS' else 'UNEXPECTED')
