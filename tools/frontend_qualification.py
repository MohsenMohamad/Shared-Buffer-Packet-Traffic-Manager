"""Production-derived representation and independent frontend capability checks."""
import json
from pathlib import Path
import re
import sys
from evidence import Case, ROOT, completed, output, sha
from frontend import read_sources
from registry import sources
from representation import stage_baseline, baseline_revision, record_fifo_candidate

BASE = ROOT / 'tests/frontends'
CANDIDATES = ('baseline', 'ansi_vectors', 'package_vectors', 'package_scoped',
              'inline_struct', 'type_parameter', 'forward_typedef', 'minimal', 'named_widths', 'bits_type', 'production')
PACKAGES = {'package_vectors','package_scoped','inline_struct','type_parameter','minimal','named_widths','bits_type'}


def audit(run, args):
    generate = Case(run, 'frontend-generate')
    generated = run.path / 'generated'
    step = generate.execute([sys.executable, str(BASE/'generate.py'), '--repo-root', str(ROOT), '--output', str(generated)])
    generate.finish(step['result'], step['first_failure'])
    if step['result'] != 'PASS':
        return
    manifest = json.loads((generated/'candidates.json').read_text())
    # Historical controls use their own headers; current modules use the registry.
    stage_baseline(generated/'baseline-rtl')
    production_probe=generated/'production/probe_unit.sv'
    production_probe.parent.mkdir()
    production_probe.write_text((BASE/'fixtures/probe_unit.sv').read_text().replace('PROBE_TYPES.svh','tm_types.svh'))
    registered=sources('production')
    def candidate_files(name):
        if name=='production':
            return [ROOT/p for p in registered['sources']]+[production_probe]
        return ([generated/'tm_fixed.sv'] if name in PACKAGES else []) + [generated/p for p in manifest[name]]+[generated/name/'probe_unit.sv']
    def candidate_includes(name):
        return [generated, ROOT/'rtl/include'] if name=='production' else [generated,generated/'baseline-rtl/rtl/include']
    for name in CANDIDATES + ('features','unpacked','interface','record_memory'):
        top = {'features':'feature_top','unpacked':'unpacked_ports','interface':'interface_top','record_memory':'record_memory'}.get(name) or ('bits_type' if name=='bits_type' else 'synth_top')
        includes = candidate_includes(name)
        if name in ('features','unpacked','interface','record_memory'):
            files=[BASE/(name+'.sv')]
        else:
            files=([generated/'tm_fixed.sv',generated/'bits_type.sv'] if name=='bits_type'
                   else candidate_files(name)+[generated/'synth_top.sv'])
        for phase in ('parse','elaborate','synthesis'):
            case=Case(run, f'frontend-{args.frontend}-{name}-{phase}')
            case.data.update(frontend=args.frontend, candidate=name, phase=phase,
                             reference_revision=baseline_revision() if name not in ('production','features','unpacked','interface','record_memory') else 'current',
                             input_digests={str(p.relative_to(ROOT)):sha(p) for p in files},
                             method='AST compilation/semantic checking without RTLIL lowering' if phase=='parse' and args.frontend=='slang' else 'deferred AST parsing' if phase=='parse' else 'RTLIL elaboration' if phase=='elaborate' else 'completed generic synthesis')
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
    if args.frontend=='slang':
        from registry import profile
        from contracts import INVALID
        for name in ('type_parameter','named_widths','production'):
            files=candidate_files(name)
            configurations=[(p,profile(p),False) for p in ('F0','F1','I0','I1','E0','E1')]
            configurations += [('invalid-'+n,dict(profile('E0'),**delta),True) for n,delta in INVALID.items()]
            for label,params,invalid in configurations:
                case=Case(run,'representation-'+name+'-'+label)
                case.data.update(parameters=params,scope='Current registered production elaboration' if name=='production' else 'Historical disposable production representation elaboration')
                script=case.path/'elaboration.ys'
                script.write_text(read_sources(files,'probe_unit',candidate_includes(name),params=params,frontend='slang'))
                step=case.execute(['yosys','-Q','-T','-s',str(script)],timeout=args.timeout)
                if invalid:
                    ok=step['returncode'] not in (0,None) and step['result']!='TIMEOUT' and 'TM_INVALID_CONFIGURATION' in output(step)
                    case.finish('PASS' if ok else 'FAIL',None if ok else 'Missing intended invalid representation configuration rejection',expected='INVALID_ELABORATION')
                else:
                    case.finish(step['result'],step['first_failure'])
    # Run the actual production-derived behavior on two heterogeneous instances.
    for name in ('ansi_vectors','type_parameter','named_widths','production','features'):
        case=Case(run,'frontend-simulation-'+name)
        if name=='features':
            files=[BASE/'features.sv',BASE/'features_tb.sv'];top='feature_test';marker='TM_FEATURE_PASS reads=16'
        else:
            files=candidate_files(name)+[generated/'test.sv'];top='test';marker='PROBE_PASS two independent configurations'
        binary=case.path/'obj'/('V'+top)
        argv=['verilator','--binary','--timing','--assert','--timescale','1ns/1ps','--build-jobs',str(args.jobs),
              '--top-module',top,'--Mdir',str(binary.parent)]+['-I'+str(p) for p in candidate_includes(name)]+list(map(str,files))
        step=case.execute(argv,timeout=args.build_timeout)
        if step['result']!='PASS' or not binary.is_file():
            case.finish(step['result'] if step['result']!='PASS' else 'TOOL_ERROR','Missing frontend behavior executable')
        else:
            case.finish(*completed(case.execute([str(binary)],cwd=case.path,timeout=args.timeout),marker))


