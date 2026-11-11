"""Bounded processes and per-case provenance shared by executable gates."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
RESULTS = {'PASS', 'FAIL', 'TIMEOUT', 'INCONCLUSIVE', 'UNSUPPORTED', 'TOOL_ERROR',
           'NOT_RUN', 'NOT_IMPLEMENTED'}
IGNORED = re.compile(r'%(?:Warning|Error)-(?:COVERIGN|CONSTRAINTIGN|UNSUPPORTED)')


def utc():
    return datetime.now(timezone.utc).isoformat()


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def provenance():
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=ROOT, text=True, timeout=30).strip()
    files = git('ls-files', '--cached', '--others', '--exclude-standard').splitlines()
    digests = {p: sha(ROOT / p) for p in files if (ROOT / p).is_file() and not p.startswith('work/')}
    return dict(source_revision=git('rev-parse', 'HEAD'), dirty=bool(git('status', '--porcelain')),
                source_digests=digests, dependency_digests={p: digests[p] for p in digests
                if p in ('tools/dependencies.json', 'tools/packages.lock.json')},
                constraint_digests={p: d for p, d in digests.items() if p.endswith(('.sdc', '.sby'))})


def execute(argv, directory, stem, timeout, cwd=None, env=None):
    """Kill the entire subprocess group on timeout, including compilers/solvers."""
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    start = utc()
    stdout, stderr = directory / (stem + '.stdout'), directory / (stem + '.stderr')
    result, returncode, error = 'PASS', None, None
    with stdout.open('w') as out, stderr.open('w') as err:
        try:
            process = subprocess.Popen(list(map(str, argv)), cwd=cwd or ROOT, env=env,
                                       stdout=out, stderr=err, start_new_session=True)
            try:
                returncode = process.wait(timeout=timeout)
                if returncode:
                    result, error = 'TOOL_ERROR', f'Process exited {returncode}'
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                returncode = process.wait()
                result, error = 'TIMEOUT', f'Timeout after {timeout}s; process group killed'
        except OSError as exc:
            result, error = 'TOOL_ERROR', str(exc)
            err.write(str(exc) + '\n')
    return dict(argv=list(map(str, argv)), cwd=str(cwd or ROOT), start_utc=start, end_utc=utc(),
                returncode=returncode, result=result, first_failure=error,
                stdout=str(stdout), stderr=str(stderr))


def output(step):
    return Path(step['stdout']).read_text(errors='replace') + Path(step['stderr']).read_text(errors='replace')


def completed(step, marker):
    text = output(step)
    functional_failure = re.search(r'UVM_(?:ERROR|FATAL)\s*(?:@|:.*[1-9])|TM_CAP_STABILITY_FAIL', text)
    if functional_failure and step['result'] != 'TIMEOUT':
        return 'FAIL', 'Functional assertion or UVM error/fatal reported'
    if step['result'] != 'PASS':
        return step['result'], step['first_failure']
    if IGNORED.search(text):
        return 'UNSUPPORTED', 'Required SV construct was ignored or unsupported'
    if marker not in text:
        return 'FAIL', 'Missing completion marker: ' + marker
    return 'PASS', None


class Case:
    def __init__(self, run, name, seed=None):
        self.path = run.path / name
        self.path.mkdir(parents=True)
        self.data = dict(schema_version=1, test=name, seed=seed, profile=run.profile,
                         start_utc=utc(), **run.provenance, tool_versions=run.versions,
                         steps=[], artifacts={})
        run.cases.append(self)

    def execute(self, argv, timeout=120, cwd=None, stem=None):
        step = execute(argv, self.path, stem or f'step{len(self.data["steps"])}', timeout, cwd)
        self.data['steps'].append(step)
        return step

    def finish(self, result, reason=None, **fields):
        assert result in RESULTS
        self.data.update(result=result, first_failure=reason, end_utc=utc(), **fields)
        (self.path / 'manifest.json').write_text(json.dumps(self.data, indent=2) + '\n')
        print(f'{self.data["test"]}: {result}' + (f' ({reason})' if reason else ''), flush=True)
        return result == 'PASS'


class Run:
    def __init__(self, path, profile='toolchain'):
        self.path, self.profile = Path(path).resolve(), profile
        self.path.mkdir(parents=True, exist_ok=True)
        self.provenance = provenance()
        self.versions, self.cases = {'python': sys.version.splitlines()[0]}, []

    def finish(self):
        for case in self.cases:
            if 'result' not in case.data:
                case.finish('TOOL_ERROR', 'Case did not finish')
        states = {c.data['result'] for c in self.cases}
        result = next((state for state in ('TIMEOUT', 'TOOL_ERROR', 'FAIL', 'UNSUPPORTED',
                      'INCONCLUSIVE', 'NOT_IMPLEMENTED', 'NOT_RUN') if state in states),
                      'PASS' if self.cases else 'TOOL_ERROR')
        summary = dict(schema_version=1, result=result, scope=getattr(self, 'scope', 'Toolchain capability fixtures only'),
                       cases=[dict(test=c.data['test'], result=c.data['result'],
                                   manifest=str(c.path / 'manifest.json')) for c in self.cases])
        (self.path / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(f'{result}: {self.path / "summary.json"}', flush=True)
        return 0 if result == 'PASS' else 1
