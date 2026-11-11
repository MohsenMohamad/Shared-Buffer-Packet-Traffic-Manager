#!/usr/bin/env python3
"""Validate repository contracts; this is not a hardware verification run."""
import json,re,sys,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
failures=[]
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
