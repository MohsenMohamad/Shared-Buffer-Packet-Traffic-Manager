"""Actual production pool mapping/STA under the precommitted study definition."""
import json
import re
from collections import Counter, defaultdict

from evidence import Case, ROOT, output, sha
from frontend import read_sources
from registry import profile, sources

EXPERIMENT = ROOT / 'experiments/allocator-scaling'
DIAGNOSTIC = re.compile(r'(?im)^\s*(?:Error|Warning)(?:\s+\d+)?\s*:')


def timing_measurements(text):
    """Completion never overrides diagnostics, incomplete coverage or empty paths."""
    if DIAGNOSTIC.search(text) or text.count('TM_STA_DONE') != 1:
        raise ValueError('STA warning/error or missing/duplicate completion')
    if text.count('TM_COVERAGE_DONE') != 1:
        raise ValueError('Missing constraint coverage check')
    result = {}
    for group in ('OVERALL', 'selection', 'availability', 'count'):
        for delay in ('max', 'min'):
            tag = f'TM_{group}_{delay}'
            if text.count(tag + '_BEGIN') != 1 or text.count(tag + '_END') != 1:
                raise ValueError('Missing/duplicate timing section: ' + tag)
            section = text.split(tag + '_BEGIN')[1].split(tag + '_END')[0]
            paths = []
            for block in section.split('Startpoint: ')[1:]:
                endpoint = re.search(r'^Endpoint: (.+)', block, re.M)
                path_group = re.search(r'^Path Group: (.+)', block, re.M)
                arrival = re.search(r'([-+]?\d+\.\d+)\s+data arrival time', block)
                slack = re.search(r'([-+]?\d+\.\d+)\s+slack', block)
                if not all((endpoint, path_group, arrival, slack)):
                    raise ValueError('Incomplete path: ' + tag)
                paths.append(dict(startpoint=block.splitlines()[0], endpoint=endpoint[1],
                                  group=path_group[1], arrival_ns=float(arrival[1]),
                                  slack_ns=float(slack[1]),
                                  cell_arcs=len(re.findall(r'\([^()]+_X\d+\)', block.split('data arrival time')[0]))))
            if not paths:
                raise ValueError('Empty constrained path section: ' + tag)
            result[group.lower() + '_' + delay] = min(paths, key=lambda p: p['slack_ns'])
            if group == 'OVERALL':
                result['groups_' + delay] = paths
    result['check_types_report'] = text.split('TM_CHECK_TYPES_BEGIN')[1].split('TM_CHECK_TYPES_END')[0].strip()
    return result


def mapping_measurements(module, expected_state):
    cells = module['cells']
    histogram = dict(Counter(c['type'] for c in cells.values()))
    state = sum(n for typ, n in histogram.items() if typ.startswith('DFF'))
    if not cells or any(t.startswith('$') for t in histogram) or state != expected_state:
        raise ValueError(f'Incomplete mapping/state: {state}, expected {expected_state}')
    drivers, sinks, names = {}, defaultdict(list), defaultdict(list)
    for name, net in module['netnames'].items():
        for bit in net['bits']:
            names[bit].append(name)
    for name, cell in cells.items():
        for port, bits in cell['connections'].items():
            for bit in bits:
                if cell['port_directions'][port] == 'input':
                    sinks[bit].append(name + '/' + port)
                else:
                    drivers[bit] = name + '/' + port
    roots = {}
    for port, kind in (('clk', 'clock'), ('rst_n', 'reset')):
        roots.update({b: kind for b in module['ports'][port]['bits']})
    # Classify reset/clock buffering trees as well as the original input nets.
    changed = True
    while changed:
        changed = False
        for cell in cells.values():
            if not cell['type'].startswith(('BUF_X', 'INV_X')):
                continue
            inputs = [b for p, bs in cell['connections'].items() if cell['port_directions'][p] == 'input' for b in bs]
            outputs = [b for p, bs in cell['connections'].items() if cell['port_directions'][p] == 'output' for b in bs]
            if len(inputs) == 1 and inputs[0] in roots:
                for bit in outputs:
                    if bit not in roots:
                        roots[bit] = roots[inputs[0]]
                        changed = True
    nets = [dict(driver=drivers.get(b, 'input:' + ','.join(names[b])),
                 aliases=sorted(names[b]), sink_pins=len(pins), kind=roots.get(b, 'data'))
            for b, pins in sinks.items() if isinstance(b, int)]
    fanout = {kind: sorted((n for n in nets if n['kind'] == kind), key=lambda n: -n['sink_pins'])[:5]
              for kind in ('data', 'reset', 'clock')}
    ports = {name: dict(direction=p['direction'], width=len(p['bits']),
                       loaded_bits=sum(bool(sinks[b]) for b in p['bits']))
             for name, p in module['ports'].items()}
    outputs = {name: len(p['bits']) for name, p in module['ports'].items() if p['direction'] == 'output'}
    if set(outputs) != {'available_id', 'free_count', 'available', 'invariant_error'}:
        raise ValueError('Missing production output')
    if any(b not in drivers for p in module['ports'].values() if p['direction'] == 'output' for b in p['bits']):
        raise ValueError('Undriven/constant production output')
    return dict(mapped_cells=histogram, state_bits=state, outputs=outputs, ports=ports,
                fanout=fanout, buffers=sum(n for t, n in histogram.items() if t.startswith('BUF_X')))


