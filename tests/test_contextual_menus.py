"""Exercise tab/source isolation in the production desktop command policies."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MAC = ROOT if (ROOT / 'VidiStudio').exists() else ROOT.parent / 'VidiStudio Mac'
WIN = ROOT if (ROOT / 'Vidi Studio Windows').exists() else ROOT.parent / 'Vidi-Studio-Windows'
SECTIONS = ['transcript', 'summary', 'descriptions', 'ad-overview', 'ad-transcript']
# Expected user-visible destinations, independent of implementation language.
SCOPES = {
    'transcribe': [0], 'import-transcript': [0], 'delete-transcript': [0],
    'generate-summary': [1], 'import-summary': [1], 'delete-summary': [1],
    'generate-ad-cues': [2], 'import-descriptions': [2], 'delete-descriptions': [2],
    'synthesize-tts': [2,3,4], 'synthesize-changed': [2,3,4], 'review-narration-issues': [2,3,4],
    'review-narration-voices': [2,3,4], 'delete-narration': [2,3,4],
    'import-ad-audio': [2,4], 'narration': [2,4], 'caption-ad-transcript': [2,4],
    'add': [0,2], 'reanalyze-selection': [0,2], 'undo': [0,2], 'redo': [0,2],
    'segment-select-all': [0,2,4], 'segment-delete-selected': [0,2,4], 'segment-edit-selected': [0,2,4],
    'segment-deselect-all': [0,2,4], 'follow': [0,2,4], 'filter-segments': [0,2,4],
    'caption-cycle': [0,2,4], 'caption-off': [0,2,4], 'caption-transcript': [0,2,4],
    'copy-to': [0,1,2,4], 'segment-edit-mode': [0,1,2,4], 'delete-current': [0,1,2],
    'summary-play': [1], 'summary-stop': [1], 'summary-zoom-in': [1], 'analyze': [],
    'prepare-video': [0,1,2,3,4], 'export': [0,1,2,3,4], 'import-assets': [0,1,2,3,4],
    'transcript': [0,1,2,3,4], 'summary': [0,1,2,3,4], 'descriptions': [0,1,2,3,4],
    'ad-overview': [0,1,2,3,4], 'ad-transcript': [0,1,2,3,4],
    'youtube-captions': [0], 'youtube-details': [0,1,2,3,4], 'youtube-refresh': [0,1,2,3,4],
    'import-original-audio': [0,1,2,3,4],
}
SOURCE_ONLY = {'youtube-captions', 'youtube-details', 'youtube-refresh', 'import-original-audio'}


def declaration(source, marker):
    start = source.index(marker); end = source.index('{', start) + 1; depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[start:end]


EDIT_ONLY = {'segment-select-all', 'segment-deselect-all', 'segment-edit-selected', 'segment-delete-selected', 'reanalyze-selection', 'undo', 'redo'}
SUMMARY_VIEW_ONLY = {'generate-summary', 'import-summary', 'delete-summary', 'delete-current'}

def cases():
    return [(section, youtube, editing, command,
             index in allowed and (youtube or command not in SOURCE_ONLY)
             and (editing or command not in EDIT_ONLY)
             and not (index == 1 and editing and (command.startswith('summary-') or command in SUMMARY_VIEW_ONLY)))
            for index, section in enumerate(SECTIONS) for youtube in (False, True)
            for editing in (False, True) for command, allowed in SCOPES.items()]


class ContextualMenus(unittest.TestCase):
    def test_mac_visibility_and_guarded_dispatch_across_all_tabs_and_sources(self):
        if sys.platform != 'darwin': self.skipTest('macOS Swift SDK required')
        source = (MAC / 'VidiStudio/KeyboardShortcuts.swift').read_text()
        production = declaration(source, 'final class EditorShortcutActions')
        harness = """import SwiftUI
