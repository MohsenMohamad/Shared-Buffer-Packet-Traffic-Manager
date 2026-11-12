"""Immutable Git baseline for representation comparison; never a production source set."""
import json
import subprocess
from pathlib import Path
from evidence import ROOT


def baseline_revision():
    return json.loads((ROOT/'verification/representation.json').read_text())['baseline_revision']


def baseline_text(path):
    return subprocess.check_output(['git', 'show', baseline_revision()+':'+str(path)],
                                   cwd=ROOT, text=True, timeout=30)


def stage_baseline(destination):
    """Extract the registered old RTL/headers without changing the worktree."""
    destination=Path(destination)
    registry=json.loads(baseline_text('verification/sources/production.json'))
    for path in registry['sources']+registry['headers']:
        target=destination/path
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_text(baseline_text(path))
    return [destination/p for p in registry['sources']], [destination/p for p in registry['include_dirs']]


def record_fifo_candidate(path):
    """Change only the actual FIFO storage element's representation."""
    import re
    path=Path(path)
    path.parent.mkdir(parents=True,exist_ok=True)
    text=(ROOT/'rtl/common/tm_axis_rx_fifo.sv').read_text()
    types=(ROOT/'rtl/include/tm_types.svh').read_text()
    beat=re.search(r'localparam type beat_t = (struct packed \{.*?\}) `TM_TYPE_END',types,re.S)
    if not beat:raise ValueError('Missing canonical beat type')
    width=', localparam integer BEAT_W=DATA_W+DATA_W/8+65'
    target='logic [BEAT_W-1:0] storage [0:RX_FIFO_DEPTH-1];'
    if text.count(width)!=1 or text.count(target)!=1:
        raise ValueError('Ambiguous FIFO record-memory transformation')
    text=text.replace(width,', localparam type beat_t='+beat[1]+'\n, localparam integer BEAT_W=$bits(beat_t)')
    path.write_text(text.replace(target,'beat_t storage [0:RX_FIFO_DEPTH-1];'))
    return path


def sequential_equivalence(run,args):
    """Sequential state/output comparison complements the independent contracts."""
    from evidence import Case, output
    from frontend import read_sources
    from registry import sources, profile
    old_files,old_includes=stage_baseline(run.path/'equivalence-baseline')
    current=sources('production')
    files=[ROOT/p for p in current['sources']]
    includes=[ROOT/p for p in current['include_dirs']]
    modules=['tm_axis_rx_fifo_api','tm_cell_pool_api','tm_desc_pool_api',
             'tm_axil_regs_api','tm_statistics_api']
    for configuration in ('F0','F1','I0','I1','E0','E1'):
        for top in modules:
            variants=(2,4) if top=='tm_axis_rx_fifo_api' else (64,8) if top=='tm_statistics_api' else (None,)
            for variant in variants:
                case=Case(run,'equivalence-'+configuration+'-'+top+('' if variant is None else '-'+str(variant)))
                params=profile(configuration)
                if top=='tm_axis_rx_fifo_api':params['RX_FIFO_DEPTH']=variant
                if top=='tm_statistics_api':params['COUNTER_W']=variant
                script=case.path/'equivalence.ys'
                text=''
                for label,inputs,dirs in [('gold',old_files,old_includes),('gate',files,includes)]:
                    text+=read_sources(inputs,top,dirs,params=params,frontend='slang')
                    text+=f'prep -top {top} -flatten\nwrite_json {case.path}/{label}-inferred.json\nasync2sync\nmemory_map\nopt\nrename {top} {label}\ndesign -stash {label}\n'
                text+='design -copy-from gold -as gold gold\ndesign -copy-from gate -as gate gate\n'
                # Compare interface shape before accepting a proof: all outputs,
                # including invalid-data bits, participate in equiv_make.
                text+=f'write_json {case.path}/models.json\n'
                text+='equiv_make gold gate equiv\nhierarchy -top equiv\nequiv_struct -icells\nequiv_simple -seq 1\nequiv_induct -seq 4\nequiv_status -assert\n'
                script.write_text(text)
                step=case.execute(['yosys','-Q','-T','-s',str(script)],timeout=max(args.timeout,300))
                inference={}
                for label in ('gold','gate'):
                    path=case.path/(label+'-inferred.json')
                    if path.exists():
                        cells=[c for m in json.loads(path.read_text())['modules'].values() for c in m['cells'].values()]
                        inference[label]=dict(
                            state=sorted((c['type'],int(c['parameters']['WIDTH'],2)) for c in cells if 'dff' in c['type'].lower()),
                            memories=sorted(tuple(int(c['parameters'][k],2) for k in ('WIDTH','SIZE','RD_PORTS','WR_PORTS','RD_CLK_ENABLE','WR_CLK_ENABLE')) for c in cells if c['type']=='$mem_v2'),
                            latches=[c['type'] for c in cells if 'latch' in c['type'].lower()])
                ports={}
                model=case.path/'models.json'
                if model.exists():
                    models=json.loads(model.read_text())['modules']
                    ports={label:{n:(v['direction'],len(v['bits'])) for n,v in models[label]['ports'].items()} for label in ('gold','gate')}
                ok=step['returncode']==0 and 'Equivalence successfully proven!' in output(step) and ports.get('gold')==ports.get('gate') and bool(ports) and len(inference)==2 and inference['gold']==inference['gate'] and not inference['gate']['latches']
                case.finish('PASS' if ok else 'TIMEOUT' if step['result']=='TIMEOUT' else 'FAIL',
                    None if ok else 'Complete sequential equivalence or matching port layouts missing',
                    baseline_revision=baseline_revision(),parameters=params,ports=ports,inference=inference,
                    method='Yosys equiv_simple plus temporal induction; all output bits, matching state correspondence; no environment/fairness assumptions',
                    scope='Supplementary equivalence to existing behavior; independent reset/protocol/ownership contract checks remain required')
