"""Selected Slang synthesis/formal frontend."""
import json
from pathlib import Path
from evidence import ROOT


def selected(args, source_set='synthesis'):
    data = json.loads((ROOT / 'verification/sources' / (source_set + '.json')).read_text())
    return getattr(args, 'frontend', None) or data['frontend']


def read_sources(files, top, includes=(), defines=(), params=None, frontend='slang', formal=False):
    if frontend != 'slang':
        raise ValueError('Unknown RTL frontend: ' + frontend)
    def slang_path(value):
        path = Path(value)
        # read_slang's argument parser retains literal Yosys quotes. Use
        # checkout-relative paths; formal staging already uses bare filenames.
        value = str(path.relative_to(ROOT)) if path.is_absolute() and path.is_relative_to(ROOT) else str(path)
        if any(c.isspace() for c in value):
            raise ValueError('Unqualified whitespace in slang source path: ' + value)
        return value
    files = ' '.join(slang_path(p) for p in files)
    flags = ' '.join('-I' + slang_path(p) for p in includes)
    defines = list(defines)
    if formal and 'FORMAL' not in defines:
        defines.append('FORMAL')
    if formal:
        from formal_symbols import check_text
        check_text('\n'.join(defines), 'formal command defines')
    flags += ' ' + ' '.join('-D' + p for p in defines)
    flags += ' ' + ' '.join('-G' + k + '=' + str(v) for k, v in (params or {}).items())
    return f'read_slang --top {top} {flags} {files}\n'
