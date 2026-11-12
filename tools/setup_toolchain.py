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
import zipfile
import sys
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


def recipe_digest():
    return hashlib.sha256(''.join(digest(ROOT / p) for p in
        ('tools/dependencies.json', 'tools/packages.lock.json', 'tools/setup_toolchain.py')).encode()).hexdigest()


def archive_name(name, pin):
    return name + ('.lib' if name == 'liberty' else '.zip' if pin.get('archive') == 'zip' else '.tar.gz')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', type=int, default=2)
    args = parser.parse_args()
    if not 1 <= args.jobs <= 8:
        parser.error('--jobs must be in 1..8')
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        parser.error('Only Linux x86-64 is qualified')
    if tuple(map(int, platform.libc_ver()[1].split('.')[:2])) < (2, 39):
        parser.error('glibc >= 2.39 required by the locked upstream Z3 binary')
    for tool in ('curl', 'dpkg-deb', 'g++', 'make', 'perl', 'git', 'pkg-config'):
        if not shutil.which(tool):
            parser.error('Missing bootstrap prerequisite: ' + tool)
    deps = json.loads((ROOT / 'tools/dependencies.json').read_text())
    packages = json.loads((ROOT / 'tools/packages.lock.json').read_text())['packages']
    cache = ROOT / '.deps/downloads'
    cache.mkdir(parents=True, exist_ok=True)
    prefix, sysroot = ROOT / '.tools/install', ROOT / '.tools/sysroot'
    logs = ROOT / '.build/setup'
    logs.mkdir(parents=True, exist_ok=True)
    downloads = {k: v for k, v in deps.items() if isinstance(v, dict) and 'url' in v}
    for pin in packages:
        fetch(pin, cache / pin['file'])
    for name, pin in downloads.items():
        fetch(pin, cache / archive_name(name, pin))
    recipe = recipe_digest()
    stamp = ROOT / '.tools/setup.json'
    needed = [prefix / 'bin' / name for name in ('verilator_bin', 'sby', 'yosys', 'yosys-abc', 'sta', 'z3')]
    needed += [ROOT / '.deps/src/uvm/src/uvm_pkg.sv', ROOT / '.tools/activate.sh']
    if stamp.is_file() and json.loads(stamp.read_text()).get('recipe_sha256') == recipe and all(p.is_file() for p in needed):
        print('Locked installation already prepared; downloads verified. Run make doctor.')
        return
    # A stale completion stamp must not survive any failed replacement build.
    stamp.unlink(missing_ok=True)
    if sysroot.is_symlink():
        sysroot.unlink()
    elif sysroot.exists():
        shutil.rmtree(sysroot)
    sysroot.mkdir(parents=True, exist_ok=True)
    prefix.mkdir(parents=True, exist_ok=True)
    for pin in packages:
        subprocess.run(['dpkg-deb', '-x', str(cache / pin['file']), str(sysroot)], check=True, timeout=120)
    # Debian alternatives are installed by maintainer scripts, which dpkg -x
    # does not execute. Supply exact local aliases instead of using host tools.
    (prefix / 'bin').mkdir(parents=True, exist_ok=True)
    for alias, target in {'automake':'automake-1.17', 'aclocal':'aclocal-1.17', 'tclsh':'tclsh8.6'}.items():
        link = prefix / 'bin' / alias
        link.unlink(missing_ok=True)
        link.symlink_to(sysroot / 'usr/bin' / target)
    # Relocate only packaged build-tool metadata, retaining license/doc files.
    mappings = {'/usr/share/autoconf': str(sysroot / 'usr/share/autoconf'),
                '/usr/share/automake-1.17': str(sysroot / 'usr/share/automake-1.17'),
                '/usr/share/aclocal-': str(sysroot / 'usr/share/aclocal-')}
    for directory in ('usr/bin', 'usr/share/autoconf', 'usr/share/automake-1.17'):
        for path in (sysroot / directory).rglob('*'):
            if path.is_file() and not path.is_symlink():
                try:
                    content = path.read_text()
                except UnicodeError:
                    continue
                for old, new in mappings.items():
                    content = content.replace(old, new)
                path.write_text(content)
    src = ROOT / '.deps/src'
    # Parent before children, so extracting Yosys never removes its locked submodules.
    names = sorted((n for n in downloads if n != 'liberty'), key=lambda n: deps[n].get('target', n).count('/'))
    for name in names:
        pin = deps[name]
        target = src / pin.get('target', name)
        archive = cache / archive_name(name, pin)
        if pin.get('archive') == 'zip':
            if target.exists():
                shutil.rmtree(target)
            target.mkdir(parents=True)
            with zipfile.ZipFile(archive) as stream:
                for info in stream.infolist():
                    relative = Path(*Path(info.filename).parts[1:])
                    if not relative.parts:
                        continue
                    destination = target / relative
                    if not destination.resolve().is_relative_to(target.resolve()):
                        raise ValueError('External zip path')
                    if info.is_dir():
                        destination.mkdir(parents=True, exist_ok=True)
                    else:
                        destination.parent.mkdir(parents=True, exist_ok=True)
                        destination.write_bytes(stream.read(info))
                        destination.chmod((info.external_attr >> 16) & 0o777 or 0o644)
        else:
            marker = target / '.archive-sha256'
            fresh = not marker.is_file() or marker.read_text().strip() != digest(archive)
            build_name = 'yosys' if pin.get('target', name).startswith('yosys') else name
            if fresh and build_name in ('yosys','opensta','eigen'):
                shutil.rmtree(logs / build_name, ignore_errors=True)
            unpack(archive, target, reuse=True)
    shutil.copyfile(cache / 'liberty.lib', ROOT / '.deps/liberty.lib')
    env = os.environ.copy()
    # Do not inherit another activated installation's PATH, Python or shared libraries.
    host_path = '/usr/local/bin:/usr/bin:/bin'
    env.update(PATH=f'{prefix}/bin:{src}/cmake/bin:{sysroot}/usr/bin:{host_path}',
               LD_LIBRARY_PATH=f'{prefix}/lib:{sysroot}/usr/lib/x86_64-linux-gnu',
               AC_MACRODIR=str(sysroot / 'usr/share/autoconf'),
               AUTOM4TE_CFG=str(sysroot / 'usr/share/autoconf/autom4te.cfg'),
               PERL5LIB=str(sysroot / 'usr/share/autoconf'),
               ACLOCAL_PATH=str(sysroot / 'usr/share/aclocal-1.17'),
               BISON_PKGDATADIR=str(sysroot / 'usr/share/bison'),
               AUTOM4TE=str(sysroot / 'usr/bin/autom4te'), M4=str(sysroot / 'usr/bin/m4'),
               PYTHONPATH=f'{prefix}/share/python3:{prefix}/share/yosys/python3:{prefix}/share/yosys',
               TCL_LIBRARY=str(sysroot / 'usr/share/tcltk/tcl8.6'),
               UVM_HOME=str(src / 'uvm'),
               GIT_CEILING_DIRECTORIES=str(src),
               PKG_CONFIG_LIBDIR=str(sysroot / 'usr/lib/x86_64-linux-gnu/pkgconfig'),
               PKG_CONFIG_SYSROOT_DIR=str(sysroot))
    for key, tool in {'AUTOCONF':'autoconf', 'AUTOHEADER':'autoheader', 'AUTORECONF':'autoreconf'}.items():
        env[key] = str(sysroot / 'usr/bin' / tool)
    env['ACLOCAL'] = str(prefix / 'bin/aclocal')
    env['AUTOMAKE'] = str(prefix / 'bin/automake')
    env['CPLUS_INCLUDE_PATH'] = str(sysroot / 'usr/include')
    env['C_INCLUDE_PATH'] = str(sysroot / 'usr/include')
    env['CC'] = shutil.which(env.get('CC', 'gcc'), path=host_path) or env.get('CC', 'gcc')
    env['CXX'] = shutil.which(env.get('CXX', 'g++'), path=host_path) or env.get('CXX', 'g++')
    records = []

    def step(name, argv, cwd=None, timeout=3600):
        print('Setup: ' + name, flush=True)
        record = execute(argv, logs, name, timeout, cwd=cwd or ROOT, env=env)
        records.append(record)
        (logs / 'steps.json').write_text(json.dumps(records, indent=2) + '\n')
        if record['result'] != 'PASS':
            raise RuntimeError(f'{name}: {record["result"]}; inspect {logs}')

    probe = logs / 'compiler.cpp'
    probe.write_text('#include <format>\nint main(){return std::format("{}",42)!="42";}\n')
    step('compiler', [env['CXX'], '-std=c++20', str(probe), '-o', str(logs / 'compiler')])
    step('compiler-run', [str(logs / 'compiler')])
    common = ['-G', 'Unix Makefiles', '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_INSTALL_PREFIX=' + str(prefix),
              '-DCMAKE_C_COMPILER=' + env['CC'], '-DCMAKE_CXX_COMPILER=' + env['CXX'],
              '-DFETCHCONTENT_FULLY_DISCONNECTED=ON']
    yosys_build = ROOT / '.build/setup/yosys'
    # Built-in slang and all its header libraries come from the selected Yosys
    # release gitlinks. Optional interactive/DPI/Python integrations are not used.
    step('yosys-configure', ['cmake', '-S', str(src / 'yosys'), '-B', str(yosys_build), *common,
         '-DCMAKE_DISABLE_FIND_PACKAGE_Git=TRUE', '-DYOSYS_USE_BUNDLED_LIBS=ON',
         '-DYOSYS_ENABLE_UNIT_TESTS=OFF', '-DYOSYS_WITHOUT_READLINE=ON', '-DYOSYS_WITHOUT_EDITLINE=ON',
         '-DYOSYS_WITHOUT_LIBFFI=ON', '-DYOSYS_WITHOUT_TCL=ON', '-DYOSYS_WITH_PYTHON=OFF',
         '-DYOSYS_SLANG_REVISION=' + deps['sv_elab']['commit'], '-DSLANG_REVISION=' + deps['slang']['commit'],
         '-DSLANG_INCLUDE_TOOLS=OFF', '-DSLANG_INCLUDE_TESTS=OFF', '-DSLANG_INCLUDE_INSTALL=OFF'])
    step('yosys-build', ['cmake', '--build', str(yosys_build), '--target', 'yosys', 'yosys-abc', 'yosys-filterlib', '-j', str(args.jobs)], timeout=7200)
    step('yosys-install', ['cmake', '--install', str(yosys_build)])
    for name, argv in [('autoconf', ['autoconf']), ('configure', ['./configure', '--prefix=' + str(prefix)]),
                       ('build', ['make', '-C', 'src', '-j' + str(args.jobs), 'opt']),
                       ('install', ['make', 'installbin', 'installredirect', 'installdata', 'VL_INST_PUBLIC_BIN_FILES=verilator_bin verilator_coverage_bin'])]:
        step('verilator-' + name, argv, src / 'verilator')
    shutil.copytree(src / 'click/src/click', prefix / 'share/python3/click', dirs_exist_ok=True)
    (prefix / 'share/licenses/click').mkdir(parents=True, exist_ok=True)
    shutil.copy2(src / 'click/LICENSE.txt', prefix / 'share/licenses/click/LICENSE.txt')
    step('sby', ['make', 'PREFIX=' + str(prefix), 'install'], src / 'sby')
    for name in ('z3',):
        for binary in (src / name / 'bin').iterdir():
            if binary.is_file():
                target = prefix / 'bin' / binary.name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(binary, target)
    step('swig-autogen', ['sh', 'autogen.sh'], src / 'swig')
    step('swig-configure', ['./configure', '--prefix=' + str(prefix), '--without-pcre', '--without-alllang', '--disable-ccache'], src / 'swig')
    step('swig-build', ['make', '-j' + str(args.jobs)], src / 'swig')
    step('swig-install', ['make', 'install'], src / 'swig')
    step('cudd-configure', ['./configure', '--prefix=' + str(prefix), '--enable-shared=no', '--enable-static=yes', '--with-pic'], src / 'cudd')
    step('cudd-build', ['make', '-j' + str(args.jobs)], src / 'cudd')
    step('cudd-install', ['make', 'install'], src / 'cudd')
    eigen_build = logs / 'eigen'
    step('eigen-configure', ['cmake', '-S', str(src / 'eigen'), '-B', str(eigen_build), *common,
                            '-DBUILD_TESTING=OFF', '-DEIGEN_BUILD_TESTING=OFF', '-DEIGEN_BUILD_DOC=OFF',
                            '-DEIGEN_BUILD_BLAS=OFF', '-DEIGEN_BUILD_LAPACK=OFF', '-DEIGEN_BUILD_DEMOS=OFF',
                            '-DCMAKE_EXPORT_PACKAGE_REGISTRY=OFF'])
    step('eigen-install', ['cmake', '--install', str(eigen_build)])
    sta_build = logs / 'opensta'
    # Upstream's CMake helper walks parent directories itself, ignoring Git's
    # ceiling setting. Supply the checksum-verified archive identity explicitly.
    sta_identity = logs / 'opensta-source-identity.cmake'
    sta_identity.write_text('set(__get_git_revision_description YES)\n'
                            'function(get_git_head_revision ref hash)\n'
                            '  set(${ref} "PINNED_SOURCE_ARCHIVE" PARENT_SCOPE)\n'
                            '  set(${hash} "' + deps['opensta']['commit'] + '" PARENT_SCOPE)\n'
                            'endfunction()\n')
    step('opensta-configure', ['cmake', '-S', str(src / 'opensta'), '-B', str(sta_build), *common,
         '-DCMAKE_PROJECT_INCLUDE=' + str(sta_identity),
         '-DUSE_TCL_READLINE=OFF', '-DCUDD_DIR=' + str(prefix), '-DCUDD_LIB=' + str(prefix / 'lib/libcudd.a'),
         '-DCUDD_INCLUDE=' + str(prefix / 'include'), '-DEigen3_DIR=' + str(prefix / 'share/eigen3/cmake'),
         '-DTCL_LIBRARY=' + str(sysroot / 'usr/lib/x86_64-linux-gnu/libtcl8.6.so'),
         '-DTCL_INCLUDE_PATH=' + str(sysroot / 'usr/include/tcl8.6'),
         '-DTCL_HEADER=' + str(sysroot / 'usr/include/tcl8.6/tcl.h'),
         '-DFLEX_INCLUDE_DIR=' + str(sysroot / 'usr/include'),
         '-DTCL_TCLSH=' + str(sysroot / 'usr/bin/tclsh8.6'),
         '-DZLIB_LIBRARY=' + str(sysroot / 'usr/lib/x86_64-linux-gnu/libz.so.1'),
         '-DZLIB_INCLUDE_DIR=' + str(sysroot / 'usr/include')])
    step('opensta-build', ['cmake', '--build', str(sta_build), '-j', str(args.jobs)])
    step('opensta-install', ['cmake', '--install', str(sta_build)])
    # CMake is a runtime bootstrap input, so retain its distribution inside the
    # sealed install rather than depending on discarded development sources.
    shutil.copytree(src / 'cmake', prefix / 'cmake', dirs_exist_ok=True)
    env['PATH'] = f'{prefix}/bin:{prefix}/cmake/bin:{sysroot}/usr/bin:{host_path}'
    keys = ('PATH', 'LD_LIBRARY_PATH', 'PYTHONPATH', 'TCL_LIBRARY', 'UVM_HOME')
    (ROOT / '.tools/environment.json').write_text(json.dumps({k: env[k] for k in keys}, indent=2) + '\n')
    (ROOT / '.tools/activate.sh').write_text(''.join(f'export {k}={shlex.quote(env[k])}\n' for k in keys))
    uvm_digests = {str(p.relative_to(ROOT)): digest(p) for p in (src / 'uvm/src').rglob('*') if p.is_file()}
    identities = {name: dict(commit=pin.get('commit'), archive_sha256=pin['sha256']) for name, pin in downloads.items()}
    stamp.write_text(json.dumps(dict(schema_version=2, recipe_sha256=recipe, sources=deps, packages=packages,
                                    uvm_digests=uvm_digests, source_identities=identities,
                                    build_host=dict(compiler=subprocess.check_output([env['CXX'], '--version'], text=True).strip(),
                                                    libc=platform.libc_ver(), architecture=platform.machine())), indent=2) + '\n')
    print('Prepared native toolchain. source .tools/activate.sh; make doctor')


if __name__ == '__main__':
    main()
