"""Execute the production FFmpeg parser and verify packaged notice preparation."""
from pathlib import Path
import importlib.util
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
WIN = ROOT if (ROOT / 'Vidi Studio Windows').is_dir() else ROOT.parent / 'Vidi-Studio-Windows'

class InformationRegressionTests(unittest.TestCase):
    def test_ffmpeg_release_and_license_are_separate_and_concise(self):
        if not shutil.which('dotnet'): self.skipTest('.NET SDK required')
        source = WIN / 'Vidi Studio Windows/Views/FfmpegVersionInfo.cs'
        harness = r'''using System;
using Vidi_Studio_Windows.Views;
class Check { static void Main() {
 foreach(var test in new[] {
  ("9.0.1-full_build-www.gyan.dev", "--enable-gpl --enable-version3", "9.0.1", "GNU GPL version 3 or later"),
  ("8.0.1", "--enable-gpl", "8.0.1", "GNU GPL version 2 or later"),
  ("7.1.2", "--enable-version3", "7.1.2", "GNU LGPL version 3 or later"),
  ("6.1", "--enable-shared", "6.1", "GNU LGPL version 2.1 or later"),
  ("N-123456-gabcdef", "--enable-gpl", "N-123456-gabcdef", "GNU GPL version 2 or later"),
  ("9.0.1", "--enable-nonfree --enable-gpl", "9.0.1", "Nonredistributable build")
 }) {
  var actual=FfmpegVersionInfo.Parse("ffmpeg version "+test.Item1+" Copyright (c) developers\nconfiguration: "+test.Item2+"\nlibavutil 60.1.1\n");
  if(actual.Version!=test.Item3 || actual.License!=test.Item4) throw new Exception(actual.ToString());
 }
 Console.WriteLine("PASS: vendor suffix, release, nightly, GPL2/3, LGPL2.1/3 and nonfree metadata");
} }
'''
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            shutil.copy2(source, path / 'FfmpegVersionInfo.cs')
            (path / 'Program.cs').write_text(harness)
            (path / 'Check.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>')
            result = subprocess.run(['dotnet','run','--project',str(path/'Check.csproj')], capture_output=True, text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_license_index_includes_original_component_and_package_notices(self):
        spec = importlib.util.spec_from_file_location('notices', WIN / 'script/prepare_license_notices.py')
        notices = importlib.util.module_from_spec(spec); spec.loader.exec_module(notices)
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            assets=root/'Vidi Studio Windows/Assets'; assets.mkdir(parents=True)
            (assets/'FFmpeg-GPLv3.txt').write_text('GPL license fixture')
            (assets/'piper-notice.txt').write_text('MIT notice fixture')
            license=root/'.venv-windows/Lib/site-packages/example-1.dist-info/licenses/LICENSE.txt'
            license.parent.mkdir(parents=True); license.write_text('Original package notice')
            notices.prepare(root)
            included=root/'runtime/engine/licenses'
            self.assertEqual((included/'FFmpeg-GPLv3.txt').read_text(),'GPL license fixture')
            self.assertEqual((included/'Piper-MIT.txt').read_text(),'MIT notice fixture')
            self.assertEqual((included/'python/example-1.dist-info/licenses/LICENSE.txt').read_text(),'Original package notice')
            self.assertIn('python/example-1.dist-info/licenses/LICENSE.txt',(included/'THIRD-PARTY-LICENSES.txt').read_text())