import AppKit
struct OutputLanguage { let id: String; let title: String }
struct SavedLanguageResult { let id: String; let language: String; let kind: String }
struct StudioProject {
    var savedLanguageResults: [SavedLanguageResult] = []
    func languageResults(kind: String, includingDrafts: Bool) -> [SavedLanguageResult] { [] }
    func activeLanguageResultID(_ kind: String) -> String? { nil }
}
enum OnlineService { case gemini, youtube }
struct ConnectivityService { static let shared = ConnectivityService(); func available(_ service: OnlineService) -> Bool { true } }
@MainActor @Observable
""" + production + """
@main struct Main { @MainActor static func main() {
    let actions = EditorShortcutActions()
    var calls: [String] = []
    actions.handler = { calls.append($0) }; actions.youtubeHandler = { calls.append($0) }
    actions.available = true; actions.hasApiKey = true; actions.canGenerateDescriptions = true
    actions.hasNarrationAudio = true; actions.hasChangedNarration = true
    actions.hasGeneratedTranscript = true; actions.hasGeneratedSummary = true; actions.hasDescriptions = true
    actions.descriptionCount = 3; actions.canImportOriginalAudio = true
    actions.canToggleNarration = true; actions.canToggleFollow = true; actions.canAddSegment = true
    actions.canUndoSegment = true; actions.canRedoSegment = true
    actions.segmentEditingAvailable = true; actions.segmentEditMode = true
    actions.segmentCount = 3; actions.selectedSegmentCount = 1
    actions.summaryActive = true; actions.summaryReadable = true; actions.summaryIsReading = true
    actions.hasCopyableResults = true; actions.hasTranscriptText = true
"""
        for section, youtube, editing, command, expected in cases():
            harness += f'actions.segmentEditMode = {str(editing).lower()}; actions.summaryEditing = {str(section == "summary" and editing).lower()}\n'
            harness += f'actions.activeSection = "{section}"; actions.youtubeProject = {str(youtube).lower()}\n'
            harness += f'precondition(actions.isCommandVisible("{command}") == {str(expected).lower()}, "visibility: {section} {youtube} {command}")\n'
            if not expected:
                harness += f'precondition(!actions.canRun("{command}")); calls = []; actions.run("{command}"); precondition(calls.isEmpty, "hidden command dispatched: {command}")\n'
        defaults = [['transcript'], ['summary'], ['descriptions'], ['descriptions'], ['transcript', 'descriptions']]
        titles = ['Transcript', 'Summary', 'Descriptions', 'Descriptions', 'AD Transcript']
        for section, kinds, title in zip(SECTIONS, defaults, titles):
            harness += f'actions.activeSection = "{section}"; precondition(actions.copyKinds(currentSectionOnly: true) == {json.dumps(kinds)}); precondition(actions.copyKinds(currentSectionOnly: false) == ["transcript", "summary", "descriptions"]); precondition(actions.currentSectionCopyTitle == "Copy and Translate {title}…")\n'
        harness += """
    actions.activeSection = "transcript"; actions.available = true
    var copyScopes: [Bool] = []
    actions.copyHandler = { copyScopes.append($0) }
    actions.copyCurrentSection(); actions.run("copy-to")
    precondition(copyScopes == [true, false])
    actions.available = false; actions.copyCurrentSection(); actions.run("copy-to")
    precondition(copyScopes == [true, false])
    actions.activeSection = "descriptions"; actions.available = true
    calls = []; actions.run("synthesize-tts"); precondition(calls == ["synthesize-tts"])
    actions.activeSection = "transcript"; actions.youtubeProject = true
    calls = []; actions.run("youtube-captions"); precondition(calls == ["youtube-captions"])
    actions.activeSection = "summary"; actions.summaryEditing = false
    calls = []; actions.run("import-summary"); precondition(calls == ["import-summary"])
    actions.available = false
    precondition(actions.isCommandVisible("import-summary") && !actions.canRun("import-summary"))
    calls = []; actions.run("import-summary"); precondition(calls.isEmpty)
    let rowActions = ["segment-one-edit", "segment-one-play", "segment-one-skip", "segment-one-preview", "segment-one-preview-stop", "segment-one-synthesize", "segment-one-rewrite", "segment-one-import-audio", "segment-one-delete-audio", "segment-one-reanalyze", "segment-one-delete"]
    actions.available = true; actions.youtubeProject = false; actions.ttsUsesGemini = false
    actions.hasApiKey = true; actions.selectedSegmentHasAudio = true; actions.selectedSegmentAudioReady = true
    for tab in ["transcript", "summary", "descriptions", "ad-overview", "ad-transcript"] {
      actions.activeSection = tab; actions.summaryEditing = false
      for editing in [false, true] { actions.segmentEditMode = editing
        for count in [0, 1, 2] { actions.selectedSegmentCount = count
          precondition(actions.canRun("segment-delete-selected") == (["transcript", "descriptions", "ad-transcript"].contains(tab) && editing && count > 0), "bulk delete selection guard")
          for kind in ["transcript", "descriptions"] { actions.selectedSegmentKind = count == 1 ? kind : nil
            for command in rowActions {
              let timed = ["transcript", "descriptions", "ad-transcript"].contains(tab)
              let kindAllowed = tab == "ad-transcript" || tab == kind
              let descriptionOnly = ["segment-one-preview", "segment-one-preview-stop", "segment-one-synthesize", "segment-one-rewrite", "segment-one-import-audio", "segment-one-delete-audio"].contains(command)
              let actionAllowed = command != "segment-one-preview-stop" && (!descriptionOnly || kind == "descriptions") && (command != "segment-one-reanalyze" || kind == "transcript")
              let expected = timed && editing && count == 1 && kindAllowed && actionAllowed
              precondition(actions.canRun(command) == expected, "single selection guard")
              calls = []; actions.run(command); precondition(calls == (expected ? [command] : []))
              precondition(actions.canRunRowCommand(command, kind: kind, hasAudio: true, audioReady: true) == (timed && kindAllowed && actionAllowed), "context row policy")
            }
          }
        }
      }
    }
    actions.activeSection = "ad-transcript"; actions.segmentEditMode = true; actions.selectedSegmentCount = 1; actions.selectedSegmentKind = "descriptions"
    actions.hasApiKey = false; actions.ttsUsesGemini = true; actions.selectedSegmentHasAudio = false; actions.selectedSegmentAudioReady = false
    for command in ["segment-one-rewrite", "segment-one-synthesize", "segment-one-delete-audio", "segment-one-preview"] { precondition(!actions.canRun(command)) }
    actions.selectedSegmentPreviewing = true; actions.segmentPreviewPaused = false
    precondition(actions.canRun("segment-one-preview") && actions.canRun("segment-one-preview-stop"))
    precondition(actions.segmentCommandTitle("segment-one-preview") == "Pause Narration")
    precondition(actions.segmentCommandTitle("segment-one-preview-stop") == "Stop Narration")
    actions.segmentPreviewPaused = true
    precondition(actions.segmentCommandTitle("segment-one-preview") == "Resume Narration")
    actions.selectedSegmentPreviewing = false
    precondition(!actions.canRun("segment-one-preview-stop"))
    precondition(actions.segmentCommandTitle("segment-one-preview") == "Play Narration")
    actions.videoPlaybackStarted = false; precondition(!actions.isCommandVisible("stop") && !actions.canRun("stop"))
    actions.videoPlaybackStarted = true; precondition(actions.isCommandVisible("stop") && actions.canRun("stop"))
    actions.videoPlaybackStarted = false
    actions.available = false; precondition(!actions.canRun("segment-one-edit"))
    final class MenuChanges: @unchecked Sendable { var count = 0 }
    let menuChanges = MenuChanges()
    actions.activeSection = "transcript"; actions.segmentEditMode = true; actions.selectedSegmentCount = 1; actions.selectedSegmentKind = "transcript"; actions.available = true
    withObservationTracking { _ = actions.canRun("segment-one-edit") } onChange: { menuChanges.count += 1 }
    actions.handler = { calls.append("latest:" + $0) }
    precondition(menuChanges.count == 0, "Replacing a callback must not recreate the visible menu")
    actions.run("segment-one-edit"); precondition(calls.last == "latest:segment-one-edit")
    actions.selectedSegmentCount = 2
    precondition(menuChanges.count == 1, "A real selection change must still invalidate menu availability")
    print("PASS: all tabs, both source types, hidden dispatch rejection, active dispatch and busy guards")
} }
"""
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder); (path / 'Main.swift').write_text(harness)
            result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(path/'modules'), str(path/'Main.swift'), '-o', str(path/'check')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(path/'check')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_windows_production_visibility_across_all_tabs_and_sources(self):
        if not shutil.which('dotnet'): self.skipTest('.NET SDK required')
        source = (WIN / 'Vidi Studio Windows/MainWindow.Menus.cs').read_text()
        production = declaration(source, '    private bool RowCommandVisible(') + declaration(source, '    private bool EditorCommandVisible(') + declaration(source, '    private bool EditorCommandVisibleInMode(') + declaration(source, '    private string[] CopyDefaultKinds(') + declaration(source, '    private string CurrentSectionCopyTitle') + ';'
        harness = """using System;
