"""Production-derived representation and independent frontend capability checks."""
import json
from pathlib import Path
import re
import sys
from evidence import Case, ROOT, completed, output, sha
from frontend import read_sources

BASE = ROOT / 'tests/frontends'
CANDIDATES = ('baseline', 'ansi_vectors', 'package_vectors', 'package_scoped',
              'inline_struct', 'type_parameter', 'forward_typedef', 'minimal', 'named_widths', 'bits_type')
PACKAGES = {'package_vectors','package_scoped','inline_struct','type_parameter','minimal','named_widths','bits_type'}


def audit(run, args):
    generate = Case(run, 'frontend-generate')
    generated = run.path / 'generated'
    step = generate.execute([sys.executable, str(BASE/'generate.py'), '--repo-root', str(ROOT), '--output', str(generated)])
    generate.finish(step['result'], step['first_failure'])
    if step['result'] != 'PASS':
        return
    manifest = json.loads((generated/'candidates.json').read_text())
    for name in CANDIDATES + ('features','unpacked','interface','record_memory'):
        top = {'features':'feature_top','unpacked':'unpacked_ports','interface':'interface_top','record_memory':'record_memory'}.get(name) or ('bits_type' if name=='bits_type' else 'synth_top')
        includes = [generated, ROOT/'rtl/include']
        if name in ('features','unpacked','interface','record_memory'):
            files=[BASE/(name+'.sv')]
        else:
            files=([generated/'tm_fixed.sv'] if name in PACKAGES else [])
            files += ([generated/'bits_type.sv'] if name=='bits_type' else
                      [generated/p for p in manifest[name]] +
                      [generated/name/'probe_unit.sv', generated/'synth_top.sv'])
        for phase in ('parse','elaborate','synthesis'):
            case=Case(run, f'frontend-{args.frontend}-{name}-{phase}')
            case.data.update(frontend=args.frontend, candidate=name, phase=phase,
                             input_digests={str(p.relative_to(ROOT)):sha(p) for p in files})
            script=case.path/'run.ys'
            command=read_sources(files,top,includes,frontend=args.frontend)
            if phase=='parse':
                if args.frontend=='slang':command=command.replace('read_slang ', 'read_slang --ast-compilation-only ',1)
                else:command=command.split('\nhierarchy')[0].replace('read_verilog -sv','read_verilog -sv -defer',1)+'\n'
            if phase=='synthesis':
                command+='proc\nmemory_collect\ncheck -assert\nwrite_json '+str(case.path/'inferred.json')+'\n'
                command+=f'synth -top {top}\ncheck -assert\nwrite_json {case.path}/netlist.json\n'
            script.write_text(command)
            step=case.execute(['yosys','-Q','-T','-s',str(script)],timeout=max(args.timeout,300))
            text=output(step)
            if name=='forward_typedef':
                # The source references a module-local typedef before declaration.
                ok=step['returncode'] not in (0,None) and step['result']!='TIMEOUT' and bool(re.search(
                    r"(?:used before|before (?:its )?declaration|unknown type|undeclared identifier).*(?:beat_t|trace_t|axil_request_t)|(?:beat_t|trace_t|axil_request_t).*(?:used before|before (?:its )?declaration|unknown type|undeclared)",text,re.I))
                case.finish('PASS' if ok else 'FAIL',None if ok else 'Expected invalid forward-reference diagnostic',expected='INVALID_FORWARD_REFERENCE')
            elif step['result']!='PASS':
                case.finish(step['result'],step['first_failure'])
            elif phase=='synthesis':
                net=json.loads((case.path/'netlist.json').read_text())
                cells=[c['type'] for m in net['modules'].values() for c in m.get('cells',{}).values()]
                bad=[c for c in cells if 'latch' in c.lower()]
                fields=dict(generic_cells=len(cells),latches=bad,netlist_sha256=sha(case.path/'netlist.json'))
                if name in ('features','record_memory'):
                    inferred=json.loads((case.path/'inferred.json').read_text())
                    memories=[c for m in inferred['modules'].values() for c in m.get('cells',{}).values() if c['type']=='$mem_v2']
                    fields['inferred_memories']=[{k:int(c['parameters'][k],2) for k in ('WIDTH','SIZE','RD_PORTS','WR_PORTS','RD_CLK_ENABLE')} for c in memories]
                    widths=[10,16] if name=='features' else [10]
                    if len(memories)!=len(widths) or sorted(int(c['parameters']['WIDTH'],2) for c in memories)!=widths:
                        bad.append('Unexpected packed-record memory count/width')
                case.finish('FAIL' if bad else 'PASS','Unexpected latch/memory structure' if bad else None,**fields)
            else:
                case.finish('PASS')
    if args.frontend=='slang':
        from registry import profile
        from contracts import INVALID
        for name in ('type_parameter','named_widths'):
            files=[generated/'tm_fixed.sv']+[generated/p for p in manifest[name]]+[generated/name/'probe_unit.sv']
            configurations=[(p,profile(p),False) for p in ('F0','F1','I0','I1','E0','E1')]
            configurations += [('invalid-'+n,dict(profile('E0'),**delta),True) for n,delta in INVALID.items()]
            for label,params,invalid in configurations:
                case=Case(run,'representation-'+name+'-'+label)
                case.data.update(parameters=params,scope='Disposable production FIFO/CSR/statistics profile elaboration; no integrated TM')
                script=case.path/'elaboration.ys'
                script.write_text(read_sources(files,'probe_unit',[generated,ROOT/'rtl/include'],params=params,frontend='slang'))
                step=case.execute(['yosys','-Q','-T','-s',str(script)],timeout=args.timeout)
                if invalid:
                    ok=step['returncode'] not in (0,None) and step['result']!='TIMEOUT' and 'TM_INVALID_CONFIGURATION' in output(step)
                    case.finish('PASS' if ok else 'FAIL',None if ok else 'Missing intended invalid representation configuration rejection',expected='INVALID_ELABORATION')
                else:
                    case.finish(step['result'],step['first_failure'])
    # Run the actual production-derived behavior on two heterogeneous instances.
    for name in ('ansi_vectors','type_parameter','named_widths','features'):
        case=Case(run,'frontend-simulation-'+name)
        if name=='features':
            files=[BASE/'features.sv',BASE/'features_tb.sv'];top='feature_test';marker='TM_FEATURE_PASS reads=16'
        else:
            files=([generated/'tm_fixed.sv'] if name in PACKAGES else [])+[generated/p for p in manifest[name]]
            files += [generated/name/'probe_unit.sv', generated/'test.sv'];top='test';marker='PROBE_PASS two independent configurations'
        binary=case.path/'obj'/('V'+top)
        argv=['verilator','--binary','--timing','--assert','--timescale','1ns/1ps','--build-jobs',str(args.jobs),
              '--top-module',top,'--Mdir',str(binary.parent),'-I'+str(generated),'-I'+str(ROOT/'rtl/include')]+list(map(str,files))
        step=case.execute(argv,timeout=args.build_timeout)
        if step['result']!='PASS' or not binary.is_file():
            case.finish(step['result'] if step['result']!='PASS' else 'TOOL_ERROR','Missing frontend behavior executable')
        else:
            case.finish(*completed(case.execute([str(binary)],cwd=case.path,timeout=args.timeout),marker))


def representation_formal(run,args):
    """Exercise richer headers/types on copies of the real production modules."""
    from copy import copy
    from formal_storage import formal_rtl
    case=Case(run,'representation-generate')
    generated=run.path/'generated'
    step=case.execute([sys.executable,str(BASE/'generate.py'),'--repo-root',str(ROOT),'--output',str(generated)])
    case.finish(step['result'],step['first_failure'])
    if step['result']!='PASS':return
    candidate=generated/'type_parameter'
    fifo=candidate/'tm_axis_rx_fifo.sv'
    text=fifo.read_text();target='logic [BEAT_W-1:0] storage [0:RX_FIFO_DEPTH-1];'
    if text.count(target)!=1:raise ValueError('Ambiguous FIFO record-memory transformation')
    fifo.write_text(text.replace(target,'beat_t storage [0:RX_FIFO_DEPTH-1];'))
    proof_args=copy(args)
    proof_args.profile='E0';proof_args.test=['fifo2','fifo4','csr'];proof_args.seed=None
    proof_args.frontend='slang';proof_args.candidate_root=candidate
    formal_rtl(run,proof_args)
