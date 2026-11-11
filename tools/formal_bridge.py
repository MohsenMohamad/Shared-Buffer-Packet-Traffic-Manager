"""Check formal property preservation and mutual inclusion of harness assumptions."""
from collections import Counter
import json
import re
from pathlib import Path
from evidence import Case, ROOT, output, sha
from frontend import read_sources, expose_symbolic_inputs
from registry import sources


def comparable(data, top, names):
    module=data['modules'][top]
    kinds=Counter(c['type'] for c in module['cells'].values())
    labels={n: c.get('attributes',{}).get('src','') for n,c in module['cells'].items()
            if c['type'] in ('$assert','$assume','$cover')}
    bits=[b for n in module['netnames'].values() for b in n['bits'] if isinstance(b,int)]
    next_bit=max(bits+[1])+1
    def fresh():
        nonlocal next_bit
        b=next_bit;next_bit+=1;return b
    # Bind each native anyseq source to the same arbitrary top input as the
    # port representation. No restriction is placed on that input's values.
    for name in names:
        original=module['netnames'].get(name,{}).get('bits',[])
        if name not in module['ports']:
            if not original:
                continue
            module['ports'][name]=dict(direction='input',bits=[b if isinstance(b,int) else fresh() for b in original])
    inputs={b for p in module['ports'].values() if p['direction']=='input' for b in p['bits']}
    assumptions=[]
    for name,cell in list(module['cells'].items()):
        if cell['type']=='$anyseq':
            if not set(cell['connections']['Y']).issubset(inputs):
                raise ValueError('Unbound symbolic source: '+name)
            del module['cells'][name]
        elif cell['type'] in ('$assert','$cover','$assume'):
            if cell['type']=='$assume':
                a,en=cell['connections']['A'],cell['connections']['EN']
                inv,term=fresh(),fresh()
                module['cells']['bridge_not_'+str(inv)]=dict(type='$not',parameters={'A_SIGNED':'0','A_WIDTH':format(1,'032b'),'Y_WIDTH':format(1,'032b')},attributes={},port_directions={'A':'input','Y':'output'},connections={'A':en,'Y':[inv]})
                module['cells']['bridge_or_'+str(term)]=dict(type='$or',parameters={k:format(v,'032b') for k,v in dict(A_SIGNED=0,B_SIGNED=0,A_WIDTH=1,B_WIDTH=1,Y_WIDTH=1).items()},attributes={},port_directions={'A':'input','B':'input','Y':'output'},connections={'A':a,'B':[inv],'Y':[term]})
                assumptions.append(term)
            del module['cells'][name]
    if not assumptions:raise ValueError('No harness assumptions to compare')
    result=fresh()
    module['cells']['bridge_all']=dict(type='$reduce_and',parameters={k:format(v,'032b') for k,v in dict(A_SIGNED=0,A_WIDTH=len(assumptions),Y_WIDTH=1).items()},attributes={},port_directions={'A':'input','Y':'output'},connections={'A':assumptions,'Y':[result]})
    module['ports']['assumptions_ok']=dict(direction='output',bits=[result])
    if top=='csr_formal':
        module['ports']['startup_state']=dict(direction='output',bits=module['netnames']['startup']['bits'])
        module['ports']['past_valid_state']=dict(direction='output',bits=module['netnames']['past_valid']['bits'])
        control=['dut.have_aw','dut.have_w','dut.have_ar','dut.bvalid','dut.rvalid']
        module['ports']['control_state']=dict(direction='output',bits=[b for n in control for b in module['netnames'][n]['bits']])
    return dict(creator=data['creator'],modules={top:module}),dict(counts=dict(kinds),properties=labels,assumptions=len(assumptions))


