"""FP-TX production safety, reachable witnesses and source-copy fault qualification."""
from pathlib import Path
import re
from evidence import Case, ROOT, output, sha
from frontend import read_sources
from formal_symbols import check_sources
from memory_tx_dut import candidate_identity

MUTATIONS = {
    'outstanding-credit': ("int'(buffered)+int'(outstanding)-int'(retire)", "int'(buffered)-int'(retire)", 'a_credit'),
    'premature-return': ('cell_return.valid = retire && retiring.cell_last;', 'cell_return.valid = issue && issue_tag.cell_last;', 'a_retirement'),
    'stale-validity': ('assign m_valid = rst_n && buffered!=0;', 'assign m_valid = rst_n ? buffered!=0 : response.valid;', 'a_reset'),
}


def mutate(text, name):
    old,new,_ = MUTATIONS[name]
    if text.count(old)!=1: raise ValueError('Missing or ambiguous production mutation anchor: '+name)
    return text.replace(old,new)


def formal_tx(run,args,configuration):
    if not args.candidate_revision: raise ValueError('FP-TX requires explicit --candidate-revision')
    identity = candidate_identity(args.candidate_revision)
    for latency in (args.memory_latency or [1,2]):
        for depth in (args.tx_depth or [4,8]):
            tasks = ['prove','cover']+list(MUTATIONS) if (latency,depth)==(2,4) else ['prove','cover']
            for task in tasks:
                case = Case(run,f'rtl-tx-L{latency}-D{depth}-{task}')
                params = {k:configuration[k] for k in ('N_RX','N_Q','N_CELL','N_DESC','CELL_BYTES','MAX_PACKET_BYTES')}
                params.update(MEM_RD_LATENCY=latency,TX_FIFO_DEPTH=depth)
                induction_depth=2 if (latency,depth)==(2,8) else 8
                case.data.update(configuration=params,candidate=identity,source_set='formal',
                    engine='smtbmc z3',method=f'unbounded k-induction, maximum depth {induction_depth}' if task=='prove' else 'cover depth 64' if task=='cover' else 'intended BMC counterexample depth 32',
                    assumptions='Two startup reset samples; arbitrary later resets and sink stalls. Legal idle-only dispatch, 1..128 byte packets. Eight distinct arbitrary fixed cell IDs stable across every reset by F01 history; arbitrary input word captured on each read with exact unreset physical response latency. Returned links may change immediately. No fairness assumption.')
                paths=['rtl/include/tm_fixed.sv','rtl/tx/tm_tx.sv','formal/tx/tx_formal.sv']
                headers=['rtl/include/tm_types.svh','rtl/include/tm_parameters.svh','rtl/include/tm_validate.svh']
                check_sources([ROOT/p for p in paths+headers],[ROOT/'rtl/include'])
                files=[]
                for path in paths+headers:
                    source=ROOT/path
                    if task in MUTATIONS and path=='rtl/tx/tm_tx.sv':
                        original=source.read_text();source=case.path/'tm_tx.sv'
                        source.write_text(mutate(original,task))
                        case.data.update(mutation=task,mutant_sha256=sha(source),detector=MUTATIONS[task][2])
                    files.append(source.name+' '+str(source))
                script=read_sources([Path(p).name for p in paths],'tx_formal',params=params,defines=['SYNTHESIS'],formal=True)
                script+='prep -top tx_formal\nasync2sync\ndffunmap'
                config=case.path/'tx.sby'
                config.write_text((ROOT/'formal/tx/tx.sby').read_text().replace('prove: depth 8','prove: depth '+str(induction_depth)).replace('@SCRIPT@',script).replace('@FILES@','\n'.join(files)))
                step=case.execute(['sby','-f','-d',case.path/'engine',config,task if task in ('prove','cover') else 'mutation'],timeout=args.timeout,cwd=case.path)
                statusfile=case.path/'engine/status'
                status=statusfile.read_text().split()[0] if statusfile.is_file() else None
                text=output(step)
                waves=[str(p) for p in (case.path/'engine').rglob('*.vcd') if p.stat().st_size]
                failures=re.findall(r'Assert failed in \S+: (\S+)',text)
                reached=re.findall(r'Reached cover statement in step (\d+) at \S+: (\S+)',text)
                if step['result']=='TIMEOUT': result,reason='TIMEOUT',step['first_failure']
                elif task in MUTATIONS:
                    intended=MUTATIONS[task][2]
                    ok=step['returncode'] not in (0,None) and status=='FAIL' and waves and any(n.rsplit('.',1)[-1]==intended for n in failures)
                    result,reason=('PASS',None) if ok else ('FAIL','Intended '+intended+' counterexample absent')
                else:
                    marker='successful proof by k-induction' if task=='prove' else 'Reached cover statement'
                    ok=status=='PASS' and step['returncode']==0 and marker in text
                    result,reason=('PASS',None) if ok else ('FAIL' if status=='FAIL' else 'INCONCLUSIVE' if status=='UNKNOWN' else 'TOOL_ERROR','Completed FP-TX result absent')
                case.data['artifacts'].update(configuration=str(config),status=str(statusfile),waveforms=waves)
                case.finish(result,reason,engine_status=status,observed_assertions=failures,
                            reached_covers=[dict(step=int(n),name=name) for n,name in reached],
                            expected='SEEDED_DEFECT_DETECTION' if task in MUTATIONS else task.upper())
