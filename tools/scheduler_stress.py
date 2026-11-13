"""Extended component traffic, fail-closed coverage, replay and defect probes."""
import json
from pathlib import Path
import re
from evidence import Case, output, sha
from registry import fingerprint
from foundation import run_result


DEFECTS={
    'lost-carry': (1,{'SCHEDULE_CREDIT'}),
    'wait-quantum': (1,{'SCHEDULE_CREDIT'}),
    'wrong-length': (1,{'SCHEDULE_CREDIT'}),
    'busy-dispatch': (1,{'SCHEDULE_GRANT','SCHEDULER_GRANT'}),
    'replacement-clear': (1,{'SCHEDULE_CREDIT'}),
    'empty-retain': (1,{'SCHEDULE_CREDIT'}),
    'rr-no-advance': (0,{'SCHEDULE_HEAD'}),
}


def mutate(text,kind):
    # These are source-copy edit sites only. The independent event/length
    # checker and its expectations come from the normative scheduling contract.
    edits={
        'extra-quantum': ('if (!visit_active)\n                    credit =',"if (!visit_active || (tx_ready && credit >= (DEFICIT_W+1)'(selected_info.length)))\n                    credit =",1),
        'missing-dispatch': ('else if (tx_ready) begin',"else if (tx_ready && 1'b0) begin",2),
        'lost-carry': ("if (credit < (DEFICIT_W+1)'(selected_info.length)) begin", "if (credit < (DEFICIT_W+1)'(selected_info.length)) begin\n                    deficits_next[cursor*DEFICIT_W +: DEFICIT_W] = '0;",1),
        'wait-quantum': ('if (!visit_active)','if (!visit_active || !tx_ready)',1),
        'wrong-length': ("credit-(DEFICIT_W+1)'(selected_info.length)","credit-(DEFICIT_W+1)'(commit.info.length)",1),
        'busy-dispatch': ('if (rst_n && cfg.run && !tx_owned) begin','if (rst_n && cfg.run) begin',2),
        'replacement-clear': ('==1 && !replaced)', '==1)',1),
        'empty-retain': ('if (counts[cursor*DESC_COUNT_W +: DESC_COUNT_W]==1 && !replaced)', "if (1'b0 && counts[cursor*DESC_COUNT_W +: DESC_COUNT_W]==1 && !replaced)",1),
    }
    if kind=='rr-no-advance':
        prefix,suffix=text.split('end else begin : g_drr',1)
        target='cursor_next = successor(cursor);'
        if prefix.count(target)!=2:
            raise ValueError('RR mutation site missing or ambiguous')
        index=prefix.rfind(target)
        return prefix[:index]+prefix[index:].replace(target,'cursor_next = cursor;',1)+'end else begin : g_drr'+suffix
    target,replacement,count=edits[kind]
    if text.count(target)!=count:
        raise ValueError('Scheduler mutation site missing or ambiguous: '+kind)
    return text.replace(target,replacement)


def intended_failure(step,text,wave,detectors):
    fatals=re.findall(r'UVM_FATAL[^\n]*\[([^]]+)\]',text)
    if not fatals:
        fatals=re.findall(r'Assertion failed[^\n]*:\s*(SCHEDULER_[A-Z_]+)\b',text)
    ok=(step['result']!='TIMEOUT' and step['returncode'] not in (0,None) and
        len(fatals)==1 and fatals[0] in detectors and wave.is_file() and wave.stat().st_size>0)
    return ok,fatals


def inspect_stress(path,mode,nq):
    def unique(items):
        data={}
        for key,value in items:
            if key in data: raise ValueError('Duplicate scheduler coverage field: '+key)
            data[key]=value
        return data
    data=json.loads(Path(path).read_text(),object_pairs_hook=unique)
    expected={'backlog.'+s for s in ('zero','one','multiple','all')}
    expected|={'cursor.wrap','reactivation.round_all','quantum.minimum','quantum.maximum','final.stall'}
    expected|={'quantum.'+s for s in ('less','equal','greater')}
    expected|={'stall.'+s for s in ('none','short','medium','long')}
    expected|={'visit.'+s for s in ('zero','one','many')}
    expected|={f'reset.{phase}.{busy}' for phase in range(6) for busy in (0,1)}
    allowed={(0,0),(2,0),(2,1),(3,0),(4,1),(5,1)}
    if mode: allowed.add((1,0))
    exclusions={f'reset.{p}.{b}':'Reset phase has incompatible pre-state ownership or no RR byte visit'
                for p in range(6) for b in (0,1) if (p,b) not in allowed}
    if mode==0: exclusions['visit.many']='Packet RR closes a visit after exactly one dispatch'
    counters=data['coverage_counts']
    if set(counters)!=expected or data['mode']!=mode:
        raise ValueError('Missing extended scheduler coverage dimensions or wrong mode')
    if any(counters[key]<=0 for key in expected-exclusions.keys()):
        raise ValueError('Unhit mandatory extended scheduler bins: '+','.join(sorted(k for k in expected-exclusions.keys() if counters[k]<=0)))
    if any(counters[key]!=0 for key in exclusions):
        raise ValueError('Impossible extended scheduler coverage bin hit')
    for key in ('random_publications','progress_checks','reconfigurations','behind','ahead','completion_commits','reactivation_boundary'):
        if data[key]<=0: raise ValueError('Required scheduler scenario absent: '+key)
    if data['random_steps']!=4800 or (mode and data['skip_commits']<=0):
        raise ValueError('Random traffic or insufficient-credit/publication scenario missing')
    quanta=data['random_quanta']
    if len(quanta)!=3 or any(len(row)!=nq for row in quanta) or any(not 64<=q<=4096 for row in quanta for q in row):
        raise ValueError('Invalid saved random quanta')
    values={q for row in quanta for q in row}
    if not {64,4096}<=values or not any(64<q<4096 for q in values):
        raise ValueError('Random quantum endpoint/interior classes absent')
    if len(data['random_qids'])!=nq or sum(data['random_qids'])!=data['random_publications'] or len(data['length_choices'])!=10 or sum(data['length_choices'])!=data['random_publications']:
        raise ValueError('Random publication statistics do not match observed API events')
    if any(count<=0 for count in data['length_choices']):
        raise ValueError('Random weighted length class absent')
    return dict(data=data,exclusions=exclusions,mandatory_hit=len(expected-exclusions.keys()),mandatory_total=len(expected-exclusions.keys()))


