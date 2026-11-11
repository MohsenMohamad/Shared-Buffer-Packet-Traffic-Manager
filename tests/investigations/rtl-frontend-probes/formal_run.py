"""Replay old prove/cover/mutation expectations through SBY/Yosys/Z3."""
import argparse
from pathlib import Path
import sys
from common import (FORMAL_CANDIDATES, REPO, execute, new_run, output_text,
                    selected, tool_identities, write_json, seconds)
from verify import verify


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidates', nargs='*')
    parser.add_argument('--repo-root', type=Path, default=REPO)
    parser.add_argument('--generated', type=Path)
    parser.add_argument('--output', type=Path, help='New, non-existing run directory')
    parser.add_argument('--timeout', type=seconds, default=120)
    parser.add_argument('--exploratory', action='store_true')
    args = parser.parse_args()
    names = selected(parser, args.candidates, FORMAL_CANDIDATES)
    repo = args.repo_root.resolve()
    generated = (args.generated or repo / '.build/rtl-frontend-probes/generated').resolve()
    preservation = verify(repo, generated)
    tools = tool_identities(['yosys', 'sby', 'z3'], args.exploratory)
    output = new_run(repo, args.output, 'formal')
    rows = []
    for name in names:
        for task in ['prove', 'cover', 'mutation']:
            label = name + '-formal-' + task
            directory = output / label
            config = output / (name + '-' + task + '.sby')
            depth = 16 if task == 'cover' else 8 if task == 'mutation' or name != 'named_widths' else 4
            inputs = {
                'tm_fixed.sv': generated / 'tm_fixed.sv',
                'tm_axis_rx_fifo.sv': generated / name / 'tm_axis_rx_fifo.sv',
                'formal_probe.sv': generated / 'formal_probe.sv',
                'tm_scoped_types.svh': generated / 'tm_scoped_types.svh',
                'tm_parameters.svh': repo / 'rtl/include/tm_parameters.svh',
                'tm_types.svh': repo / 'rtl/include/tm_types.svh',
                'tm_validate.svh': repo / 'rtl/include/tm_validate.svh',
                'fifo_properties.svh': repo / 'formal/pools/fifo_properties.svh',
            }
            # SBY splits [files] on whitespace without shell quoting. Use a
            # per-run staging directory to support checkout paths with spaces.
            staged = output / (name + '-' + task + '-inputs')
            staged.mkdir()
            for filename, source in inputs.items():
                (staged / filename).write_bytes(source.read_bytes())
            config.write_text(f'''[options]
mode {'cover' if task == 'cover' else 'prove'}
depth {depth}
[engines]
smtbmc z3
[script]
read_verilog -formal -sv {'-D MUTATION' if task == 'mutation' else ''} tm_fixed.sv tm_axis_rx_fifo.sv formal_probe.sv
prep -top formal_top
async2sync
dffunmap
[files]
''' + ''.join(f'{filename} {staged.name}/{filename}\n' for filename in inputs))
            row = execute(output, label, ['sby', '-f', '-d', str(directory), str(config)], output, args.timeout)
            status = (directory / 'status').read_text().split()[0] if (directory / 'status').is_file() else None
            text = output_text(output, row)
            waves = list(directory.rglob('*.vcd'))
            nonempty_waves = bool(waves) and all(p.stat().st_size > 0 for p in waves)
            if task == 'mutation':
                matched = row['returncode'] == 2 and status == 'FAIL' and nonempty_waves and all(
                    f'Assert failed in formal_top.{instance}: a_snapshot' in text for instance in ['a', 'b'])
                expectation = 'SEEDED_DEFECT_DETECTION'
            elif task == 'cover':
                covers = ['c_snapshot_last_lane', 'c_full', 'c_collision', 'c_stall',
                          'c_wrap', 'c_drain', 'c_reset_collision']
                matched = row['returncode'] == 0 and status == 'PASS' and nonempty_waves and all(
                    any('Reached cover statement' in line and cover in line for line in text.splitlines())
                    for cover in covers) and text.count('Reached cover statement') == 8
                expectation = 'COVER_REACHED'
            else:
                matched = row['returncode'] == 0 and status == 'PASS' and 'successful proof by k-induction' in text
                expectation = 'UNBOUNDED_K_INDUCTION'
            row.update(expectation=expectation, matched=matched, status=status, depth=depth)
            rows.append(row)
            print(label, row['returncode'], status, 'MATCH' if matched else 'MISMATCH', flush=True)
    matched = all(row['matched'] for row in rows)
    write_json(output / 'summary.json', dict(execution_kind='preservation-rerun' if not args.exploratory
               else 'exploratory-comparison', tools=tools, preservation=preservation,
               old_expectations_matched=matched, cases=rows))
    print('Evidence:', output)
    return 0 if matched else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError) as error:
        sys.exit(str(error))
