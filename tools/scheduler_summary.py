#!/usr/bin/env python3
"""Compact actual scheduler results; raw processes remain in their artifacts."""
import argparse
import json
import os
from pathlib import Path


def collect(root):
    root=root.resolve()
    records=[];runs=[];provenance={}
    for path in sorted(root.glob('*/summary.json')):
        summary=json.loads(path.read_text())
        selected=[]
        for entry in summary['cases']:
            manifest=Path(entry['manifest'])
            data=json.loads(manifest.read_text())
            if not data['test'].startswith(('scheduler-','rtl-scheduler-')): continue
            keys=('test','result','first_failure','seed','profile','source_revision','dirty','parameters',
                  'configuration','expected','detector','observed_fatals','observed_basecase_assertions',
                  'reached_covers','engine_status','method','assumptions','metrics','finite_endpoints',
                  'coverage','stress','requested_seeds','replay','response_bound','tx_retirement_bound')
            row={key:data[key] for key in keys if key in data}
            row['artifact_digests']={key:value for key,value in data['artifacts'].items() if key.endswith('_sha256')}
            row['raw_case']=str(manifest.relative_to(root))
            selected.append(row)
            identity=data['source_revision']+('-dirty' if data['dirty'] else '')
            if identity not in provenance:
                versions=data['tool_versions']
                provenance[identity]=dict(dependencies=data['dependency_digests'],constraints=data['constraint_digests'],
                    source_digests=data.get('registered_source_digests',{}),
                    tools={key:(value if key=='slang_revision' else value.splitlines()[0]) for key,value in versions.items()
                           if key in ('python','verilator','yosys','sby','z3','compiler','slang_revision')})
            else:
                provenance[identity]['source_digests'].update(data.get('registered_source_digests',{}))
                provenance[identity]['tools'].update({key:(value if key=='slang_revision' else value.splitlines()[0])
                    for key,value in data['tool_versions'].items() if key in ('python','verilator','yosys','sby','z3','compiler','slang_revision')})
        if selected:
            records.extend(selected)
            runs.append(dict(run=path.parent.name,result=summary['result'],cases=len(selected)))
    if not records: raise ValueError('Missing scheduler manifests')
    return dict(schema_version=1,scope='Production scheduler/queue component; fixture metadata/TX, no integrated payload or system fairness',
                workflow_run=os.environ.get('GITHUB_RUN_ID'),workflow_sha=os.environ.get('GITHUB_SHA'),
                runs=runs,provenance=provenance,cases=records)


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--runs',type=Path,default=Path('.build/runs'))
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    args.output.write_text(json.dumps(collect(args.runs),indent=2)+'\n')
