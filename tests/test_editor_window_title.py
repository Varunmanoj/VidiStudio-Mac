"""Exercise production editor title formatting independently of UI timing."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from tests.test_segment_duration_bounds import declaration

class EditorWindowTitleTests(unittest.TestCase):
    def test_titles_include_project_and_each_active_section(self):
        root = Path(__file__).resolve().parents[1]
        mac = root if (root / 'VidiStudio').exists() else root.parent / 'VidiStudio Mac'
        source = (mac / 'VidiStudio/KeyboardShortcuts.swift').read_text()
        members = declaration(source, 'var activeSectionTitle: String') + '\n' + declaration(source, 'func windowTitle(projectName:')
        harness = 'struct Fixture { var activeSection: String;\n' + members + '\n}\n' + '''
let sections = [("transcript", "Transcript"), ("summary", "Summary"), ("descriptions", "Descriptions"), ("ad-overview", "AD Overview"), ("ad-transcript", "AD Transcript")]
for (id, title) in sections {
    let fixture = Fixture(activeSection: id)
    precondition(fixture.windowTitle(projectName: "Test हिन्दी") == "Test हिन्दी — " + title)
    precondition(fixture.windowTitle(projectName: "Renamed") == "Renamed — " + title)
}
print("PASS: all editor section titles include the current project name")
'''
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            (path / 'main.swift').write_text(harness)
            compiled = subprocess.run(['xcrun', 'swiftc', str(path / 'main.swift'), '-module-cache-path', str(path / 'modules'), '-o', str(path / 'check')], capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            result = subprocess.run([str(path / 'check')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
