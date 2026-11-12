"""G1 checks production declarations, never functional traffic-manager behavior."""
import re
import os
import sys
from evidence import Case, ROOT, completed, output
from registry import profile, sources, fingerprint
from frontend import read_sources, selected

PARAMETERS = ('DATA_W N_RX N_Q CELL_BYTES N_CELL N_DESC MAX_PACKET_BYTES RX_FIFO_DEPTH '
              'MEM_RD_LATENCY TX_FIFO_DEPTH SCHED_MODE QUANTUM_DEFAULT TRACE_ENABLE '
              'CELL_ID_W DESC_ID_W CELL_COUNT_W DESC_COUNT_W DEFICIT_W').split()
# Each rejection isolates a supported-range/width/credit rule.
INVALID = {
    'data-width': {'DATA_W':32}, 'rx-count': {'N_RX':3}, 'queue-count': {'N_Q':3},
    'cell-size': {'CELL_BYTES':8}, 'cell-power': {'N_CELL':24},
    'cell-min': {'N_CELL':8}, 'cell-max': {'N_CELL':2048},
    'desc-power': {'N_DESC':12}, 'desc-min': {'N_DESC':4}, 'desc-max': {'N_DESC':512},
    'length-min': {'MAX_PACKET_BYTES':63}, 'length-max': {'MAX_PACKET_BYTES':1537},
    'capacity': {'MAX_PACKET_BYTES':257,'N_CELL':16,'CELL_BYTES':16},
    'rx-depth': {'RX_FIFO_DEPTH':1}, 'read-latency': {'MEM_RD_LATENCY':3},
    'read-credit': {'MEM_RD_LATENCY':2,'TX_FIFO_DEPTH':3},
    'scheduler': {'SCHED_MODE':2}, 'quantum-min': {'QUANTUM_DEFAULT':63},
    'quantum-max': {'QUANTUM_DEFAULT':4097}, 'trace': {'TRACE_ENABLE':2},
    'cell-index': {'CELL_ID_W':1}, 'desc-index': {'DESC_ID_W':1},
    'cell-count': {'CELL_COUNT_W':1}, 'desc-count': {'DESC_COUNT_W':1},
    'deficit': {'DEFICIT_W':12},
}


def wrapper(path, monitor=False):
    # Derive from the production declarations themselves; no copied port list.
    declarations = '\n'.join((ROOT/p).read_text() for p in sources('production')['sources'])
    modules = ['tm_top'] + re.findall(r'^module (tm_\w+_api)', declarations, re.M)
    text = 'module tm_contract_elab #(\n`include "tm_parameters.svh"\n) ();\n'
    text += '`include "tm_types.svh"\n'
    if monitor:
        text += '`include "tm_monitor_types.svh"\n'
    for index, name in enumerate(modules):
        text += name + ' #(' + ','.join(f'.{p}({p})' for p in PARAMETERS) + f') api{index}();\n'
    # Literal widths catch layout drift; parameter guard separately rejects invalids.
    text += '''input_user_t input_probe; output_user_t output_probe;
status_t status_probe; beat_t beat_probe; descriptor_t info_probe;
generate if (STATUS_W!=45 || $bits(input_probe.qid)!=8 || $bits(output_probe.source)!=8 || $bits(input_probe)!=64 || $bits(output_probe)!=64 ||
        $bits(status_probe)!=STATUS_W || $bits(beat_probe)!=BEAT_W || $bits(info_probe)!=DESC_INFO_W)
        begin : g_layout TM_INVALID_LAYOUT invalid_layout(); end endgenerate
endmodule
'''
    text = text.replace('endmodule\n', """localparam input_user_t INPUT_LAYOUT = '{reserved:24'h123456,tag:16'h789a,length:16'hbcde,qid:8'hf0};
localparam output_user_t OUTPUT_LAYOUT = '{reserved:16'h1234,source:8'h56,tag:16'h789a,length:16'hbcde,qid:8'hf0};
localparam status_t STATUS_LAYOUT = '{valid:1'b1,code:FRAME_ERROR,tag:16'h1234,qid:8'h56,length:16'h789a};
localparam beat_t BEAT_LAYOUT = '{data:64'h0123456789abcdef,keep:8'h55,last:1'b1,user:64'hfedcba9876543210};
generate if (INPUT_LAYOUT!=64'h123456789abcdef0 || OUTPUT_LAYOUT!=64'h123456789abcdef0 ||
    STATUS_LAYOUT!={1'b1,4'd6,16'h1234,8'h56,16'h789a} ||
    BEAT_LAYOUT!={64'h0123456789abcdef,8'h55,1'b1,64'hfedcba9876543210} ||
    COMMITTED!=0 || BAD_QID!=1 || BAD_LENGTH!=2 || QUEUE_LIMIT!=3 || NO_DESCRIPTOR!=4 || NO_CELLS!=5 ||
    FREE!=0 || RX!=1 || QUEUED!=2 || TX!=3 || ABORT!=4 ||
    IDLE!=0 || RECEIVE!=1 || DRAIN_REJECT!=2 || ABORT_DRAIN!=3 || OKAY!=0 || SLVERR!=2 || DECERR!=3)
    begin : g_wire_layout TM_INVALID_LAYOUT changed_wire_layout(); end endgenerate
endmodule
""")
    path.write_text(text)


