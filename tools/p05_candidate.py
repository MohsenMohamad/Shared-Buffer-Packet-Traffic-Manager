#!/usr/bin/env python3
"""Opaque exact-source candidate entry: preserve child status and private diagnostics."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
from uuid import uuid4

ROOT=Path(__file__).resolve().parents[1]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rtl-revision',required=True)
    parser.add_argument('--profile',default='I1')
    parser.add_argument('--seed',type=int,default=17)
    parser.add_argument('--jobs',type=int,default=2)
    parser.add_argument('--timeout',type=float)
    parser.add_argument('--formal',action='store_true')
    args=parser.parse_args()
    directory=ROOT/'.build/p05-public'/uuid4().hex;directory.mkdir(parents=True)
    command=[sys.executable,str(ROOT/'tools/run.py'),'formal-rtl' if args.formal else 'regression',
             '--profile',args.profile,'--test','memory-tx','--candidate-revision',args.rtl_revision,
             '--jobs',str(args.jobs),'--timeout',str(args.timeout or (300 if args.formal else 180)),
             '--build-timeout','600','--output',str(directory/'runs')]
    if not args.formal:command+=['--seed',str(args.seed)]
    with (directory/'dv.stdout').open('w') as out,(directory/'dv.stderr').open('w') as err:
        child=subprocess.run(command,cwd=ROOT,stdout=out,stderr=err)
    summaries=list((directory/'runs').glob('*/summary.json'))
    summary=json.loads(summaries[0].read_text()) if len(summaries)==1 else {}
    ok=child.returncode==0 and summary.get('result')=='PASS' and bool(summary.get('cases'))
    report=dict(result='PASS' if ok else 'FAIL',requested_rtl_revision=args.rtl_revision,
                profile=args.profile,seed=None if args.formal else args.seed,child_returncode=child.returncode,
                executed_command=command,diagnostics=str(directory),summary=summary)
    candidate=list((directory/'runs').glob('*/candidate-public.json'))
    if len(candidate)==1:report['candidate']=json.loads(candidate[0].read_text())
    (directory/'public-result.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(dict(result=report['result'],rtl_revision=args.rtl_revision,profile=args.profile,
                         child_returncode=child.returncode,public_result=str(directory/'public-result.json'))))
    return 0 if ok else child.returncode if child.returncode>0 else 128-child.returncode if child.returncode<0 else 1


if __name__=='__main__':raise SystemExit(main())
