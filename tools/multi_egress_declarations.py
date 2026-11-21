"""Exercise the standalone multi-egress declarations and fail-closed fixtures."""
from collections import Counter
import json
import re
from shutil import copyfile

from evidence import Case, ROOT, completed, output, sha
from frontend import read_sources
from registry import sources

SOURCE_SET = 'multi-egress-declarations'
TOP = 'tm_multi_ports'
PAIR = 'tm_multi_pair'
LAYOUT = 'tm_multi_layout_top'

# Expected declarations from the interface tables, in primary/small order.
PORTS = {
    'clk': ('input', 1, 1), 'rst_n': ('input', 1, 1), 'epoch_id': ('input', 64, 64),
    'ingress': ('input', 496, 248), 'ingress_ready': ('output', 4, 2),
    'egress': ('output', 460, 226), 'egress_ready': ('input', 4, 2),
    'disposition': ('output', 208, 104), 'cell_read': ('output', 182, 162),
    'cell_write': ('output', 523, 517), 'cell_response': ('input', 694, 674),
    'observation': ('output', 6360, 3589),
    's_axil_awvalid': ('input', 1, 1), 's_axil_awready': ('output', 1, 1),
    's_axil_awaddr': ('input', 32, 32), 's_axil_awprot': ('input', 3, 3),
    's_axil_wvalid': ('input', 1, 1), 's_axil_wready': ('output', 1, 1),
    's_axil_wdata': ('input', 32, 32), 's_axil_wstrb': ('input', 4, 4),
    's_axil_bvalid': ('output', 1, 1), 's_axil_bready': ('input', 1, 1),
    's_axil_bresp': ('output', 2, 2),
    's_axil_arvalid': ('input', 1, 1), 's_axil_arready': ('output', 1, 1),
    's_axil_araddr': ('input', 32, 32), 's_axil_arprot': ('input', 3, 3),
    's_axil_rvalid': ('output', 1, 1), 's_axil_rready': ('input', 1, 1),
    's_axil_rdata': ('output', 32, 32), 's_axil_rresp': ('output', 2, 2),
}
GUARDS = {
    'profile': ('PROFILE', 2, 'PROFILE'),
    'latency-zero': ('MEM_RD_LATENCY', 0, 'READ_LATENCY'),
    'latency-three': ('MEM_RD_LATENCY', 3, 'READ_LATENCY'),
    'ingresses': ('N_RX', 3, 'GEOMETRY'),
    'egresses': ('N_TX', 3, 'GEOMETRY'),
    'classes': ('N_CLASS', 3, 'GEOMETRY'),
    'cell-pool': ('N_CELL', 512, 'GEOMETRY'),
    'descriptor-pool': ('N_DESC', 128, 'GEOMETRY'),
    'frame-limit': ('MAX_FRAME_BYTES', 1535, 'GEOMETRY'),
    'stream-width': ('DATA_W', 32, 'PAYLOAD_WIDTH'),
    'cell-width': ('CELL_W', 256, 'PAYLOAD_WIDTH'),
}
DETECTORS = {
    'reverse-bytes': 'byte-order',
    'truncate-route': 'raw-route',
    'suppress-cleanup': 'cleanup-return',
    'alias-csr': 'csr-address-alias',
    'swap-halves': 'snapshot-word-order',
}
DECLARATION_SWAPS = {
    'egress-source-destination': (
        'rtl/include/multi_egress/tm_multi_types.svh',
        '    tm_multi_fixed::stream_beat_t beat;\n',
        '    rx_id_t source;', '    tx_id_t destination;'
    ),
    'disposition-destination-class': (
        'rtl/include/multi_egress/tm_multi_fixed.sv',
        '        disposition_code_t code;\n        logic [15:0] length;\n',
        '        logic [7:0] destination;', '        logic [7:0] traffic_class;'
    ),
}
GROUPS = ('profile', 'bytes-keeps', 'raw-and-status', 'physical-ports', 'memory',
          'all-return-masks', 'allocation-return-overlap', 'batch-and-correlation')
