"""Run the production Windows row/selection guards without WinUI."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from tests.test_contextual_menus import declaration, MAC, WIN


class SingleSegmentMenu(unittest.TestCase):
    def test_windows_production_selection_tab_prerequisite_and_stale_row_guards(self):
        if not shutil.which('dotnet'): self.skipTest('.NET SDK required')
        source = (WIN/'Vidi Studio Windows/MainWindow.Menus.cs').read_text()
        methods = ''.join(declaration(source, marker) for marker in (
            '    private bool CanRunSingleSegmentCommand(', '    private Models.Segment? SingleSelectedSegment(',
            '    private bool SegmentBelongsToCurrentTab(', '    private bool RowCommandVisible(',
            '    private bool CanRunRowCommand(', '    private string SegmentCommandTitle('))
        player_source = (WIN/'Vidi Studio Windows/MainWindow.Presentation.cs').read_text()
        methods += ''.join(declaration(player_source, marker) for marker in ('    private void ToggleSegmentPreviewPause(', '    private void ClearSegmentPreview(', '    private void StopSegmentPreview('))
        harness = '''using System; using System.Linq; using System.Collections.Generic; using Segment=Models.Segment;
namespace Models { class Segment { public string Id = "same-id"; public bool IsDescription, AudioReady, IsPreviewing, PreviewPaused; public string? Audio; }
class Project { public bool IsYouTube; public List<Segment> Cues = new(), Transcript = new(); } }
enum OnlineService { YouTube }
class ConnectivityService { public static ConnectivityService Shared = new(); public bool Available(OnlineService s) => true; }
class ModelState { public Models.Project? Project = new(); public bool Idle = true, CanUseAI = true; public string Engine = "local"; public string CurrentNarrationEngine() => Engine; }
class Picker { public int SelectedIndex; }
class Rows { public List<object> SelectedItems = new(), Items = new(); }
class Speech { public int Plays, Pauses; public object? Source; public void Play() { Plays++; } public void Pause() { Pauses++; } }
class Check { Speech speech = new(); Models.Segment? previewingSegment; bool segmentPreviewPaused; void UpdateDesktopMenuStates() {}
ModelState Model = new(); Picker Section = new(); Rows Segments = new();
bool desktopEditorVisible = true, validationShowcaseActive, windowClosed, editMode;
''' + methods + '''
static void Main() {
 var c = new Check(); var transcript = new Models.Segment(); var description = new Models.Segment {IsDescription=true, Audio="audio.wav", AudioReady=true};
 c.Model.Project!.Transcript.Add(transcript); c.Model.Project.Cues.Add(description);
 string[] actions = {"segment-one-edit", "segment-one-play", "segment-one-skip", "segment-one-preview", "segment-one-preview-stop", "segment-one-synthesize", "segment-one-rewrite", "segment-one-import-audio", "segment-one-delete-audio", "segment-one-reanalyze", "segment-one-delete"};
 foreach(var tab in new[]{0,1,2,3,4}) {c.Section.SelectedIndex=tab;
 foreach(var editing in new[]{false,true}) {c.editMode=editing;
 foreach(var count in new[]{0,1,2}) foreach(var row in new[]{transcript,description}) {
 c.Segments.Items.Clear(); c.Segments.Items.Add(transcript); c.Segments.Items.Add(description);
 c.Segments.SelectedItems.Clear(); if(count>0)c.Segments.SelectedItems.Add(row); if(count>1)c.Segments.SelectedItems.Add(ReferenceEquals(row,transcript)?description:transcript);
 foreach(var action in actions) {
 var timed = tab is 0 or 2 or 4; var kindAllowed=tab==4||row.IsDescription==(tab==2);
 var adOnly = new[]{"segment-one-preview","segment-one-synthesize","segment-one-rewrite","segment-one-import-audio","segment-one-delete-audio"}.Contains(action);
 var allowed = action!="segment-one-preview-stop"&&(!adOnly||row.IsDescription)&&(action!="segment-one-reanalyze"||!row.IsDescription);
 if(c.CanRunSingleSegmentCommand(action)!=(timed&&editing&&count==1&&kindAllowed&&allowed))throw new Exception("selection policy: "+action);
 if(c.CanRunRowCommand(action,row)!=(timed&&kindAllowed&&allowed))throw new Exception("context policy: "+action);
 }
 }}}
 c.Section.SelectedIndex=4;c.editMode=true;c.Segments.SelectedItems.Clear();c.Segments.SelectedItems.Add(description);
 c.Model.CanUseAI=false;c.Model.Engine="gemini";description.Audio=null;description.AudioReady=false;
 foreach(var action in new[]{"segment-one-rewrite","segment-one-synthesize","segment-one-delete-audio","segment-one-preview"})if(c.CanRunSingleSegmentCommand(action))throw new Exception("prerequisite");
 c.previewingSegment=description;description.IsPreviewing=true;
 if(!c.CanRunSingleSegmentCommand("segment-one-preview")||!c.CanRunSingleSegmentCommand("segment-one-preview-stop"))throw new Exception("active narration controls");
 if(c.SegmentCommandTitle("segment-one-preview")!="Pause Narration")throw new Exception("stop label");
 c.ToggleSegmentPreviewPause(description);if(!c.segmentPreviewPaused||c.speech.Pauses!=1||c.SegmentCommandTitle("segment-one-preview")!="Resume Narration")throw new Exception("pause");
 c.ToggleSegmentPreviewPause(transcript);if(c.speech.Plays!=0)throw new Exception("wrong row resume");
 c.ToggleSegmentPreviewPause(description);if(c.segmentPreviewPaused||c.speech.Plays!=1)throw new Exception("resume");
 c.StopSegmentPreview();if(c.previewingSegment!=null||description.IsPreviewing||c.segmentPreviewPaused||c.CanRunSingleSegmentCommand("segment-one-preview-stop"))throw new Exception("stop");
 c.Model.Idle=false;if(c.CanRunSingleSegmentCommand("segment-one-edit"))throw new Exception("busy");c.Model.Idle=true;
 c.Segments.Items.Remove(description);if(c.CanRunSingleSegmentCommand("segment-one-edit"))throw new Exception("stale row");
 c.Segments.Items.Add(description);c.Model.Project.Cues.Clear();if(c.CanRunSingleSegmentCommand("segment-one-edit"))throw new Exception("stale result");
 if(c.SegmentCommandTitle("segment-one-edit", transcript)!="Edit Transcript Segment…"||c.SegmentCommandTitle("segment-one-edit", description)!="Edit Audio description Segment…")throw new Exception("title");
 Console.WriteLine("PASS: single-selection guards, row kinds, tab scope, busy/prerequisites, stale rows and same IDs across kinds");
} }
'''
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder);(path/'Program.cs').write_text(harness)
            (path/'Check.csproj').write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><Nullable>enable</Nullable></PropertyGroup></Project>')
            result=subprocess.run(['dotnet','run','--project',str(path/'Check.csproj')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_shared_context_dispatch_and_bulk_delete_edit_menu_contract(self):
        mac=(MAC/'VidiStudio/KeyboardShortcuts.swift').read_text();content=(MAC/'VidiStudio/ContentView.swift').read_text()
        win=(WIN/'Vidi Studio Windows/MainWindow.Menus.cs').read_text();commands=(WIN/'Vidi Studio Windows/MainWindow.Commands.cs').read_text()
        mac_edit=mac.split('CommandGroup(replacing: .pasteboard)',1)[1].split('CommandGroup(replacing: .textEditing)',1)[0]
        win_edit=win.split('Menu("Edit",',1)[1].split('Menu("View",',1)[0]
        self.assertIn('editor?.run("segment-delete-selected")',mac_edit);self.assertIn('Command("segment-delete-selected")',win_edit)
        for text in [mac_edit,win_edit]:self.assertNotIn('"segment-one-delete"',text)
        self.assertIn('.contextMenu { segmentRowContextMenu(row) }',content)
        self.assertIn('guard canRunSegmentRowAction(action, row: row) else { return }',content)
        self.assertIn('guard shortcutActions.canRun(action), selectedSegmentIDs.count == 1, selectedRows.count == 1,',content)
        self.assertIn('if (!CanRunRowCommand(id, segment)) return;',commands)
        self.assertIn('await RunSegmentRowCommandAsync(id, segment)',commands)
        self.assertIn('if (SingleSelectedSegment() is { } segment) await RunSegmentRowCommandAsync(id, segment);',win)
        self.assertIn('p.Transcript.Where(c => segment.IsDescription || c.Id != segment.Id)',commands)
        self.assertIn('p.Cues.Where(c => !segment.IsDescription || c.Id != segment.Id)',commands)
