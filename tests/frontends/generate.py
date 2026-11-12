from pathlib import Path
import re, json

import argparse
HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description="Generate disposable production RTL representation candidates")
parser.add_argument('--repo-root',type=Path,default=HERE.parents[1])
parser.add_argument('--output',type=Path)
args=parser.parse_args()
ROOT=args.repo_root.resolve()
OUT=(args.output or ROOT/'.build/frontends/generated').resolve()
OUT.mkdir(parents=True,exist_ok=True)
FIXTURES=HERE/'fixtures'
for filename in ['probe_unit.sv','test.sv','formal_probe.sv','bits_type.sv','synth_top.sv']:
    (OUT/filename).write_bytes((FIXTURES/filename).read_bytes())
types=(ROOT/'rtl/include/tm_types.svh').read_text()
params=(ROOT/'rtl/include/tm_parameters.svh').read_text()
decls=dict((name,body.strip()) for body,name in re.findall(r'typedef\s+(.*?)\s+(\w+_t);',types,re.S))
# The first match includes preceding comments/localparams. Extract only the type.
decls['cell_id_t']='logic [CELL_ID_W-1:0]'
fixed=['status_code_t','owner_t','rx_phase_t','axil_resp_t','input_user_t','output_user_t','status_t','stats_command_t','axil_request_t','axil_response_t']
package='package tm_fixed;\n'+''.join('typedef '+decls[n]+' '+n+';\n' for n in fixed)+'localparam integer STATUS_W=45;\nendpackage\n'
(OUT/'tm_fixed.sv').write_text(package)
local_types=types
for n in fixed:
    local_types=re.sub(r'typedef\s+'+re.escape(decls[n])+r'\s+'+n+r';','',local_types)
local_types=re.sub(r'localparam integer STATUS_W=45;','',local_types)
local_types='import tm_fixed::*;\n'+local_types
(OUT/'tm_local_types.svh').write_text(local_types)

def expanded(t):
    if t in fixed:return 'tm_fixed::'+t
    s=decls[t]
    return re.sub(r'\b\w+_t\b',lambda m: expanded(m[0]),s)

modules=['rtl/common/tm_axis_rx_fifo.sv','rtl/csr/tm_axil_regs.sv','rtl/csr/tm_statistics.sv']
manifest={}
for candidate in ['baseline','ansi_vectors','package_vectors','inline_struct','type_parameter','forward_typedef']:
    folder=OUT/candidate;folder.mkdir(exist_ok=True)
    info=[]
    for path in modules:
        original=(ROOT/path).read_text()
        match=re.search(r'\) \((.*?)\);\n`include "tm_types.svh"\n(.*?)`include "tm_validate.svh"',original,re.S)
        if not match:raise ValueError(path)
        portnames=[x.strip() for x in match[1].split(',')]
        # Comments are retained below the transformed header only if behavioral.
        porttext=re.sub(r'//[^\n]*','',match[2])
        ports={}
        for direction,t,names in re.findall(r'(input|output)\s+(logic(?:\s+\[[^]]+\])?|\w+_t)\s+([^;]+);',porttext):
            for name in names.split(','): ports[name.strip()]=(direction,t.strip())
        assert set(ports)==set(portnames),(path,ports,portnames)
        if candidate=='baseline':new=original
        else:
            headers=[]; bridges=[]; checks=[]; typepars=[]
            for name in portnames:
                direction,t=ports[name];ht=t
                if t.endswith('_t'):
                    if candidate=='forward_typedef':pass
                    elif candidate in ['inline_struct','type_parameter']:
                        ht=expanded(t)
                        if candidate=='type_parameter' and t not in fixed:
                            ht='PORT_'+t
                            if ht not in [x[0] for x in typepars]:typepars.append((ht,expanded(t)))
                    elif candidate=='package_vectors' and t in fixed:
                        ht='tm_fixed::'+t
                    else:
                        # Width formula is derived from the actual type declaration,
                        # independent of $bits(type), which the pinned frontend lacks.
                        def width(typ):
                            s=decls[typ]
                            if s.startswith('logic'):
                                return re.search(r'\[(.*)-1:0\]',s)[1] if '[' in s else '1'
                            if s.startswith('enum'):
                                return str(int(re.search(r'\[(\d+):0\]',s)[1])+1)
                            fields=s[s.index('{')+1:s.rindex('}')]
                            widths=[]
                            for field in fields.split(';'):
                                field=field.strip()
                                if not field:continue
                                typ,fieldnames=field.rsplit(' ',1)
                                w=width(typ) if typ in decls else (re.search(r'\[(.*)-1:0\]',typ)[1] if '-1:0]' in typ else str(int(re.search(r'\[(\d+):0\]',typ)[1])+1) if '[' in typ else '1')
                                widths.append('('+w+')')
                            return '+'.join(widths)
                        w=width(t)
                        # Keep boundary names; use suffixed internal records only in
                        # temporary copies. The body is rewritten by token boundary.
                        ht='logic [('+w+')-1:0]'
                        internal=name+'_typed'
                        bridges.append(t+' '+internal+';\nassign '+(internal+' = '+name if direction=='input' else name+' = '+internal)+';\n')
                        checks.append('if ($bits('+internal+') != $bits('+name+')) begin : g_width_'+name+' TM_INVALID_LAYOUT bad(); end\n')
                headers.append('    '+direction+' '+ht+' '+name)
            prefix=original[:match.start()]
            # Width dependencies visible before ANSI ports, never overrideable.
            derived=types[types.index('localparam integer RX_ID_W'):types.index('typedef logic')]
            if candidate in ['package_vectors','inline_struct','type_parameter']:
                derived=derived.replace('localparam integer STATUS_W=45;\n','')
            prefix+='\n, '+derived.replace(';\n',',\n').rstrip(',\n')
            if typepars:prefix+='\n'+''.join(', parameter type '+n+' = '+t+'\n' for n,t in typepars)
            body=original[match.end():]
            for name,(direction,t) in ports.items():
                if any(b.startswith(t+' '+name+'_typed;') for b in bridges):
                    body=re.sub(r'\b'+name+r'\b',name+'_typed',body)
            bodytypes=local_types if candidate in ['package_vectors','inline_struct','type_parameter'] else types
            bodytypes=re.sub(r'localparam integer .*?;\n','',bodytypes)
            new=prefix+'\n) (\n'+',\n'.join(headers)+'\n);\n'+bodytypes+'\n'+''.join(bridges)+'generate\n'+''.join(checks)+'endgenerate\n`include "tm_validate.svh"'+body
        target=folder/Path(path).name;target.write_text(new);info.append(str(target))
    manifest[candidate]=info