PROFILES = [(p, latency) for p in (0, 1) for latency in (1, 2)]
PAIR_INSTANCES = {'primary_ports': (0, 2), 'small_ports': (1, 1)}


def ast_nodes(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from ast_nodes(child)
    elif isinstance(value, list):
        for child in value:
            yield from ast_nodes(child)


def range_width(value):
    left, right = map(int, value.strip('[]').split(':'))
    return abs(left - right) + 1


def verilator_shape(path, top, parameters):
    tree = json.loads(path.read_text())
    index = {node['addr']: node for node in ast_nodes(tree) if 'addr' in node}
    modules = {node['name']: node for node in tree['modulesp']}

    def width(reference):
        node = index[reference]
        kind = node['type']
        if kind == 'BASICDTYPE':
            return range_width(node['range']) if 'range' in node else 1
        if kind == 'PARAMTYPEDTYPE':
            return width(node['dtypep'])
        if kind in ('REFDTYPE', 'ENUMDTYPE', 'MEMBERDTYPE'):
            return width(node['refDTypep'])
        if kind == 'PACKARRAYDTYPE':
            return range_width(node['declRange']) * width(node['refDTypep'])
        if kind == 'STRUCTDTYPE':
            return sum(width(member['addr']) for member in node['membersp'])
        raise ValueError('Unexpected Verilator public port type: ' + kind)

    def shape(module, profile, latency):
        rows = module['stmtsp']
        for name, expected in [('PROFILE', profile), ('MEM_RD_LATENCY', latency)]:
            parameter = next(row for row in rows if row.get('name') == name)
            value = int(parameter['valuep'][0]['name'].split('h')[-1], 16)
            if value != expected:
                raise ValueError(f'{name} elaborated as {value}, expected {expected}')
        return {row['name']: (row['direction'].lower(), width(row['dtypep']))
                for row in rows if row.get('varType') == 'PORT'}

    if top == PAIR:
        instances = {row['name']: row['modName'] for row in modules[top]['stmtsp']
                     if row.get('type') == 'CELL'}
        if instances.keys() != PAIR_INSTANCES.keys():
            raise ValueError(f'Unexpected pair instances: {instances}')
        return {name: shape(modules[instances[name]], *settings)
                for name, settings in PAIR_INSTANCES.items()}
    return shape(modules[top], parameters['PROFILE'], parameters['MEM_RD_LATENCY'])


def slang_shape(path, top):
    modules = json.loads(path.read_text())['modules']

    def ports(module):
        return {name: (row['direction'], len(row['bits']))
                for name, row in modules[module]['ports'].items()}

    if top == PAIR:
        instances = modules[top]['cells']
        if instances.keys() != PAIR_INSTANCES.keys():
            raise ValueError(f'Unexpected pair instances: {list(instances)}')
        return {name: ports(instances[name]['type']) for name in PAIR_INSTANCES}
    return ports(top)


def check_port_set(actual, profile):
    expected = {name: (direction, (primary, small)[profile])
                for name, (direction, primary, small) in PORTS.items()}
    mismatch = {name: [expected.get(name), actual.get(name)]
                for name in sorted(expected.keys() | actual.keys())
                if expected.get(name) != actual.get(name)}
    if mismatch:
        raise ValueError(f'Port direction or width mismatch [expected, actual]: {mismatch}')


def elaborate(case, args, tool, registered, parameters=None, guard=None):
    parameters = parameters or {}
    top = TOP if parameters else PAIR
    includes = registered['include_dirs']
    files = [path for path in registered['sources'] if path.startswith('rtl/')]
    if top == PAIR:
        files += [path for path in registered['sources'] if path.endswith('/tm_multi_pair.sv')]
    if tool == 'verilator':
        obj = case.path / 'obj'
        report = obj / ('V' + top + '.tree.json')
        command = ['verilator', '--json-only', '--top-module', top, '--Mdir', str(obj)]
        if top == PAIR:
            command += ['-Wno-PINMISSING']  # Non-probed pins on this fixture only.
        command += ['-I' + path for path in includes]
        command += [f'-G{name}={value}' for name, value in parameters.items()] + files
    else:
        report = case.path / 'ports.json'
        script = case.path / 'elaborate.ys'
        commands = read_sources(files, top, includes, params=parameters, frontend=args.frontend)
        if top == PAIR:
            commands = commands.replace('read_slang ', 'read_slang --keep-hierarchy '
                '-Wno-unconnected-input-port -Wno-unconnected-output-port ', 1)
        script.write_text(commands + f'write_json {report}\n')
        command = ['yosys', '-Q', '-T', '-s', str(script)]
    case.data.update(parameters=parameters, paired=PAIR_INSTANCES if top == PAIR else None,
                     source_set=SOURCE_SET)
    step = case.execute(command, timeout=args.timeout)
    if guard:
        diagnostics = [line for line in output(step).splitlines()
                       if re.search(r'%Error|ERROR:', line)]
        sentinels = set(re.findall(r'TM_MULTI_INVALID_[A-Z_]+', '\n'.join(diagnostics)))
        ok = step['result'] == 'TOOL_ERROR' and step['returncode'] not in (None, 0) and sentinels == {guard}
        case.finish('PASS' if ok else 'FAIL', None if ok else 'Expected named elaboration guard',
                    expected='INVALID_ELABORATION', guard=guard, observed_guards=sorted(sentinels))
        return

    result, reason = completed(step, 'Verilator: Walltime' if tool == 'verilator' else 'Build succeeded')
    if result == 'PASS':
        try:
            shape = verilator_shape(report, top, parameters) if tool == 'verilator' else slang_shape(report, top)
            if top == PAIR:
                for name, (profile, _) in PAIR_INSTANCES.items():
                    check_port_set(shape[name], profile)
            else:
                check_port_set(shape, parameters['PROFILE'])
        except (OSError, KeyError, TypeError, ValueError, StopIteration) as error:
            result, reason = 'FAIL', str(error) or 'Missing elaborated parameter'
    case.finish(result, reason, port_report=str(report))


def build_layout(case, args, registered, cwd=None):
    binary = case.path / 'obj' / ('V' + LAYOUT)
    files = [path for path in registered['sources'] if not path.endswith('/tm_multi_pair.sv')]
    command = ['verilator', '--binary', '--timing', '--assert', '--timescale', '1ns/1ps',
               '--build-jobs', str(args.jobs), '--top-module', LAYOUT, '--Mdir', str(binary.parent)]
    command += ['-I' + path for path in registered['include_dirs']] + files
    step = case.execute(command, cwd=cwd, timeout=args.build_timeout)
    result, reason = completed(step, 'Verilator: Walltime')
    if result == 'PASS' and not binary.is_file():
        result, reason = 'TOOL_ERROR', 'Missing compiled layout executable'
    return binary, result, reason


def qualify_declaration_swap(case, args, registered, name, legal_result):
    filename, prefix, first, second = DECLARATION_SWAPS[name]
    detector = name + '-layout'
    case.data.update(expected='PLANTED_DECLARATION_SWAP', detector=detector,
                     legal_neighbor=legal_result, mutated_file=filename,
                     swapped=[first.strip(), second.strip()])
    if legal_result != 'PASS':
        case.finish('NOT_RUN', 'Legal layout fixture did not pass')
        return

    fixture = case.path / 'sources'
    # Compile exclusively from this copy so include lookup cannot pick the unchanged header.
    for path in registered['sources'] + registered['headers']:
        destination = fixture / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        copyfile(ROOT / path, destination)
    declaration = fixture / filename
    source = declaration.read_text()
    before = f'{prefix}{first}\n{second}\n'
    if source.count(before) != 1:
        case.finish('FAIL', 'Expected exactly one adjacent field pair to swap')
        return
    declaration.write_text(source.replace(before, f'{prefix}{second}\n{first}\n', 1))
    case.data['mutated_sha256'] = sha(declaration)

    binary, result, reason = build_layout(case, args, registered, cwd=fixture)
    if result != 'PASS':
        case.finish(result, reason)
        return

    observed = {}
    for profile in (0, 1):
        step = case.execute([binary, f'+layout-profile={profile}'], cwd=case.path,
                            timeout=args.timeout, stem=f'profile{profile}')
        text = output(step)
        detected = re.findall(r'TM03_DETECT ([^\s]+) profile=(\d+) latency=([12])\b', text)
        ok = (step['result'] == 'TOOL_ERROR' and step['returncode'] not in (None, 0)
              and text.count('TM03_DETECT') == 1 and len(detected) == 1
              and detected[0][:2] == (detector, str(profile)) and 'TM03_LAYOUT_PASS' not in text)
        observed[profile] = dict(detected=detected, returncode=step['returncode'], passed=ok)
    ok = all(record['passed'] for record in observed.values())
    case.finish('PASS' if ok else 'FAIL', None if ok else 'Expected named detector in both profiles',
                observed=observed)


def simulate(run, args, registered):
    build = Case(run, 'layout-build')
    binary, result, reason = build_layout(build, args, registered)
    build.finish(result, reason)

    positive = Case(run, 'layout-legal-neighbors')
    if result != 'PASS':
        positive.finish('NOT_RUN', 'Layout compilation failed')
        for mutation in DETECTORS:
            Case(run, 'planted-' + mutation).finish('NOT_RUN', 'Layout compilation failed')
        for name in DECLARATION_SWAPS:
            Case(run, 'planted-swap-' + name).finish('NOT_RUN', 'Layout compilation failed')
        return

    step = positive.execute([binary], cwd=positive.path, timeout=args.timeout)
    result, reason = completed(step, 'TM03_LAYOUT_PASS')
    markers = Counter(line for line in output(step).splitlines() if line.startswith('TM03_'))
    wanted = Counter(f'TM03_CASE {group} profile={p} latency={latency}'
                     for p, latency in PROFILES for group in GROUPS)
    wanted.update(['TM03_CSR_MAP ports=4 words=1135', 'TM03_CSR_MAP ports=2 words=573',
                   'TM03_CSR_SNAPSHOT ports=4 words=4', 'TM03_CSR_SNAPSHOT ports=2 words=4',
                   'TM03_LAYOUT_PASS'])
    if result == 'PASS' and markers != wanted:
        result, reason = 'FAIL', f'Missing {list((wanted-markers).elements())} or unexpected {list((markers-wanted).elements())}'
    positive.finish(result, reason, observed=dict(markers))

    for mutation, detector in DETECTORS.items():
        case = Case(run, 'planted-' + mutation)
        step = case.execute([binary, '+' + mutation], cwd=case.path, timeout=args.timeout)
        detected = re.findall(r'TM03_DETECT ([^\s]+)', output(step))
        ok = result == 'PASS' and step['result'] == 'TOOL_ERROR' and step['returncode'] not in (None, 0)
        ok = ok and detected == [detector] and 'TM03_LAYOUT_PASS' not in output(step)
        case.finish('PASS' if ok else 'FAIL', None if ok else 'Missing designated detection or passing neighbor',
                    expected='PLANTED_FIXTURE_DEFECT', detector=detector, observed_detectors=detected,
                    legal_neighbor=positive.data['result'])

    for name in DECLARATION_SWAPS:
        qualify_declaration_swap(Case(run, 'planted-swap-' + name), args, registered,
                                 name, positive.data['result'])


def declarations(run, args):
    run.scope = 'Multi-egress declaration elaboration and wire/CSR layout fixtures'
    registered = sources(SOURCE_SET)
    for tool in ('verilator', 'slang'):
        for profile, latency in PROFILES:
            name = f'{tool}-profile{profile}-latency{latency}'
            elaborate(Case(run, name), args, tool, registered,
                      {'PROFILE': profile, 'MEM_RD_LATENCY': latency})
        elaborate(Case(run, tool + '-paired'), args, tool, registered)
        for name, (parameter, value, guard) in GUARDS.items():
            elaborate(Case(run, tool + '-invalid-' + name), args, tool, registered,
                      {'PROFILE': 0, 'MEM_RD_LATENCY': 1, parameter: value}, 'TM_MULTI_INVALID_' + guard)
    simulate(run, args, registered)
