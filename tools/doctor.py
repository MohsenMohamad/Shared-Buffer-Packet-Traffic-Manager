#!/usr/bin/env python3
"""Report exact installed versions and bootstrap capabilities; not hardware validation."""
import json
import hashlib
import os
from pathlib import Path
import re
import sys

from evidence import Case, ROOT, Run, completed, output, sha

PROBES = {
    'verilator': (['verilator', '--version'], r'Verilator 5\.054\b'),
    'verilator_coverage': (['verilator_coverage', '--version'], r'Verilator 5\.054\b'),
    'yosys': (['yosys', '-V'], r'Yosys 0\.52 .*fee39a3284c90249e1d9684cf6944ffbbcbb8f90'),
    'abc': (['yosys-abc', '-c', 'version'], r'UC Berkeley, ABC'),
    'sby': (['sby', '--version'], r'SBY v0\.71\b'),
    'z3': (['z3', '--version'], r'Z3 version 4\.13\.3\b'),
    'opensta': (['sta', '-version'], r'2\.0\.17\b'),
    'compiler': ([os.environ.get('CXX', 'g++'), '--version'], r'14\.2\.0\b'),
    'python': ([sys.executable, '--version'], r'Python 3\.(?:1[1-9]|[2-9][0-9])\.'),
    'make': (['make', '--version'], r'GNU Make'),
    'bash': (['bash', '--version'], r'GNU bash'),
}


def qualify(run):
    case = Case(run, 'versions')
    failures = []
    for name, (argv, expected) in PROBES.items():
        step = case.execute(argv, timeout=30, stem=name)
        text = output(step).strip()
        run.versions[name] = text if text else 'unavailable'
        if step['result'] != 'PASS' or not re.search(expected, text):
            failures.append(name + ': missing executable or incompatible version')
    try:
        stamp = json.loads((ROOT / '.tools/setup.json').read_text())
        deps = json.loads((ROOT / 'tools/dependencies.json').read_text())
        if stamp['sources'] != deps:
            failures.append('Setup does not match dependency lock; rerun tools/setup.sh')
        recipe = hashlib.sha256(''.join(sha(ROOT / p) for p in
            ('tools/dependencies.json', 'tools/packages.lock.json', 'tools/setup_toolchain.py')).encode()).hexdigest()
        if stamp['recipe_sha256'] != recipe:
            failures.append('Setup recipe changed; rerun tools/setup.sh')
        if stamp['packages'] != json.loads((ROOT / 'tools/packages.lock.json').read_text())['packages']:
            failures.append('Setup package set differs from lock')
        for name in ('verilator', 'uvm', 'sby', 'liberty'):
            path = ROOT / '.deps/downloads' / (name + ('.lib' if name == 'liberty' else '.tar.gz'))
            if sha(path) != deps[name]['sha256']:
                failures.append('Archive checksum mismatch: ' + name)
        if not stamp['uvm_digests']:
            failures.append('Missing UVM source provenance')
        for path, expected in stamp['uvm_digests'].items():
            if sha(ROOT / path) != expected:
                failures.append('UVM source modified: ' + path)
        if sha(ROOT / '.deps/liberty.lib') != deps['liberty']['sha256']:
            failures.append('Liberty checksum mismatch')
        if Path(os.environ.get('UVM_HOME', '')).resolve() != ROOT / '.deps/src/uvm':
            failures.append('UVM_HOME must select the repository installation')
    except (OSError, KeyError, ValueError) as error:
        failures.append('Missing or malformed locked setup: ' + str(error))
    case.finish('TOOL_ERROR' if failures else 'PASS', '; '.join(failures) or None)
    cxx = Case(run, 'cxx20')
    source = cxx.path / 'probe.cpp'
    source.write_text('#include <concepts>\n#include <iostream>\n'
                      'template<std::integral T> T twice(T x) { return x+x; }\n'
                      'int main(){ if(twice(21)!=42) return 1; std::cout<<"TM_CXX20_PASS\\n"; }\n')
    build = cxx.execute([os.environ.get('CXX', 'g++'), '-std=c++20', str(source), '-o', str(cxx.path / 'probe')])
    if build['result'] != 'PASS':
        cxx.finish(build['result'], build['first_failure'])
    else:
        cxx.finish(*completed(cxx.execute([str(cxx.path / 'probe')]), 'TM_CXX20_PASS'))
    z3 = Case(run, 'solver-sat-unsat')
    smt = z3.path / 'probe.smt2'
    smt.write_text('(declare-const x Int)\n(assert (= x 3))\n(check-sat)\n'
                   '(assert (= x 4))\n(check-sat)\n')
    step = z3.execute(['z3', str(smt)])
    ok = step['result'] == 'PASS' and output(step).split() == ['sat', 'unsat']
    z3.finish('PASS' if ok else step['result'] if step['result'] != 'PASS' else 'FAIL',
              None if ok else 'Expected SAT followed by UNSAT')


if __name__ == '__main__':
    from run import main
    sys.exit(main(['doctor', *sys.argv[1:]]))
