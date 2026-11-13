#!/usr/bin/env python3
"""Separate designer smoke registration; uses existing evidence/failure capture."""
import argparse
import json
import os
from pathlib import Path
import re
import resource
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from evidence import Case, Run, completed, output, utc  # noqa: E402
from registry import profile, sources  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', action='append', choices=['F0', 'F1', 'I0', 'I1', 'E0', 'E1'])
    parser.add_argument('--depth', action='append', type=int, choices=[4, 8])
    parser.add_argument('--jobs', type=int, default=2)
    args = parser.parse_args()
    activation = ROOT / '.tools/environment.json'
    if activation.is_file():
        os.environ.update(json.loads(activation.read_text()))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    run = Run(ROOT / '.build/runs' / ('designer-memory-tx-' + utc().replace(':', '')),
              profile='designer')
    run.scope = 'Designer smoke of production RAM/metadata/TX; independent qualification remains P05-DV.'
    run.versions['verilator'] = subprocess.check_output(['verilator', '--version'], text=True).strip()
    registered = sources('production')
    designer = json.loads((ROOT / 'dv/designer/sources.json').read_text())
    for name in args.profile or ['E0', 'I1']:
        for depth in args.depth or [4, 8]:
            case = Case(run, f'{name}-depth{depth}')
            params = dict(profile(name), TX_FIFO_DEPTH=depth)
            case.data.update(parameters=params, source_set='production + dv/designer/sources.json')
            binary = case.path / 'obj/Vmemory_tx_tb'
            argv = ['verilator', '--binary', '--timing', '--assert', '--timescale', '1ns/1ps',
                    '--build-jobs', str(args.jobs), '--top-module', 'memory_tx_tb',
                    '--Mdir', str(binary.parent)]
            argv += ['-I' + str(ROOT / p) for p in registered['include_dirs']]
            argv += [f'-G{k}={v}' for k, v in params.items()]
            argv += [str(ROOT / p) for p in registered['sources'] + designer['sources']]
            build = case.execute(argv, timeout=240)
            if build['result'] != 'PASS' or not binary.is_file():
                case.finish('TOOL_ERROR', 'Designer compilation failed or executable missing')
                break
            step = case.execute([str(binary)], timeout=60, cwd=case.path)
            result, why = completed(step, 'TM_DESIGNER_MEMORY_TX_PASS')
            metrics = re.search(r'TM_DESIGNER_MEMORY_TX_PASS (.*)', output(step))
            case.finish(result, why, metrics={k: int(v) for k, v in re.findall(
                r'(\w+)=(\d+)', metrics[1])} if metrics else {})
            if result != 'PASS':
                break
        if case.data['result'] != 'PASS':
            break
    return run.finish()


if __name__ == '__main__':
    sys.exit(main())
