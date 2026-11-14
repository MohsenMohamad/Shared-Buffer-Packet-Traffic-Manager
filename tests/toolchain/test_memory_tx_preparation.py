"""Preparation boundaries and real capture behavior in explicitly isolated fixtures."""
import json
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
import evidence
import memory_tx
import registry


def public_ram_header(root):
    """Read public ports in either layout, stopping before the RAM body."""
    for name in ('rtl/include/tm_module_ports.sv', 'rtl/memory/tm_packet_ram.sv'):
        path = root / name
        if not path.is_file():
            continue
        header = []
        with path.open() as source:
            for line in source:
                if not header and not re.match(r'\s*module\s+tm_packet_ram_api\b', line):
                    continue
                header.append(line)
                if ');' in line:
                    return ''.join(header).split(');', 1)[0] + ');'
        if header:
            raise AssertionError('Unterminated tm_packet_ram_api public header: ' + name)
    raise AssertionError('Missing tm_packet_ram_api public header')


class PreparationBoundaryTests(unittest.TestCase):
    def test_empty_selection_rejected_before_source_resolution(self):
        with patch.object(registry,'sources',side_effect=AssertionError('must not resolve sources')):
            with self.assertRaisesRegex(ValueError,'Empty'):
                registry.selection('E0',[])

    def test_preparation_rejects_inheritance_before_reading_another_list(self):
        def read(name):
            self.assertEqual(name,'sources/memory-tx-preparation.json')
            return dict(extends='production',sources=[],headers=[],include_dirs=[])
        with patch.object(registry,'read',side_effect=read):
            with self.assertRaisesRegex(ValueError,'Preparation'):
                registry.sources('memory-tx-preparation')

    def test_preparation_rejects_implementation_path_before_open(self):
        for path in ('rtl/tx/forbidden.sv','rtl/include/../../rtl/tx/forbidden.sv'):
            data=dict(sources=[path],headers=[],include_dirs=[])
            with patch.object(registry,'read',return_value=data):
                with self.assertRaisesRegex(ValueError,'Preparation'):
                    registry.sources('memory-tx-preparation')

    def test_preparation_cannot_mix_dependency_regressions(self):
        with patch.object(registry,'sources',side_effect=AssertionError('must not resolve sources')):
            with self.assertRaisesRegex(ValueError,'Preparation'):
                registry.selection('E0',['memory-tx-oracle','pools'])

    def test_registered_set_is_explicit_and_has_no_production_inheritance(self):
        data=registry.read('sources/memory-tx-preparation.json')
        self.assertNotIn('extends',data)
        selected=registry.sources('memory-tx-preparation')
        self.assertTrue(selected['sources'])
        for path in selected['sources']+selected['headers']:
            if path.startswith('rtl/'):
                self.assertTrue(path.startswith('rtl/include/'))

    def fixture(self,path):
        subprocess.run(['git','init','-q',str(path)],check=True)
        for key,value in [('user.name','Isolated Test Fixture'),('user.email','fixture@example.invalid')]:
            subprocess.run(['git','-C',str(path),'config',key,value],check=True)
        (path/'allowed').mkdir();(path/'forbidden').mkdir()
        (path/'allowed/api.txt').write_text('public declaration\n')
        (path/'forbidden/implementation.txt').write_text('must not be hashed\n')
        subprocess.run(['git','-C',str(path),'add','.'],check=True)
        subprocess.run(['git','-C',str(path),'commit','-qm','fixture'],check=True)

    def test_scoped_identity_does_not_hash_implementation(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);self.fixture(root)
            original=evidence.sha
            def guarded(path):
                self.assertNotIn('forbidden',str(path))
                return original(path)
            with patch.object(evidence,'ROOT',root),patch.object(evidence,'sha',side_effect=guarded):
                identity=evidence.provenance(['allowed'])
            self.assertEqual(set(identity['source_digests']),{'allowed/api.txt'})
            self.assertEqual(identity['source_identity_paths'],['allowed'])

    def test_unexpected_failure_capture_survives_outside_output_path(self):
        with tempfile.TemporaryDirectory() as temp,tempfile.TemporaryDirectory() as outside:
            root=Path(temp);self.fixture(root)
            (root/'allowed/api.txt').write_text('dirty captured public source\n')
            with patch.object(evidence,'ROOT',root):
                run=evidence.Run(Path(outside)/'run',source_paths=['allowed'])
                case=evidence.Case(run,'isolated-unexpected-tool-error')
                step=case.execute([sys.executable,'-c','raise RuntimeError("isolated error")'])
                case.finish(step['result'],step['first_failure'])
            captures=list((root/'verification/failures').glob('*.json'))
            self.assertEqual(len(captures),1)
            capture=json.loads(captures[0].read_text())
            self.assertEqual(capture['result'],'TOOL_ERROR')
            self.assertEqual(capture['changed_since_run_start'],[])
            self.assertTrue((captures[0].parent/capture['source_patch']).is_file())
            self.assertIn('isolated error',capture['log_tails'][0]['stderr']['text'])

    def test_future_dut_mode_is_non_success_without_reading_implementation(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);self.fixture(root)
            with patch.object(evidence,'ROOT',root):
                run=evidence.Run(root/'output',source_paths=['allowed'])
                memory_tx.memory_tx_dut(run,None)
                self.assertNotEqual(run.finish(),0)
            self.assertEqual(run.cases[0].data['result'],'NOT_RUN')
            self.assertFalse(run.cases[0].data['steps'])

    def test_build_reuse_requires_matching_identity_and_binary(self):
        from copy import deepcopy
        from evidence import sha
        from memory_tx_bench import validate_build_reuse
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);old_dir=root/'old';old_dir.mkdir();(old_dir/'obj').mkdir()
            binary=old_dir/'obj/Vmemory_tx_replay_top';binary.write_bytes(b'isolated synthetic binary')
            (old_dir/'tm_bench_config.svh').write_text('parameter int DEPTH=4;\n')
            current=dict(parameters={'depth':4},registered_source_digests={'public.sv':'abc'},
                         tool_versions={'verilator':'pinned'},dependency_digests={'lock':'123'})
            command=['verilator','-I'+str(old_dir),'--Mdir',str(old_dir/'obj')]
            data=dict(current,result='PASS',test='memory-tx-bench-build',source_set='memory-tx-preparation',
                      steps=[dict(argv=command,returncode=0)],source_revision='fixture',dirty=False,binary_sha256=sha(binary))
            path=old_dir/'manifest.json'
            new_dir=root/'new'
            argv=['verilator','-I'+str(new_dir),'--Mdir',str(new_dir/'obj')]
            path.write_text(json.dumps(data))
            reused=validate_build_reuse(path,current,argv,new_dir,{'DEPTH':4})
            self.assertEqual(reused['binary_sha256'],sha(binary))
            for key in ('parameters','registered_source_digests','tool_versions','dependency_digests'):
                corrupt=deepcopy(data);corrupt[key]={'wrong':'identity'};path.write_text(json.dumps(corrupt))
                with self.assertRaisesRegex(ValueError,'identity mismatch'):
                    validate_build_reuse(path,current,argv,new_dir,{'DEPTH':4})
            path.write_text(json.dumps(data));binary.write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError,'binary hash'):
                validate_build_reuse(path,current,argv,new_dir,{'DEPTH':4})

    def test_public_response_has_no_backpressure(self):
        ram=public_ram_header(ROOT)
        self.assertIn('output ram_response_t response',ram)
        self.assertNotIn('ready',ram)

    def test_public_response_check_in_both_layouts(self):
        header = ('module tm_packet_ram_api (\n'
                  '    output ram_response_t response\n);\n')
        for layout in ('rtl/include/tm_module_ports.sv', 'rtl/memory/tm_packet_ram.sv'):
            for extra in ('', ', input logic response_ready'):
                with self.subTest(layout=layout, backpressure=bool(extra)):
                    with tempfile.TemporaryDirectory() as temp:
                        root = Path(temp)
                        declarations = root / 'rtl/include/tm_module_ports.sv'
                        declarations.parent.mkdir(parents=True)
                        declarations.write_text('// Other public declarations only.\n')
                        target = root / layout
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_text(header.replace('response\n', 'response' + extra + '\n'))
                        with patch.dict(globals(), ROOT=root):
                            if extra:
                                with self.assertRaisesRegex(AssertionError, 'ready'):
                                    self.test_public_response_has_no_backpressure()
                            else:
                                self.test_public_response_has_no_backpressure()

    def test_public_response_check_requires_header_and_ignores_body(self):
        from io import StringIO

        class HeaderOnly(StringIO):
            def __next__(self):
                line = super().__next__()
                if 'BODY' in line:
                    raise AssertionError('Implementation body must not be read')
                return line

        header = 'module tm_packet_ram_api (output ram_response_t response);\n'
        with patch.object(Path, 'is_file', return_value=True):
            with patch.object(Path, 'open', side_effect=lambda: HeaderOnly(header + 'BODY\n')):
                self.assertEqual(public_ram_header(ROOT), header.rstrip())
            for text, error in (('// No RAM declaration\n', 'Missing'),
                                ('module tm_packet_ram_api (\n', 'Unterminated')):
                with self.subTest(error=error):
                    with patch.object(Path, 'open', side_effect=lambda: StringIO(text)):
                        with self.assertRaisesRegex(AssertionError, error):
                            public_ram_header(ROOT)


if __name__=='__main__':unittest.main()
