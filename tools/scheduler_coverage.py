"""Replay compatible saved scheduler coverage without combining elaborations."""
import json
import re
from pathlib import Path
from evidence import Case, sha
from registry import fingerprint, read, profile
from scheduler import scheduler_coverage


def inspect(path, profile_name):
    manifest=json.loads(Path(path).read_text())
    if manifest['result']!='PASS' or manifest['profile']!=profile_name or manifest.get('source_set')!='scheduler':
        raise ValueError('Coverage requires a passing scheduler case of the selected profile')
    mode=manifest['parameters']['SCHED_MODE']
    stress=bool(re.fullmatch(f'scheduler-mode{mode}-stress-(?:[0-9]+|replay)',manifest['test']))
    if mode not in (0,1) or (manifest['test']!=f'scheduler-mode{mode}' and not stress):
        raise ValueError('Coverage requires an unmutated production elaboration')
    expected=profile(profile_name)
    expected.update(SCHED_MODE=mode,
                    CELL_ID_W=max(1,(expected['N_CELL']-1).bit_length()),
                    CELL_COUNT_W=expected['N_CELL'].bit_length(),
                    DESC_ID_W=max(1,(expected['N_DESC']-1).bit_length()),
                    DESC_COUNT_W=expected['N_DESC'].bit_length(),
                    DEFICIT_W=(4096+expected['MAX_PACKET_BYTES']-1).bit_length())
    if any(manifest['parameters'].get(key)!=value for key,value in expected.items()):
        raise ValueError('Coverage parameter mismatch')
    if manifest['registered_source_digests']!=fingerprint('scheduler'):
        raise ValueError('Coverage source/instrumentation mismatch')
    artifacts=manifest['artifacts']
    if sha(artifacts['coverage'])!=artifacts['coverage_sha256']:
        raise ValueError('Coverage artifact digest mismatch')
    coverage=scheduler_coverage(Path(artifacts['coverage']),mode)
    if coverage!=manifest['coverage']:
        raise ValueError('Saved coverage summary mismatch')
    extra={}
    if stress:
        from scheduler_stress import inspect_stress
        for name in ('functional_coverage','events'):
            if sha(artifacts[name])!=artifacts[name+'_sha256']:
                raise ValueError('Extended coverage artifact digest mismatch: '+name)
        extra=inspect_stress(artifacts['functional_coverage'],mode,expected['N_Q'])
        if extra!=manifest['stress']: raise ValueError('Extended coverage summary mismatch')
    return dict(stress=extra,parameters=manifest['parameters'],source_revision=manifest['source_revision'],
                dirty=manifest['dirty'],source_digests=manifest['registered_source_digests'],
                coverage=coverage,source_manifest=str(path))


def scheduler_saved_coverage(run,args):
    registered=read('coverage.json')['selections']['scheduler']
    if registered['handler']!='scheduler_saved_coverage' or registered['source_set']!='scheduler':
        raise ValueError('Unregistered scheduler coverage handler/source set')
    if args.test!=['scheduler'] or not args.coverage_manifest or args.seed is not None:
        raise ValueError('coverage requires --test scheduler and nonempty --coverage-manifest inputs; no seed')
    if len(set(args.coverage_manifest))!=len(args.coverage_manifest):
        raise ValueError('Duplicate coverage manifest')
    for index,path in enumerate(args.coverage_manifest):
        case=Case(run,'scheduler-coverage-'+str(index))
        try:
            data=inspect(path,args.profile)
            result=case.path/'coverage-summary.json'
            result.write_text(json.dumps(data,indent=2)+'\n')
            case.data.update(parameters=data['parameters'],coverage=data['coverage'])
            case.data['artifacts']['summary']=str(result)
            case.finish('PASS')
        except (OSError,ValueError,KeyError,TypeError) as error:
            case.finish('FAIL',str(error))
