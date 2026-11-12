"""One registered synthesis/formal frontend, with an explicit diagnostic path."""
import json
from pathlib import Path
from evidence import ROOT


def selected(args, source_set='synthesis'):
    data = json.loads((ROOT / 'verification/sources' / (source_set + '.json')).read_text())
    return getattr(args, 'frontend', None) or data['frontend']


def read_sources(files, top, includes=(), defines=(), params=None, frontend='slang', formal=False):
    if frontend not in ('slang', 'verilog'):
        raise ValueError('Unknown RTL frontend: ' + frontend)
    def slang_path(value):
        path = Path(value)
        # read_slang's argument parser retains literal Yosys quotes. Use
        # checkout-relative paths; formal staging already uses bare filenames.
        value = str(path.relative_to(ROOT)) if path.is_absolute() and path.is_relative_to(ROOT) else str(path)
        if any(c.isspace() for c in value):
            raise ValueError('Unqualified whitespace in slang source path: ' + value)
        return value
    files = ' '.join(slang_path(p) if frontend == 'slang' else json.dumps(str(p)) for p in files)
    flags = ' '.join('-I' + (slang_path(p) if frontend == 'slang' else str(p)) for p in includes)
    defines = list(defines)
    if formal and 'FORMAL' not in defines:
        defines.append('FORMAL')
    if formal and frontend == 'slang':
        from formal_symbols import check_text
        check_text('\n'.join(defines), 'formal command defines')
    flags += ' ' + ' '.join('-D' + p for p in defines)
    if frontend == 'slang':
        flags += ' ' + ' '.join('-G' + k + '=' + str(v) for k, v in (params or {}).items())
        return f'read_slang --top {top} {flags} {files}\n'
    command = 'read_verilog -sv' + (' -formal' if formal else '')
    result = f'{command} {flags} {files}\n'
    result += f'hierarchy -check -top {top} ' + ' '.join(f'-chparam {k} {v}' for k,v in (params or {}).items()) + '\n'
    return result


def expose_symbolic_inputs(source):
    """Expose anyseq internals as free input ports, retaining all uses/assumptions.

    The supported harnesses have one non-ANSI module with a clock input. This
    bridge is deliberately restricted and fails on syntax it has not qualified.
    Native read_verilog remains available on the original representation.
    """
    import re
    text = Path(source).read_text()
    match = re.search(r'^module (storage_formal|csr_formal)\(input clk\);', text, re.M)
    if not match:
        raise ValueError('Unqualified symbolic harness header: ' + str(source))
    ports = []
    def declare(m):
        typ, names = m.groups()
        fields = [p.strip() for p in names.split(',')]
        if any(not re.fullmatch(r'[A-Za-z_]\w*', p) for p in fields):
            raise ValueError('Unqualified symbolic declaration')
        ports.extend(fields)
        return 'input ' + typ + ' ' + names + ';'
    text = re.sub(r'\(\* anyseq \*\)\s+(logic(?:\s*\[[^]]+\])?|\w+_t)\s+([^;]+);', declare, text)
    if '(* anyseq *)' in text or not ports:
        raise ValueError('Unconverted symbolic input')
    # Conditional storage declarations must keep their port lists conditional.
    if match[1] == 'storage_formal':
        header = '''module storage_formal(clk,rst_n,
`ifdef PROVE_CELL
allocate,release_cell
`elsif PROVE_DESC
admit,tx_return,abort_return
`else
enable,s_valid,m_ready,s_beat
`endif
);
input clk;'''
    else:
        header = 'module csr_formal(clk,' + ','.join(ports) + ');\ninput clk;'
    adapted = text.replace(match[0], header, 1)
    from formal_symbols import check_text
    check_text(adapted, source)
    return adapted, ports
