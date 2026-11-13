"""Validate and summarize independent queue coverage without merging elaborations."""
import json
import re
from pathlib import Path
from evidence import Case, sha
from registry import fingerprint, read


def inspect(manifest_path, profile_name):
    manifest=json.loads(Path(manifest_path).read_text())
    if manifest['result']!='PASS' or manifest['profile']!=profile_name or manifest.get('source_set')!='queues-independent':
        raise ValueError('Coverage requires passing independent queue manifests of the selected profile')
    if manifest['registered_source_digests']!=fingerprint('queues-independent'):
        raise ValueError('Coverage source/instrumentation mismatch')
    artifacts=manifest['artifacts']
    for name in ('coverage','functional_coverage'):
        if sha(artifacts[name])!=artifacts[name+'_sha256']:
            raise ValueError('Coverage artifact digest mismatch: '+name)
    data=json.loads(Path(artifacts['functional_coverage']).read_text())
    nq=manifest['parameters']['N_Q']
    keys={(b['qid'],b['pre_count'],b['event']) for b in data['bins']}
    if len(data['bins'])!=nq*12 or keys!={(q,c,e) for q in range(nq) for c in range(3) for e in range(4)}:
        raise ValueError('Missing or duplicate functional bins')
    for b in data['bins']:
        illegal=b['pre_count']==0 and b['event'] in (1,3)
        if (illegal and b['hits']!=0) or (not illegal and b['hits']<=0):
            raise ValueError('Illegal action hit or mandatory queue bin missing')
    for key in ('delayed_publish','reuse','tx_retained','full','reset_active','reset_collision',
                'read_checks','link_collision','same_singleton','same_long','different','empty_publish'):
        if data[key]<=0:
            raise ValueError('Missing lifetime/collision bin: '+key)
    points={}
    holes=[]
    for line in Path(artifacts['coverage']).read_text().splitlines():
        match=re.fullmatch(r"C '(.*)' (\d+)",line)
        if not match:
            continue
        fields=dict(part.split('\x02',1) for part in match[1].split('\x01') if '\x02' in part)
        if '/rtl/queue/' not in fields.get('f',''):
            continue
        name=Path(fields['f']).name
        kind=fields.get('t','unknown')
        count=int(match[2])
        group=points.setdefault(name,{}).setdefault(kind,dict(hit=0,total=0))
        group['total']+=1; group['hit']+=int(count>0)
        if count==0:
            holes.append(dict(file=name,line=fields.get('l'),kind=kind,expression=fields.get('o')))
    if not points or any(not values.get('line',{}).get('hit') for values in points.values()):
        raise ValueError('Missing production queue code coverage')
    return dict(parameters=manifest['parameters'],source_revision=manifest['source_revision'],
                dirty=manifest['dirty'],source_digests=manifest['registered_source_digests'],
                functional=data,code=points,unhit=holes,source_manifest=str(manifest_path))


def queue_coverage(run,args):
    registered=read('coverage.json')['selections']['queues-independent']
    if registered['handler']!='queue_coverage' or registered['source_set']!='queues-independent':
        raise ValueError('Unregistered queue coverage handler/source set')
    if args.test!=['queues-independent'] or not args.coverage_manifest or args.seed is not None:
        raise ValueError('coverage requires --test queues-independent and nonempty --coverage-manifest inputs; no seed')
    if len(set(args.coverage_manifest))!=len(args.coverage_manifest):
        raise ValueError('Duplicate coverage manifest')
    for index,path in enumerate(args.coverage_manifest):
        case=Case(run,'queue-coverage-'+str(index))
        try:
            data=inspect(path,args.profile)
            result=case.path/'coverage-summary.json'
            result.write_text(json.dumps(data,indent=2)+'\n')
            case.data.update(coverage=data['code'],functional=data['functional'])
            case.data['artifacts']['summary']=str(result)
            case.finish('PASS')
        except (OSError,ValueError,KeyError,TypeError) as error:
            case.finish('FAIL',str(error))
