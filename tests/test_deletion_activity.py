"""Run production deletion activity state, including overlapping work and cleanup."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

class DeletionActivityTests(unittest.TestCase):
    def test_mac_registry_keeps_progress_until_all_confirmed_work_finishes(self):
        if sys.platform != 'darwin': self.skipTest('macOS Swift SDK required')
        root = Path(__file__).resolve().parents[1]
        mac = root if (root / 'VidiStudio').exists() else root.parent / 'VidiStudio Mac'
        source = (mac / 'VidiStudio/DeletionActivity.swift').read_text()
        source = source[:source.index('\nstruct DeletionProgressBanner')].replace('@Observable ', '')
        harness = source + '''
@main struct Main {
 @MainActor static func main() {
    let state = DeletionActivityRegistry.shared
    precondition(state.activities.isEmpty)
    precondition(state.begin(command: "preview-delete-results", projectName: "Sample") == nil)
    precondition(state.begin(command: "transcribe", projectName: "Sample") == nil)
    let one = state.begin(command: "delete-results", projectName: "Sample")!
    let two = state.begin(title: "Moving project to Bin…", projectName: "Sample")
    precondition(state.activities.count == 2)
    state.finish(one); precondition(state.activities.count == 1 && state.messages[0].contains("Moving project"))
    state.finish(one); precondition(state.activities.count == 1)
    state.finish(two); state.finish(nil); precondition(state.activities.isEmpty)
    print("PASS: deletion classification, concurrent activity and completion/error cleanup")
 }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory); (folder / 'Main.swift').write_text(harness)
            result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(folder / 'Main.swift'), '-module-cache-path', str(folder / 'modules'), '-o', str(folder / 'check')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(folder / 'check')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_failed_project_move_clears_progress_without_closing_project(self):
        if sys.platform != 'darwin': self.skipTest('macOS Swift SDK required')
        root = Path(__file__).resolve().parents[1]
        mac = root if (root / 'VidiStudio').exists() else root.parent / 'VidiStudio Mac'
        source = (mac / 'VidiStudio/StudioModel.swift').read_text()
        start = source.index('    func trashProject(_ project: StudioProject, completion:')
        opening = source.index('{', start); end = opening + 1; depth = 1
        while depth:
            depth += (source[end] == '{') - (source[end] == '}'); end += 1
        method = source[start:end]
        registry = (mac / 'VidiStudio/DeletionActivity.swift').read_text().split('\nstruct DeletionProgressBanner')[0].replace('@Observable ', '')
        harness = registry + r'''
final class FailedFiles: @unchecked Sendable {
 static let `default` = FailedFiles()
 func fileExists(atPath: String) -> Bool { true }
 func trashItem(at: URL, resultingItemURL: UnsafeMutablePointer<NSURL?>?) throws { throw NSError(domain:"test", code:1) }
}
typealias FileManager = FailedFiles
struct StudioProject { let id: String; let name: String; let folder: URL? }
enum Issue { case projectDelete }
@MainActor final class Harness {
 var busy=false; var selectedID: String? = "fixture"; var message=""; var error: String?; var reloaded=false
 func forgetProject(_ project: StudioProject) { selectedID=nil }
 func reload() { reloaded=true }
 func present(_ issue: Issue, technicalDetails: String, context: String) { error=technicalDetails }
''' + method + r'''
}
@main struct Main {
 @MainActor static func main() async throws {
  let model=Harness(); var completed=false; var closed=false
  let observer=NotificationCenter.default.addObserver(forName:.vidiStudioProjectDeleted, object:nil, queue:.main) { _ in MainActor.assumeIsolated { closed=true } }
  defer { NotificationCenter.default.removeObserver(observer) }
  model.trashProject(StudioProject(id:"fixture",name:"Fixture",folder:URL(fileURLWithPath:"/tmp/failure-fixture"))) { completed=true }
  precondition(model.busy && !DeletionActivityRegistry.shared.activities.isEmpty)
  for _ in 0..<100 { if model.error != nil { break }; try await Task.sleep(for:.milliseconds(10)) }
  precondition(model.error != nil && !model.busy && DeletionActivityRegistry.shared.activities.isEmpty)
  precondition(!closed && !completed && !model.reloaded && model.selectedID == "fixture")
 }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            folder=Path(directory); (folder/'Main.swift').write_text(harness)
            result=subprocess.run(['xcrun','swiftc','-parse-as-library',str(folder/'Main.swift'),'-module-cache-path',str(folder/'modules'),'-o',str(folder/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result=subprocess.run([str(folder/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_windows_registry_disposes_activity_after_failure(self):
        if not shutil.which('dotnet'): self.skipTest('dotnet SDK required')
        root = Path(__file__).resolve().parents[1]
        win = root if (root / 'Vidi Studio Windows').exists() else root.parent / 'Vidi-Studio-Windows'
        source = win / 'Vidi Studio Windows/Services/DeletionActivity.cs'
        harness = '''using System;
using Vidi_Studio_Windows.Services;
if (DeletionActivity.BeginForCommand("preview-delete-results", "Sample") != null) throw new Exception("Preview is not deletion");
try {
 using var activity = DeletionActivity.BeginForCommand("delete-results", "Sample");
 if (DeletionActivity.Message == null) throw new Exception("Progress missing");
 using (var nested = DeletionActivity.Begin("Moving project to Recycle Bin…", "Other")) {
   if (DeletionActivity.Message == null) throw new Exception("Nested progress missing");
 }
 if (DeletionActivity.Message == null) throw new Exception("Cleared before outer work finished");
 throw new InvalidOperationException("Simulated failure");
} catch (InvalidOperationException) { }
if (DeletionActivity.Message != null) throw new Exception("Progress stuck after failure");
Console.WriteLine("PASS: Windows deletion progress lifecycle and failure cleanup");
'''
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory); (folder / 'Program.cs').write_text(harness)
            (folder / 'Check.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework><OutputType>Exe</OutputType><Nullable>enable</Nullable><NoWarn>CA1416</NoWarn></PropertyGroup><ItemGroup><Compile Include="'+str(source)+'"/></ItemGroup></Project>')
            result = subprocess.run(['dotnet', 'run', '--project', str(folder / 'Check.csproj')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