using System.Linq;
class Picker { public int SelectedIndex; }
class Project { public bool IsYouTube; }
class Studio { public Project? Project = new(); }
class Check {
    class Row { public bool IsDescription; }
    Row? SingleSelectedSegment() => null;
    Row? previewingSegment; bool videoPlaybackStarted;
    Picker Section = new(); Studio Model = new(); bool editMode, summaryEditMode;
""" + production + """
    static void Main() {
        var check = new Check();
"""
        for section, youtube, editing, command, expected in cases():
            harness += f'check.editMode = {str(editing).lower()}; check.summaryEditMode = {str(section == "summary" and editing).lower()};\n'
            harness += f'check.Section.SelectedIndex = {SECTIONS.index(section)}; check.Model.Project!.IsYouTube = {str(youtube).lower()};\n'
            harness += f'if (check.EditorCommandVisible("{command}") != {str(expected).lower()}) throw new Exception("{section} {youtube} {command}");\n'
        defaults = [['transcript'], ['summary'], ['descriptions'], ['descriptions'], ['transcript', 'descriptions']]
        titles = ['Transcript', 'Summary', 'Descriptions', 'Descriptions', 'AD Transcript']
        for index, (kinds, title) in enumerate(zip(defaults, titles)):
            expected = 'new[] { ' + ', '.join(json.dumps(kind) for kind in kinds) + ' }'
            harness += f'check.Section.SelectedIndex = {index}; if (!check.CopyDefaultKinds(true).SequenceEqual({expected}) || !check.CopyDefaultKinds(false).SequenceEqual(new[] {{ "transcript", "summary", "descriptions" }}) || check.CurrentSectionCopyTitle != "Copy and Translate {title}…") throw new Exception("Copy defaults {index}");\n'
        harness += 'Console.WriteLine("PASS: Windows production tab/source visibility matrix"); } }'
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder); (path / 'Program.cs').write_text(harness)
            (path / 'Check.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><Nullable>enable</Nullable></PropertyGroup></Project>')
            result = subprocess.run(['dotnet', 'run', '--project', str(path/'Check.csproj')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_menu_rendering_and_accelerators_share_context_guards(self):
        import runpy
        contract = runpy.run_path(str(ROOT / 'script/contextual_menu_contract.py'))
        mac = (MAC/'VidiStudio/KeyboardShortcuts.swift').read_text()
        win = (WIN/'Vidi Studio Windows/MainWindow.Menus.cs').read_text()
        contract['check_contextual_menus'](mac, win)
        for text in ['isCommandVisible(action)', 'shortcuts.filter { editor?.isCommandVisible($0.id) == true }', 'if editor?.youtubeProject == true {', 'if editor?.summaryActive == true && editor?.summaryEditing != true {']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                contract['check_contextual_menus'](mac.replace(text, 'missing-context-guard'), win)
        for text in ['desktopEditorVisible && !EditorCommandVisible(id)', '&& EditorCommandVisible(id)', 'menu.Title == "YouTube" && !YouTubeMenusVisible']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                contract['check_contextual_menus'](mac, win.replace(text, 'missing-context-guard'))

if __name__ == '__main__': unittest.main()
