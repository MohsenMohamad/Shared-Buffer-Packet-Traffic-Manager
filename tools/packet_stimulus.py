"""Inspect saved generated packets against independent handshakes and coverage."""
from collections import Counter, defaultdict
import hashlib
import json


def records(path):
    rows = [json.loads(line) for line in path.read_text().splitlines()]
    if not rows:
        raise ValueError(f'Empty recorded stimulus/evidence: {path.name}')
    return rows


def normalized_beat(row):
    return dict(data=int(row['data'], 16), keep=row['keep'], last=row['last'], user=int(row['user'], 16))


def payload_byte(pattern, seed, offset):
    if pattern == 0:
        return (seed + offset) & 255
    if pattern == 1:
        return seed & 255
    if pattern == 2:
        return (0x55 if offset % 2 == 0 else 0xaa) ^ (seed & 255)
    mixed = (seed ^ (offset * 0x9e3779b9)) & 0xffffffff
    mixed ^= (mixed << 13) & 0xffffffff
    mixed ^= mixed >> 17
    mixed ^= (mixed << 5) & 0xffffffff
    return mixed & 255


def histogram(rows, field, values):
    counts = Counter(row[field] for row in rows)
    return {str(value): counts[value] for value in values}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def compare_handshakes(captures, statuses, outputs, observed, n_rx):
    """Check exact captured beats and dispositions; compare valid output bytes."""
    actual_captures, actual_statuses = defaultdict(list), defaultdict(list)
    actual_outputs = []
    last_stamp = {}
    for row in observed:
        kind, source = row['kind'], row['source']
        require(kind in ('capture', 'output', 'status') and 0 <= source < n_rx, 'Invalid observed handshake')
        key = kind, source
        stamp = row['epoch'], row['cycle']
        require(key not in last_stamp or stamp > last_stamp[key], 'Duplicate/stale observed handshake')
        last_stamp[key] = stamp
        if kind == 'capture':
            actual_captures[source].append(normalized_beat(row))
        elif kind == 'status':
            actual_statuses[source].append({k: row[k] for k in ('code', 'qid', 'length', 'tag')})
        else:
            actual_outputs.append(normalized_beat(row))
    require(dict(actual_captures) == dict(captures), 'Generated beats do not equal accepted input handshakes')
    require(dict(actual_statuses) == dict(statuses), 'Missing/wrong directed or legal disposition')
    require(len(actual_outputs) == len(outputs), 'Missing/duplicate observed output beats')
    for expected, actual in zip(outputs, actual_outputs):
        require(all(actual[k] == expected[k] for k in ('keep', 'last', 'user')), 'Observed output framing/metadata mismatch')
        for lane in range(8):
            if expected['keep'] & (1 << lane):
                require((actual['data'] >> (lane*8)) & 255 == (expected['data'] >> (lane*8)) & 255,
                        'Observed output payload mismatch')



