"""Owned profiles, source sets and executable suite selection."""
import json
from evidence import ROOT


def read(name):
    return json.loads((ROOT / 'verification' / name).read_text())


def sources(name, seen=()):
    if name in seen or name not in ('formal', 'multi-egress-declarations'):
        raise ValueError('Unknown or cyclic source set: ' + name)
    data = read('sources/' + name + '.json')
    if name == 'multi-egress-declarations':
        if 'extends' in data:
            raise ValueError('Multi-egress declarations must have an isolated source list')
        for filename in data['sources'] + data['headers'] + data['include_dirs']:
            target = (ROOT / filename).resolve()
            allowed = (ROOT / 'rtl/include/multi_egress', ROOT / 'tests/multi_egress')
            if not any(target.is_relative_to(directory) for directory in allowed):
                raise ValueError('Unexpected multi-egress declaration input: ' + filename)
    inherited = sources(data['extends'], (*seen, name)) if 'extends' in data else dict(
        sources=[], headers=[], include_dirs=[])
    result = {key: list(dict.fromkeys(inherited[key] + data[key]))
              for key in ('sources', 'headers', 'include_dirs')}
    for key, paths in result.items():
        for path in paths:
            target = (ROOT / path).resolve()
            if not target.is_relative_to(ROOT) or not target.exists():
                raise ValueError('Missing or external registered path: ' + path)
            if key != 'include_dirs' and name == 'formal' and not path.startswith(('rtl/', 'formal/')):
                raise ValueError('Non-production source in formal: ' + path)
    if name == 'formal':
        from formal_symbols import check_sources
        # No registry-provided exception list: diagnostic fixtures cannot opt in.
        check_sources([ROOT / p for p in result['sources'] + result['headers']],
                      [ROOT / p for p in result['include_dirs']])
    return result
