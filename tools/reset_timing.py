"""Focused actual mapped FIFO/allocator qualification of the frozen R01 model."""
from collections import Counter, defaultdict
from copy import deepcopy
import json
import os
import re

from allocator_scaling import mapping_measurements
from evidence import Case, ROOT, execute, output, sha
from frontend import read_sources
from registry import profile, sources
from timing_constraints import CONFIG, constraints, render

EXPERIMENT = CONFIG.parent
DIAGNOSTIC = re.compile(r'(?im)^\s*(?:Error|Warning)(?:\s+\d+)?\s*:')
BASE_GROUPS = ('overall', 'data', 'data_rr', 'data_ir', 'data_ro', 'data_io', 'reset_checks', 'reset_effects')


def measurements(text, model, allocator):
    if DIAGNOSTIC.search(text) or text.count('R01_DONE') != 1:
        raise ValueError('STA diagnostic or incomplete execution')
    coverage = re.findall(r'^R01_COVERAGE (\d+) (\d+) (\d+)$', text, re.M)
    if len(coverage) != 1 or any(int(n) == 0 for n in coverage[0]):
        raise ValueError('Missing nonempty endpoint coverage')
    data = dict(coverage=dict(zip(('output_bits', 'registers', 'async_pins'), map(int, coverage[0]))), paths={})
    groups = BASE_GROUPS + (('selection', 'availability', 'count') if allocator else ())
    for group in groups:
        for delay in ('max', 'min'):
            tag = f'R01_{group}_{delay}'
            if text.count(tag + '_BEGIN') != 1 or text.count(tag + '_END') != 1:
                raise ValueError('Missing timing section: ' + tag)
            section = text.split(tag + '_BEGIN')[1].split(tag + '_END')[0]
            paths = []
            for block in section.split('Startpoint: ')[1:]:
                def field(pattern):
                    match = re.search(pattern, block, re.M)
                    if match is None:
                        raise ValueError('Incomplete path in ' + tag)
                    return match[1]
                arrival = float(field(r'([-+]?\d+\.\d+)\s+data arrival time'))
                paths.append(dict(startpoint=block.splitlines()[0], endpoint=field(r'^Endpoint: (.+)'),
                                  path_group=field(r'^Path Group: (.+)'), arrival_ns=arrival,
                                  slack_ns=float(field(r'([-+]?\d+\.\d+)\s+slack'))))
                # The last cell/port row before arrival names the actual path pin.
                rows = re.findall(r'^.*?\s([\w.\[\]/]+) \([^()]+\)\s*$', block.split('data arrival time')[0], re.M)
                paths[-1]['endpoint_pin'] = rows[-1] if rows else paths[-1]['endpoint']
                if group.startswith('data') or group == 'reset_effects':
                    if paths[-1]['path_group'] != 'clk':
                        raise ValueError('Asynchronous check in data/reset-effects category')
                if group == 'reset_checks':
                    check = 'recovery' if delay == 'max' else 'removal'
                    port_row = re.search(r'^\s*\d+\s+([-+]?\d+\.\d+)\s+([-+]?\d+\.\d+)\s+([-+]?\d+\.\d+)\s+([-+]?\d+\.\d+)\s+\^ rst_n \(in\)\s*$', block, re.M)
                    if port_row is None:
                        raise ValueError('Missing rising reset port event')
                    paths[-1].update(port_capacitance_ff=float(port_row[1]), port_slew_ns=float(port_row[2]),
                                     virtual_driver_delay_ns=float(port_row[3]), port_arrival_ns=float(port_row[4]))
                    if not re.search(r'library ' + check + r' time', block):
                        raise ValueError('Required reset check type absent: ' + check)
            if not paths:
                if group != 'data_io' or section.strip() != 'R01_NOT_PRESENT':
                    raise ValueError('Empty timing section: ' + tag)
                data['paths'][group + '_' + delay] = None
            else:
                data['paths'][group + '_' + delay] = min(paths, key=lambda p: p['slack_ns'])
    paths = data['paths']
    phase = model['period_ns'] / 2 if model['edge'] == 'fall' else 0
    lower = phase + model['reset_min_ns'] - paths['reset_checks_min']['slack_ns']
    upper = phase + model['reset_max_ns'] + paths['reset_checks_max']['slack_ns']
    # A rising launch belongs to the window after that rise and before the next.
    data['required_source_delay_window_ns_after_rise'] = [round(lower, 5), round(upper, 5)]
    port_min = paths['reset_checks_min']['port_arrival_ns']
    port_max = paths['reset_checks_max']['port_arrival_ns']
    data['modeled_port_release_ns_after_rise'] = [port_min, port_max]
    data['required_port_release_window_ns_after_rise'] = [
        round(port_min - paths['reset_checks_min']['slack_ns'], 5),
        round(port_max + paths['reset_checks_max']['slack_ns'], 5)]
    data['release_window_nonempty'] = lower <= upper
    data['category_closure'] = {
        category: 'PASS' if all(paths[group + '_' + delay]['slack_ns'] >= 0
                               for delay in ('max', 'min')) else 'FAIL'
        for category, group in (('data_setup_hold', 'data'), ('reset_recovery_removal', 'reset_checks'),
                                ('reset_effects', 'reset_effects'))}
    data['electrical'] = {}
    for name in ('max slew', 'max capacitance'):
        section = re.search(r'\n' + name + r'\n.*?^-+\n([^\n]+)', text, re.M | re.S)
        if section is None:
            raise ValueError('Missing electrical report: ' + name)
        row = re.fullmatch(r'(\S+)\s+([-+]?\d+\.\d+)\s+([-+]?\d+\.\d+)\s+([-+]?\d+\.\d+)\s+\((?:MET|VIOLATED)\)', section[1])
        if row is None:
            raise ValueError('Incomplete electrical report: ' + name)
        data['electrical'][name] = dict(pin=row[1], limit=float(row[2]), actual=float(row[3]), slack=float(row[4]))
    data['category_closure']['electrical'] = 'PASS' if all(e['slack'] >= 0 for e in data['electrical'].values()) else 'FAIL'
    data['model_closure'] = 'PASS' if all(v == 'PASS' for v in data['category_closure'].values()) else 'FAIL'
    data['source_closure'] = 'UNRESOLVED'
    return data


