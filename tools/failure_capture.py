"""Durable source patches and bounded diagnostics for unexpected case failures."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from uuid import uuid4

CAPTURE_PATH = 'verification/failures'
SOURCE_PATHS = ['.', ':(exclude)' + CAPTURE_PATH]


def git(root, *args, diff=False):
    result = subprocess.run(['git', *args], cwd=root, capture_output=True, timeout=30)
    if result.returncode not in ((0, 1) if diff else (0,)):
        raise RuntimeError(result.stderr.decode(errors='replace').strip())
    return result.stdout


def snapshot(root):
    """HEAD plus tracked edits and nonignored new files, excluding prior captures."""
    revision = git(root, 'rev-parse', 'HEAD').decode().strip()
    patch = git(root, 'diff', '--no-ext-diff', '--binary', 'HEAD', '--', *SOURCE_PATHS)
    untracked = git(root, 'ls-files', '--others', '--exclude-standard', '-z',
                    '--', *SOURCE_PATHS).split(b'\0')
    for name in filter(None, untracked):
        patch += git(root, 'diff', '--no-ext-diff', '--no-index', '--binary',
                     '--', '/dev/null', os.fsdecode(name), diff=True)
    return revision, patch


def log_tail(name):
    if not name:
        return dict(text='', unavailable='No log path')
    try:
        with Path(name).open('rb') as stream:
            size = stream.seek(0, os.SEEK_END)
            stream.seek(max(0, size - 65536))
            lines = stream.read().decode(errors='replace').splitlines()
        text = '\n'.join(lines[-40:])
        return dict(text=text[-8192:], truncated=size > 65536 or len(lines) > 40
                    or len(text) > 8192)
    except OSError as error:
        return dict(text='', unavailable=str(error))


def capture_failure(data, path, root):
    root, path = Path(root), Path(path)
    directory = root / CAPTURE_PATH
    directory.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    test = re.sub(r'[^A-Za-z0-9_.-]+', '_', str(data['test']))[:80]
    name = f'{stamp}-{test}-{uuid4().hex[:12]}'
    record = {key: data[key] for key in ('test', 'result', 'first_failure', 'profile',
              'seed', 'tool_versions', 'parameters', 'source_set', 'source_digests',
              'dependency_digests', 'constraint_digests') if key in data}
    record.update(schema_version=1, captured_utc=stamp, disposition='unclassified',
                  run_source_revision=data.get('source_revision'),
                  run_dirty=data.get('dirty'), run_directory=str(path),
                  steps=data.get('steps', []), artifacts=data.get('artifacts', {}))
    try:
        revision, patch = snapshot(root)
        record.update(source_revision=revision, dirty=bool(patch), source_patch=None)
        if patch:
            patch_path = directory / (name + '.patch')
            patch_path.write_bytes(patch)
            record.update(source_patch=patch_path.name,
                          source_patch_sha256=hashlib.sha256(patch).hexdigest())
        # The run records digests before execution; do not silently claim that a
        # later source snapshot is the same if files changed during the run.
        mismatches = []
        for filename, expected in data.get('source_digests', {}).items():
            if filename.startswith(CAPTURE_PATH + '/'):
                continue
            source = root / filename
            actual = hashlib.sha256(source.read_bytes()).hexdigest() if source.is_file() else None
            if actual != expected:
                mismatches.append(filename)
        if 'source_digests' in data:
            current = git(root, 'ls-files', '--cached', '--others', '--exclude-standard',
                          '-z', '--', *SOURCE_PATHS).split(b'\0')
            mismatches += [os.fsdecode(p) for p in filter(None, current)
                           if os.fsdecode(p) not in data['source_digests']
                           and not os.fsdecode(p).startswith('work/')
                           and (root / os.fsdecode(p)).is_file()]
        record['changed_since_run_start'] = mismatches
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        record['source_capture_error'] = str(error)
    # Keep the first failing command's diagnostics even if the case subsequently
    # reran successfully for tracing; the last command alone can hide the failure.
    steps = data.get('steps', [])
    selected = [i for i, step in enumerate(steps) if step.get('result') != 'PASS']
    selected = sorted(set(selected[:1] + selected[-1:] + ([len(steps)-1] if steps else [])))
    record['log_tails'] = [dict(step=i, stdout=log_tail(steps[i].get('stdout')),
                              stderr=log_tail(steps[i].get('stderr'))) for i in selected]
    target = directory / (name + '.json')
    temporary = target.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(record, indent=2) + '\n')
    temporary.replace(target)
    return str(target.relative_to(root))
