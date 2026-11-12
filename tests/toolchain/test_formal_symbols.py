"""Symbolic policy must reject new sources, headers and disguised constructs."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools'))
from formal_symbols import check_sources, check_text
from registry import sources, read
from symbolic_qualification import outcome


class SymbolicPolicyTests(unittest.TestCase):
    def test_formatting_attributes_and_functions(self):
        for symbol in ('anyseq', 'anyconst'):
            for text in (f'(* {symbol} *) logic x;',
                         f'(* keep=1,\n {symbol} = 1 *) logic x;',
                         f'(* /* comment */ {symbol}\n*) logic [3:0] x;',
                         f'wire x = ${symbol};', f'wire x = ${symbol} ( );',
                         f'(* \\{symbol}  *) logic x;',
                         f'`define SYMBOL {symbol}\n(* `SYMBOL *) logic x;'):
                with self.subTest(text=text), self.assertRaisesRegex(ValueError, 'Unqualified symbolic'):
                    check_text(text, 'new.sv')

    def test_command_defines_cannot_introduce_symbolic_alias(self):
        from frontend import read_sources
        for definition in ('SYMBOL=anyconst', 'SOURCE=$anyseq()', 'SYMBOL=any``const'):
            with self.subTest(definition=definition), self.assertRaises(ValueError):
                read_sources(['new.sv'], 'new', defines=[definition], formal=True)

    def test_comments_and_strings_are_not_symbols(self):
        check_text('// (* anyconst *)\n/* $anyseq */\ninitial $display("anyconst // $anyseq");', 'new.sv')

    def test_preprocessor_cannot_hide_unchecked_source(self):
        for text in ('`ifdef NEVER\n(* anyconst *) wire x;\n`endif',
                     '`define SYMBOL any``const\n(* `SYMBOL *) wire x;',
                     '`define SYMBOL any' + chr(92) + '\nconst\n(* `SYMBOL *) wire x;'):
            with self.assertRaises(ValueError):
                check_text(text, 'new.sv')

    def test_transitive_unlisted_header(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path/'new.sv').write_text('`include "first.svh"\nmodule new; endmodule')
            (path/'first.svh').write_text('`include "second.svh"')
            (path/'second.svh').write_text('(*\n anyconst=1\n*) logic x;')
            with self.assertRaisesRegex(ValueError, 'second.svh'):
                check_sources([path/'new.sv'], [path])

    def test_explicit_headers_and_missing_or_macro_includes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'new.svh'
            for text in ('wire x=$anyconst();', '`include "missing.svh"', '`include `H'):
                path.write_text(text)
                with self.subTest(text=text), self.assertRaises(ValueError):
                    check_sources([path])
            path.write_text('// `include "missing.svh"\n/* `include `H */\ninitial $display("`include `H");')
            self.assertEqual(check_sources([path]), [path])

    def test_legacy_adapter_exception_is_canonical_and_anyseq_only(self):
        registered = sources('formal')
        self.assertIn('formal/symbolic/symbolic_inputs.sv', registered['sources'])
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'storage_formal.sv'
            path.write_text((ROOT/'formal/pools/storage_formal.sv').read_text())
            with self.assertRaisesRegex(ValueError, 'Unqualified symbolic'):
                check_sources([path], legacy=True)
        from frontend import expose_symbolic_inputs
        with patch.object(Path, 'read_text', return_value='module storage_formal(input clk);\n(* anyseq *) logic a;\n(* anyconst *) logic b;\nendmodule'):
            with self.assertRaisesRegex(ValueError, 'Unqualified symbolic'):
                expose_symbolic_inputs(ROOT/'formal/pools/storage_formal.sv')

    def test_registry_cannot_exempt_diagnostic_fixture(self):
        original = read('sources/formal.json')
        for fixture in ('symbolic_attributes.sv', 'symbolic_functions.sv', 'anyconst_control.sv'):
            data = dict(original, sources=original['sources']+['tests/frontends/'+fixture],
                        symbolic_exceptions=['tests/frontends/'+fixture])
            with patch('registry.read', side_effect=lambda name: data if name == 'sources/formal.json' else read(name)):
                with self.assertRaisesRegex(ValueError, 'Non-production source'):
                    sources('formal')

    def test_registry_rejects_new_formal_source_and_header(self):
        original = read('sources/formal.json')
        with tempfile.TemporaryDirectory(dir=ROOT/'formal') as directory:
            path = Path(directory)/'new.svh'
            path.write_text('(* anyconst *) logic x;')
            for field in ('sources', 'headers'):
                data = dict(original, **{field:original[field]+[str(path.relative_to(ROOT))]})
                with patch('registry.read', side_effect=lambda name: data if name == 'sources/formal.json' else read(name)):
                    with self.assertRaisesRegex(ValueError, 'Unqualified symbolic'):
                        sources('formal')

    def test_legacy_bridge_keeps_all_controls_when_new_proofs_are_registered(self):
        from formal_bridge import legacy_configurations
        configurations = read('formal.json')['configurations']
        expected = {'cell', 'descriptor', 'fifo2', 'fifo4', 'csr'}
        self.assertIn('queues', configurations)
        # A future explicit-input proof has no native defines or old harness.
        expanded = dict(configurations, future_explicit_input={'top': 'future'})
        with patch('formal_bridge.read', return_value={'configurations': expanded}):
            selected = legacy_configurations()
        self.assertEqual(set(selected), expected)
        for name in expected:
            self.assertIs(selected[name], configurations[name])
        for missing in expected:
            incomplete = {k: v for k, v in expanded.items() if k != missing}
            with self.subTest(missing=missing), patch('formal_bridge.read',
                    return_value={'configurations': incomplete}):
                with self.assertRaises(KeyError):
                    legacy_configurations()

    def test_crash_and_wrong_assertion_cannot_detect_negative(self):
        for status in (None, 'ERROR', 'UNKNOWN', 'FAIL'):
            result, _ = outcome({'result':'TOOL_ERROR', 'returncode':1}, status,
                                'crash\nAssert failed in top: unrelated', ['trace.vcd'],
                                'ASSERT_FAIL', ['a_constant'])
            self.assertNotEqual(result, 'PASS')
        result, _ = outcome({'result':'TOOL_ERROR', 'returncode':1}, 'FAIL',
                            'Assert failed in top: a_constant', ['trace.vcd'],
                            'ASSERT_FAIL', ['a_constant'])
        self.assertEqual(result, 'PASS')


if __name__ == '__main__':
    unittest.main()
