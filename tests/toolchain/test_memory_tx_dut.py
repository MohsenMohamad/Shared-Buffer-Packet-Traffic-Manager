"""Exact candidate identity and live edge-seal negatives; no production execution."""
import sys
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
sys.path.insert(0,str(ROOT/'dv/memory_tx'))
from dut import decode_edge
from oracle import Violation
import memory_tx_dut


class CandidateAdapterTests(unittest.TestCase):
    def test_missing_duplicate_mixed_and_truncated_edges_fail(self):
        row='TM_EDGE 0 '+' '.join('0' for _ in range(12))+'\n'
        self.assertEqual(len(decode_edge(row,0)),12)
        for line,tick,detector in [(row,1,'adapter_sample_sequence'),
                                   (row.replace('TM_EDGE 0','TM_EDGE 2'),0,'adapter_sample_sequence'),
                                   ('TM_EDGE 0 0\n',0,'adapter_sample_shape'),
                                   ('not a sampled edge\n',0,'adapter_protocol')]:
            with self.subTest(detector=detector):
                with self.assertRaises(Violation) as caught: decode_edge(line,tick)
                self.assertEqual(caught.exception.detector,detector)

    def test_candidate_source_change_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            subprocess.run(['git','init','-q',str(root)],check=True)
            for path in memory_tx_dut.RTL_PATHS+memory_tx_dut.HEADERS:
                file=root/path;file.parent.mkdir(parents=True,exist_ok=True)
                file.write_text('// isolated identity fixture '+path+'\n')
            subprocess.run(['git','-C',str(root),'add','.'],check=True)
            subprocess.run(['git','-C',str(root),'-c','user.name=Identity Fixture',
                            '-c','user.email=fixture@example.invalid','commit','-qm','fixture'],check=True)
            revision=subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip()
            with patch.object(memory_tx_dut,'ROOT',root):
                self.assertEqual(memory_tx_dut.candidate_identity(revision)['rtl_revision'],revision)
                (root/memory_tx_dut.RTL_PATHS[-1]).write_text('// changed synthetic source\n')
                with self.assertRaisesRegex(ValueError,'Selected candidate source differs'):
                    memory_tx_dut.candidate_identity(revision)
