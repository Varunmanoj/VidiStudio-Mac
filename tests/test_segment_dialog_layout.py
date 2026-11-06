from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

class SegmentDialogLayoutTests(unittest.TestCase):
    def test_production_sheet_size_fits_compact_and_resized_presenters(self):
        if sys.platform != 'darwin': self.skipTest('macOS Swift SDK required')
        root = Path(__file__).resolve().parents[1]
        mac = root if (root / 'VidiStudio').exists() else root.parent / 'VidiStudio Mac'
        source = (mac / 'VidiStudio/SegmentDialogViewport.swift').read_text()
        start = source.index('enum SegmentDialogLayout')
        end = source.index('\nstruct SegmentDialogViewport', start)
        harness = 'import Foundation\n' + source[start:end] + '''
@main struct Main { static func main() {
    let cases: [(CGSize, CGSize)] = [
        (CGSize(width: 1600, height: 1000), CGSize(width: 1920, height: 1080)),
        (CGSize(width: 1000, height: 650), CGSize(width: 1392, height: 715)),
        (CGSize(width: 700, height: 400), CGSize(width: 768, height: 480)),
        (CGSize(width: 590, height: 560), CGSize(width: 1024, height: 640))
    ]
    for (parent, screen) in cases {
        let size = SegmentDialogLayout.size(parent: parent, screen: screen)
        precondition(size.width <= parent.width - 32 && size.width <= screen.width - 64)
        precondition(size.height <= parent.height - 24 && size.height <= screen.height - 96)
        precondition(size.width > 400 && size.height > 300)
    }
    let compact = SegmentDialogLayout.size(parent: CGSize(width: 700, height: 400), screen: CGSize(width: 768, height: 480))
    let large = SegmentDialogLayout.size(parent: CGSize(width: 1600, height: 1000), screen: CGSize(width: 1920, height: 1080))
    precondition(compact.height < large.height && large.width == 780 && large.height == 680)
    print("PASS: segment sheet viewport constraints")
}}
'''
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory); (folder / 'Main.swift').write_text(harness)
            result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(folder / 'Main.swift'), '-module-cache-path', str(folder / 'modules'), '-o', str(folder / 'check')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(folder / 'check')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