def frontend(run, args, tool, name, params, invalid=False, monitor=False, component=None):
    case = Case(run, tool + '-' + name, (args.seed or [17])[0])
    source_set = 'simulation' if monitor else 'synthesis' if tool == 'yosys' else 'production'
    registered = sources(source_set)
    case.data.update(scope='Declaration/parameter elaboration only; no functional verification',
                     parameters=params, source_set=source_set,
                     registered_source_digests=fingerprint(source_set))
    harness = case.path / 'tm_contract_elab.sv'
    wrapper(harness, monitor)
    top = component or 'tm_contract_elab'
    includes = [str(ROOT / p) for p in registered['include_dirs']]
    files = [str(ROOT / p) for p in registered['sources']] + ([] if component else [str(harness)])
    if tool == 'verilator':
        # PINMISSING is confined to the elaboration harness's intentionally open
        # declarations. No behavioral lint or unconnected-net qualification.
        argv = ['verilator', '--lint-only', '-Wno-PINMISSING', '--top-module', top,
                '--Mdir', str(case.path / 'obj')] + ['-I'+p for p in includes]
        argv += [f'-G{k}={v}' for k, v in params.items()] + files
    else:
        script = case.path / 'elaborate.ys'
        case.data['frontend'] = selected(args)
        script.write_text(read_sources(files, top, includes, params=params, frontend=selected(args)))
        argv = ['yosys', '-s', str(script)]
    step = case.execute(argv, timeout=args.timeout)
    text = output(step)
    if invalid:
        ok = (step['result']=='TOOL_ERROR' and step['returncode'] not in (None, 0)
              and 'TM_INVALID_CONFIGURATION' in text and
              ('%Error' in text if tool == 'verilator' else 'ERROR:' in text))
        case.finish('PASS' if ok else step['result'] if step['result']=='TIMEOUT' or step['returncode'] is None else 'FAIL',
                    None if ok else 'Missing intended configuration elaboration rejection',
                    expected='INVALID_ELABORATION')
    else:
        marker = 'End of script.' if tool == 'yosys' else 'Verilator: Walltime'
        case.finish(*completed(step, marker))


def contracts(run, args):
    params = profile(args.profile)
    for tool in ('verilator', 'yosys'):
        frontend(run, args, tool, args.profile, params)
        # Exercise portable monitor records in simulation only.
        if tool == 'verilator':
            frontend(run, args, tool, args.profile+'-monitor', params, monitor=True)
        for name, delta in INVALID.items():
            # Deficit width 12 is invalid even in the smallest production profile.
            frontend(run, args, tool, 'invalid-'+name, dict(params, **delta), invalid=True)
        frontend(run, args, tool, 'options', dict(params, RX_FIFO_DEPTH=4, TX_FIFO_DEPTH=8,
                 SCHED_MODE=0, QUANTUM_DEFAULT=4096, TRACE_ENABLE=0))
        # Component-specific guards are not part of the common profile wrapper.
        invalid_components = [
            ('counter-zero', 'tm_statistics_api', dict(COUNTER_W=0)),
            ('counter-wide', 'tm_statistics_api', dict(COUNTER_W=65)),
            ('bitmap-capacity', 'tm_bitmap_pool', dict(CAPACITY=0)),
            ('bitmap-id-zero', 'tm_bitmap_pool', dict(ID_W=0)),
            ('bitmap-id-small', 'tm_bitmap_pool', dict(ID_W=3)),
            ('bitmap-count', 'tm_bitmap_pool', dict(COUNT_W=4)),
            ('bitmap-returns-zero', 'tm_bitmap_pool', dict(RETURNS=0)),
            ('bitmap-returns-three', 'tm_bitmap_pool', dict(RETURNS=3)),
        ]
        for name, component, overrides in invalid_components:
            frontend(run, args, tool, 'invalid-'+name, overrides,
                     invalid=True, component=component)

    case = Case(run, 'independent-event-batching', (args.seed or [17])[0])
    os.environ['TM_CONTRACT_SEED'] = str((args.seed or [17])[0])
    step = case.execute([sys.executable, '-m', 'unittest', 'discover', '-s',
                        str(ROOT / 'tests/contracts'), '-p', 'test_*.py', '-v'], timeout=args.timeout)
    match = re.search(r'Ran (\d+) tests?', output(step))
    ok = step['result']=='PASS' and match and int(match[1])>0 and re.search(r'(?m)^OK$', output(step))
    digests = re.findall(r'TM_BATCH_ORDERS seed=([0-9]+) digest=([0-9a-f]{64})', output(step))
    ok = ok and len(digests)==4 and len(set(digests))==1 and digests[0][0]==os.environ['TM_CONTRACT_SEED']
    case.finish('PASS' if ok else step['result'] if step['result']!='PASS' else 'FAIL',
                None if ok else 'Contract tests failed, zero tests, or missing callback-order replay digest',
                callback_permutations=720, permutation_digest=digests[0][1] if digests else None)
