"""Replay the original simulation/synthesis matrix, checking expected rejections."""
import argparse
import concurrent.futures
import json
from pathlib import Path
import sys
from common import (CANDIDATES, REPO, execute, new_run, output_text, selected,
                    tool_identities, write_json, ys_path, seconds)
from verify import verify

PACKAGES = {'package_vectors', 'inline_struct', 'type_parameter', 'package_scoped',
            'minimal', 'named_widths'}
REJECTIONS = {
    'package_vectors': 'unexpected TOK_PACKAGESEP',
    'inline_struct': 'unexpected TOK_STRUCT',
    'type_parameter': "unexpected TOK_ID, expecting ',' or '=' or ')'",
    'forward_typedef': "unexpected TOK_ID, expecting ',' or '=' or ')'",
    'bits_type': 'expecting OP_CAST',
}


def run_candidate(name, repo, generated, output, args, manifest):
    folder = output / name
    folder.mkdir()
    pkg = [str(generated / 'tm_fixed.sv')] if name in PACKAGES or name == 'bits_type' else []
    files = pkg + ([str(generated / 'bits_type.sv')] if name == 'bits_type' else
                   [str(generated / p) for p in manifest[name]] +
                   [str(generated / name / 'probe_unit.sv')])
    include = ['-I' + str(generated), '-I' + str(repo / 'rtl/include')]
    rows = []
    if args.phase != 'synthesis':
        top = 'bits_type_test' if name == 'bits_type' else 'test'
        test = [] if name == 'bits_type' else [str(generated / 'test.sv')]
        # Preserve the original bits_type command's implicit timescale and build defaults.
        flags = [] if name == 'bits_type' else ['--timescale', '1ns/1ps', '--build-jobs', str(args.jobs)]
        argv = ['verilator', '--binary', '--timing', '--assert'] + flags
        argv += ['--top-module', top, '--Mdir', str(folder / 'obj')]
        argv += ([] if name == 'bits_type' else include) + files + test
        build = execute(output, name + '-build', argv, generated, args.build_timeout)
        text = output_text(output, build)
        if name == 'forward_typedef':
            build['expectation'] = 'REJECT_REFERENCE_BEFORE_DECLARATION'
            build['matched'] = build['returncode'] == 1 and "Reference to 'trace_t' before declaration" in text
        else:
            build['expectation'] = 'BUILD'
            build['matched'] = build['returncode'] == 0 and (folder / 'obj' / ('V' + top)).is_file()
        rows.append(build)
        if build['returncode'] == 0:
            sim = execute(output, name + '-simulation', [str(folder / 'obj' / ('V' + top))], generated, args.timeout)
            text = output_text(output, sim)
            markers = ['BITS_TYPE_PASS'] if name == 'bits_type' else [
                'PROBE_PASS two independent configurations',
                'N_Q=2 N_CELL=16 N_RX=1 DEPTH=2 STATS_W=1290',
                'N_Q=4 N_CELL=32 N_RX=2 DEPTH=4 STATS_W=1944',
            ]
            sim.update(expectation='SIMULATION', matched=sim['returncode'] == 0 and all(m in text for m in markers))
            rows.append(sim)
        elif name != 'forward_typedef':
            rows.append(dict(label=name + '-simulation', returncode=None, expectation='SIMULATION',
                             matched=False, status='NOT_RUN', reason='Build failed'))
    if args.phase == 'simulation':
        return rows
    script = folder / 'synth.ys'
    synth_files = files + ([] if name == 'bits_type' else [str(generated / 'synth_top.sv')])
    # The old frontend does not unquote -I paths. Stage the identical headers
    # locally so the include option remains -I. even in a relocated checkout.
    for source in list(generated.glob('*.svh')) + list((repo / 'rtl/include').glob('*.svh')):
        (folder / source.name).write_bytes(source.read_bytes())
    read = 'read_verilog -sv -I.'
    read += ' ' + ' '.join(ys_path(p) for p in synth_files)
    synth_top = 'bits_type' if name == 'bits_type' else 'synth_top'
    script.write_text(read + '\nhierarchy -check -top ' + synth_top + '\nsynth -top ' + synth_top +
                      '\ncheck -assert\nstat\nwrite_json ' + ys_path(folder / 'netlist.json') + '\n')
    synth = execute(output, name + '-synthesis', ['yosys', '-s', str(script)], folder, args.timeout)
    text = output_text(output, synth)
    if name in REJECTIONS:
        synth.update(expectation='REJECT_FRONTEND', matched=synth['returncode'] == 1 and REJECTIONS[name] in text)
    else:
        synth.update(expectation='SYNTHESIS', matched=synth['returncode'] == 0 and
                     'End of script.' in text and (folder / 'netlist.json').is_file())
    rows.append(synth)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidates', nargs='*')
    parser.add_argument('--repo-root', type=Path, default=REPO)
    parser.add_argument('--generated', type=Path)
    parser.add_argument('--output', type=Path, help='New, non-existing run directory')
    parser.add_argument('--phase', choices=['all', 'simulation', 'synthesis'], default='all')
    parser.add_argument('--jobs', type=int, choices=range(1, 9), default=2)
    parser.add_argument('--timeout', type=seconds, default=180)
    parser.add_argument('--build-timeout', type=seconds, default=240)
    parser.add_argument('--exploratory', action='store_true', help='Label a comparison using other tools')
    args = parser.parse_args()
    names = selected(parser, args.candidates, CANDIDATES + ('bits_type',))
    repo = args.repo_root.resolve()
    generated = (args.generated or repo / '.build/rtl-frontend-probes/generated').resolve()
    preservation = verify(repo, generated)
    tools = tool_identities(['verilator', 'yosys'], args.exploratory)
    output = new_run(repo, args.output, 'simulation-synthesis')
    manifest = json.loads((generated / 'candidates.json').read_text())
    rows = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        for records in pool.map(lambda n: run_candidate(n, repo, generated, output, args, manifest), names):
            rows.extend(records)
            for row in records:
                print(row['label'], row['returncode'], 'MATCH' if row['matched'] else 'MISMATCH', flush=True)
    matched = all(row['matched'] for row in rows)
    write_json(output / 'summary.json', dict(execution_kind='preservation-rerun' if not args.exploratory
               else 'exploratory-comparison', tools=tools, preservation=preservation,
               old_expectations_matched=matched, cases=rows))
    print('Evidence:', output)
    return 0 if matched else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError) as error:
        sys.exit(str(error))
