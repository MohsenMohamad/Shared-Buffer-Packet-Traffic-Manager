#!/usr/bin/env python3
"""Prepare one sealed toolchain for CI; consumers validate and never build."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

from evidence import ROOT, execute, sha

# Setup writes absolute paths into the installation. Include the checkout path
# in compatibility rather than pretending that the payload is relocatable.
INPUTS = ('tools/dependencies.json', 'tools/packages.lock.json',
          'tools/setup_toolchain.py', 'tools/setup.sh', 'tools/evidence.py',
          'tools/toolchain_cache.py')
PAYLOAD = ('.tools/install', '.tools/sysroot', '.tools/activate.sh',
           '.tools/environment.json', '.tools/setup.json', '.deps/downloads',
           '.deps/src/uvm', '.deps/liberty.lib')
MANIFEST = '.tools/cache-manifest.json'
CACHE_PREFIX = 'tm-tools-v2-'
BUILD_FLAGS = ('CC', 'CFLAGS', 'CXXFLAGS', 'CPPFLAGS', 'LDFLAGS', 'MAKEFLAGS')


def command(argv):
    return subprocess.check_output(argv, text=True, timeout=30).strip()


def compatibility(root=ROOT):
    compiler = os.environ.get('CXX', 'g++')
    runtime = Path(command([compiler, '-print-file-name=libstdc++.so.6']))
    return dict(schema_version=1, checkout=str(root.resolve()),
                inputs={p: sha(root / p) for p in INPUTS},
                system=platform.system(), architecture=platform.machine(),
                os_release=sha('/etc/os-release'), libc=platform.libc_ver(),
                python_abi=f'{sys.version_info.major}.{sys.version_info.minor}',
                build_flags={name: os.environ.get(name) for name in BUILD_FLAGS},
                compiler=dict(command=compiler, version=command([compiler, '--version']),
                              target=command([compiler, '-dumpmachine']),
                              libstdcxx_sha256=sha(runtime)))


def cache_key(identity):
    data = json.dumps(identity, sort_keys=True, separators=(',', ':')).encode()
    return CACHE_PREFIX + hashlib.sha256(data).hexdigest()


def inventory(root=ROOT):
    entries = {}
    for name in PAYLOAD:
        base = root / name
        if not base.exists():
            raise ValueError('Missing payload: ' + name)
        paths = [base, *sorted(base.rglob('*'))] if base.is_dir() else [base]
        for path in paths:
            relative = str(path.relative_to(root))
            if path.is_symlink():
                entries[relative] = dict(link=os.readlink(path))
            elif path.is_file():
                entries[relative] = dict(sha256=sha(path), mode=path.stat().st_mode & 0o777)
    return entries


def seal(identity, root=ROOT):
    # Called only after setup AND doctor succeeded. An interrupted build cannot
    # leave a completion manifest that the producer would accept next time.
    data = dict(schema_version=1, key=cache_key(identity), identity=identity,
                files=inventory(root))
    target = root / MANIFEST
    temporary = target.with_suffix('.partial')
    temporary.write_text(json.dumps(data, indent=2) + '\n')
    temporary.replace(target)


def check_payload(identity, root=ROOT):
    data = json.loads((root / MANIFEST).read_text())
    # Compare the canonical key, since JSON converts tuples to lists.
    if data['schema_version'] != 1 or data['key'] != cache_key(identity):
        raise ValueError('Toolchain cache compatibility mismatch')
    if cache_key(data['identity']) != data['key']:
        raise ValueError('Malformed cache identity')
    if not data['files'] or data['files'] != inventory(root):
        raise ValueError('Toolchain payload missing, modified or incomplete')


def checked_step(argv, stem, timeout, root=ROOT):
    step = execute(argv, root / '.build/setup-cache', stem, timeout, cwd=root)
    if step['result'] != 'PASS':
        raise RuntimeError(f'{stem}: {step["result"]}; inspect {step["stderr"]} and {step["stdout"]}')
    return step


def validate(identity, root=ROOT):
    check_payload(identity, root)
    return checked_step([sys.executable, 'tools/run.py', 'doctor'], 'restore-doctor', 300, root)


def warning(message):
    escaped = message.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    print('::warning::' + escaped, flush=True)


def prepare(identity, jobs, root=ROOT, restored_key=None):
    logs = root / '.build/setup-cache'
    logs.mkdir(parents=True, exist_ok=True)
    report = dict(key=cache_key(identity), source='cold', cache_status='miss',
                  restored_key=restored_key or None, result='TOOL_ERROR', steps=[])
    had_candidate = bool(restored_key) or (root / MANIFEST).exists()
    try:
        try:
            if restored_key and restored_key != report['key']:
                raise ValueError('Restored Actions key differs from installation identity')
            report['steps'].append(validate(identity, root))
            report['source'] = 'cache'
            report['cache_status'] = 'accepted'
        except (OSError, ValueError, KeyError, TypeError, RuntimeError) as error:
            if had_candidate:
                report['cache_status'] = 'rejected'
                report['rejected_key'] = restored_key or report['key']
                report['restore_rejected'] = str(error)
                warning(f'Rejected toolchain cache {report["rejected_key"]}: {error}. '
                        'Rebuilding cold, not reusing this entry. If the immutable exact '
                        'entry remains bad, bump CACHE_PREFIX before expecting healthy reuse.')
            # CI owns these ignored directories. Discard partial/stale build
            # trees as well as stamps, so a cold rebuild cannot reuse old objects.
            for name in ('.tools', '.deps', '.build/setup/yosys', '.build/setup/eigen', '.build/setup/opensta'):
                path = root / name
                if path.is_symlink():
                    path.unlink()
                elif path.exists():
                    shutil.rmtree(path)
            report['steps'].append(checked_step(
                [sys.executable, 'tools/setup_toolchain.py', '--jobs', str(jobs)],
                'cold-setup', 14400, root))
            report['steps'].append(checked_step(
                [sys.executable, 'tools/run.py', 'doctor'], 'cold-doctor', 300, root))
            seal(identity, root)
        report['result'] = 'PASS'
        print(f'Toolchain {report["source"]}: PASS ({report["key"]})', flush=True)
    except Exception as error:
        report['first_failure'] = str(error)
        raise
    finally:
        (logs / 'preparation.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('key', 'prepare', 'validate'))
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--github-output', type=Path)
    parser.add_argument('--restored-key', help='Actual key returned by Actions cache restore')
    args = parser.parse_args()
    if not 1 <= args.jobs <= 8:
        parser.error('--jobs must be in 1..8')
    identity = compatibility()
    if args.action == 'key':
        key = cache_key(identity)
        print(key)
        if args.github_output:
            with args.github_output.open('a') as stream:
                stream.write('key=' + key + '\n')
    elif args.action == 'prepare':
        prepare(identity, args.jobs, restored_key=args.restored_key)
    else:
        validate(identity)
        print('Restored toolchain integrity, compatibility and doctor: PASS')


if __name__ == '__main__':
    main()