def structure(module, point, params):
    if 'fifo' not in point['name']:
        capacity = params['N_CELL' if point['top'] == 'tm_cell_pool_api' else 'N_DESC']
        result = mapping_measurements(module, capacity + capacity.bit_length() + 1)
    else:
        depth = point['depth']
        beat_width = params['DATA_W'] + params['DATA_W'] // 8 + 65
        expected = beat_width * depth + 2 * (depth - 1).bit_length() + depth.bit_length() + 1
        histogram = Counter(c['type'] for c in module['cells'].values())
        if any(t.startswith('$') or t.startswith('LAT') for t in histogram):
            raise ValueError('Unmapped cells or latches')
        state = sum(n for t, n in histogram.items() if t.startswith('DFF'))
        if state != expected:
            raise ValueError(f'FIFO state {state} != {expected}')
        outputs = {name: len(p['bits']) for name, p in module['ports'].items() if p['direction'] == 'output'}
        if outputs != dict(s_ready=1, m_valid=1, empty=1, m_beat=beat_width):
            raise ValueError('Incomplete FIFO outputs')
        driven = {b for c in module['cells'].values() for p, bs in c['connections'].items()
                  if c['port_directions'][p] == 'output' for b in bs}
        if any(b not in driven for p in module['ports'].values() if p['direction'] == 'output' for b in p['bits']):
            raise ValueError('Undriven or constant FIFO output')
        result = dict(state_bits=state, mapped_cells=dict(histogram), outputs=outputs,
                      payload_bits=beat_width * depth)
    sinks = defaultdict(list)
    reset_bits = set(module['ports']['rst_n']['bits'])
    async_pins = []
    for name, cell in module['cells'].items():
        for pin, bits in cell['connections'].items():
            if cell['port_directions'][pin] == 'input':
                for bit in bits:
                    sinks[bit].append(name + '/' + pin)
            if cell['type'].startswith('DFF') and pin in ('RN', 'SN'):
                async_pins.append(name + '/' + pin)
    # Propagate reset classification only through mapped buffers/inverters.
    changed = True
    while changed:
        changed = False
        for cell in module['cells'].values():
            ins = [b for p, bs in cell['connections'].items() if cell['port_directions'][p] == 'input' for b in bs]
            outs = [b for p, bs in cell['connections'].items() if cell['port_directions'][p] == 'output' for b in bs]
            if cell['type'].startswith(('BUF_X', 'INV_X')) and len(ins) == 1 and ins[0] in reset_bits:
                for bit in outs:
                    if bit not in reset_bits:
                        reset_bits.add(bit)
                        changed = True
    result['reset_fanout'] = dict(root_sink_pins=sum(len(sinks[b]) for b in module['ports']['rst_n']['bits']),
                                  async_pin_count=len(async_pins), tree_net_count=len(reset_bits),
                                  max_tree_sink_pins=max(len(sinks[b]) for b in reset_bits))
    return result


