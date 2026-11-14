#!/usr/bin/env python3
"""Combine pinned candidate with a clean detached DV checkout at its prepared path."""
import json
from pathlib import Path
import subprocess
from evidence import ROOT, Run, Case, utc


def git(*args):
    return subprocess.check_output(['git',*args],cwd=ROOT,text=True).strip()


def main():
    identity=json.loads((ROOT/'verification/candidates/p05.json').read_text())
    candidate=identity['rtl_revision']
    if subprocess.run(['git','symbolic-ref','-q','HEAD'],cwd=ROOT,capture_output=True).returncode==0:
        raise SystemExit('Candidate CI staging requires a detached disposable checkout')
    if git('status','--porcelain'):raise SystemExit('Candidate CI staging requires a clean checkout')
    dv=git('rev-parse','HEAD');base=git('rev-parse','origin/main')
    run=Run(ROOT/'.build/runs'/('p05-ci-stage-'+utc().replace(':','')))
    case=Case(run,'p05-ci-combination')
    step=case.execute(['git','fetch','origin',candidate],timeout=120)
    if step['result']!='PASS':case.finish(step['result'],step['first_failure']);return run.finish()
    step=case.execute(['git','-c','user.name=P05 qualification CI','-c','user.email=p05-qualification@invalid',
                       'merge','--no-ff',candidate,'-m','test: stage exact P05 candidate for CI'],timeout=120)
    if step['result']!='PASS':case.finish(step['result'],step['first_failure']);return run.finish()
    record=dict(main_revision=base,dv_revision=dv,rtl_revision=candidate,combined_revision=git('rev-parse','HEAD'),
                combined_tree=git('rev-parse','HEAD^{tree}'),resolutions=[],dirty=bool(git('status','--porcelain')))
    (ROOT/'.build/p05-ci-combination.json').write_text(json.dumps(record,indent=2)+'\n')
    case.finish('PASS',combination=record)
    return run.finish()


if __name__=='__main__':raise SystemExit(main())