def characterize(run, args):
    definition = json.loads((EXPERIMENT / 'config.json').read_text())
    deps = json.loads((ROOT / 'tools/dependencies.json').read_text())
    liberty = ROOT / '.deps/liberty.lib'
    if sha(liberty) != deps['liberty']['sha256']:
        raise ValueError('Liberty digest differs from qualified lock')
    if any(c.data.get('result') != 'PASS' for c in run.cases):
        raise ValueError('Qualified doctor required before characterization')
    registered = sources(definition['source_set'])
    definition_digests = {str(p.relative_to(ROOT)): sha(p) for p in sorted(EXPERIMENT.iterdir()) if p.is_file()}
    for profile_name in definition['profiles']:
        params = profile(profile_name)
        for pool, top in definition['pools'].items():
            case = Case(run, f'allocator-{profile_name}-{pool}')
            case.data.update(parameters=params, definition_digests=definition_digests,
                             registered_sources=registered, liberty_sha256=sha(liberty),
                             profile=profile_name, pool=pool)
            capacity = params['N_CELL' if pool == 'cell' else 'N_DESC']
            expected_state = capacity + capacity.bit_length() + 1
            netlist, mapped, stats = (case.path / name for name in ('mapped.v', 'mapped.json', 'stats.json'))
            substitutions = dict(READ=read_sources(registered['sources'], top, registered['include_dirs'],
                                                  params=params, frontend=definition['frontend']).strip(),
                                 TOP=top, LIBERTY=liberty, ABC_CONSTR=EXPERIMENT / 'abc.constr',
                                 NETLIST=netlist, JSON=mapped, STATS=stats)
            script = (EXPERIMENT / 'mapping.ys.in').read_text()
            for key, value in substitutions.items():
                script = script.replace('@' + key + '@', str(value))
            script_path = case.path / 'mapping.ys'
            script_path.write_text(script)
            step = case.execute(['yosys', '-Q', '-T', '-s', str(script_path)],
                                timeout=definition['synthesis_timeout_s'])
            if step['result'] != 'PASS':
                case.finish(step['result'], step['first_failure'])
                continue
            try:
                measurements = mapping_measurements(json.loads(mapped.read_text())['modules'][top], expected_state)
                measurements['area_um2'] = json.loads(stats.read_text())['modules']['\\' + top]['area']
                measurements['capacity'] = capacity
                case.finish('PASS', measurements=measurements, netlist_sha256=sha(netlist),
                            script_sha256=sha(script_path))
            except (OSError, KeyError, ValueError) as error:
                case.finish('FAIL', str(error))
                continue
            for mode in definition['sta_modes']:
                timing = Case(run, f'allocator-sta-{profile_name}-{pool}-{mode}')
                timing.data.update(profile=profile_name, pool=pool, mode=mode,
                                   definition_digests=definition_digests, netlist_sha256=sha(netlist),
                                   liberty_sha256=sha(liberty))
                # Per-process environment avoids leaking one point into another.
                import os
                from evidence import execute
                env = dict(os.environ, TM_LIBERTY=str(liberty), TM_NETLIST=str(netlist),
                           TM_TOP=top, TM_SDC=str(EXPERIMENT / 'timing.sdc'), TM_DRIVE_MODE=mode)
                step = execute(['sta', '-no_init', '-exit', str(EXPERIMENT / 'timing.tcl')],
                               timing.path, 'sta', definition['sta_timeout_s'], env=env)
                timing.data['steps'].append(step)
                if step['result'] != 'PASS':
                    timing.finish(step['result'], step['first_failure'])
                    continue
                try:
                    data = timing_measurements(output(step))
                    timing.finish('PASS', measurements=data,
                                  timing_closure='PASS' if all(data[g + '_' + d]['slack_ns'] >= 0
                                                             for g in ('overall',) for d in ('max', 'min')) else 'FAIL')
                except (ValueError, KeyError, IndexError) as error:
                    timing.finish('FAIL', str(error))