def sta(case, netlist, point, model, mapped_structure, negative=None):
    sdc = render(model)
    expected = None
    if negative == 'missing-reset-min':
        sdc = '\n'.join(line for line in sdc.splitlines() if not (line.startswith('set_input_delay -min') and line.endswith('$reset'))) + '\n'
        expected = 'R01_MISSING_RESET_min'
    elif negative == 'missing-reset-max':
        sdc = '\n'.join(line for line in sdc.splitlines() if not (line.startswith('set_input_delay -max') and line.endswith('$reset'))) + '\n'
        expected = 'R01_MISSING_RESET_max'
    elif negative == 'missing-reset-port':
        sdc = sdc.replace('set reset [get_ports rst_n]', 'set reset [get_ports no_such_reset]')
        expected = 'R01_RESET_PORT'
    elif negative in ('false-path-reset', 'drop-removal'):
        sdc += ('set_false_path -from [get_ports rst_n]\n' if negative == 'false-path-reset' else
                'set_disable_timing -from CK -to RN [all_registers]\n')
        expected = 'R01_TIMING_EXCEPTION'
    elif negative == 'bad-command':
        sdc += 'r01_deliberate_bad_command\n'
        expected = 'r01_deliberate_bad_command'
    sdc_path = case.path / 'timing.sdc'
    sdc_path.write_text(sdc)
    env = dict(os.environ, TM_NETLIST=str(netlist), TM_LIBERTY=str(ROOT / '.deps/liberty.lib'),
               TM_SDC=str(sdc_path), TM_TOP=point['top'], TM_RESET_MIN=str(model['reset_min_ns']),
               TM_RESET_MAX=str(model['reset_max_ns']), TM_RESET_EDGE=model['edge'])
    step = execute(['sta', '-no_init', '-exit', str(EXPERIMENT / 'timing.tcl')], case.path, 'sta', 300, env=env)
    case.data['steps'].append(step)
    case.data.update(model=model, netlist_sha256=sha(netlist), sdc_sha256=sha(sdc_path))
    if negative:
        ok = step['result'] != 'TIMEOUT' and expected in output(step) and DIAGNOSTIC.search(output(step)) is not None
        case.finish('PASS' if ok else 'FAIL', None if ok else 'Intended constraint rejection absent',
                    expected_negative=negative, intended_detector=expected, measurement_valid=False)
        return
    if step['result'] != 'PASS':
        case.finish(step['result'], step['first_failure'])
        return
    try:
        data = measurements(output(step), model, 'fifo' not in point['name'])
        expected = dict(output_bits=sum(mapped_structure['outputs'].values()),
                        registers=mapped_structure['state_bits'],
                        async_pins=mapped_structure['reset_fanout']['async_pin_count'])
        if data['coverage'] != expected:
            raise ValueError('STA endpoint inventory differs from mapped structure')
        case.finish('PASS', measurement_valid=True, measurements=data)
    except (ValueError, KeyError, IndexError) as error:
        case.finish('FAIL', str(error))


