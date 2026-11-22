#!/usr/bin/env python3
"""Validate repository contracts; this is not a hardware verification run."""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

from ci_policy import complete_paths

ROOT = Path(__file__).resolve().parents[1]


def raw_artifact(path):
    if path.startswith(('.build/', '.work/', 'work/')):
        return True
    name = path.rsplit('/', 1)[-1].lower()
    if path.startswith('verification/failures/'):
        return path != 'verification/failures/README.md'
    if path.startswith('docs/results/'):
        return name.endswith(('.json', '.jsonl', '.log', '.stdout', '.stderr', '.vcd',
                              '.fst', '.tar.gz', '.tar.zst', '.zip', '-annotations.txt',
                              '.dat'))
    return path.startswith('verification/') and name in {
        'results.json', 'manifest.json', 'summary.json', 'coverage.dat',
    }


def changed_paths(pr_diff):
    if pr_diff:
        event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
        return complete_paths(event, ROOT, include_deletions=False)
    # Check the index and tracked edits locally, including anything force-added.
    diff = ['git', 'diff', '--name-only', '--no-renames', '--diff-filter=ACMRT', '-z']
    paths = subprocess.check_output(diff, cwd=ROOT, timeout=60)
    staged = subprocess.check_output([*diff, '--cached', 'HEAD'], cwd=ROOT, timeout=60)
    return os.fsdecode(paths + staged).split('\0')


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--pr-diff', action='store_true', help='Check the full PR merge-base diff')
args = parser.parse_args()
try:
    failures = [f'{path!r}: raw run artifact belongs in ignored storage or CI artifacts'
                for path in sorted(set(changed_paths(args.pr_diff))) if raw_artifact(path)]
except (KeyError, OSError, ValueError, subprocess.SubprocessError) as error:
    sys.exit(f'Unable to check raw artifacts: {error}')

# Limit checks to repository inputs, excluding ignored dependency/scratch trees.
paths=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','--','*.md'],cwd=ROOT,text=True).splitlines()
for path in paths:
    f=ROOT/path
    if any(p.startswith('.') for p in f.relative_to(ROOT).parts):
        continue
    text=f.read_text()
    if text.count('```')%2:
        failures.append(f'{f.relative_to(ROOT)}: unbalanced code fence')
    for target in re.findall(r'\]\(([^)\s]+)\)',text):
        if target.startswith(('http:','https:','mailto:','#')):
            continue
        if not (f.parent/target.split('#',1)[0]).exists():
            failures.append(f'{f.relative_to(ROOT)}: missing link {target}')
def validate_requirements(data):
    if (not isinstance(data, dict) or set(data) != {'schema_version', 'requirements'}
            or data['schema_version'] != 2 or not isinstance(data['requirements'], list)):
        raise ValueError('expected the version 2 requirements-only schema')
    rows = data['requirements']
    if not rows:
        raise ValueError('empty requirement catalog')
    ids = set()
    for index, row in enumerate(rows, 1):
        if not isinstance(row, dict) or set(row) != {'id', 'name', 'requirement'}:
            raise ValueError(f'requirement row {index} must contain only id, name and requirement')
        if not all(isinstance(value, str) and value.strip() for value in row.values()):
            raise ValueError(f'requirement row {index} contains empty or non-text fields')
        ident = row['id']
        if not re.fullmatch(r'[A-Z]+-[0-9]{2}', ident) or ident in ids:
            raise ValueError(f'invalid or duplicate requirement ID: {ident}')
        ids.add(ident)
    return ids


ids = set()
try:
    ids = validate_requirements(json.loads((ROOT / 'verification/requirements.json').read_text()))
    json.loads((ROOT / 'tools/dependencies.json').read_text())
except (OSError, ValueError) as error:
    failures.append(f'Invalid repository input: {error}')
if failures:
    print('\n'.join(failures),file=sys.stderr);sys.exit(1)
print(f'Repository contracts: PASS ({len(ids)} requirements; hardware not evaluated)')