(OUT/'candidates.json').write_text(json.dumps(manifest,indent=2))

# Yosys read_verilog supports explicit package scope but rejects import syntax.
fixed_names=fixed+['STATUS_W']+re.findall(r'\b([A-Z][A-Z_]*)\s*=',package)
def scoped(s):
    s=s.replace('import tm_fixed::*;','')
    return re.sub(r'(?<!::)\b('+'|'.join(fixed_names)+r')\b',lambda m:'tm_fixed::'+m[0],s)
(OUT/'tm_scoped_types.svh').write_text(scoped(local_types))
folder=OUT/'package_scoped';folder.mkdir(exist_ok=True)
for path in manifest['package_vectors']:
    p=Path(path)
    (folder/p.name).write_text(scoped(p.read_text()))
manifest['package_scoped']=[str(folder/Path(s).name) for s in manifest['package_vectors']]
(OUT/'candidates.json').write_text(json.dumps(manifest,indent=2))

connections=re.findall(r'parameter integer (\w+)',params)
(OUT/'connections.svh').write_text(','.join('.'+n+'('+n+')' for n in connections)+'\n')
for name in manifest:
    inc='tm_scoped_types.svh' if name=='package_scoped' else 'tm_local_types.svh' if name in ['package_vectors','inline_struct','type_parameter'] else 'tm_types.svh'
    unit=(OUT/'probe_unit.sv').read_text().replace('PROBE_TYPES.svh',inc)
    (OUT/name/'probe_unit.sv').write_text(scoped(unit) if name=='package_scoped' else unit)

# FIFO logic never accesses beat fields: its packed vector is already the
# appropriate representation internally, so no typed bridge is necessary.
folder=OUT/'minimal';folder.mkdir(exist_ok=True)
for source in manifest['package_scoped']:
    p=Path(source)
    s=p.read_text()
    if p.name=='tm_axis_rx_fifo.sv':
        s=s[:s.index('// Module-local packed types:')]+s[s.index('`include "tm_validate.svh"'):]
        s=s.replace('s_beat_typed','s_beat').replace('m_beat_typed','m_beat')
        # Retain only BEAT_W from the derived-width header for this module.
        a=s.index(', localparam integer RX_ID_W=')
        b=s.index('\n) (',a)
        s=s[:a]+', localparam integer BEAT_W=DATA_W+DATA_W/8+65'+s[b:]
    (folder/p.name).write_text(s)
(folder/'probe_unit.sv').write_text(scoped((OUT/'probe_unit.sv').read_text().replace('PROBE_TYPES.svh','tm_scoped_types.svh')))
manifest['minimal']=[str(folder/Path(s).name) for s in manifest['package_scoped']]
(OUT/'candidates.json').write_text(json.dumps(manifest,indent=2))

# Same representation with named, non-overridable ANSI width constants.
folder=OUT/'named_widths';folder.mkdir(exist_ok=True)
width_names={'s_beat':'BEAT_W','m_beat':'BEAT_W','output_beat':'BEAT_W',
    'events':'TRACE_W','live':'LIVE_W','live_stats':'STATISTICS_W',
    'shadow_stats':'STATISTICS_W','cfg':'CONFIG_W'}
for source in manifest['minimal']:
    p=Path(source);s=p.read_text();constants={}
    def name_width(m):
        name=m[4];constant=width_names[name]
        if constant!='BEAT_W':constants[constant]=m[2]
        return m[1]+'['+constant+'-1:0] '+name
    s=re.sub(r'((?:input|output) logic )\[\((.*?)\)-1:0\]( )(s_beat|m_beat|output_beat|events|live|live_stats|shadow_stats|cfg)\b',name_width,s)
    s=s.replace('\n) (',''.join(',\nlocalparam integer '+n+'=('+w+')' for n,w in constants.items())+'\n) (',1)
    (folder/p.name).write_text(s)
(folder/'probe_unit.sv').write_text((OUT/'minimal/probe_unit.sv').read_text())
manifest['named_widths']=[str(folder/Path(s).name) for s in manifest['minimal']]
(OUT/'candidates.json').write_text(json.dumps(manifest,indent=2))

# Portable manifest; no source text is rewritten here.
manifest={name:[str(Path(path).relative_to(OUT)) for path in paths] for name,paths in manifest.items()}
(OUT/'candidates.json').write_text(json.dumps(manifest,indent=2)+'\n')
