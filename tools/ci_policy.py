#!/usr/bin/env python3
"""Select full CI from event metadata and the complete PR merge-base diff."""
import json
import os
from pathlib import Path
import re
import subprocess

# Only orientation/prose documents are cosmetic. Never allow all docs or *.md.
COSMETIC = frozenset(('README.md',))
REQUIRED = ('repository', 'policy', 'prepare', 'capability', 'contracts', 'storage',
            'csr', 'foundation')


def complete_paths(event, root):
    """Local Git has no API pagination cap; any missing history fails closed."""
    pr = event['pull_request']
    base, head = pr['base']['sha'], pr['head']['sha']
    if not all(re.fullmatch(r'[0-9a-f]{40}', sha) for sha in (base, head)):
        raise ValueError('Missing immutable PR base/head SHA')
    data = subprocess.check_output(
        ['git', 'diff', '--name-only', '--no-renames', '-z', base + '...' + head],
        cwd=root, timeout=60)
    if not data or not data.endswith(b'\0'):
        raise ValueError('Empty or incomplete PR diff')
    return data[:-1].decode('utf-8').split('\0')


def decision(name, event, paths=None, complete=False):
    if name in ('push', 'workflow_dispatch'):
        return True, 'main push or manual request'
    if name != 'pull_request':
        raise ValueError('Unsupported CI event: ' + name)
    action = event.get('action')
    labels = {label['name'] for label in event['pull_request'].get('labels', [])}
    if action == 'labeled':
        requested = event.get('label', {}).get('name') == 'full-ci'
        return requested, 'full-ci label request' if requested else 'unrelated label; no request'
    if action == 'ready_for_review':
        return True, 'ready-for-review request'
    if action not in ('opened', 'synchronize', 'reopened'):
        raise ValueError('Unsupported PR action: ' + str(action))
    if 'full-ci' in labels:
        return True, 'persistent full-ci request'
    if event['pull_request'].get('draft', False):
        return False, 'unlabeled draft iteration'
    if not complete or not paths:
        return True, 'incomplete diff; conservatively substantive'
    substantive = any(path not in COSMETIC for path in paths)
    return substantive, 'substantive PR diff' if substantive else 'allowlisted prose-only PR diff'


def qualification(needs):
    policy = needs.get('policy', {})
    requested = policy.get('outputs', {}).get('full')
    if policy.get('result') != 'success' or requested not in ('true', 'false'):
        return False, 'FAIL: missing/failed policy decision'
    if needs.get('repository', {}).get('result') != 'success':
        return False, 'FAIL: light repository/unit/syntax checks did not succeed'
    if requested == 'false':
        if any(needs.get(job, {}).get('result') != 'skipped' for job in REQUIRED[2:]):
            return False, 'FAIL: unrequested heavy jobs were not all skipped'
        return True, 'NOT_REQUESTED: light checks succeeded; full qualification did not execute'
    missing = [job for job in REQUIRED if needs.get(job, {}).get('result') != 'success']
    if missing:
        return False, 'FAIL: requested jobs failed, skipped or missing: ' + ', '.join(missing)
    return True, 'PASS: all requested full-CI suites succeeded'


def main():
    if os.environ.get('CI_SUMMARY_NEEDS'):
        ok, message = qualification(json.loads(os.environ['CI_SUMMARY_NEEDS']))
        print(message)
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as stream:
            stream.write(message + '\n')
        raise SystemExit(0 if ok else 1)
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    name = os.environ['GITHUB_EVENT_NAME']
    paths, complete = None, False
    if name == 'pull_request':
        try:
            paths = complete_paths(event, Path(__file__).resolve().parents[1])
            complete = True
        except (KeyError, OSError, ValueError, subprocess.SubprocessError) as error:
            print('Diff unavailable; treating as substantive:', error)
    full, reason = decision(name, event, paths, complete)
    print(f'Full CI requested: {full}; {reason}')
    with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
        stream.write(f'full={str(full).lower()}\n')
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as stream:
        stream.write(f'Full CI requested: **{full}**; {reason}.\n')


if __name__ == '__main__':
    main()
