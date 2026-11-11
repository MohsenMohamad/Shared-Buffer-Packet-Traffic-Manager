"""FP-CSR production protocol proof, covers and coupled-channel mutation."""
from evidence import Case, ROOT, output, sha
from registry import sources, fingerprint
from frontend import read_sources, selected, expose_symbolic_inputs


def formal_csr(run, args, configuration):
    registered = sources('formal')
    for task in ('prove', 'cover', 'mutation'):
        case = Case(run, 'rtl-csr-'+task)
        case.data.update(configuration=configuration, source_set='formal',
                         registered_source_digests=fingerprint('formal'), engine='smtbmc z3',
                         method='bounded reachability depth 24' if task == 'cover' else 'unbounded k-induction',
                         assumptions='Reset low for first two sampled edges; later resets arbitrary. AW/W/AR source fields stable while stalled. No response-ready fairness or AW/W coupling.')
        files = []
        for path in registered['sources']+registered['headers']:
            source = ROOT/path
            if task == 'mutation' and source.name == 'tm_axil_regs.sv':
                mutant = case.path/source.name
                text = source.read_text()
                target = 'bus_rsp.awready = rst_n && !have_aw && !bvalid;'
                if text.count(target) != 1:
                    raise ValueError('Coupled-channel mutation site missing or ambiguous')
                mutant.write_text(text.replace(target, target[:-1]+' && bus_req.wvalid;'))
                source = mutant
                case.data.update(mutation='AWREADY depends on WVALID', mutant_sha256=sha(mutant))
            if source.name == 'csr_formal.sv' and selected(args, 'formal') == 'slang':
                text, ports = expose_symbolic_inputs(source)
                source = case.path / source.name
                source.write_text(text)
                case.data.update(symbolic_inputs=ports, harness_sha256=sha(source),
                                 symbolic_representation='arbitrary top-level inputs; assumptions/properties unchanged')
            files.append(source.name+' '+str(source))
        case.data['frontend'] = selected(args, 'formal')
        script = read_sources([(ROOT/p).name for p in registered['sources'] if p != 'formal/pools/storage_formal.sv'], 'csr_formal', frontend=selected(args, 'formal'), formal=True)
        script += 'prep -top csr_formal\nasync2sync\ndffunmap'
        config = case.path/'csr.sby'
        config.write_text((ROOT/'formal/csr/csr.sby').read_text().replace('@SCRIPT@',script).replace('@FILES@','\n'.join(files)))
        step = case.execute(['sby','-f','-d',str(case.path/'engine'),str(config),task],timeout=args.timeout,cwd=case.path)
        status_file = case.path/'engine/status'
        status = status_file.read_text().split()[0] if status_file.is_file() else None
        waves = [str(p) for p in (case.path/'engine').rglob('*.vcd') if p.stat().st_size]
        text = output(step)
        if step['result'] == 'TIMEOUT':
            result, why = 'TIMEOUT', step['first_failure']
        elif task == 'mutation':
            ok = step['returncode'] not in (0,None) and status == 'FAIL' and bool(waves) and 'a_aw_independent' in text and 'Assert failed' in text
            result, why = ('PASS',None) if ok else ('FAIL','Intended independent-AW assertion counterexample missing')
        else:
            marker = 'Reached cover statement' if task == 'cover' else 'successful proof by k-induction'
            ok = step['returncode'] == 0 and status == 'PASS' and marker in text and (task != 'cover' or bool(waves))
            result, why = ('PASS',None) if ok else ('FAIL' if status == 'FAIL' else 'INCONCLUSIVE' if status == 'UNKNOWN' else 'TOOL_ERROR','Completed production proof/cover missing')
        case.data['artifacts'].update(status=str(status_file), traces=waves, configuration=str(config))
        case.finish(result, why, engine_status=status, expected='SEEDED_DEFECT_DETECTION' if task == 'mutation' else task.upper())
