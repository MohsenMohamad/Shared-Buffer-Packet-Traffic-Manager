"""Distinct production proof route: real storage APIs, never P00 fixtures."""
import json
import re
from evidence import Case, ROOT, output, sha
from registry import sources, fingerprint
from frontend import read_sources, selected as selected_frontend


def selection(args):
    specs = json.loads((ROOT/'verification/formal.json').read_text())['configurations']
    # The unmerged exact-candidate proof needs an explicit selection and source
    # identity. Existing main/storage gates must not acquire that dependency.
    selected = [name for name in specs if name != 'memory-tx'] if args.test is None else args.test
    if args.profile != 'E0' or not selected or len(set(selected))!=len(selected) or any(s not in specs for s in selected):
        raise ValueError('formal-rtl requires profile E0 and nonempty distinct production selections: '+', '.join(specs))
    if args.seed is not None:
        raise ValueError('formal-rtl is symbolic; --seed is not applicable')
    return specs, selected


def formal_rtl(run, args):
    specs, selected = selection(args)
    registered = sources('formal')
    for name in selected:
        if name == 'memory-tx':
            from formal_tx import formal_tx
            formal_tx(run, args, specs[name])
            continue
        if name == 'queues-independent':
            from formal_queue_independent import formal_queue_independent
            formal_queue_independent(run, args, specs[name])
            continue
        if name == 'scheduler':
            from formal_scheduler import formal_scheduler
            formal_scheduler(run, args, specs[name])
            continue
        if name == 'queues':
            from formal_queue import formal_queue
            formal_queue(run, args, specs[name])
            continue
        if name == 'csr':
            from formal_csr import formal_csr
            formal_csr(run, args, specs[name])
            continue
        for task in ('prove','cover','mutation') if name in ('cell','descriptor') else ('prove','cover'):
            case = Case(run, 'rtl-'+name+'-'+task)
            case.data.update(configuration=specs[name], source_set='formal',
                             registered_source_digests=fingerprint('formal'),
                             assumptions='Reset low at first two sampled edges; later resets and every action input arbitrary',
                             engine='smtbmc z3', method='unbounded k-induction' if task!='cover' else 'bounded reachability depth 40')
            files=[]
            for path in registered['sources']+registered['headers']:
                source=ROOT/path
                if task=='mutation' and source.name=='tm_bitmap_pool.sv':
                    mutant=case.path/source.name
                    original=source.read_text()
                    target="next_count = next_count + DELTA_W'(1);"
                    if original.count(target)!=1:
                        raise ValueError('Wrong-delta mutation site missing or ambiguous')
                    mutant.write_text(original.replace(target,"next_count = next_count + DELTA_W'(2);"))
                    source=mutant
                    case.data.update(mutation='Return adds two credits instead of one', mutant_sha256=sha(mutant))
                files.append(source.name+' '+str(source))
            case.data['frontend'] = selected_frontend(args, 'formal')
            script=read_sources([(ROOT/p).name for p in registered['sources']], 'storage_formal', defines=specs[name]['defines'], frontend=selected_frontend(args, 'formal'), formal=True)
            script+='prep -top storage_formal\nasync2sync\ndffunmap'
            template=(ROOT/'formal/pools/storage.sby').read_text()
            config=case.path/'storage.sby'
            config.write_text(template.replace('@SCRIPT@',script).replace('@FILES@','\n'.join(files)))
            step=case.execute(['sby','-f','-d',str(case.path/'engine'),str(config),task],timeout=args.timeout,cwd=case.path)
            status_file=case.path/'engine/status'
            status=status_file.read_text().split()[0] if status_file.is_file() else None
            waves=[str(p) for p in (case.path/'engine').rglob('*.vcd') if p.stat().st_size]
            text=output(step)
            if step['result']=='TIMEOUT' or step['returncode'] is None:
                result,why=step['result'],step['first_failure']
            elif task=='mutation':
                ok=step['returncode']!=0 and status=='FAIL' and waves and 'a_population' in text and 'Assert failed' in text
                result,why=('PASS',None) if ok else ('TOOL_ERROR','Missing intended population-invariant counterexample')
            elif status=='FAIL':
                result,why='FAIL','Production property failed or required cover unreachable'
            else:
                marker='successful proof by k-induction' if task=='prove' else 'Reached cover statement'
                ok=step['returncode']==0 and status=='PASS' and marker in text and (task!='cover' or bool(waves))
                result,why=('PASS',None) if ok else ('INCONCLUSIVE' if status=='UNKNOWN' else 'TOOL_ERROR','Missing completed production proof/cover evidence')
            case.data['artifacts'].update(status=str(status_file),traces=waves,configuration=str(config))
            case.finish(result,why,engine_status=status,expected='POPULATION_COUNTEREXAMPLE' if task=='mutation' else task.upper())
