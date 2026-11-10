#!/usr/bin/env python3
"""Build and execute a focused SV/UVM capability fixture with Verilator."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def execute(argv, **kwargs):
    try:
        return subprocess.run(argv, capture_output=True, text=True, **kwargs)
    except subprocess.TimeoutExpired as error:
        def decoded(value):
            return value.decode(errors='replace') if isinstance(value, bytes) else (value or '')
        return subprocess.CompletedProcess(argv, 124, decoded(error.stdout),
                                           decoded(error.stderr) + '\nTM_TOOL_TIMEOUT\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--verilator', default='verilator')
    parser.add_argument('--uvm-home', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT / '.build/capabilities')
    parser.add_argument('--jobs', type=int, default=1)
    args = parser.parse_args()
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    tool = shutil.which(args.verilator)
    if not tool:
        parser.error('Verilator executable not found')
    coverage_tool = Path(tool).with_name('verilator_coverage')
    if not coverage_tool.is_file():
        parser.error('verilator_coverage must be installed beside Verilator')
    uvm = args.uvm_home.resolve() / 'src'
    if not (uvm / 'uvm_pkg.sv').is_file():
        parser.error('--uvm-home must contain src/uvm_pkg.sv')
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'tests/toolchain/uvm_smoke.sv'
    version = subprocess.run([tool, '--version'], check=True, text=True, capture_output=True).stdout.strip()
    command = [tool, '--binary', '--timing', '--assert', '--coverage', '--trace-vcd',
               '--timescale', '1ns/1ps', '+define+UVM_NO_DPI',
               '--build-jobs', str(args.jobs), '--output-split', '20000',
               '--output-split-cfuncs', '500', '-CFLAGS', '-O0',
               '+incdir+' + str(uvm), str(uvm / 'uvm_pkg.sv'), str(source),
               '--top-module', 'tm_uvm_capabilities', '--Mdir', str(out / 'obj')]
    start = time.monotonic()
    build = execute(command, timeout=1200)
    build_text = build.stdout + build.stderr
    (out / 'build.log').write_text(build_text)
    summary = dict(schema_version=1, scope='SV/UVM capability fixture only', tool=version,
                   source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(), command=command,
                   build_seconds=round(time.monotonic()-start, 3), cases=[])
    if build.returncode or re.search(r'%(?:Warning|Error)-(?:COVERIGN|CONSTRAINTIGN|UNSUPPORTED)', build_text):
        summary.update(result='TIMEOUT' if build.returncode==124 else 'TOOL_ERROR',
                       reason='Compilation failed, timed out or a required construct was ignored')
    else:
        binary = out / 'obj/Vtm_uvm_capabilities'
        digests = []
        for name, seed, mutation in [('seed17',17,False),('seed17_replay',17,False),('seed19',19,False),('held_data_mutation',17,True)]:
            case = out / name
            case.mkdir(exist_ok=True)
            for generated in ('run.log', 'coverage.dat', 'coverage_summary.txt', 'wave.vcd'):
                (case / generated).unlink(missing_ok=True)
            argv = [str(binary), '+verilator+seed+' + str(seed), '+UVM_NO_RELNOTES']
            if mutation:
                argv += ['+MUTATION_HOLD', '+TRACE']
            run = execute(argv, cwd=case, timeout=120)
            log = run.stdout + run.stderr
            (case / 'run.log').write_text(log)
            coverage_points = None
            if mutation:
                wave = case / 'wave.vcd'
                ok = run.returncode not in (0,124) and 'TM_CAP_STABILITY_FAIL' in log and wave.is_file() and wave.stat().st_size>0
            else:
                found = re.search(r'TM_UVM_SMOKE_PASS transactions=64 digest=([0-9a-fA-F]+)', log)
                ok = run.returncode == 0 and found is not None and (case/'coverage.dat').is_file()
                if re.search(r'UVM_(?:ERROR|FATAL)\s*:\s*[1-9]', log):
                    ok = False
                if found:
                    digests.append(found.group(1))
                if (case / 'coverage.dat').is_file():
                    coverage = execute([str(coverage_tool), '--report', 'summary', str(case / 'coverage.dat')], timeout=60)
                    report = coverage.stdout + coverage.stderr
                    (case / 'coverage_summary.txt').write_text(report)
                    bins = re.search(r'covergroup\s*:\s*([0-9.]+)%\s+\(\s*(\d+)/\s*(\d+)\)', report)
                    if coverage.returncode or not bins or int(bins.group(2))==0:
                        ok = False
                    else:
                        coverage_points = dict(hit=int(bins.group(2)), total=int(bins.group(3)),
                                               tool_reported_percent=float(bins.group(1)))
            summary['cases'].append(dict(name=name, seed=seed, expected='ASSERTION_FAILURE' if mutation else 'PASS',
                                         returncode=run.returncode, result='TIMEOUT' if run.returncode==124 else ('PASS' if ok else 'FAIL'),
                                         covergroup_points=coverage_points))
        replay = len(digests)==3 and digests[0]==digests[1] and digests[0]!=digests[2]
        summary['seed_replay_passed'] = replay
        summary['result'] = 'PASS' if replay and all(c['result']=='PASS' for c in summary['cases']) else 'FAIL'
    (out / 'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(json.dumps(summary, indent=2))
    return 0 if summary['result']=='PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
