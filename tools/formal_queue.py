"""FP-QUEUE/FP-ORDER on production controller and metadata link child."""
from pathlib import Path
from evidence import Case, ROOT, output, sha
from registry import sources, fingerprint
from frontend import read_sources


def formal_queue(run, args, configuration):
    if args.frontend != 'slang':
        raise ValueError('Queue production proof requires the qualified Slang frontend')
    registered = sources('formal')
    for task in ('prove', 'cover', 'mutation'):
        case = Case(run, 'rtl-queues-'+task)
        case.data.update(configuration=configuration, source_set='formal',
                         registered_source_digests=fingerprint('formal'), frontend='slang',
                         engine='smtbmc z3', method='bounded reachability depth 16' if task=='cover' else 'unbounded k-induction',
                         assumptions='Two startup reset samples; arbitrary later resets. Commit ID/qid in range, legal RX owner, not in any pre-state list; total queued below capacity on commit. Commit assumes external caller_rx_owned predicate; actual global owner transitions remain P11A. Fixed arbitrary witnesses held across later reset. Pop attempts arbitrary; accepted only on nonempty pre-state model. No fairness.')
        paths = ['rtl/include/tm_fixed.sv', 'rtl/queue/tm_queue_ctrl.sv',
                 'rtl/queue/tm_desc_links.sv', 'formal/queue/queue_formal.sv']
        files=[]
        for path in paths+registered['headers']:
            source=ROOT/path
            if task=='mutation' and source.name=='tm_queue_ctrl.sv':
                mutant=case.path/source.name
                target='heads_next[q*DESC_ID_W +: DESC_ID_W] = commit.desc;'
                text=source.read_text()
                # Only remove the singleton simultaneous replacement bypass.
                site='if (counts[q*DESC_COUNT_W +: DESC_COUNT_W]==1)\n                    '+target
                if text.count(site)!=1:
                    raise ValueError('Singleton bypass mutation site missing or ambiguous')
                mutant.write_text(text.replace(site,site.replace('= commit.desc;', '= old_head_next;')))
                source=mutant
                case.data.update(mutation='Singleton replacement follows stale old tail link', mutant_sha256=sha(mutant))
            files.append(source.name+' '+str(source))
        params={k:configuration[k] for k in ('N_RX','N_Q','N_CELL','N_DESC','CELL_BYTES','MAX_PACKET_BYTES')}
        script=read_sources([Path(p).name for p in paths], 'queue_formal', params=params, frontend='slang',formal=True)
        script+='prep -top queue_formal\nasync2sync\ndffunmap\nmemory_map\nopt_clean'
        config=case.path/'queue.sby'
        config.write_text((ROOT/'formal/queue/queue.sby').read_text().replace('@SCRIPT@',script).replace('@FILES@','\n'.join(files)))
        step=case.execute(['sby','-f','-d',str(case.path/'engine'),str(config),task], timeout=args.timeout,cwd=case.path)
        status_file=case.path/'engine/status'
        status=status_file.read_text().split()[0] if status_file.is_file() else None
        waves=[str(p) for p in (case.path/'engine').rglob('*.vcd') if p.stat().st_size]
        text=output(step)
        if step['result']=='TIMEOUT':
            result,why='TIMEOUT',step['first_failure']
        elif task=='mutation':
            ok=step['returncode'] not in (0,None) and status=='FAIL' and waves and 'a_order' in text and 'Assert failed' in text
            result,why=('PASS',None) if ok else ('TOOL_ERROR','Missing intended a_order counterexample')
        else:
            marker='Reached cover statement' if task=='cover' else 'successful proof by k-induction'
            ok=step['returncode']==0 and status=='PASS' and marker in text and (task!='cover' or bool(waves))
            result,why=('PASS',None) if ok else ('FAIL' if status=='FAIL' else 'INCONCLUSIVE' if status=='UNKNOWN' else 'TOOL_ERROR','Completed production proof/cover missing')
        case.data['artifacts'].update(status=str(status_file), traces=waves, configuration=str(config))
        case.finish(result,why,engine_status=status,expected='ORDER_COUNTEREXAMPLE' if task=='mutation' else task.upper())
