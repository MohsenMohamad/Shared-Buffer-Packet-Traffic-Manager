"""Owned profiles, source sets and executable suite selection."""
import json
from pathlib import Path
from evidence import ROOT, sha


def read(name):
    return json.loads((ROOT / 'verification' / name).read_text())


def profile(name):
    data = read('profiles.json')
    if name not in data['profiles']:
        raise ValueError('Unknown functional profile: ' + name)
    return dict(data['defaults'], **data['profiles'][name])


def sources(name, seen=()):
    if name in seen or name not in ('production', 'simulation', 'formal', 'synthesis', 'uvm-foundation', 'csr', 'queues'):
        raise ValueError('Unknown or cyclic source set: ' + name)
    data = read('sources/' + name + '.json')
    inherited = sources(data['extends'], (*seen, name)) if 'extends' in data else dict(
        sources=[], headers=[], include_dirs=[])
    result = {key: list(dict.fromkeys(inherited[key] + data[key]))
              for key in ('sources', 'headers', 'include_dirs')}
    for key, paths in result.items():
        for path in paths:
            target = (ROOT / path).resolve()
            if not target.is_relative_to(ROOT) or not target.exists():
                raise ValueError('Missing or external registered path: ' + path)
            if key != 'include_dirs' and name in ('production', 'formal', 'synthesis') and not (path.startswith('rtl/') or (name=='formal' and path.startswith('formal/'))):
                raise ValueError('Non-production source in ' + name + ': ' + path)
    if name == 'formal':
        from formal_symbols import check_sources
        # No registry-provided exception list: diagnostic fixtures cannot opt in.
        check_sources([ROOT / p for p in result['sources'] + result['headers']],
                      [ROOT / p for p in result['include_dirs']], legacy=True)
    return result


def selection(profile_name, tests):
    profile(profile_name)
    suites = read('suites.json')['suites']
    selected = ['contracts'] if tests is None else tests
    if not selected or len(set(selected)) != len(selected):
        raise ValueError('Empty or duplicate regression selection')
    for name in selected:
        if name not in suites or profile_name not in suites[name]['profiles']:
            raise ValueError('Unknown suite/profile selection: ' + name)
        if suites[name]['handler'] not in ('contracts', 'pools', 'uvm-foundation', 'csr', 'queues'):
            raise ValueError('Suite has no executable handler: ' + name)
        for source_set in suites[name]['source_sets']:
            sources(source_set)
    return selected


def fingerprint(name):
    data = sources(name)
    return {p: sha(ROOT / p) for p in data['sources'] + data['headers']}
