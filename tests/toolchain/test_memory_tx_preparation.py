"""Preparation boundaries and real capture behavior in explicitly isolated fixtures."""
import json
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
            self.assertEqual(run.cases[0].data['result'],'NOT_IMPLEMENTED')
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
        ports=(ROOT/'rtl/include/tm_module_ports.sv').read_text()
        ram=ports.split('module tm_packet_ram_api',1)[1].split('endmodule',1)[0]
        self.assertIn('output ram_response_t response',ram)
        self.assertNotIn('ready',ram)


if __name__=='__main__':unittest.main()
