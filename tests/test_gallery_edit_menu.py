"""Selection, source and shared dispatch for the All Projects Edit menu."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from tests.test_contextual_menus import MAC, WIN, declaration

class GalleryEditMenu(unittest.TestCase):
    def test_gallery_commands_validate_current_selection_and_dispatch(self):
        production=declaration((MAC/'VidiStudio/ProjectGridView.swift').read_text(),'struct AllProjectsActions')
        harness='''import SwiftUI
struct OutputLanguage {}
enum ProjectListSort {case lastOpened, name, duration, type}
enum ProjectSourceFilter {case all, local, youtube}
struct StudioProject {var id="one"; var folder:URL?=URL(fileURLWithPath:"/tmp/project");var integrityPlaceholder:Bool?=false;var hasGeneratedContent=true;var isYouTubeURLProject=false;var canGenerateDescriptions=true}
@MainActor final class ConnectivityService {static let shared=ConnectivityService();enum Service {case youtube,gemini};func available(_ service:Service)->Bool {true}}
@MainActor final class StudioModel {
 var busy=false;var listedProjects=[StudioProject()];var hasApiKey=true;var apiKeyVerified:Bool?=true;var isAIProcessingBlocked=false;var developer=false;var calls=[String]()
 func canManageProject(_ action:String,project:StudioProject)->Bool {
  if action=="youtube-open-browser" {return project.isYouTubeURLProject}
  if action=="open-configuration" {return developer}
  return !busy && project.folder != nil && project.integrityPlaceholder != true
 }
 func requestProjectManagement(_ action:String,project:StudioProject){calls.append(action+":"+project.id)}
 func removeProjectFromList(_ project:StudioProject){calls.append("remove:"+project.id)}
}
@MainActor
'''+production+'''
@main struct Main { @MainActor static func main() {
 let model=StudioModel();var calls=[String]()
 func actions(_ project:StudioProject?)->AllProjectsActions {
  AllProjectsActions(studio:model,project:project,sourceFilter:.constant(.all),languageFilter:.constant("all"),search:.constant(""),projectSort:.constant(.lastOpened),perform:{calls.append($0+":"+$1.id)})
 }
 let ids=["open-gallery-window","rename-project","youtube-open-browser","project-settings","show-in-finder","open-configuration","analyze","prepare-video","transcribe","generate-summary","generate-ad-cues","export","remove-from-list","delete-content","delete-project"]
 for id in ids {precondition(!actions(nil).canRun(id)); actions(nil).run(id)}
 precondition(calls.isEmpty && model.calls.isEmpty)
 var local=StudioProject();let selected=actions(local)
 precondition(!selected.canRun("youtube-open-browser") && !selected.canRun("open-configuration"))
 selected.run("open-gallery-window");precondition(calls==["open-gallery-window:one"])
 selected.run("rename-project");precondition(model.calls==["rename-project:one"])
 local.id="two";local.isYouTubeURLProject=true
 precondition(actions(local).canRun("youtube-open-browser"));actions(local).run("youtube-open-browser")
 precondition(model.calls.last=="youtube-open-browser:two")
 model.busy=true
 for id in ids {precondition(!actions(local).canRun(id))}
 model.busy=false;local.integrityPlaceholder=true
 precondition(!actions(local).canRun("export") && actions(local).canRun("delete-project"))
 print("PASS: no selection and busy block actions, selected source and project determine dispatch")
} }
'''
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder);(path/'Main.swift').write_text(harness)
            result=subprocess.run(['xcrun','swiftc','-parse-as-library',str(path/'Main.swift'),'-o',str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result=subprocess.run([str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_gallery_edit_wiring_on_both_desktops(self):
        mac=(MAC/'VidiStudio/KeyboardShortcuts.swift').read_text()
        win=(WIN/'Vidi Studio Windows/MainWindow.Menus.cs').read_text()
        edit = mac[mac.index('CommandMenu("Edit")'):mac.index('CommandMenu("Playback")')]
        self.assertEqual(__import__('re').findall(r'allProjects.run\("([^"]+)"\)', edit), ['focus-search', 'clear-search', 'rename-project'])
        self.assertIn('Menu("Edit", Command("focus-search"), Command("clear-search"), Command("open-search-result"), Separator(), Command("rename-project", libraryOnly: true),',win)
        win_edit = win[win.index('Menu("Edit",'):win.index('Menu("View",')]
        self.assertEqual(__import__('re').findall(r'Command\("([^"]+)", libraryOnly: true\)',win_edit), ['rename-project'])
        mac_file = declaration(mac,'CommandGroup(after: .newItem)')
        self.assertIn('allProjects.run("open-gallery-window")',mac_file)
        win_file = win[win.index('Menu("File",'):win.index('Menu("Edit",')]
        self.assertIn('Command("open-gallery-window", libraryOnly: true)',win_file)
        self.assertIn('case "open-gallery-window": openNewWindow(project)',(MAC/'VidiStudio/ProjectBrowserPage.swift').read_text())
        self.assertIn('libraryOnlyMenuItems.Contains(item) && !LibraryCommandVisible(id)',win)
        self.assertIn('if (id == "youtube-open-browser") return youtubeBrowserCanRun != null || ProjectManagementTarget()?.IsYouTube == true;',win)
        self.assertIn('case "open-gallery-window":\n            case "open-selected-project": if (SelectedGalleryProject()',win)
        self.assertIn('!desktopEditorVisible && menu.Title is "Playback" ?',win)
