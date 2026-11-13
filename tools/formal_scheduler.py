"""FP-SCHED production grant, credit and bounds proofs; separate RR elaboration."""
from pathlib import Path
from evidence import Case, ROOT, output, sha
from registry import sources, fingerprint
from frontend import read_sources


def formal_scheduler(run, args, configuration):
    registered = sources('formal')
    for mode in (1, 0):
        for task in (('prove','cover','mutation') if mode else ('prove','cover')):
            case = Case(run, f'rtl-scheduler-mode{mode}-{task}')
            case.data.update(configuration=dict(configuration,SCHED_MODE=mode), source_set='formal',
                             registered_source_digests=fingerprint('formal'), frontend='slang',
                             engine='smtbmc z3', method='bounded reachability depth 16' if task=='cover' else 'unbounded k-induction',
                             assumptions='Two startup reset samples; arbitrary later reset. Legal static 64..4096 per-qid quanta. Abstract P03 merged count transitions (0..2), immutable pre-state heads until pop, legal selected packet length 1..MAX. Completion only while TX owns; readiness/completion have no progress bound.')
            paths = ['rtl/include/tm_fixed.sv','rtl/scheduler/tm_drr.sv','formal/scheduler/scheduler_formal.sv']
            files=[]
            for path in paths+registered['headers']:
                source=ROOT/path
                if task=='mutation' and source.name=='tm_drr.sv':
                    mutant=case.path/source.name
                    original=source.read_text()
                    target='if (!visit_active)\n                    credit ='
                    if original.count(target)!=1:
                        raise ValueError('Extra-quantum mutation site missing or ambiguous')
                    mutant.write_text(original.replace(target,"if (!visit_active || (tx_ready && credit >= (DEFICIT_W+1)'(selected_info.length)))\n                    credit ="))
                    source=mutant
                    case.data.update(mutation='Quantum also added for a continuing packet visit',mutant_sha256=sha(mutant))
                files.append(source.name+' '+str(source))
            params={k:configuration[k] for k in ('N_RX','N_Q','N_CELL','N_DESC','CELL_BYTES','MAX_PACKET_BYTES')}
            params['SCHED_MODE']=mode
            script=read_sources([Path(p).name for p in paths],'scheduler_formal',params=params,frontend='slang',formal=True)
            script+='prep -top scheduler_formal\nasync2sync\ndffunmap'
            config=case.path/'scheduler.sby'
            config.write_text((ROOT/'formal/scheduler/scheduler.sby').read_text().replace('@SCRIPT@',script).replace('@FILES@','\n'.join(files)))
            step=case.execute(['sby','-f','-d',str(case.path/'engine'),str(config),task],timeout=args.timeout,cwd=case.path)
            status_file=case.path/'engine/status'
            status=status_file.read_text().split()[0] if status_file.is_file() else None
            waves=[str(p) for p in (case.path/'engine').rglob('*.vcd') if p.stat().st_size]
            text=output(step)
            if step['result']=='TIMEOUT':
                result,why='TIMEOUT',step['first_failure']
            elif task=='mutation':
                ok=step['returncode'] not in (0,None) and status=='FAIL' and waves and 'a_credit' in text and 'Assert failed' in text
                result,why=('PASS',None) if ok else ('TOOL_ERROR','Missing intended a_credit counterexample')
            else:
                marker='Reached cover statement' if task=='cover' else 'successful proof by k-induction'
                ok=step['returncode']==0 and status=='PASS' and marker in text and (task!='cover' or bool(waves))
                result,why=('PASS',None) if ok else ('FAIL' if status=='FAIL' else 'INCONCLUSIVE' if status=='UNKNOWN' else 'TOOL_ERROR','Completed production proof/cover missing')
            case.data['artifacts'].update(status=str(status_file),traces=waves,configuration=str(config))
            case.finish(result,why,engine_status=status,expected='CREDIT_COUNTEREXAMPLE' if task=='mutation' else task.upper())