def stress_runs(run,args,binary,parameters):
    from scheduler import scheduler_coverage
    mode=parameters['SCHED_MODE']
    seed=(args.seed or [17])[0]
    seeds=[seed,1+(seed+13)%(2**31-1),1+(seed+35)%(2**31-1)]
    reference=None
    for index,current in enumerate(seeds+[seed]):
        case=Case(run,f'scheduler-mode{mode}-stress-'+('replay' if index==3 else str(current)),current)
        case.data.update(parameters=parameters,source_set='scheduler',registered_source_digests=fingerprint('scheduler'))
        step=case.execute([str(binary),f'+verilator+seed+{current}','+UVM_NO_RELNOTES',
                           '+UVM_TESTNAME=tm_scheduler_stress_test','+DETACHED_STIMULUS_PROBE'],timeout=args.timeout,cwd=case.path)
        result,why=run_result(step,'TM_SCHED_STRESS_PASS')
        if result=='PASS':
            try:
                functional=case.path/'scheduler-stress.json'; events=case.path/'scheduler-events.jsonl'; coverage=case.path/'coverage.dat'
                case.data['stress']=inspect_stress(functional,mode,parameters['N_Q'])
                case.data['coverage']=scheduler_coverage(coverage,mode)
                for key,path in (('functional_coverage',functional),('events',events),('coverage',coverage)):
                    if not path.is_file() or path.stat().st_size==0: raise ValueError('Missing saved '+key)
                    case.data['artifacts'].update({key:str(path),key+'_sha256':sha(path)})
                digest=case.data['artifacts']['events_sha256']
                if index==0: reference=digest
                elif index==3 and digest!=reference: raise ValueError('Same-seed passive event replay differs')
                elif index in (1,2) and digest==reference: raise ValueError('Distinct seeds did not change passive events')
            except (OSError,ValueError,KeyError,TypeError) as error:
                result,why='FAIL',str(error)
        if result!='PASS' and step['result']!='TIMEOUT':
            rerun=case.path/'failing-rerun';rerun.mkdir()
            case.execute([str(binary),f'+verilator+seed+{current}','+UVM_TESTNAME=tm_scheduler_stress_test','+DETACHED_STIMULUS_PROBE','+TRACE'],timeout=args.timeout,cwd=rerun)
            case.data['artifacts']['waveform']=str(rerun/'wave.vcd')
        case.finish(result,why,replay=index==3,requested_seeds=seeds)
    # Neighbor-contract mutations use the same production elaboration, with a
    # separate intended input diagnostic before policy can consume bad events.
    if mode==1:
        for probe,detector in [('done_unowned','SCHED_INPUT_DONE'),('done_mismatch','SCHED_INPUT_DONE'),
                               ('duplicate_commit','SCHED_INPUT_COMMIT'),('config','SCHED_INPUT_CONFIG'),('stale_done','SCHED_INPUT_DONE')]:
            case=Case(run,'scheduler-input-'+probe,seed)
            step=case.execute([str(binary),f'+verilator+seed+{seed}','+UVM_TESTNAME=tm_scheduler_stress_test','+TRACE','+INPUT_PROBE='+probe],timeout=args.timeout,cwd=case.path)
            wave=case.path/'wave.vcd'
            ok,fatals=intended_failure(step,output(step),wave,{detector})
            case.data['artifacts']['waveform']=str(wave)
            case.finish('PASS' if ok else 'FAIL',None if ok else 'Intended input contract diagnostic missing',
                        expected='SEEDED_NEIGHBOR_VIOLATION',detector=detector,observed_fatals=fatals)
