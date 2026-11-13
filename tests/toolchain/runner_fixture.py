"""Isolated current runner sources for CLI tests; no capture redirection switch."""
from pathlib import Path
import shutil
import subprocess


def isolated_runner_repository(destination, source):
    destination, source = Path(destination), Path(source)
    destination.mkdir(parents=True)
    for name in ('tools', 'verification'):
        shutil.copytree(source / name, destination / name,
                        ignore=shutil.ignore_patterns('__pycache__', 'failures'))
    def git(*args):
        subprocess.run(['git', *args], cwd=destination, check=True, capture_output=True)
    git('init', '-q')
    git('config', 'user.name', 'Fixture')
    git('config', 'user.email', 'fixture@example.invalid')
    git('add', '.')
    git('commit', '-qm', 'Runner test fixture')
    return destination