def inspect_stimulus(path, parameters, saved_coverage):
    """Fail closed on missing records, ignored constraints or traffic not captured.

    This audits a serial generator-qualification scenario, not the TM admission
    algorithm. The UVM byte/service/policy checkers remain monitor-derived.
    """
    packets = records(path / 'stimulus.jsonl')
    observed = records(path / 'handshakes.jsonl')
    n_rx, n_q = parameters['N_RX'], parameters['N_Q']
    maximum, cell_bytes = parameters['MAX_PACKET_BYTES'], parameters['CELL_BYTES']
    require(len(packets) == 155 + n_q, 'Unexpected generated packet count')
    require([p['index'] for p in packets] == list(range(len(packets))), 'Missing/reordered packet records')
    phases = Counter(p['phase'] for p in packets)
    require(phases == Counter({'boundary': 9, 'keep-width': 8, 'profile-lanes': n_q, 'random': 128,
                              **{f'directed-{i}': 1 for i in range(10)}}), 'Wrong scenario selection')
    captures, statuses = defaultdict(list), defaultdict(list)
    outputs = []
    legal_packets = []
    for packet in packets:
        source = packet['source']
        require(0 <= source < n_rx, 'Generated source outside selected profile')
        beats = [normalized_beat(beat) for beat in packet['beats']]
        require(bool(beats), 'Empty generated packet')
        captures[source].extend(beats)
        header = beats[0]['user']
        statuses[source].append(dict(code=packet['expected_status'], qid=header & 255,
                                     length=(header >> 8) & 65535, tag=(header >> 24) & 65535))
        directed = packet['phase'].startswith('directed-')
        if not directed:
            length = packet['length']
            require(1 <= length <= maximum and 0 <= packet['qid'] < n_q, 'Illegal constrained header')
            require(packet['pattern'] in range(4) and packet['gap'] in range(4), 'Illegal pattern/gap')
            require(packet['class'] in range(4), 'Illegal length class')
            allowed = {0: {1, 7, 8, 9}, 1: {cell_bytes-1, cell_bytes, cell_bytes+1},
                       2: {maximum-1, maximum}}
            require(packet['class'] == 3 or length in allowed[packet['class']], 'Ignored class/length constraint')
            require(packet['beat_count'] == len(beats) == (length+7)//8 and
                    packet['cell_count'] == (length+cell_bytes-1)//cell_bytes and
                    packet['final_keep'] == (1 << ((length-1) % 8 + 1))-1, 'Ignored framing constraint')
            require(packet['tag'] == 7, 'Duplicate-tag scenario lost')
            for index, beat in enumerate(beats):
                expected_data = sum(payload_byte(packet['pattern'], packet['payload_seed'], index*8+lane) << (lane*8)
                                    for lane in range(8))
                expected_user = ((0 if index == 0 else 123) << 40) | (7 << 24) | (length << 8) | packet['qid']
                final = index == len(beats)-1
                require(beat == dict(data=expected_data, keep=packet['final_keep'] if final else 255,
                                     last=int(final), user=expected_user), 'Generated beat violates packet configuration')
            legal_packets.append(packet)
        require(packet['expected_status'] == (0 if not directed or packet['phase'] == 'directed-9'
                else [1, 2, 2, 6, 6, 6, 6, 6, 6][int(packet['phase'].split('-')[1])]),
                'Directed error semantics changed')
        if packet['expected_status'] == 0:
            output_user = (source << 40) | (header & ((1 << 40)-1))
            outputs.extend(dict(beat, user=output_user) for beat in beats)

    compare_handshakes(captures, statuses, outputs, observed, n_rx)

    boundaries = {1, 7, 8, 9, cell_bytes-1, cell_bytes, cell_bytes+1, maximum-1, maximum}
    require(boundaries <= {p['length'] for p in legal_packets}, 'Missing length boundary')
    require({p['source'] for p in legal_packets} == set(range(n_rx)), 'Missing profile source')
    require({p['qid'] for p in legal_packets} == set(range(n_q)), 'Missing profile queue')
    require({p['final_keep'].bit_count() for p in legal_packets} == set(range(1, 9)), 'Missing final keep width')
    random_packets = [p for p in packets if p['phase'] == 'random']
    distributions = {field: histogram(random_packets, field, values) for field, values in
                     (('source', range(n_rx)), ('qid', range(n_q)), ('class', range(4)),
                      ('pattern', range(4)), ('gap', range(4)))}
    for field in ('source', 'qid'):
        require(all(distributions[field].values()), f'Random distribution missed {field}')
    # Fixed broad envelopes test the intended weighting without asserting exact
    # solver probabilities or random-stream portability across stack versions.
    for field in ('pattern', 'gap'):
        require(all(8 <= count <= 64 for count in distributions[field].values()), f'Collapsed random {field} distribution')
    for value, lower, upper in ((0, 8, 64), (1, 8, 64), (2, 4, 40), (3, 16, 88)):
        require(lower <= distributions['class'][str(value)] <= upper, 'Collapsed weighted length distribution')
    require(len({p['payload_seed'] for p in random_packets}) >= 120, 'Collapsed payload seed diversity')
    bins = saved_coverage['functional_bins']
    required = ['::packets.packet_length.'+name for name in
                ('one', 'seven', 'word', 'word_plus', 'cell_minus', 'cell_exact', 'cell_plus', 'max_minus', 'maximum')]
    required += [f'::packets.final_width.widths[{i}]' for i in range(8)]
    required += [f'::packets.source_port.ports[{i}]' for i in range(n_rx)]
    required += [f'::packets.queue_id.queues[{i}]' for i in range(n_q)]
    for suffix in required:
        require(any(name.endswith(suffix) and count > 0 for name, count in bins.items()), 'Missing saved packet coverage bin: '+suffix)
    for dimension in ('source_port', 'queue_id', 'packet_length', 'final_width'):
        count = sum(count for name, count in bins.items() if '::packets.'+dimension+'.' in name)
        require(count == len(legal_packets)+1, 'Saved packet coverage does not account for observed legal frames: '+dimension)
    return dict(packets=len(packets), legal_packets=len(legal_packets), random_packets=128,
                directed_statuses=[p['expected_status'] for p in packets if p['phase'].startswith('directed-')],
                captured_beats=sum(map(len, captures.values())), output_beats=len(outputs),
                boundaries=sorted(boundaries), final_widths=list(range(1, 9)), distributions=distributions,
                stimulus_digest=hashlib.sha256((path/'stimulus.jsonl').read_bytes()).hexdigest(),
                handshake_digest=hashlib.sha256((path/'handshakes.jsonl').read_bytes()).hexdigest())
