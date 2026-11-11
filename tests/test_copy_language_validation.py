"""Compile production UI guards and verify their submission wiring."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from tests.test_copy_progress import method

ROOT = Path(__file__).resolve().parents[1]
MAC = ROOT if (ROOT/'VidiStudio').exists() else ROOT.parent/'VidiStudio Mac'
WIN = ROOT if (ROOT/'Vidi Studio Windows').exists() else ROOT.parent/'Vidi-Studio-Windows'


class CopyLanguageValidation(unittest.TestCase):
    def test_production_mac_predicate_blocks_same_language_in_both_modes(self):
        if sys.platform != 'darwin': self.skipTest('Swift SDK required')
        source = (MAC/'VidiStudio/LanguageResults.swift').read_text()
        predicate = method(source, '    private var canSubmit: Bool').replace('private ', '')
        harness = '''class Studio { var hasValidApiKey = true }
struct Check {
    var source = "en", target = "hi", translateText = true, allowed = true
    var included = ["transcript"]
    var studio = Studio()
    func canCopy() -> Bool { allowed }
''' + predicate + '''
}
@main struct Main { static func main() {
    var check = Check()
    for source in ["auto", "en", "hi"] { for target in ["auto", "en", "hi"] {
        for translating in [false, true] { for api in [false, true] { for allowed in [false, true] { for content in [false, true] {
            check.source = source; check.target = target; check.translateText = translating
            check.studio.hasValidApiKey = api; check.allowed = allowed; check.included = content ? ["transcript"] : []
            let expected = allowed && content && source != target && (!translating || (api && target != "auto"))
            precondition(check.canSubmit == expected)
        } } } }
    } }
    print("PASS: 144 UI states, including translation/copy and Auto equality")
} }
'''
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder); (path/'Main.swift').write_text(harness)
            result = subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(path/'modules'),str(path/'Main.swift'),'-o',str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result = subprocess.run([str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_production_windows_predicate_blocks_null_empty_and_matching_languages(self):
        if not shutil.which('dotnet'): self.skipTest('.NET SDK required')
        source = (WIN/'Vidi Studio Windows/MainWindow.LanguageResults.cs').read_text()
        predicate = method(source, '    private static bool CopyLanguagesDiffer(')
        harness = 'using System; class Check {\n' + predicate + '''
static void Main() {
    foreach (var source in new string?[] { null, "", "auto", "en", "hi" })
    foreach (var target in new string?[] { null, "", "auto", "en", "hi" }) {
        var expected = !string.IsNullOrEmpty(source) && !string.IsNullOrEmpty(target) && source != target;
        if (CopyLanguagesDiffer(source, target) != expected) throw new Exception("Invalid copy language guard");
    }
    Console.WriteLine("PASS: 25 Windows language-pair states");
} }
'''
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder); (path/'Program.cs').write_text(harness)
            (path/'Check.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><Nullable>enable</Nullable></PropertyGroup></Project>')
            result = subprocess.run(['dotnet','run','--project',str(path/'Check.csproj')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_disabled_state_and_final_dispatch_recheck_the_same_condition(self):
        mac = (MAC/'VidiStudio/LanguageResults.swift').read_text()
        win = (WIN/'Vidi Studio Windows/MainWindow.LanguageResults.cs').read_text()
        self.assertIn('guard canSubmit else { return }', mac)
        self.assertIn('.disabled(!canSubmit)', mac)
        self.assertIn('dialog.IsPrimaryButtonEnabled = CanCopyLanguageResults && differentLanguages &&', win)
        self.assertEqual(win.count('CopyLanguagesDiffer((source.SelectedItem as OutputLanguage)?.Id, (target.SelectedItem as OutputLanguage)?.Id)'), 2)
        self.assertIn('target.SelectionChanged += (_, _) => UpdatePrimary();', win)
        self.assertIn('source.SelectionChanged += (_, _) => Refresh();', win)
