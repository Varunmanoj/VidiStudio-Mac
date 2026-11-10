from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest
from tests.test_ad_audio_readiness import declaration

ROOT = Path(__file__).resolve().parents[1]


class InspectorContentStatusTests(unittest.TestCase):
    def test_actual_tab_status_and_result_numbers(self):
        source = (ROOT/'VidiStudio/LanguageResults.swift').read_text()
        status = declaration(source, 'struct InspectorContentStatus:')
        methods = declaration(source, 'extension StudioProject {\n    func inspectorContentStatus(')
        fixture = (ROOT/'tests/inspector_content_status_harness.swift').read_text()
        fixture = fixture.replace('// PRODUCTION_STATUS', status).replace('// PRODUCTION_METHODS', methods)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            (path/'Check.swift').write_text(fixture)
            result = subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(path/'modules'),str(path/'Check.swift'),'-o',str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result = subprocess.run([str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_desktop_status_and_number_views_use_the_projections(self):
        mac = (ROOT/'VidiStudio/ContentView.swift').read_text()
        win = ROOT.parent/'Vidi-Studio-Windows/Vidi Studio Windows'
        windows = (win/'MainWindow.Inspector.cs').read_text()
        self.assertIn('inspectorContentStatuses(section: editorActions.activeSection)', mac)
        self.assertNotIn('ForEach(p.adAudioReadinessByLanguage)', mac)
        self.assertIn('view.ContentStatuses(section)', windows)
        self.assertIn('inspectorActiveAudioReadiness.Visibility = active == null ? Visibility.Collapsed : Visibility.Visible', windows)
        self.assertIn('Text("#\\(segmentNumber)")', mac)
        self.assertIn('.accessibilityLabel("\\(row.kind) segment \\(segmentNumber)")', mac)
        xaml = (win/'MainWindow.xaml').read_text()
        self.assertIn('Text="{Binding SegmentNumberText}"', xaml)
        self.assertIn('AutomationProperties.Name="{Binding SegmentNumberLabel}"', xaml)
        model = (win/'Models/StudioProject.cs').read_text()
        self.assertIn('result.Cues[i].SegmentNumber = i + 1', model)
        self.assertIn('row.SegmentNumber = i + 1', model)
        self.assertIn('cue.SegmentNumber = i + 1', model)
        self.assertIn('item.SegmentNumber = i + 1', model)

    @unittest.skipUnless(shutil.which('dotnet'), 'Requires the .NET SDK')
    def test_windows_production_status_counts_and_empty_text_eligibility(self):
        win = ROOT.parent/'Vidi-Studio-Windows/Vidi Studio Windows'
        source = (win/'Models/StudioProject.cs').read_text()
        fixture = (ROOT/'tests/windows_content_status_harness.cs').read_text()
        for marker, label in [('    public InspectorContentStatus? ContentStatus(', 'STATUS_METHOD'), ('    public List<InspectorContentStatus> ContentStatuses(', 'STATUS_LIST'), ('public sealed record InspectorContentStatus(', 'STATUS_RECORD')]:
            fixture = fixture.replace('// PRODUCTION_'+label, declaration(source, marker))
        start = source.index('    public bool CanExportText(')
        end = source.index('    };', start)+6
        fixture = fixture.replace('// PRODUCTION_EXPORT_PREDICATE', source[start:end])
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            (path/'Program.cs').write_text(fixture)
            (path/'Check.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup><ItemGroup><Compile Include="'+str(win/'Models/LanguageResult.cs')+'" /></ItemGroup></Project>')
            result = subprocess.run(['dotnet','run','--project',str(path/'Check.csproj'),'--verbosity','quiet'],capture_output=True,text=True,timeout=120)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
