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
    if not path.startswith(('verification/failures/', 'docs/results/')):
        return False
    name = path.rsplit('/', 1)[-1].lower()
    return (name.endswith(('.log', '.stdout', '.stderr', '.vcd', '.fst', '.tar.gz',
                           '.tar.zst', '.zip', '-annotations.txt'))
            or name in {'manifest.json', 'summary.json', 'coverage.dat'})


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
data=json.loads((ROOT/'verification/requirements.json').read_text())
ids=[r['id'] for r in data['requirements']]
if len(ids)!=len(set(ids)) or len(ids)<40:
    failures.append('requirement IDs must be unique and complete')
allowed={'NOT_IMPLEMENTED','NOT_RUN','PASS','FAIL','TIMEOUT','INCONCLUSIVE','UNSUPPORTED','TOOL_ERROR'}
for row in data['requirements']:
    if row['status'] not in allowed:
        failures.append('invalid requirement status '+row['id'])
    if row['status']=='PASS' and not row.get('tests'):
        failures.append('PASS has no test mapping: '+row['id'])
for path in ['tools/dependencies.json','verification/requirements.json']:
    json.loads((ROOT/path).read_text())
if failures:
    print('\n'.join(failures),file=sys.stderr);sys.exit(1)
print(f'Repository contracts: PASS ({len(ids)} requirements; hardware not evaluated)')
