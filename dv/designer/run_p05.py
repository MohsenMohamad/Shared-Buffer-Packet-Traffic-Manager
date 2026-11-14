#!/usr/bin/env python3
"""Explicit RTL/designer-only checks. Never traverse or digest independent DV."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / 'dv/designer/p05_sources.json'
PROFILES = {
    'F0': (4, 16, 64, 1024, 256, 1536, 1),
    'F1': (4, 16, 64, 1024, 256, 1536, 2),
    'I0': (2, 4, 16, 32, 16, 256, 1),
    'I1': (2, 4, 16, 32, 16, 256, 2),
    'E0': (1, 2, 16, 16, 8, 128, 1),
    'E1': (4, 8, 32, 64, 32, 512, 2),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', choices=PROFILES, default='I0')
    parser.add_argument('--latency', type=int, choices=(1, 2))
    parser.add_argument('--depth', type=int, default=4)
    parser.add_argument('--seed', type=int, action='append')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--lint', action='store_true')
    mode.add_argument('--synth', action='store_true')
    args = parser.parse_args()
    seeds = args.seed or [17]
    if args.depth < (args.latency or PROFILES[args.profile][-1]) + 2 or any(s <= 0 for s in seeds):
        parser.error('depth must be at least latency+2; seed must be positive')
    registry = json.loads(REGISTRY.read_text())
    production = json.loads((ROOT / 'verification/sources/production.json').read_text())
    # Source paths come only from the two explicit, permitted registrations.
    sources = production['sources'] if args.lint or args.synth else registry['sources']
    assert all(p.startswith(('rtl/', 'dv/designer/')) for p in sources)
    profile = PROFILES[args.profile]
    params = dict(zip(('N_RX', 'N_Q', 'CELL_BYTES', 'N_CELL', 'N_DESC',
                       'MAX_PACKET_BYTES', 'MEM_RD_LATENCY'), profile))
    params['MEM_RD_LATENCY'] = args.latency or profile[-1]
    params['TX_FIFO_DEPTH'] = args.depth
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    label = f'{args.profile}-l{params["MEM_RD_LATENCY"]}-d{args.depth}'
    build = ROOT / 'work/p05' / f'{stamp}-{label}'
    build.mkdir(parents=True)
    record = {'scope': 'RTL-owned designer check', 'arguments': vars(args),
              'parameters': params, 'commands': [], 'result': 'NOT_RUN', 'seeds': seeds,
              'rtl_base_revision': subprocess.check_output(
                  ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'rtl_dirty_paths': subprocess.check_output(
                  ['git', 'status', '--porcelain', '--', 'rtl', 'dv/designer',
                   'verification/sources/production.json'], cwd=ROOT, text=True).splitlines(),
              'tool_versions': {tool: subprocess.check_output(
                  [tool, option], cwd=ROOT, text=True).strip()
                  for tool, option in [('verilator', '--version'), ('yosys', '-V')]}}

    def capture_failure():
        target = ROOT / 'verification/failures' / f'p05-designer-{stamp}'
        target.mkdir(parents=True)
        # Preserve only known RTL and this smoke/runner/config, never Git diffs
        # or repository-wide provenance. No source hashing is performed.
        paths = set(production['sources'] + production['headers'] +
                    registry['sources'] + ['dv/designer/run_p05.py',
                    'dv/designer/p05_sources.json', 'verification/sources/production.json'])
        with tarfile.open(target / 'source.tar.gz', 'w:gz') as archive:
            for name in sorted(paths):
                archive.add(ROOT / name, arcname=name, recursive=False)
        record['source_snapshot'] = 'source.tar.gz'
        for log in build.glob('*.log'):
            shutil.copyfile(log, target / log.name)
        record['disposition'] = 'unresolved'
        (target / 'capture.json').write_text(json.dumps(record, indent=2)+'\n')
        print(f'Failure preserved: {target.relative_to(ROOT)}', flush=True)

    def run(argv, name, timeout):
        record['commands'].append(argv)
        try:
            completed = subprocess.run(argv, cwd=ROOT, env=os.environ,
                                       capture_output=True, text=True, timeout=timeout)
            (build / f'{name}.stdout.log').write_text(completed.stdout)
            (build / f'{name}.stderr.log').write_text(completed.stderr)
            good = completed.returncode == 0
            if name.startswith('simulate-'):
                good &= 'DESIGNER_SMOKE_PASS' in completed.stdout
            record['result'] = 'PASS' if good else 'FAIL'
            record['returncode'] = completed.returncode
        except (subprocess.TimeoutExpired, OSError) as error:
            (build / f'{name}.stderr.log').write_text(str(error))
            record['result'] = 'TOOL_ERROR'
            good = False
        (build / 'result.json').write_text(json.dumps(record, indent=2)+'\n')
        if not good:
            capture_failure()
            # All native inputs are permitted RTL/designer sources.
            print((build / f'{name}.stderr.log').read_text()[-8000:])
            stdout = build / f'{name}.stdout.log'
            if stdout.exists():
                print(stdout.read_text()[-4000:])
            return False
        if name.startswith('simulate-'):
            print(completed.stdout.strip())
        return True

    common = ['verilator', '--assert', '-Irtl/include']
    if args.synth:
        for top in ('tm_metadata_api', 'tm_packet_ram_api', 'tm_tx_api'):
            read = ['read_slang', '-Irtl/include', '--top', top]
            for key, value in params.items():
                read += ['-G', f'{key}={value}']
            netlist = build / f'{top}.json'
            script = ' '.join(read+sources)
            script += f'; hierarchy -check; proc; opt; memory_collect; check -assert; write_json {netlist}'
            script += f'; synth -top {top} -noabc; check -assert; stat'
            if not run(['yosys', '-Q', '-T', '-p', script], f'synth-{top}', 240):
                return 1
            if top == 'tm_packet_ram_api':
                design = json.loads(netlist.read_text())
                cells = design['modules'][top]['cells']
                memories = [c for c in cells.values() if c['type'] == '$mem_v2' and
                            c['parameters']['MEMID'] == '\\payload']
                expected = {'WIDTH': 64, 'SIZE': params['N_CELL']*params['CELL_BYTES']//8,
                            'RD_PORTS': 1, 'WR_PORTS': 1}
                if len(memories) != 1 or any(
                        int(memories[0]['parameters'][k], 2) != v for k, v in expected.items()):
                    record['result'] = 'FAIL'
                    record['first_failure'] = 'Production payload memory port/capacity mismatch'
                    capture_failure()
                    return 1
                record['payload_memory'] = expected
                (build / 'result.json').write_text(json.dumps(record, indent=2)+'\n')
    elif args.lint:
        for top in ('tm_metadata_api', 'tm_packet_ram_api', 'tm_tx_api',
                    'tm_queue_ctrl_api', 'tm_drr_api'):
            cmd = common + ['--lint-only', '--top-module', top]
            cmd += [f'-G{k}={v}' for k, v in params.items()] + sources
            if not run(cmd, f'lint-{top}', 120):
                return 1
    else:
        cmd = common + ['--binary', '--timing', '-j', '2', '--top-module', registry['top'],
                        '--Mdir', str(build / 'obj')]
        cmd += [f'-G{k}={v}' for k, v in params.items()] + sources
        if not run(cmd, 'compile', 1200):
            return 1
        for seed in seeds:
            if not run([str(build / 'obj' / ('V'+registry['top'])), f'+seed={seed}'],
                       f'simulate-{seed}', 60):
                return 1
    print(f'{record["result"]} {label} {build.relative_to(ROOT)}', flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
