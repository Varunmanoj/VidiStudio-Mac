"""Exercise real single/bulk editor presentation and persistence guards."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from tests.test_segment_duration_bounds import declaration

ROOT = Path(__file__).resolve().parents[1]


class SegmentEditAccessTests(unittest.TestCase):
    def test_single_edits_save_in_view_mode_and_bulk_edits_still_require_edit_mode(self):
        source = (ROOT / 'VidiStudio/ContentView.swift').read_text()
        methods = '\n'.join(declaration(source, marker).replace('private ', '') for marker in [
            '    private var canCreateSegment:', '    private var canOpenSegmentEditor:',
            '    private func presentSegmentEditor(', '    private func presentBulkSegmentEditor(',
            '    private func saveEditedRows('])
        methods = methods.replace('pauseAndCaptureTime { _ in', 'pauseAndCaptureTime { [self] _ in')
        fixture = (ROOT / 'tests/segment_edit_access_harness.swift').read_text().replace('// PRODUCTION_METHODS', methods)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            (path / 'Check.swift').write_text(fixture)
            result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(path/'modules'), str(path/'Check.swift'), '-o', str(path/'check')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(path/'check')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_context_menu_parity_and_double_click_remain_scoped(self):
        mac = (ROOT / 'VidiStudio/ContentView.swift').read_text()
        win = ROOT.parent / 'Vidi-Studio-Windows/Vidi Studio Windows'
        menu = (win / 'MainWindow.Commands.cs').read_text()
        editor = declaration((win / 'MainWindow.xaml.cs').read_text(), '    private async Task EditSegment(')
        self.assertIn('Item("Edit segment", async (_, _) => await EditSegment(segment));', menu)
        self.assertNotIn('!editMode', editor)
        self.assertIn('.disabled(!canOpenSegmentEditor)', mac)
        self.assertIn('.onTapGesture(count: 2) {\n                                guard segmentEditMode else { return }', mac)
        self.assertNotIn('Enter Edit mode to edit segment text and timing', mac)
