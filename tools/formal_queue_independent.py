"""Independent qualification of the audited P03 production queue harness."""
from pathlib import Path
from evidence import Case, ROOT, sha, output
from registry import sources, fingerprint
from frontend import read_sources
from symbolic_qualification import outcome


def formal_queue_independent(run, args, configuration):
    if args.frontend != 'slang':
        raise ValueError('Independent queue proof requires qualified Slang')
    registered = sources('formal')
    # Each disposable production mutation has an exact named checker, never a generic crash.
    mutations = {
        'order': ('rtl/queue/tm_queue_ctrl.sv',
                  "if (counts[q*DESC_COUNT_W +: DESC_COUNT_W]==1)\n                    heads_next[q*DESC_ID_W +: DESC_ID_W] = commit.desc;",
                  "if (counts[q*DESC_COUNT_W +: DESC_COUNT_W]==1)\n                    heads_next[q*DESC_ID_W +: DESC_ID_W] = old_head_next;", 'a_order'),
        'link': ('rtl/queue/tm_queue_ctrl.sv',
                 'next_write.next_id = commit.desc;', 'next_write.next_id = tails[q*DESC_ID_W +: DESC_ID_W];', 'a_link_payload'),
        'count': ('rtl/queue/tm_queue_ctrl.sv',
                  "counts[q*DESC_COUNT_W +: DESC_COUNT_W] + DESC_COUNT_W'(1);",
                  "counts[q*DESC_COUNT_W +: DESC_COUNT_W] + DESC_COUNT_W'(2);", 'a_count'),
    }
    paths = ['rtl/include/tm_fixed.sv','rtl/queue/tm_queue_ctrl.sv',
             'rtl/queue/tm_desc_links.sv','formal/queue/queue_formal.sv']
    for task in ('prove','cover',*mutations):
        case = Case(run, 'rtl-queues-independent-'+task)
        case.data.update(configuration=configuration, frontend='slang', engine='smtbmc z3',
                         method='bounded reachability depth 24' if task=='cover' else 'unbounded k-induction',
                         registered_source_digests=fingerprint('formal'),
                         assumptions='Two startup reset samples, later resets arbitrary; fixed qid/descriptor witnesses stable across reset. Commit assumes external caller_rx_owned predicate, in-range ID/qid, absence from all pre-state queues and capacity. Dispatch uses independent pre-state head. P11A must discharge ownership, packet completion and real pool/TX caller contracts. No fairness.')
        files=[]
        for path in paths+registered['headers']:
            source=ROOT/path
            if task in mutations and path==mutations[task][0]:
                _, target, replacement, detector = mutations[task]
                original=source.read_text()
                expected_sites=2 if task=='link' else 1
                if original.count(target)!=expected_sites:
                    raise ValueError('Missing/ambiguous '+task+' mutation site')
                mutant=case.path/source.name
                mutant.write_text(original.replace(target,replacement))
                source=mutant
                case.data.update(mutation=task, intended_detector=detector, mutant_sha256=sha(mutant))
            files.append(source.name+' '+str(source))
        params={k:configuration[k] for k in ('N_RX','N_Q','N_CELL','N_DESC','CELL_BYTES','MAX_PACKET_BYTES')}
        script=read_sources([Path(p).name for p in paths],'queue_formal',params=params,frontend='slang',formal=True)
        script+='prep -top queue_formal\nasync2sync\ndffunmap\nmemory_map\nopt_clean'
        config=case.path/'queue.sby'
        config.write_text((ROOT/'formal/queue/independent.sby').read_text().replace('@SCRIPT@',script).replace('@FILES@','\n'.join(files)))
        step=case.execute(['sby','-f','-d',str(case.path/'engine'),str(config),task],timeout=args.timeout,cwd=case.path)
        status_file=case.path/'engine/status'
        status=status_file.read_text().split()[0] if status_file.is_file() else None
        waves=[str(p) for p in (case.path/'engine').rglob('*.vcd') if p.stat().st_size]
        logs=output(step)
        if step['result']=='TIMEOUT':
            result,why='TIMEOUT',step['first_failure']
        elif task in mutations:
            result,why=outcome(step,status,logs,waves,'ASSERT_FAIL',[mutations[task][3]])
        else:
            marker='Reached cover statement' if task=='cover' else 'successful proof by k-induction'
            ok=step['returncode']==0 and status=='PASS' and marker in logs and (task!='cover' or bool(waves))
            result,why=('PASS',None) if ok else ('FAIL' if status=='FAIL' else 'INCONCLUSIVE' if status=='UNKNOWN' else 'TOOL_ERROR','Missing completed independent production proof/cover')
        case.data['artifacts'].update(status=str(status_file),traces=waves,configuration=str(config))
        case.finish(result,why,engine_status=status,expected='INTENDED_COUNTEREXAMPLE' if task in mutations else task.upper())
