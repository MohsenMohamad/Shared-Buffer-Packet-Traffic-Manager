#!/usr/bin/env python3
"""Install checksum-locked native tools into user-owned directories, without sudo."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import subprocess
import tarfile
from evidence import execute

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def fetch(pin, target):
    if not target.exists():
        temporary = target.with_suffix(target.suffix + '.partial')
        subprocess.run(['curl', '--fail', '--location', '--retry', '2', '--max-time', '180',
                        pin['url'], '-o', str(temporary)], check=True, timeout=600)
        if digest(temporary) != pin['sha256']:
            raise ValueError('Downloaded checksum mismatch: ' + target.name)
        temporary.replace(target)
    if digest(target) != pin['sha256']:
        raise ValueError('Cached checksum mismatch: ' + target.name)


def unpack(archive, target, reuse=False):
    marker = target / '.archive-sha256'
    if reuse and marker.is_file() and marker.read_text().strip() == digest(archive):
        return
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True)
    with tarfile.open(archive) as stream:
        for member in stream.getmembers():
            member.name = '/'.join(member.name.split('/')[1:])
            if member.name:
                stream.extract(member, target, filter='data')
    marker.write_text(digest(archive) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', type=int, default=2)
    args = parser.parse_args()
    if not 1 <= args.jobs <= 8:
        parser.error('--jobs must be in 1..8')
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        parser.error('Only Linux x86-64 is qualified')
    # These Debian binaries require the qualified base ABI, not an Ubuntu sysroot.
    if tuple(map(int, platform.libc_ver()[1].split('.')[:2])) < (2, 38):
        parser.error('glibc >= 2.38 required by the locked Debian binaries')
    for tool in ('curl', 'dpkg-deb', 'g++', 'make', 'perl', 'git'):
        if not shutil.which(tool):
            parser.error('Missing bootstrap prerequisite: ' + tool)
    deps = json.loads((ROOT / 'tools/dependencies.json').read_text())
    packages = json.loads((ROOT / 'tools/packages.lock.json').read_text())['packages']
    cache = ROOT / '.deps/downloads'
    cache.mkdir(parents=True, exist_ok=True)
    prefix, sysroot = ROOT / '.tools/install', ROOT / '.tools/sysroot'
    logs = ROOT / '.build/setup'
    logs.mkdir(parents=True, exist_ok=True)
    for pin in packages:
        fetch(pin, cache / pin['file'])
    for name in ('verilator', 'uvm', 'sby', 'liberty'):
        fetch(deps[name], cache / (name + ('.lib' if name == 'liberty' else '.tar.gz')))
    recipe = hashlib.sha256(''.join(digest(ROOT / p) for p in
        ('tools/dependencies.json', 'tools/packages.lock.json', 'tools/setup_toolchain.py')).encode()).hexdigest()
    stamp = ROOT / '.tools/setup.json'
    if stamp.exists() and json.loads(stamp.read_text()).get('recipe_sha256') == recipe:
        needed = [prefix / 'bin/verilator_bin', prefix / 'bin/sby', sysroot / 'usr/bin/yosys',
                  sysroot / 'usr/bin/sta', ROOT / '.deps/src/uvm/src/uvm_pkg.sv',
                  ROOT / '.tools/activate.sh']
        if all(path.is_file() for path in needed):
            print('Locked installation already prepared; downloads verified. Run make doctor.')
            return
    sysroot.mkdir(parents=True, exist_ok=True)
    previous = json.loads(stamp.read_text()) if stamp.exists() else {}
    packages_present = previous.get('packages') == packages and all(
        (sysroot / path).is_file() for path in ('usr/bin/yosys', 'usr/bin/sta', 'usr/bin/z3', 'usr/include/zlib.h'))
    if not packages_present:
        for pin in packages:
            subprocess.run(['dpkg-deb', '-x', str(cache / pin['file']), str(sysroot)],
                           check=True, timeout=120)
    else:
        # Restore original packaged text before relocation; repeated prefix
        # replacement on already relocated files would duplicate the path.
        autoconf = next(pin for pin in packages if pin['name'] == 'autoconf')
        subprocess.run(['dpkg-deb', '-x', str(cache / autoconf['file']), str(sysroot)],
                       check=True, timeout=120)
    # Relocate packaged Autoconf data; upstream SV/UVM sources stay unmodified.
    auto = sysroot / 'usr/share/autoconf'
    for path in list((sysroot / 'usr/bin').glob('auto*')) + list(auto.rglob('*')):
        if path.is_file() and not path.is_symlink():
            try:
                content = path.read_text()
            except UnicodeError:
                continue
            path.write_text(content.replace('/usr/share/autoconf', str(auto)))
    env = os.environ.copy()
    env['PATH'] = f'{prefix}/bin:{sysroot}/usr/bin:' + env['PATH']
    for key, value in {
        'LD_LIBRARY_PATH': str(sysroot / 'usr/lib/x86_64-linux-gnu'),
        'AC_MACRODIR': str(auto), 'AUTOM4TE_CFG': str(auto / 'autom4te.cfg'),
        'PERL5LIB': str(auto), 'BISON_PKGDATADIR': str(sysroot / 'usr/share/bison'),
        'AUTOM4TE': str(sysroot / 'usr/bin/autom4te'), 'M4': str(sysroot / 'usr/bin/m4'),
        'PYTHONPATH': f'{prefix}/share/yosys/python3:{sysroot}/usr/share/yosys:{sysroot}/usr/share/yosys/python3:{sysroot}/usr/lib/python3/dist-packages',
        'TCL_LIBRARY': str(sysroot / 'usr/share/tcltk/tcl8.6'),
        'UVM_HOME': str(ROOT / '.deps/src/uvm'),
    }.items():
        env[key] = value
    activation = ''.join(f'export {key}={shlex.quote(env[key])}\n' for key in
                         ('PATH', 'LD_LIBRARY_PATH', 'AC_MACRODIR', 'AUTOM4TE_CFG', 'PERL5LIB',
                          'BISON_PKGDATADIR', 'AUTOM4TE', 'M4', 'PYTHONPATH', 'TCL_LIBRARY', 'UVM_HOME'))
    (ROOT / '.tools/activate.sh').write_text(activation)
    (ROOT / '.tools/environment.json').write_text(json.dumps({key: env[key] for key in
        ('PATH', 'LD_LIBRARY_PATH', 'AC_MACRODIR', 'AUTOM4TE_CFG', 'PERL5LIB',
         'BISON_PKGDATADIR', 'AUTOM4TE', 'M4', 'PYTHONPATH', 'TCL_LIBRARY', 'UVM_HOME')}, indent=2) + '\n')
    for name in ('verilator', 'uvm', 'sby'):
        unpack(cache / (name + '.tar.gz'), ROOT / '.deps/src' / name, reuse=name == 'verilator')
    shutil.copyfile(cache / 'liberty.lib', ROOT / '.deps/liberty.lib')
    steps = [('autoconf', ['autoconf'], 'verilator'),
             ('configure', ['./configure', '--prefix=' + str(prefix)], 'verilator'),
             ('build', ['make', '-C', 'src', '-j' + str(args.jobs), 'opt'], 'verilator'),
             ('install', ['make', 'install-all',
                          'VL_INST_PUBLIC_BIN_FILES=verilator_bin verilator_coverage_bin'], 'verilator'),
             ('sby', ['make', 'PREFIX=' + str(prefix), 'install'], 'sby')]
    records = []
    for name, argv, directory in steps:
        print('Setup: ' + name, flush=True)
        record = execute(argv, logs, name, 1800, cwd=ROOT / '.deps/src' / directory, env=env)
        records.append(record)
        (logs / 'steps.json').write_text(json.dumps(records, indent=2) + '\n')
        if record['result'] != 'PASS':
            raise RuntimeError(f'{name}: {record["result"]}; inspect {logs}')
    uvm_digests = {str(p.relative_to(ROOT)): digest(p) for p in
                   (ROOT / '.deps/src/uvm/src').rglob('*') if p.is_file()}
    stamp.write_text(json.dumps(dict(schema_version=1, recipe_sha256=recipe,
                                    sources=deps, packages=packages, uvm_digests=uvm_digests), indent=2) + '\n')
    print('Prepared native toolchain. source .tools/activate.sh; make doctor')


if __name__ == '__main__':
    main()
