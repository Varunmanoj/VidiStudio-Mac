from pathlib import Path
import subprocess
import tempfile
import sys
import unittest
src=Path(__file__).resolve().parents[1].joinpath('VidiStudio/ProjectGridView.swift').read_text()
start=src.index('@MainActor\nstruct AllProjectsActions');end=src.index('private struct AllProjectsKey',start)
stubs='''import SwiftUI
import Foundation
@MainActor final class StudioModel {
 var busy=false; var hasApiKey=true; var apiKeyVerified: Bool?=true; var isAIProcessingBlocked=false
}
enum ProjectSourceFilter { case all, local, youtube }
struct StudioProject {
 var id: String; var folder: URL?=URL(fileURLWithPath:"/tmp/project"); var integrityPlaceholder: Bool?=false
 var hasGeneratedContent=true; var isYouTubeURLProject=false; var canGenerateDescriptions=true
}
@MainActor final class ConnectivityService {
 enum Service { case youtube, gemini }; static let shared=ConnectivityService(); var online=true
 func available(_ service: Service)->Bool { online }
}
'''
checks='''
@main struct Checks {
 @MainActor static func main() {
  let model=StudioModel(); var source=ProjectSourceFilter.all; var language="all"; var search=""; var calls:[String]=[]
  let selected=StudioProject(id:"selected-project")
  func actions(_ project:StudioProject?) -> AllProjectsActions {
   AllProjectsActions(studio:model, project:project, sourceFilter:Binding(get:{source},set:{source=$0}),languageFilter:Binding(get:{language},set:{language=$0}),search:Binding(get:{search},set:{search=$0}),perform:{action,project in calls.append(action+":"+project.id)})
  }
  let none=actions(nil)
  for id in ["export","delete-content","delete-project","open-selected-project","analyze"] { precondition(!none.canRun(id)); none.run(id) }
  precondition(calls.isEmpty)
  let a=actions(selected)
  a.run("export"); a.run("delete-content"); a.run("delete-project"); a.run("open-selected-project")
  precondition(calls==["export:selected-project","delete-content:selected-project","delete-project:selected-project","open-selected-project:selected-project"])
  model.busy=true
  let count=calls.count
  for id in ["export","delete-content","delete-project","open-selected-project","analyze"] { precondition(!a.canRun(id)); a.run(id) }
  precondition(calls.count==count); model.busy=false
  model.hasApiKey=false; precondition(!a.canRun("analyze")); precondition(a.canRun("export"));model.hasApiKey=true
  model.apiKeyVerified=false; precondition(!a.canRun("transcribe"));model.apiKeyVerified=true
  model.isAIProcessingBlocked=true; precondition(!a.canRun("generate-summary"));model.isAIProcessingBlocked=false
  ConnectivityService.shared.online=false;precondition(!a.canRun("analyze"));precondition(a.canRun("export"));ConnectivityService.shared.online=true
  var damaged=selected;damaged.integrityPlaceholder=true
  precondition(!actions(damaged).canRun("export"));precondition(actions(damaged).canRun("delete-project"))
  var noContent=selected;noContent.hasGeneratedContent=false;noContent.canGenerateDescriptions=false
  precondition(!actions(noContent).canRun("delete-content"));precondition(!actions(noContent).canRun("generate-ad-cues"))
  precondition(!a.canRun("projects-reset-filters"));a.run("projects-source-youtube");precondition(source == .youtube)
  search="sample";language="en";precondition(a.canRun("projects-reset-filters"));a.run("projects-reset-filters")
  precondition(source == .all && language == "all" && search.isEmpty);precondition(calls.count==count)
  print("PASS: actual AllProjectsActions dispatch, missing selection, busy, damaged project, API/connectivity guards, source/language/search bindings and reset")
 }
}
'''

@unittest.skipUnless(sys.platform == "darwin", "Requires the macOS SwiftUI SDK")
class AllProjectsCommandGuards(unittest.TestCase):
    def test_selected_target_and_availability(self):
        with tempfile.TemporaryDirectory(prefix="vidistudio-library-commands-") as directory:
            path = Path(directory) / "Commands.swift"
            binary = Path(directory) / "Commands"
            path.write_text(stubs + src[start:end] + checks)
            compiled = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(path), "-o", str(binary)], capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
