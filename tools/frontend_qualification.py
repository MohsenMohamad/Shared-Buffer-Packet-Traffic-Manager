"""Current Slang feature acceptance and memory inference checks."""
import json
from pathlib import Path
from evidence import Case, ROOT, completed, output, sha
from frontend import read_sources

BASE = ROOT / 'tests/frontends'


def audit(run, args):
    for name in ('features','unpacked','interface','record_memory'):
        top = {'features':'feature_top','unpacked':'unpacked_ports','interface':'interface_top','record_memory':'record_memory'}.get(name)
        includes = []
        files = [BASE/(name+'.sv')]
        for phase in ('parse','elaborate','synthesis'):
            case=Case(run, f'frontend-{args.frontend}-{name}-{phase}')
            case.data.update(frontend=args.frontend, candidate=name, phase=phase,
                             reference_revision='current',
                             input_digests={str(p.relative_to(ROOT)):sha(p) for p in files},
                             method='AST compilation/semantic checking without RTLIL lowering' if phase=='parse' else 'RTLIL elaboration' if phase=='elaborate' else 'completed generic synthesis')
            script=case.path/'run.ys'
            command=read_sources(files,top,includes,frontend=args.frontend)
            if phase=='parse':
                command=command.replace('read_slang ', 'read_slang --ast-compilation-only ',1)
            if phase=='synthesis':
                command+='proc\nmemory_collect\ncheck -assert\nwrite_json '+str(case.path/'inferred.json')+'\n'
                command+=f'synth -top {top}\ncheck -assert\nwrite_json {case.path}/netlist.json\n'
            script.write_text(command)
            step=case.execute(['yosys','-Q','-T','-s',str(script)],timeout=max(args.timeout,300))
            text=output(step)
            if step['result']!='PASS':
                case.finish(step['result'],step['first_failure'])
            elif phase=='synthesis':
                net=json.loads((case.path/'netlist.json').read_text())
                cells=[c['type'] for m in net['modules'].values() for c in m.get('cells',{}).values()]
                bad=[c for c in cells if 'latch' in c.lower()]
                fields=dict(generic_cells=len(cells),latches=bad,netlist_sha256=sha(case.path/'netlist.json'))
                if name in ('features','record_memory'):
                    inferred=json.loads((case.path/'inferred.json').read_text())
                    memories=[c for m in inferred['modules'].values() for c in m.get('cells',{}).values() if c['type']=='$mem_v2']
                    fields['inferred_memories']=[{k:int(c['parameters'][k],2) for k in ('WIDTH','SIZE','RD_PORTS','WR_PORTS','RD_CLK_ENABLE','WR_CLK_ENABLE')} for c in memories]
                    widths=[10,16] if name=='features' else [10]
                    if len(memories)!=len(widths) or sorted(int(c['parameters']['WIDTH'],2) for c in memories)!=widths:
                        bad.append('Unexpected packed-record memory count/width')
                    # Before memory_dff, the read register is a separate cell.
                    # Both fixtures require four words, one asynchronous read
                    # port feeding that register and one clocked write port.
                    if any(any(m[k]!=v for k,v in dict(SIZE=4,RD_PORTS=1,WR_PORTS=1,
                                                      RD_CLK_ENABLE=0,WR_CLK_ENABLE=1).items())
                           for m in fields['inferred_memories']):
                        bad.append('Unexpected inferred memory depth/ports/clocks')
                case.finish('FAIL' if bad else 'PASS','Unexpected latch/memory structure' if bad else None,**fields)
            else:
                case.finish('PASS')
    # Exercise independent feature behavior on heterogeneous instances.
    for name in ('features',):
        case=Case(run,'frontend-simulation-'+name)
        files=[BASE/'features.sv',BASE/'features_tb.sv'];top='feature_test';marker='TM_FEATURE_PASS reads=16'
        binary=case.path/'obj'/('V'+top)
        argv=['verilator','--binary','--timing','--assert','--timescale','1ns/1ps','--build-jobs',str(args.jobs),
              '--top-module',top,'--Mdir',str(binary.parent)]+['-I'+str(p) for p in []]+list(map(str,files))
        step=case.execute(argv,timeout=args.build_timeout)
        if step['result']!='PASS' or not binary.is_file():
            case.finish(step['result'] if step['result']!='PASS' else 'TOOL_ERROR','Missing frontend behavior executable')
        else:
            case.finish(*completed(case.execute([str(binary)],cwd=case.path,timeout=args.timeout),marker))

    memory_semantics(run, args)


def memory_semantics(run,args):
    for frontend in ('slang',):
        for task in ('prove','cover'):
            case=Case(run,'record-memory-'+frontend+'-'+task)
            top='record_memory_formal'
            files=['record_memory.sv','record_memory_formal.sv']
            config=case.path/'memory.sby'
            config.write_text('[options]\nmode '+task+'\ndepth 12\n[engines]\nsmtbmc z3\n[script]\n'+
                              read_sources(files,top,frontend=frontend,formal=True)+
                              f'prep -top {top}\n[files]\n'+
                              '\n'.join(str(ROOT/'tests/frontends'/p) for p in files)+'\n')
            step=case.execute(['sby','-f','-d',str(case.path/'engine'),str(config)],timeout=args.timeout,cwd=case.path)
            sf=case.path/'engine/status';status=sf.read_text().split()[0] if sf.is_file() else None
            waves=[str(p) for p in (case.path/'engine').rglob('*.vcd') if p.stat().st_size]
            text=output(step)
            marker='Reached cover statement' if task=='cover' else 'successful proof by k-induction'
            ok=step['returncode']==0 and status=='PASS' and marker in text and (task!='cover' or bool(waves))
            expected=task.upper()
            case.finish('PASS' if ok else step['result'] if step['result']=='TIMEOUT' else 'INCONCLUSIVE' if status=='UNKNOWN' else 'FAIL',None if ok else 'Missing intended complete-word memory proof/cover/counterexample',
                        expected=expected,engine_status=status,traces=waves,scope='Minimized frontend memory semantics; not production TM')
