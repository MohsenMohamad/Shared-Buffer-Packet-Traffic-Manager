"""Fail-closed symbolic-source policy; this checks source, never translates RTL."""
from pathlib import Path
import re

from evidence import ROOT

# Preserve strings while removing comments so commented includes cannot add files.
LEXEMES = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"', re.S)
SYMBOL = re.compile(r'(?<![\w$])(?:\$|\\)?(?:anyseq|anyconst|allseq|allconst)(?!\w)')


def uncomment(text):
    text = re.sub(r'\\\r?\n', '', text)
    return LEXEMES.sub(lambda m: m[0] if m[0].startswith('"') else
                       re.sub(r'[^\n]', ' ', m[0]), text)


def check_text(text, source):
    code = re.sub(r'"(?:\\.|[^"\\])*"', '""', uncomment(text))
    match = SYMBOL.search(code)
    if match:
        line = code.count('\n', 0, match.start()) + 1
        raise ValueError(f'Unqualified symbolic construct in {source}:{line}: {match[0]}')
    # Macro concatenation can manufacture an otherwise invisible symbolic name.
    # It is outside this source policy's qualified subset, including dead branches.
    if '``' in code:
        raise ValueError('Unqualified formal token concatenation in ' + str(source))


def check_sources(files, includes=()):
    """Check all listed sources/headers and their transitive literal includes.

    Inspect all preprocessor branches. Macro includes, missing headers and source
    escapes fail closed. All production harnesses and headers follow the same policy; there are no
    path-based exceptions.
    """
    visited = set()
    include_dirs = [Path(p).resolve() for p in includes]

    def visit(source):
        source = Path(source).resolve()
        if source in visited:
            return
        visited.add(source)
        text = source.read_text()
        check_text(text, source)
        code = uncomment(text)
        for match in re.finditer(r'"(?:\\.|[^"\\])*"|`include\b([^\n]*)', code):
            if match[1] is None:  # A string literal containing directive text.
                continue
            literal = re.fullmatch(r'\s*"([^"\n]+)"\s*', match[1])
            if not literal:
                raise ValueError('Unqualified formal include in ' + str(source))
            candidates = [p / literal[1] for p in [source.parent, *include_dirs]]
            target = next((p.resolve() for p in candidates if p.is_file()), None)
            if target is None:
                raise ValueError('Missing formal include: ' + literal[1])
            # Registered production files must never pull in an external header.
            if source.is_relative_to(ROOT) and not target.is_relative_to(ROOT):
                raise ValueError('External formal include: ' + str(target))
            visit(target)

    for source in files:
        visit(source)
    return sorted(visited)
