"""Reject stale/partial installations and enforce a single producer boundary."""
import copy
from contextlib import redirect_stdout
import io
import json
import os
import subprocess
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import toolchain_cache as cache


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.identity = dict(inputs={'lock': 'abc'}, compiler='qualified', architecture='x86_64')

    def populate(self):
        for name in cache.PAYLOAD:
            path = self.root / name
            if name in ('.tools/install', '.tools/sysroot', '.deps/downloads', '.deps/src/uvm'):
                path.mkdir(parents=True)
                path = path / 'example'
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name)
            path.chmod(0o644)
        os.symlink('example', self.root / '.tools/install/link')

    def test_integrity_includes_deletion_bytes_mode_and_symlink(self):
        self.populate()
        cache.seal(self.identity, self.root)
        cache.check_payload(self.identity, self.root)
        path = self.root / '.tools/install/example'
        original = path.read_bytes()
        path.write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'incomplete'):
            cache.check_payload(self.identity, self.root)
        path.write_bytes(original)
        path.chmod(0o755)
        with self.assertRaises(ValueError):
            cache.check_payload(self.identity, self.root)
        path.chmod(0o644)
        link = self.root / '.tools/install/link'
        link.unlink()
        os.symlink('missing', link)
        with self.assertRaises(ValueError):
            cache.check_payload(self.identity, self.root)
        link.unlink()
        os.symlink('example', link)
        path.unlink()
        with self.assertRaises(ValueError):
            cache.check_payload(self.identity, self.root)

    def test_transfer_preserves_modes_under_restrictive_umask(self):
        self.populate()
        (self.root / '.tools/install/example').chmod(0o755)
        cache.seal(self.identity, self.root)
        archive = self.root / 'installation.tar'
        subprocess.run(['tar', '-cf', str(archive), *cache.PAYLOAD, cache.MANIFEST],
                       cwd=self.root, check=True, timeout=30)
        consumer = self.root / 'consumer'
        consumer.mkdir()
        subprocess.run(['tar', '-xpf', str(archive)], cwd=consumer, check=True,
                       preexec_fn=lambda: os.umask(0o077), timeout=30)
        cache.check_payload(self.identity, consumer)

    def test_partial_payload_rejected(self):
        self.populate()
        (self.root / '.tools/setup.json').unlink()
        with self.assertRaisesRegex(ValueError, 'Missing payload'):
            cache.seal(self.identity, self.root)
        self.assertFalse((self.root / cache.MANIFEST).exists())

    def test_mismatched_identity_rejected(self):
        self.populate()
        cache.seal(self.identity, self.root)
        other = dict(self.identity, compiler='new')
        with self.assertRaisesRegex(ValueError, 'compatibility'):
            cache.check_payload(other, self.root)
        path = self.root / cache.MANIFEST
        data = json.loads(path.read_text())
        data['identity']['compiler'] = 'forged'
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'Malformed'):
            cache.check_payload(self.identity, self.root)

    def test_cold_once_then_reuse_without_setup(self):
        calls = []
        def step(argv, stem, timeout, root):
            calls.append(stem)
            if stem == 'cold-setup':
                self.populate()
            return {'result': 'PASS', 'argv': argv}
        with patch.object(cache, 'checked_step', side_effect=step):
            self.assertEqual(cache.prepare(self.identity, 2, self.root)['source'], 'cold')
            self.assertEqual(cache.prepare(self.identity, 2, self.root)['source'], 'cache')
        self.assertEqual(calls, ['cold-setup', 'cold-doctor', 'restore-doctor'])

    def test_current_validator_executes_without_changing_installation_key(self):
        for name in cache.INPUTS:
            path = self.root / name
            path.parent.mkdir(exist_ok=True, parents=True)
            path.write_text(name)
        runtime = self.root / 'libstdc++.so.6'
        runtime.write_bytes(b'ABI')
        def command(argv):
            return str(runtime) if argv[-1].startswith('-print-file-name') else 'qualified'
        validator = self.root / 'tools/doctor.py'
        runner = self.root / 'tools/run.py'
        runner.write_text('import sys\nsys.dont_write_bytecode = True\n'
                          'assert sys.argv[1:] == ["doctor"]\nimport doctor\n')
        validator.write_text('from pathlib import Path\n'
                             'Path("validator-marker").write_text("initial")\n')
        with patch.object(cache, 'command', side_effect=command):
            identity = cache.compatibility(self.root)
            self.populate()
            cache.seal(identity, self.root)
            cache.validate(identity, self.root)
            self.assertEqual((self.root / 'validator-marker').read_text(), 'initial')
            runner.write_text(runner.read_text() + '# another registered suite\n')
            validator.write_text('from pathlib import Path\n'
                                 'Path("validator-marker").write_text("current")\n'
                                 'raise SystemExit(9)\n')
            self.assertEqual(cache.cache_key(cache.compatibility(self.root)),
                             cache.cache_key(identity))
            # The unchanged installation still passes integrity, but the current
            # validator must run and reject it rather than trust its old seal.
            cache.check_payload(identity, self.root)
            with self.assertRaisesRegex(RuntimeError, 'restore-doctor: TOOL_ERROR'):
                cache.validate(identity, self.root)
            self.assertEqual((self.root / 'validator-marker').read_text(), 'current')

    def test_exact_hit_without_manifest_warns_and_is_reported_as_cold(self):
        key = cache.cache_key(self.identity)
        def step(argv, stem, timeout, root):
            if stem == 'cold-setup':
                self.populate()
            return {'result': 'PASS'}
        console = io.StringIO()
        with redirect_stdout(console), patch.object(cache, 'checked_step', side_effect=step):
            report = cache.prepare(self.identity, 2, self.root, restored_key=key)
        self.assertEqual((report['source'], report['cache_status']), ('cold', 'rejected'))
        self.assertEqual(report['rejected_key'], key)
        self.assertIn('cache-manifest.json', report['restore_rejected'])
        self.assertIn('::warning::Rejected toolchain cache ' + key, console.getvalue())
        self.assertIn('CACHE_PREFIX', console.getvalue())
        cache.check_payload(self.identity, self.root)

    def test_failed_build_is_never_sealed(self):
        with patch.object(cache, 'checked_step', side_effect=RuntimeError('build failed')):
            with self.assertRaisesRegex(RuntimeError, 'build failed'):
                cache.prepare(self.identity, 2, self.root)
        self.assertFalse((self.root / cache.MANIFEST).exists())
        report = json.loads((self.root / '.build/setup-cache/preparation.json').read_text())
        self.assertEqual(report['result'], 'TOOL_ERROR')
        self.assertEqual(report['first_failure'], 'build failed')

    def test_generation_bump_and_warning_escaping(self):
        key = cache.cache_key(self.identity)
        with patch.object(cache, 'CACHE_PREFIX', 'tm-tools-v2-'):
            self.assertNotEqual(cache.cache_key(self.identity), key)
            self.assertTrue(cache.cache_key(self.identity).startswith('tm-tools-v2-'))
        console = io.StringIO()
        with redirect_stdout(console):
            cache.warning('bad%input\n::error::not a second command\r')
        self.assertEqual(console.getvalue(),
                         '::warning::bad%25input%0A::error::not a second command%0D\n')

    def test_failed_doctor_cannot_seal_and_consumer_never_builds(self):
        self.populate()
        cache.seal(self.identity, self.root)
        with patch.object(cache, 'checked_step', side_effect=RuntimeError('doctor failed')) as step:
            with self.assertRaisesRegex(RuntimeError, 'doctor failed'):
                cache.validate(self.identity, self.root)
            self.assertEqual(step.call_count, 1)
            self.assertEqual(step.call_args.args[1], 'restore-doctor')
        (self.root / cache.MANIFEST).unlink()
        def step(argv, stem, timeout, root):
            if stem == 'cold-setup':
                self.populate()
                return {'result': 'PASS'}
            raise RuntimeError('doctor failed')
        with patch.object(cache, 'checked_step', side_effect=step):
            with self.assertRaises(RuntimeError):
                cache.prepare(self.identity, 2, self.root)
        self.assertFalse((self.root / cache.MANIFEST).exists())
        report = json.loads((self.root / '.build/setup-cache/preparation.json').read_text())
        self.assertEqual(report['result'], 'TOOL_ERROR')

    def test_rejected_restore_has_one_clean_producer_build(self):
        self.populate()
        cache.seal(self.identity, self.root)
        (self.root / cache.MANIFEST).write_text('[]')
        def step(argv, stem, timeout, root):
            if stem == 'cold-setup':
                self.assertFalse((self.root / '.tools').exists())
                self.populate()
            return {'result': 'PASS'}
        with patch.object(cache, 'checked_step', side_effect=step) as mocked:
            report = cache.prepare(self.identity, 2, self.root)
            self.assertEqual(report['source'], 'cold')
            self.assertEqual(report['cache_status'], 'rejected')
            self.assertEqual(mocked.call_count, 2)
        cache.check_payload(self.identity, self.root)

    def test_key_uses_setup_inputs_and_host_abi_without_git_revision(self):
        for name in cache.INPUTS:
            path = self.root / name
            path.parent.mkdir(exist_ok=True, parents=True)
            path.write_text(name)
            path.chmod(0o644)
        runtime = self.root / 'libstdc++.so.6'
        runtime.write_bytes(b'ABI1')
        def command(argv):
            return str(runtime) if argv[-1].startswith('-print-file-name') else 'qualified'
        with patch.object(cache, 'command', side_effect=command):
            original = cache.compatibility(self.root)
            key = cache.cache_key(original)
            for name in cache.INPUTS:
                path = self.root / name
                path.write_text(name + ' changed')
                self.assertNotEqual(cache.cache_key(cache.compatibility(self.root)), key, name)
                path.write_text(name)
            path.chmod(0o644)
            for name in cache.BUILD_FLAGS:
                with patch.dict(os.environ, {name: 'changed-build-option'}):
                    self.assertNotEqual(cache.cache_key(cache.compatibility(self.root)), key, name)
            runtime.write_bytes(b'ABI2')
            self.assertNotEqual(cache.cache_key(cache.compatibility(self.root)), key)
        for field in ('checkout', 'system', 'architecture', 'os_release', 'libc', 'python_abi', 'compiler'):
            changed = copy.deepcopy(original)
            changed[field] = 'different'
            self.assertNotEqual(cache.cache_key(changed), key, field)
        # Unrelated source changes and commit changes are deliberately absent.
        (self.root / 'rtl.sv').write_text('new RTL')
        self.assertNotIn('source_revision', original)


if __name__ == '__main__':
    unittest.main()
