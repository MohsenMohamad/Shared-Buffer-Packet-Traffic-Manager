"""Require byte-identical generated RTL/harnesses and original production inputs."""
import argparse
from pathlib import Path
from common import HERE, REPO, digest, write_json
import json


def verify(repo, generated):
    original = json.loads((HERE / 'original/provenance.json').read_text())
    checked = {}
    for group, root in [('source_sha256', generated), ('fixture_sha256', generated),
                        ('input_sha256', repo)]:
        for name, expected in original[group].items():
            path = root / name
            actual = digest(path) if path.is_file() else None
            if actual != expected:
                raise RuntimeError(f'Preservation mismatch in {group}: {path}; '
                                   f'expected {expected}, observed {actual}')
            checked[group + ':' + name] = actual
    for name, expected in original['source_sha256'].items():
        if digest(HERE / 'original/sources' / name) != expected:
            raise RuntimeError(f'Frozen source modified: {name}')
    return dict(execution_kind='preservation-byte-comparison',
                investigated_revision=original['head'], checked=checked,
                note='SV and included production/property inputs are byte-identical; '
                     'runner path resolution and result classification are new orchestration.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo-root', type=Path, default=REPO)
    parser.add_argument('--generated', type=Path)
    args = parser.parse_args()
    repo = args.repo_root.resolve()
    generated = (args.generated or repo / '.build/rtl-frontend-probes/generated').resolve()
    result = verify(repo, generated)
    write_json(generated / 'preservation-check.json', result)
    print(f'PASS: {len(result["checked"])} original source, fixture and input digests match')
