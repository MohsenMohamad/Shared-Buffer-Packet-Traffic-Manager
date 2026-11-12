"""Replay native phase scripts with an explicitly isolated diagnostic executable."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from evidence import Case, Run

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--reference', type=Path, required=True, help='Completed native frontend run directory')
parser.add_argument('--yosys', type=Path, required=True, help='Absolute control executable')
parser.add_argument('--library-path', required=True, help='Control runtime directory; excludes modern libraries')
parser.add_argument('--output', type=Path, required=True, help='Fresh output directory')
args = parser.parse_args()
if not args.yosys.is_absolute() or args.output.exists():
    parser.error('Use an absolute executable and a fresh output directory')
os.environ.update(PATH=str(args.yosys.parent) + ':/usr/local/bin:/usr/bin:/bin',
                  LD_LIBRARY_PATH=args.library_path)
run = Run(args.output)
run.scope = 'Native diagnostic phase comparison; successful parsing is not accepted semantics'
run.versions['yosys'] = str(args.yosys) + ': ' + subprocess.check_output([str(args.yosys), '-V'], text=True).strip()
for item in json.loads((args.reference / 'summary.json').read_text())['cases']:
    original = (args.reference / item['test']).resolve()
    data = json.loads((original / 'manifest.json').read_text())
    phase, candidate = data.get('phase'), data.get('candidate')
    if phase not in ('parse', 'elaborate') and not (phase == 'synthesis' and candidate in ('features', 'unpacked', 'interface', 'record_memory')):
        continue
    case = Case(run, item['test'].replace('frontend-verilog', 'control-verilog'))
    script = case.path / 'run.ys'
    script.write_text((original / 'run.ys').read_text().replace(str(original), str(case.path)))
    step = case.execute([str(args.yosys), '-Q', '-T', '-s', str(script)], timeout=300)
    fields = {key: data[key] for key in ('candidate', 'phase', 'method', 'input_digests')}
    if (case.path / 'inferred.json').exists():
        net = json.loads((case.path / 'inferred.json').read_text())
        fields['inferred_memories'] = [{key: int(cell['parameters'][key], 2)
            for key in ('WIDTH', 'SIZE', 'RD_PORTS', 'WR_PORTS')}
            for module in net['modules'].values() for cell in module.get('cells', {}).values()
            if cell['type'] == '$mem_v2']
    case.finish(step['result'], step['first_failure'], **fields)
sys.exit(run.finish())
