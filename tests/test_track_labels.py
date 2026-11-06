"""Real Apple media-option names and non-destructive multi-language verification."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from tests import test_multitrack_exports as fixtures

ROOT=Path(__file__).resolve().parents[1]
MAC=ROOT if (ROOT/'VidiStudio').exists() else ROOT.parent/'VidiStudio Mac'

@unittest.skipUnless(sys.platform=='darwin','Apple media selection requires macOS')
class NativeTrackLabels(unittest.TestCase):
    def test_four_audio_tracks_keep_names_languages_and_bytes(self):
        fixtures.SelectedTracks.setUpClass()
        try:
            case=fixtures.SelectedTracks();case.setUp();case.plan['format']='mov'
            output,_=case.run_plan(case.plan)
            with tempfile.TemporaryDirectory() as folder:
                helper=Path(folder)/'inspect'
                compile=subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(Path(folder)/'modules'),str(MAC/'VidiStudio/AccessibilityMetadataWriter.swift'),str(MAC/'tests/export_track_inspector.swift'),'-o',str(helper)],capture_output=True,text=True)
                self.assertEqual(compile.returncode,0,compile.stderr)
                before=hashlib.sha256(output.read_bytes()).hexdigest()
                run=subprocess.run([str(helper),str(output),'--finalize','--described'],capture_output=True,text=True)
                self.assertEqual(run.returncode,0,run.stdout+run.stderr)
                self.assertEqual(hashlib.sha256(output.read_bytes()).hexdigest(),before)
                data=json.loads(run.stdout)
                audio=data['groups']['audio']
                self.assertEqual(len(audio),4)
                self.assertIn('Original Audio',audio[0]['displayName'])
                for row,title in zip(audio,['Original Audio','Auto - Audio Description','English - Audio Description','Hindi - Audio Description']):
                    self.assertIn(title,row['metadata'])
                    self.assertIn(title,row['displayName'])
                self.assertEqual([r['describesVideo'] for r in audio],[False,True,True,True])
                self.assertIn(data['tracks']['audio'][2]['language'],('en','eng'))
                self.assertIn(data['tracks']['audio'][3]['language'],('hi','hin'))
        finally:fixtures.SelectedTracks.tearDownClass()