def bridge(run,args):
    symbolics(run,args)
    memory_semantics(run,args)
    specs=json.loads((ROOT/'verification/formal.json').read_text())['configurations']
    registered=sources('formal')
    for name,spec in specs.items():
        top='csr_formal' if name=='csr' else 'storage_formal'
        harness=ROOT/('formal/csr/csr_formal.sv' if name=='csr' else 'formal/pools/storage_formal.sv')
        adapted,ports=expose_symbolic_inputs(harness)
        artifacts={}
        for variant,frontend in (('native-symbolic','verilog'),('slang-ports','slang')):
            case=Case(run,'bridge-'+name+'-'+variant)
            files=[ROOT/p for p in registered['sources'] if not p.startswith('formal/')]
            source=case.path/harness.name
            source.write_text(harness.read_text() if variant=='native-symbolic' else adapted)
            files.append(source)
            script=case.path/'lower.ys'; net=case.path/'raw.json'
            script.write_text(read_sources(files,top,[ROOT/p for p in registered['include_dirs']],spec['defines'],frontend=frontend,formal=True)+
                              f'prep -top {top}\nflatten\nasync2sync\ndffunmap\nchformal -lower\nwrite_json {net}\n')
            step=case.execute(['yosys','-Q','-T','-s',str(script)],timeout=args.timeout)
            if step['result']!='PASS' or not net.is_file():
                case.finish(step['result'] if step['result']!='PASS' else 'TOOL_ERROR','Cannot lower harness comparison')
                continue
            try:
                normalized,inventory=comparable(json.loads(net.read_text()),top,ports)
                dest=case.path/'comparable.json';dest.write_text(json.dumps(normalized)+'\n')
                artifacts[variant]=(dest,normalized,inventory)
                case.finish('PASS',formal_inventory=inventory,harness_sha256=sha(source))
            except ValueError as error:
                case.finish('FAIL',str(error))
        if len(artifacts)!=2:continue
        gold,gate=artifacts['native-symbolic'],artifacts['slang-ports']
        # All assertion/assumption/cover instances must survive lowering. Labels
        # and locations are saved separately, including loop-expanded instances.
        expected={k:v for k,v in gold[2]['counts'].items() if k in ('$assert','$assume','$cover')}
        observed={k:v for k,v in gate[2]['counts'].items() if k in ('$assert','$assume','$cover')}
        count=Case(run,'bridge-'+name+'-property-counts')
        count.finish('PASS' if observed==expected else 'FAIL',None if observed==expected else 'Formal property inventory changed',native=expected,slang=observed)
        for direction in ('native-implies-slang','slang-implies-native'):
            case=Case(run,'bridge-'+name+'-'+direction)
            script=case.path/'equivalence.ys'
            script.write_text(f'read_json {gold[0]}\nrename {top} gold\nread_json {gate[0]}\nrename {top} gate\n')
            gp=gold[1]['modules'][top]['ports'];tp=gate[1]['modules'][top]['ports']
            inputs={k:len(v['bits']) for k,v in tp.items() if v['direction']=='input'}
            text='module bridge_equivalence('+','.join('input '+('['+str(w-1)+':0] ' if w>1 else '')+n for n,w in inputs.items())+');\n'
            for label,ps,output_name in [('gold',gp,'native_ok'),('gate',tp,'slang_ok')]:
                connections=[f'.{n}({n})' for n,v in ps.items() if v['direction']=='input']
                for n,v in ps.items():
                    if v['direction']!='output':continue
                    signal=output_name if n=='assumptions_ok' else label+'_'+n
                    text+='wire ['+str(len(v['bits'])-1)+':0] '+signal+';\n'
                    connections.append(f'.{n}({signal})')
                text+=label+' instance_'+label+'('+','.join(connections)+');\n'
            if top=='csr_formal':
                # These are additional proved invariants, not assumptions. They
                # relate the two real DUT control states after startup reset so
                # k-induction cannot start from unrelated unreachable states.
                text+='always @(posedge clk) begin\n'
                text+='a_startup_equal: assert(gold_startup_state==gate_startup_state);\n'
                text+='a_past_equal: assert(gold_past_valid_state==gate_past_valid_state);\n'
                text+='if(gold_startup_state!=0) a_control_equal: assert(gold_control_state==gate_control_state);\nend\n'
            assumed,asserted=('native_ok','slang_ok') if direction=='native-implies-slang' else ('slang_ok','native_ok')
            text+=f'always @(posedge clk) begin assume({assumed}); a_assumption_inclusion: assert({asserted}); end\nendmodule\n'
            wrapper=case.path/'equivalence.sv';wrapper.write_text(text)
            script.write_text(script.read_text()+f'read_verilog -formal -sv {wrapper}\nprep -top bridge_equivalence\n')
            config=case.path/'equivalence.sby'
            config.write_text('[options]\nmode prove\ndepth 8\n[engines]\nsmtbmc z3\n[script]\n'+script.read_text())
            step=case.execute(['sby','-f','-d',str(case.path/'engine'),str(config)],timeout=max(args.timeout,300),cwd=case.path)
            status=case.path/'engine/status'
            ok=step['returncode']==0 and status.is_file() and status.read_text().split()[0]=='PASS' and 'successful proof by k-induction' in output(step)
            case.finish('PASS' if ok else step['result'] if step['result']=='TIMEOUT' else 'INCONCLUSIVE' if status.is_file() and status.read_text().split()[0]=='UNKNOWN' else 'FAIL',None if ok else 'Unbounded assumption-inclusion proof missing',
                        method='Mutual trace inclusion of complete assumption predicates; production DUT retained; all arbitrary inputs shared; no fairness added')


