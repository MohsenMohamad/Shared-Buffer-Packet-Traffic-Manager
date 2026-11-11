"""Bounded commands and evidence for the isolated frontend probes."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import time

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
CANDIDATES = (
    'baseline', 'ansi_vectors', 'package_vectors', 'inline_struct',
    'type_parameter', 'forward_typedef', 'package_scoped', 'minimal', 'named_widths',
)
FORMAL_CANDIDATES = ('ansi_vectors', 'package_scoped', 'minimal', 'named_widths')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')


def tool_identities(names, exploratory=False):
    options = {'verilator': '--version', 'yosys': '-V', 'sby': '--version', 'z3': '--version'}
    patterns = {
        'verilator': r'^Verilator 5\.054\b',
        'yosys': r'^Yosys 0\.52 \(git sha1 fee39a3284c90249e1d9684cf6944ffbbcbb8f90\)',
        'sby': r'^SBY v0\.71$',
        'z3': r'^Z3 version 4\.13\.3\b',
    }
    identities = {}
    for name in names:
        executable = shutil.which(name)
        if not executable:
            raise RuntimeError(f'Missing required tool: {name}; no tests executed')
        result = subprocess.run([executable, options[name]], capture_output=True, text=True, timeout=20)
        version = (result.stdout + result.stderr).strip()
        if result.returncode:
            raise RuntimeError(f'Cannot identify {name}: exit {result.returncode}')
        matches = bool(re.search(patterns[name], version))
        identities[name] = dict(executable=executable, identity=version, matches_old_pin=matches)
        if not matches and not exploratory:
            raise RuntimeError(f'{name} does not match the old qualified pin: {version}; '
                               'use --exploratory only for a separately labelled comparison')
    return identities


def new_run(repo, output, suite):
    if output is None:
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
        output = repo / '.build/rtl-frontend-probes/runs' / (suite + '-' + stamp)
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    return output


def execute(output, label, argv, cwd, timeout):
    directory = output / 'logs' / label
    directory.mkdir(parents=True, exist_ok=False)
    start = time.monotonic()
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    with (directory / 'stdout').open('w') as stdout, (directory / 'stderr').open('w') as stderr:
        process = subprocess.Popen(argv, cwd=cwd, stdout=stdout, stderr=stderr, start_new_session=True)
        try:
            rc = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            # Give SBY time to terminate solver process groups it owns.
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            rc = 'TIMEOUT'
    row = dict(label=label, argv=list(map(str, argv)), shell=shlex.join(list(map(str, argv))),
               cwd=str(cwd), returncode=rc, started_utc=started,
               seconds=round(time.monotonic() - start, 3))
    write_json(directory / 'command.json', row)
    return row


def output_text(output, row):
    directory = output / 'logs' / row['label']
    return (directory / 'stdout').read_text() + '\n' + (directory / 'stderr').read_text()


def selected(parser, requested, allowed):
    names = requested or list(allowed)
    if len(names) != len(set(names)) or any(name not in allowed for name in names):
        parser.error('Select distinct known candidates: ' + ', '.join(allowed))
    return names


def ys_path(path):
    return json.dumps(str(path))


def seconds(value):
    number = int(value)
    if not 1 <= number <= 3600:
        raise argparse.ArgumentTypeError('timeout must be 1..3600 seconds')
    return number
