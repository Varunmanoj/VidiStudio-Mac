"""Shared desktop language selection must override legacy section targets."""
import copy
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from tests import test_language_results as fixtures
lr = fixtures.lr
from tests.test_copy_progress import method

ROOT = Path(__file__).resolve().parents[1]
MAC = ROOT if (ROOT/'VidiStudio').exists() else ROOT.parent/'VidiStudio Mac'
WIN = ROOT if (ROOT/'Vidi Studio Windows').exists() else ROOT.parent/'Vidi-Studio-Windows'


class SharedInspectorLanguage(unittest.TestCase):
    setUp = fixtures.LanguageResultsTests.setUp
    args = fixtures.LanguageResultsTests.args
    def test_explicit_analysis_language_overrides_all_legacy_targets(self):
        for command in ('analyze', 'regenerate-all'):
            for code in ('auto', 'en', 'hi'):
                with self.subTest(command=command, code=code):
                    p = copy.deepcopy(self.p)
                    p['selectedLanguage'] = code
                    p['sectionLanguages'] = dict(transcript='fr', summary='ta', descriptions='de')
                    lr.project(p)
                    before = copy.deepcopy(p['languageResults'])
                    stages = []
                    self.core.local = lambda root, path: root/path
                    self.core.cleanup_project_storage = lambda *args: None
                    def produce(args, *unused):
                        stages.append((args.command, args.language))
                        return {}
                    with patch.object(lr, 'organize_exports'), patch.object(lr, 'organize_assets'), patch.object(lr, 'produce', side_effect=produce):
                        lr._run(self.args(command, language=code, start_stage='transcribe'), self.root, p, self.core, lambda *args: None)
                    self.assertEqual(stages, [(stage, code) for stage in ('transcribe', 'generate-summary', 'generate-ad-cues')])
                    self.assertEqual(p['languageResults'], before)
                    self.assertEqual(p['selectedLanguage'], code)

    def test_mac_operation_language_ignores_legacy_targets(self):
        if sys.platform != 'darwin': self.skipTest('Swift SDK required')
        source=(MAC/'VidiStudio/LanguageResults.swift').read_text()
        members='\n'.join(method(source, marker) for marker in ('    func sectionLanguage(', '    func operationLanguage('))
        harness='''struct Project {
 var languageCode = "en"
 var sectionLanguages = ["transcript":"fr", "summary":"hi", "descriptions":"ta", "adAudio":"de"]
''' + members + '''
}
var p = Project()
for code in ["auto", "en", "hi"] {
 p.languageCode = code
 for command in ["analyze", "regenerate-all", "transcribe", "generate-summary", "generate-ad-cues", "import-transcript", "import-summary", "import-ad-transcript", "import-ad-audio", "synthesize-tts", "rewrite-cue"] {
  precondition(p.operationLanguage(command) == code)
 }
 for kind in ["transcript", "summary", "descriptions", "adAudio"] { precondition(p.sectionLanguage(kind) == code) }
}
print("PASS: all desktop operations follow project language despite legacy targets")
'''
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder); (path/'main.swift').write_text(harness)
            result=subprocess.run(['xcrun','swiftc','-module-cache-path',str(path/'modules'),str(path/'main.swift'),'-o',str(path/'check')], capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result=subprocess.run([str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