def symbolics(run,args):
    base=ROOT/'tests/frontends'
    for frontend in ('verilog','slang'):
        for variant in ('symbolic_attributes','symbolic_functions','symbolic_ports'):
            case=Case(run,'symbolic-'+frontend+'-'+variant+'-sources')
            source=base/(variant+'.sv' if variant!='symbolic_ports' else 'symbolics.sv')
            net=case.path/'sources.json';script=case.path/'sources.ys'
            script.write_text(read_sources([source],variant,frontend=frontend,formal=True)+f'prep -top {variant}\nwrite_json {net}\n')
            step=case.execute(['yosys','-Q','-T','-s',str(script)],timeout=args.timeout)
            text=output(step)
            if frontend=='slang' and variant=='symbolic_functions':
                ok=step['returncode'] not in (0,None) and step['result']!='TIMEOUT' and "unknown system name '$anyseq'" in text and "unknown system name '$anyconst'" in text
                case.finish('PASS' if ok else 'FAIL',None if ok else 'Missing intended unsupported symbolic-function diagnostic',
                            expected='REJECT_UNSUPPORTED_FUNCTIONS',capability='UNSUPPORTED')
                continue
            if step['result']!='PASS' or not net.is_file():
                case.finish(step['result'] if step['result']!='PASS' else 'TOOL_ERROR','Symbolic-source elaboration failed')
                continue
            module=json.loads(net.read_text())['modules'][variant]
            kinds=Counter(c['type'] for c in module['cells'].values())
            unsupported=frontend=='slang' and variant=='symbolic_attributes'
            if variant=='symbolic_ports':
                ok=set(module['ports'])=={'clk','rst_n','enable','arbitrary'}
            else:
                ok=(kinds['$anyseq']==0 and kinds['$anyconst']==0) if unsupported else (kinds['$anyseq']==1 and kinds['$anyconst']==1)
            case.finish('PASS' if ok else 'FAIL',None if ok else 'Unexpected symbolic input representation',
                        capability='UNSUPPORTED' if unsupported else 'SUPPORTED',source_cells=dict(kinds),
                        symbolic_nets={n:v['bits'] for n,v in module['netnames'].items() if n in ('arbitrary','fixed_bit')})
            if not ok:continue
            tasks=('prove',) if unsupported else ('prove','cover','mutation') if variant=='symbolic_ports' else ('prove','cover')
            for task in tasks:
                check=Case(run,'symbolic-'+frontend+'-'+variant+'-'+task)
                config=check.path/'symbolic.sby'
                defines=['MUTATE'] if task=='mutation' else []
                config.write_text('[options]\nmode '+('cover' if task=='cover' else 'prove')+'\ndepth 12\n[engines]\nsmtbmc z3\n[script]\n'+
                                  read_sources([source.name],variant,defines=defines,frontend=frontend,formal=True)+
                                  f'prep -top {variant}\nasync2sync\ndffunmap\n[files]\n{source.name} {source}\n')
                step=check.execute(['sby','-f','-d',str(check.path/'engine'),str(config)],timeout=args.timeout,cwd=check.path)
                status=check.path/'engine/status';status=status.read_text().split()[0] if status.is_file() else None
                waves=[str(p) for p in (check.path/'engine').rglob('*.vcd') if p.stat().st_size]
                text=output(step)
                if unsupported or task=='mutation':
                    label='a_constant' if unsupported else 'a_capture'
                    ok=step['returncode'] not in (0,None) and step['result']!='TIMEOUT' and status=='FAIL' and waves and label in text and 'Assert failed' in text
                    expected='DETECT_LOST_ANYCONST_SEMANTICS' if unsupported else 'SEEDED_DEFECT_DETECTION'
                else:
                    marker='Reached cover statement' if task=='cover' else 'successful proof by k-induction'
                    ok=step['returncode']==0 and status=='PASS' and marker in text and (task!='cover' or bool(waves));expected=task.upper()
                check.finish('PASS' if ok else step['result'] if step['result']=='TIMEOUT' else 'FAIL',None if ok else 'Missing intended symbolic-input proof/cover/detection',
                             expected=expected,capability='UNSUPPORTED' if unsupported else 'SUPPORTED',engine_status=status,traces=waves)


def memory_semantics(run,args):
    for frontend in ('verilog','slang'):
        for task in ('prove','cover') if frontend=='slang' else ('prove',):
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
            if frontend=='verilog':
                ok=step['returncode'] not in (0,None) and step['result']!='TIMEOUT' and status=='FAIL' and waves and ('a_word' in text or 'a_contents' in text) and 'Assert failed' in text
                expected='DETECT_RECORD_ARRAY_MEMORY_MISINTERPRETATION'
            else:
                marker='Reached cover statement' if task=='cover' else 'successful proof by k-induction'
                ok=step['returncode']==0 and status=='PASS' and marker in text and (task!='cover' or bool(waves));expected=task.upper()
            case.finish('PASS' if ok else step['result'] if step['result']=='TIMEOUT' else 'INCONCLUSIVE' if status=='UNKNOWN' else 'FAIL',None if ok else 'Missing intended complete-word memory proof/cover/counterexample',
                        expected=expected,engine_status=status,traces=waves,scope='Minimized frontend memory semantics; not production TM')
