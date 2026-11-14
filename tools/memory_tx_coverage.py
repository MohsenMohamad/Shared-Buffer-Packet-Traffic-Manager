"""Extract unmutated production coverage without combining different elaborations."""
import json
import re
from pathlib import Path
from evidence import Case, ROOT, sha
from registry import fingerprint


def code_coverage(path):
    result={}
    for line in Path(path).read_text().splitlines():
        match=re.fullmatch(r"C '(.*)' (\d+)",line)
        if not match:continue
        fields=dict(item.split('\x02',1) for item in match[1].split('\x01') if '\x02' in item)
        filename=fields.get('f','')
        owned=next((p for p in ('rtl/memory/tm_packet_ram.sv','rtl/memory/tm_metadata.sv','rtl/tx/tm_tx.sv') if filename.endswith('/'+p)),None)
        if owned:
            counter=result.setdefault(owned,{}).setdefault(fields.get('t','unknown'),dict(hit=0,total=0))
            counter['total']+=1;counter['hit']+=int(int(match[2])>0)
    for path in ('rtl/memory/tm_packet_ram.sv','rtl/memory/tm_metadata.sv','rtl/tx/tm_tx.sv'):
        if not result.get(path,{}).get('line',{}).get('hit'):
            raise ValueError('Missing nonzero production line coverage: '+path)
    return result


def memory_tx_coverage(run,args):
    if args.test!=['memory-tx'] or not args.coverage_manifest or args.seed is not None:
        raise ValueError('memory-tx coverage requires nonempty --coverage-manifest inputs and no seed')
    if len(set(args.coverage_manifest))!=len(args.coverage_manifest):raise ValueError('Duplicate coverage input')
    for index,path in enumerate(args.coverage_manifest):
        case=Case(run,'memory-tx-coverage-'+str(index))
        try:
            data=json.loads(path.read_text())
            if data['result']!='PASS' or data['profile']!=args.profile or not re.fullmatch(r'memory-tx-L[12]-D[48]-seed\d+-run[0-3]',data['test']):
                raise ValueError('Coverage requires a passing unmutated production run of the selected profile')
            build=json.loads(Path(data['build_manifest']).read_text())
            if build['result']!='PASS' or build['registered_source_digests']!=fingerprint('memory-tx'):
                raise ValueError('Coverage HDL/configuration source mismatch')
            binary=Path(data['build_manifest']).parent/'obj/Vmemory_tx_dut_top'
            if sha(binary)!=data['binary_sha256']:raise ValueError('Coverage binary identity mismatch')
            for name in ('dv/memory_tx/dut_server.cpp','dv/memory_tx/dut.py','dv/memory_tx/adapter.py','dv/memory_tx/oracle.py','dv/memory_tx/ledger.py'):
                if sha(ROOT/name)!=data['source_digests'][name]:raise ValueError('Coverage adapter/checker identity mismatch: '+name)
            artifacts=data['artifacts'];observed=data['observed_qualification']
            if sha(artifacts['samples'])!=observed['sample_sha256']:raise ValueError('Observed sample artifact changed')
            if sha(artifacts['coverage'])!=observed['coverage_sha256']:raise ValueError('Coverage artifact changed')
            summary=dict(parameters=data['parameters'],candidate=data['candidate'],source_revision=data['source_revision'],dirty=data['dirty'],
                         production_code=code_coverage(artifacts['coverage']),functional=observed['bins'],
                         dut_bins=observed['dut_bins'],reset_crosses=observed['reset_crosses'],occupancy_crosses=observed['occupancy_crosses'],
                         performance=observed['performance'],ram_component=observed['ram_component'],
                         source_manifest=str(path),coverage_sha256=observed['coverage_sha256'],scope='Exact unmutated elaboration; observed functional requirements, no structural P12B comparison or code-coverage closure claim')
            (case.path/'coverage-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
            case.data.update(parameters=data['parameters'],coverage=summary)
            case.finish('PASS')
        except (OSError,ValueError,KeyError,TypeError) as error:case.finish('FAIL',str(error))
