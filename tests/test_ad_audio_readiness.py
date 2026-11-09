from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

def declaration(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

class ADAudioReadinessTests(unittest.TestCase):
    def test_real_readiness_is_language_specific_and_matches_export_eligibility(self):
        model = (ROOT/'VidiStudio/StudioModel.swift').read_text()
        language = (ROOT/'VidiStudio/LanguageResults.swift').read_text()
        methods = '\n'.join(declaration(model, marker) for marker in [
            '    func hasUsableExportNarration(', '    func hasCompleteExportNarration('])
        readiness = declaration(language, 'struct ADAudioReadiness:')
        extension = declaration(language, 'extension StudioProject {\n    func adAudioReadiness')
        fixture = (ROOT/'tests/ad_audio_readiness_harness.swift').read_text()
        fixture = fixture.replace('// PRODUCTION_METHODS', methods).replace('// PRODUCTION_READINESS', readiness + '\n' + extension)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder); source = path/'Check.swift'; source.write_text(fixture)
            compile = subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(path/'modules'),str(source),'-o',str(path/'check')],capture_output=True,text=True)
            self.assertEqual(compile.returncode,0,compile.stdout+compile.stderr)
            run = subprocess.run([str(path/'check')],capture_output=True,text=True)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)

    def test_export_languages_and_groups_come_only_from_outputs(self):
        language = (ROOT/'VidiStudio/LanguageResults.swift').read_text()
        production = declaration(language, 'extension StudioProject {\n    func languagesForExport')
        fixture = r"""import Foundation
struct Provenance { let language: String; let languages: [String]? }
struct StudioProject {
    var exports: [String] = []
    var exportResults: [String: Provenance]? = [:]
}
PRODUCTION
var p = StudioProject(exports: ["exports/en/english.mp4", "exports/en+hi/both.m4a", "exports/old.txt"], exportResults: [
    "exports/en/english.mp4": Provenance(language: "en", languages: nil),
    "exports/en+hi/both.m4a": Provenance(language: "en", languages: ["en", "hi", "en"]),
    "exports/fr/stale.mp4": Provenance(language: "fr", languages: ["fr"])
])
precondition(p.exportLanguageCodes == ["auto", "en", "hi"])
precondition(p.languageGroupForExport("exports/en/english.mp4") == "en")
precondition(p.languageGroupForExport("exports/en+hi/both.m4a") == "multilingual")
precondition(p.languagesForExport("exports/en+hi/both.m4a") == ["en", "hi"])
p.exports.removeLast()
precondition(p.exportLanguageCodes == ["en", "hi"])
p.exportResults = [:]
precondition(p.exportLanguageCodes == ["en", "hi"], "Old language folders must match the filter")
p.exports = []
precondition(p.exportLanguageCodes.isEmpty)
print("PASS: output-only languages, multilingual grouping, old folder fallback and stale metadata")
""".replace('PRODUCTION', production)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder); source = path/'Group.swift'; source.write_text(fixture)
            compile = subprocess.run(['xcrun','swiftc','-module-cache-path',str(path/'modules'),str(source),'-o',str(path/'check')],capture_output=True,text=True)
            self.assertEqual(compile.returncode,0,compile.stdout+compile.stderr)
            run = subprocess.run([str(path/'check')],capture_output=True,text=True)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