def representation_formal(run,args):
    """Prove registered production modules with the original independent properties."""
    from copy import copy
    from formal_storage import formal_rtl
    proof_args=copy(args)
    proof_args.profile='E0';proof_args.test=['fifo2','fifo4','csr'];proof_args.seed=None
    proof_args.frontend='slang'
    formal_rtl(run,proof_args)
    # Explicitly label the alternate storage proof as a disposable comparison.
    record_args=copy(proof_args)
    record_args.test=['fifo2','fifo4']
    record_args.candidate_root=run.path/'record-candidate'
    record_args.representation_label='record-'
    record_fifo_candidate(record_args.candidate_root/'tm_axis_rx_fifo.sv')
    formal_rtl(run,record_args)
    from representation import sequential_equivalence
    sequential_equivalence(run,args)


def fifo_mapping(run,args):
    """Map every payload bit of real FIFO copies, with explicit IO timing."""
    from registry import profile
    from run import sta_result
    liberty=ROOT/'.deps/liberty.lib'
    old_files,old_includes=stage_baseline(run.path/'baseline')
    # Reassess the historical workaround on the actual FIFO, without changing
    # any operation: full packed records and vectors must infer the same ports.
    candidate=record_fifo_candidate(run.path/'record-fifo.sv')
    top='tm_axis_rx_fifo_api'
    measurements={}
    for representation in ('baseline-vector','production-vector','candidate-record'):
        for depth in (2,4):
            case=Case(run,f'fifo-map-{representation}-depth{depth}')
            params=dict(profile('E0'),RX_FIFO_DEPTH=depth)
            files=[old_files[[p.name for p in old_files].index('tm_axis_rx_fifo.sv')]] if representation=='baseline-vector' else [ROOT/'rtl/common/tm_axis_rx_fifo.sv'] if representation=='production-vector' else [candidate]
            includes=old_includes if representation=='baseline-vector' else [ROOT/'rtl/include']
            inferred=case.path/'inferred.json'
            netlist,stats,script=case.path/'mapped.v',case.path/'stats.json',case.path/'mapping.ys'
            script.write_text(read_sources(files,top,includes,params=params,frontend='slang')+
                              f'proc\nmemory_collect\nwrite_json {inferred}\ndesign -reset\n'+
                              read_sources(files,top,includes,params=params,frontend='slang')+
                              f'synth -top {top} -noabc\ndffunmap\ndfflibmap -liberty {liberty}\nabc -liberty {liberty}\nclean\n'+
                              f'read_liberty -lib {liberty}\ncheck -assert\nwrite_verilog -noattr {netlist}\ntee -o {stats} stat -json -liberty {liberty}\n')
            step=case.execute(['yosys','-Q','-T','-s',str(script)],timeout=max(args.timeout,300))
            if step['result']!='PASS':
                case.finish(step['result'],step['first_failure']);continue
            try:
                data=json.loads(stats.read_text())['modules']['\\'+top]
                cells=data['num_cells_by_type']
                if not cells or any(n.startswith('$') for n in cells) or not any(n.startswith('DFF') for n in cells):
                    raise ValueError('Expected fully mapped sequential/combinational FIFO')
                memories=[c for m in json.loads(inferred.read_text())['modules'].values() for c in m['cells'].values() if c['type']=='$mem_v2']
                memory_ports=[{k:int(c['parameters'][k],2) for k in ('WIDTH','SIZE','RD_PORTS','WR_PORTS','RD_CLK_ENABLE','WR_CLK_ENABLE')} for c in memories]
                if memory_ports!=[dict(WIDTH=137,SIZE=depth,RD_PORTS=1,WR_PORTS=1,RD_CLK_ENABLE=0,WR_CLK_ENABLE=1)]:
                    raise ValueError('FIFO memory width/depth/port semantics changed')
                measurements[(representation,depth)]=(cells,data['area'],memory_ports)
                case.finish('PASS',parameters=params,payload_bits=137*depth,inferred_memories=memory_ports,mapped_cells=cells,area=data['area'],
                            source_digests={str(p.relative_to(ROOT)):sha(p) for p in files},netlist_sha256=sha(netlist),
                            scope='Actual E0 FIFO including all payload bits; representation copies only; no allocator/TM characterization')
            except (OSError,ValueError,KeyError) as error:
                case.finish('FAIL',str(error));continue
            timing=Case(run,f'fifo-sta-{representation}-depth{depth}')
            sdc=timing.path/'timing.sdc';tcl=timing.path/'timing.tcl'
            sdc.write_text('create_clock -name clk -period 10 [get_ports clk]\nset_clock_uncertainty 0.05 [get_clocks clk]\n'+
                           'set data_inputs [all_inputs -no_clocks]\n'+
                           'set_input_delay -max -clock clk 1 $data_inputs\nset_input_delay -min -clock clk 0.2 $data_inputs\n'+
                           'set_input_transition 0.05 $data_inputs\nset_output_delay -max -clock clk 1 [all_outputs]\n'+
                           'set_output_delay -min -clock clk 0.2 [all_outputs]\nset_load 10.0 [all_outputs]\n')
            tcl.write_text(f'read_liberty {liberty}\nread_verilog {netlist}\nlink_design {top}\nread_sdc {sdc}\n'+
                           'report_units\ncheck_setup -verbose\nputs TM_STA_MAX_BEGIN\nreport_checks -path_delay max -format full_clock_expanded\n'+
                           'puts TM_STA_MIN_BEGIN\nreport_checks -path_delay min -format full_clock_expanded\nputs TM_STA_DONE\nexit\n')
            step=timing.execute(['sta','-no_init','-exit',str(tcl)],timeout=args.timeout)
            text=output(step)
            slacks=re.findall(r'([-+]?\d+\.\d+)\s+slack',text)
            reports=[dict(startpoint=start.strip(),endpoint=end.strip(),group=group.strip(),
                          delay=delay,slack_ns=slack) for start,end,group,delay,slack in re.findall(
                r'Startpoint: ([^\n]+)\nEndpoint: ([^\n]+)\nPath Group: ([^\n]+)\nPath Type: (max|min).*?([-+]?\d+\.\d+)\s+slack',text,re.S)]
            timing.finish(*sta_result(step),slacks_ns=slacks,path_reports=reports,
                          timing_closure='FAIL' if any(float(v)<0 for v in slacks) else 'PASS',
                          constraints_sha256=sha(sdc),netlist_sha256=sha(netlist),
                          analysis='Nangate45 typical 1.10 V / 25 C; ns/fF; ideal clock; explicit IO including reset; no timing exceptions; pre-layout')
    comparison=Case(run,'fifo-mapping-comparison')
    ok=len(measurements)==6 and all(measurements[('baseline-vector',depth)]==measurements[(variant,depth)]
        for depth in (2,4) for variant in ('production-vector','candidate-record'))
    comparison.finish('PASS' if ok else 'FAIL',None if ok else 'Unexpected FIFO mapping/inference difference',
                      baseline_revision=baseline_revision(),scope='Identical matched memory dimensions/ports, cell histogram and area; timing closure remains separately reported')
