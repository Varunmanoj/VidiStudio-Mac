"""Reject actual context-menu hierarchy, target and state drift."""
from pathlib import Path
import runpy
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parent
CHECK = runpy.run_path(str(ROOT/'script/context_menu_layout_contract.py'))['check_context_menu_layouts']

class ContextMenuLayouts(unittest.TestCase):
    def test_actual_desktop_declarations_match(self):
        CHECK(WORKSPACE)

    def test_packaged_smoke_activation_preserves_context_mode(self):
        win=WORKSPACE/'Vidi-Studio-Windows'
        for file in ['Vidi Studio Windows/App.xaml.cs','Vidi Studio Windows/MainWindow.SmokeTest.cs','script/test-windows-ui.ps1']:
            self.assertIn('VIDISTUDIO_UI_SMOKE_CONTEXT_MENUS_ONLY', (win/file).read_text(encoding='utf-8'))

    def test_regressions_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            names = ['VidiStudio Mac/VidiStudio/ProjectBrowserPage.swift', 'VidiStudio Mac/VidiStudio/ProjectGridView.swift', 'VidiStudio Mac/VidiStudio/EditorProjectBrowser.swift']
            names += ['Vidi-Studio-Windows/Vidi Studio Windows/' + name for name in ['MainWindow.Commands.cs','MainWindow.ContextMenus.cs','MainWindow.YouTube.cs','MainWindow.xaml.cs']]
            for name in names:
                target=root/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((WORKSPACE/name).read_bytes())
            for filename, original, changed in [
                ('MainWindow.Commands.cs', 'MenuFlyoutSubItem { Text = "Analysis"', 'MenuFlyoutSubItem { Text = "Processing"'),
                ('MainWindow.Commands.cs', 'Item("delete-content", "Choose Content to Delete…");', ''),
                ('MainWindow.Commands.cs', 'if (!CanRunProjectContextCommand(id, project, editorBrowser)) return;', 'if (false) return;'),
                ('MainWindow.Commands.cs', 'Item("open-project-here", "Open in This Window");', 'Item("export");'),
                ('MainWindow.YouTube.cs', 'ReferenceEquals(list.SelectedItem, target) && youtubeBrowserCanRun?.Invoke(id) == true', 'true'),
                ('MainWindow.xaml.cs', 'copyToItem.Visibility = desktopEditorVisible && EditorCommandVisible("copy-to")', 'copyToItem.Visibility = true'),
                ('MainWindow.ContextMenus.cs', 'Read Selected Text Only', 'Read everything')]:
                file=root/'Vidi-Studio-Windows/Vidi Studio Windows'/filename;source=file.read_text();self.assertIn(original, source)
                file.write_text(source.replace(original,changed))
                with self.subTest(filename=filename,change=original),self.assertRaises(ValueError):CHECK(root)
                file.write_text(source)
