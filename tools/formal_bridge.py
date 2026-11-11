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
    return dict(creator=data['creator'],modules={top:module}),dict(counts=dict(kinds),properties=labels,assumptions=len(assumptions))


def bridge(run,args):
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
            text='module bridge_equivalence('+','.join('input '+('['+str(w-1)+':0] ' if w>1 else '')+n for n,w in inputs.items())+');\nwire native_ok,slang_ok;\n'
            for label,ps,output_name in [('gold',gp,'native_ok'),('gate',tp,'slang_ok')]:
                connections=[f'.{n}({n})' for n,v in ps.items() if v['direction']=='input']+[f'.assumptions_ok({output_name})']
                text+=label+' instance_'+label+'('+','.join(connections)+');\n'
            assumed,asserted=('native_ok','slang_ok') if direction=='native-implies-slang' else ('slang_ok','native_ok')
            text+=f'always @(posedge clk) begin assume({assumed}); a_assumption_inclusion: assert({asserted}); end\nendmodule\n'
            wrapper=case.path/'equivalence.sv';wrapper.write_text(text)
            script.write_text(script.read_text()+f'read_verilog -formal -sv {wrapper}\nprep -top bridge_equivalence\n')
            config=case.path/'equivalence.sby'
            config.write_text('[options]\nmode prove\ndepth 8\n[engines]\nsmtbmc z3\n[script]\n'+script.read_text())
            step=case.execute(['sby','-f','-d',str(case.path/'engine'),str(config)],timeout=max(args.timeout,300),cwd=case.path)
            status=case.path/'engine/status'
            ok=step['returncode']==0 and status.is_file() and status.read_text().split()[0]=='PASS' and 'successful proof by k-induction' in output(step)
            case.finish('PASS' if ok else step['result'] if step['result']=='TIMEOUT' else 'FAIL',None if ok else 'Unbounded assumption-inclusion proof missing',
                        method='Mutual trace inclusion of complete assumption predicates; production DUT retained; all arbitrary inputs shared; no fairness added')
