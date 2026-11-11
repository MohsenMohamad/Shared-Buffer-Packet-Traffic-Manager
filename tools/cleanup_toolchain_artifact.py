#!/usr/bin/env python3
"""Delete only the handoff uploaded by this run/attempt; retain diagnostics."""
import argparse
import json
import os
from pathlib import Path
import re
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def api_request(method, path, token):
    request = Request('https://api.github.com' + path, method=method, headers={
        'Authorization': 'Bearer ' + token,
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
    })
    with urlopen(request, timeout=30) as response:
        data = response.read()
    return json.loads(data) if data else None


def cleanup(repository, run_id, attempt, artifact_id, token):
    report = dict(status='retention-fallback', artifact_id=artifact_id,
                  artifact_name=f'toolchain-{run_id}-{attempt}')
    if not artifact_id:
        report.update(status='not-selected',
                      reason='No completed producer handoff ID; no artifact selected. '
                             'Any handoff left by cancellation retains its one-day expiry.')
        return report
    try:
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
            raise ValueError('Invalid repository selector')
        if any(not re.fullmatch(r'[1-9][0-9]*', str(value))
               for value in (run_id, attempt, artifact_id)):
            raise ValueError('Run, attempt and artifact IDs must be positive integers')
        if not token:
            raise ValueError('No cleanup token available')
        path = f'/repos/{repository}/actions/artifacts/{artifact_id}'
        metadata = api_request('GET', path, token)
        if not isinstance(metadata, dict) or not isinstance(metadata.get('workflow_run'), dict):
            raise ValueError('Artifact metadata lacks a verifiable workflow run')
        if (str(metadata.get('id')) != str(artifact_id)
                or metadata.get('name') != report['artifact_name']
                or str(metadata['workflow_run'].get('id')) != str(run_id)):
            raise ValueError('Artifact ID/name/run does not match this run and attempt; refusing deletion')
        api_request('DELETE', path, token)
        report.update(status='deleted', reason='Deleted only this run/attempt handoff; diagnostics retained.')
    except HTTPError as error:
        # GitHub can conceal inaccessible private resources behind HTTP 404.
        # Do not turn unavailable metadata into a successful-deletion claim.
        report['reason'] = f'GitHub API HTTP {error.code}; cleanup not confirmed'
    except (OSError, URLError, ValueError) as error:
        report['reason'] = f'Cleanup not confirmed: {error}'
    return report


def publish(report):
    message = f'Handoff {report["artifact_name"]} ({report["artifact_id"] or "no ID"}): {report["reason"]}'
    if report['status'] == 'retention-fallback':
        message += '. Any remaining handoff expires after one day.'
    escaped = message.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    level = 'warning' if report['status'] == 'retention-fallback' else 'notice'
    print(f'::{level}::{escaped}', flush=True)
    print(json.dumps(report, sort_keys=True), flush=True)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a') as stream:
            stream.write('### Toolchain handoff cleanup\n\n' + message + '\n')
    if os.environ.get('GITHUB_OUTPUT'):
        with Path(os.environ['GITHUB_OUTPUT']).open('a') as stream:
            stream.write('status=' + report['status'] + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', required=True)
    parser.add_argument('--run-id', required=True)
    parser.add_argument('--run-attempt', required=True)
    parser.add_argument('--artifact-id', required=True)
    args = parser.parse_args()
    publish(cleanup(args.repository, args.run_id, args.run_attempt, args.artifact_id,
                    os.environ.get('GITHUB_TOKEN', '')))


if __name__ == '__main__':
    main()
