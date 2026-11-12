#!/usr/bin/env python3
"""Python/JSON/shell syntax and Python unit checks; no installed HDL tools."""
import ast
import json
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


def syntax(root=ROOT):
    paths = subprocess.check_output(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z',
         '--', '*.py', '*.json', '*.sh'], cwd=root).decode().split('\0')
    for suffix in ('.py', '.json', '.sh'):
        selected = [p for p in paths if p.endswith(suffix) and not p.startswith('work/')]
        if not selected:
            raise ValueError('Missing/empty syntax selection: ' + suffix)
        for name in selected:
            path = root / name
            if suffix == '.py':
                ast.parse(path.read_text(), filename=name)
            elif suffix == '.json':
                json.loads(path.read_text())
            else:
                subprocess.run(['bash', '-n', str(path)], check=True, timeout=30)
        print(f'{suffix} syntax: {len(selected)} files checked', flush=True)


def units(directory=ROOT / 'tests/toolchain'):
    if not directory.is_dir() or not list(directory.glob('test_*.py')):
        raise ValueError('Missing/empty Python unit selection: ' + str(directory))
    suite = unittest.defaultTestLoader.discover(str(directory), pattern='test_*.py')
    if suite.countTestCases() == 0:
        raise ValueError('Empty Python unit selection')
    return unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful()


def main():
    syntax()
    return 0 if units() else 1


if __name__ == '__main__':
    sys.exit(main())
