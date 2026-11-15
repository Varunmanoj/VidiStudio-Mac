"""Execute the production settings rules, including saved incompatible preferences."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MAC = ROOT / 'VidiStudio Mac'
WIN = ROOT / 'Vidi-Studio-Windows'


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    end, depth = opening + 1, 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


class GeminiPlayback(unittest.TestCase):
    def test_mac_engine_switch_preview_rejection_and_saved_migration(self):
        source = (MAC / 'VidiStudio/StudioModel.swift').read_text()
        members = '\n'.join(declaration(source, marker) for marker in (
            '    var ttsMode =', '    var narrationPlayback =',
            '    mutating func normalizeNarrationPlayback()'))
        harness = '''import Foundation
struct Settings: Codable {
MEMBERS
}
var settings = Settings()
for local in ["system", "piper"] {
    settings.ttsMode = local
    settings.narrationPlayback = "device"
    precondition(settings.narrationPlayback == "device")
    settings.ttsMode = "gemini"
    precondition(settings.ttsMode == "gemini" && settings.narrationPlayback == "generated")
    settings.narrationPlayback = "device"
    precondition(settings.narrationPlayback == "generated")
    settings.ttsMode = local
    precondition(settings.narrationPlayback == "generated")
}
for old in ["device", "ondevice"] {
    let json = "{\\"ttsMode\\":\\"gemini\\",\\"narrationPlayback\\":\\"\\(old)\\"}"
    var restored = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    precondition(restored.normalizeNarrationPlayback())
    precondition(!restored.normalizeNarrationPlayback())
    let reopened = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(restored))
    precondition(reopened.ttsMode == "gemini" && reopened.narrationPlayback == "generated")
}
print("PASS: local preview, Gemini coercion/rejection, migration, persistence and idempotence")
'''.replace('MEMBERS', members)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            (path / 'Main.swift').write_text(harness)
            build = subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(path / 'modules'),
                                    str(path / 'Main.swift'), '-o', str(path / 'check')], capture_output=True, text=True)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(path / 'check')], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    @unittest.skipUnless(shutil.which('dotnet'), '.NET SDK required')
    def test_windows_real_store_set_save_load_reload_and_legacy_alias(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            source = WIN / 'Vidi Studio Windows/Services/SettingsStore.cs'
            shutil.copyfile(source, path / 'SettingsStore.cs')
            version = subprocess.check_output(['dotnet', '--version'], text=True).split('.')[0]
            (path / 'Check.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup>'
                '<OutputType>Exe</OutputType><TargetFramework>net' + version + '.0</TargetFramework>'
                '<Nullable>enable</Nullable></PropertyGroup></Project>')
            (path / 'Program.cs').write_text('''using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using Vidi_Studio_Windows.Services;
class Program {
 static void Check(bool condition) { if (!condition) throw new Exception("Invalid narration combination"); }
 static void Main(string[] args) {
  Environment.SetEnvironmentVariable("VIDISTUDIO_CONFIG", args[0]);
  var settings = new SettingsStore();
  foreach (var local in new[] {"windows-core", "sapi5", "piper"}) {
   settings.Set("ttsMode", local); settings.Set("narrationPlayback", "device");
   Check(settings.Get("narrationPlayback") == "ondevice");
   settings.Set("ttsMode", "gemini");
   Check(settings.Get("ttsMode") == "gemini" && settings.Get("narrationPlayback") == "generated");
   settings.Set("narrationPlayback", "ondevice"); Check(settings.Get("narrationPlayback") == "generated");
   settings.Set("ttsMode", local); Check(settings.Get("narrationPlayback") == "generated");
  }
  foreach (var old in new[] {"device", "ondevice"}) {
   File.WriteAllText(args[0], new JsonObject { ["ttsMode"]="gemini", ["narrationPlayback"]=old }.ToJsonString());
   settings = new SettingsStore(); Check(settings.Get("narrationPlayback") == "generated");
   Check(JsonNode.Parse(File.ReadAllText(args[0]))!["narrationPlayback"]!.GetValue<string>() == "generated");
   settings.Data["narrationPlayback"] = old; settings.Save(); settings.Reload();
   Check(settings.Get("ttsMode") == "gemini" && settings.Get("narrationPlayback") == "generated");
   Check(!SettingsStore.NormalizeNarrationPlayback(settings.Data));
  }
  Console.WriteLine("PASS: actual settings store transitions, aliases, load migration, save and reload");
 }
}
namespace Vidi_Studio_Windows.Services {
 static class CredentialStore { public static string? Read()=>null; public static bool Write(string value)=>false; }
 static class PromptDefaults { public static void Upgrade(JsonObject saved, JsonObject defaults) {} }
}
namespace Vidi_Studio_Windows.Models { static class Json { public static JsonSerializerOptions Options = new(); } }
''')
            run = subprocess.run(['dotnet', 'run', '--project', str(path / 'Check.csproj'), '--',
                                  str(path / 'config.json')], capture_output=True, text=True, timeout=60)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)


if __name__ == '__main__':
    unittest.main()