def characterize(run, args):
    run.scope = 'R01 actual standalone mapped FIFO/allocator; valid execution is separate from closure; physical source unresolved'
    config = json.loads(CONFIG.read_text())
    liberty = ROOT / '.deps/liberty.lib'
    if sha(liberty) != config['library_sha256'] or any(c.data.get('result') != 'PASS' for c in run.cases):
        raise ValueError('Locked library and doctor PASS required')
    registered = sources('synthesis')
    maps = {}
    for point in config['points']:
        params = profile(point['profile'])
        if 'depth' in point:
            params['RX_FIFO_DEPTH'] = point['depth']
        case = Case(run, 'r01-map-' + point['name'])
        case.data.update(point=point, parameters=params, registered_sources=registered)
        paths = {key: case.path / filename for key, filename in
                 (('NETLIST', 'mapped.v'), ('JSON', 'mapped.json'), ('STATS', 'stats.json'))}
        values = dict(READ=read_sources(registered['sources'], point['top'], registered['include_dirs'], params=params).strip(),
                      TOP=point['top'], LIBERTY=liberty, ABC_CONSTR=ROOT / 'experiments/allocator-scaling/abc.constr', **paths)
        script = (ROOT / 'experiments/allocator-scaling/mapping.ys.in').read_text()
        for key, value in values.items():
            script = script.replace('@' + key + '@', str(value))
        script_path = case.path / 'mapping.ys'
        script_path.write_text(script)
        step = case.execute(['yosys', '-Q', '-T', '-s', str(script_path)], timeout=config['synthesis_timeout_s'])
        if step['result'] != 'PASS':
            case.finish(step['result'], step['first_failure'])
            continue
        try:
            data = structure(json.loads(paths['JSON'].read_text())['modules'][point['top']], point, params)
            data['area_um2'] = json.loads(paths['STATS'].read_text())['modules']['\\' + point['top']]['area']
            case.finish('PASS', measurements=data, netlist_sha256=sha(paths['NETLIST']),
                        mapping_script_sha256=sha(script_path))
        except (ValueError, KeyError, OSError) as error:
            case.finish('FAIL', str(error))
            continue
        maps[point['name']] = (paths['NETLIST'], data)
        for scenario in config['scenarios']:
            for mode in config['modes']:
                case = Case(run, f'r01-{point["name"]}-{scenario}-{mode}')
                case.data['point'] = point
                sta(case, paths['NETLIST'], point, constraints(config, point['study'], scenario, mode), data)
    for point in (config['points'][0], config['points'][2]):
        for negative in config['negative_cases']:
            case = Case(run, f'r01-negative-{point["name"]}-{negative}')
            if point['name'] not in maps:
                case.finish('NOT_RUN', 'Mapped representative unavailable')
                continue
            bad = deepcopy(config)
            scenario = 'fall-reference-r01'
            if negative == 'reversed-envelope':
                bad['scenarios'][scenario]['reset_min_ns'] = 0.3
                try:
                    constraints(bad, point['study'], scenario, 'slew')
                except ValueError as error:
                    case.finish('PASS', expected_negative=negative, intended_detector=str(error), measurement_valid=False)
                else:
                    case.finish('FAIL', 'Reversed envelope accepted')
            else:
                sta(case, maps[point['name']][0], point, constraints(config, point['study'], scenario, 'slew'), maps[point['name']][1], negative)
