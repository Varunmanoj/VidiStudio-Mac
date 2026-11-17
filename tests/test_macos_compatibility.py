import importlib.util
import plistlib
import struct
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    'macos_compatibility', Path(__file__).resolve().parents[1] / 'script/check_macos_compatibility.py')
audit_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit_module)


def binary(minimum, sdk=(27, 2), cpu=0x100000C):
    header = struct.pack('<IiiIIIII', 0xFEEDFACF, cpu, 0, 2, 1, 24, 0, 0)
    command = struct.pack('<IIIIII', 0x32, 24, 1,
                          minimum[0] << 16 | minimum[1] << 8,
                          sdk[0] << 16 | sdk[1] << 8, 0)
    return header + command


class MacCompatibilityTests(unittest.TestCase):
    def test_new_sdk_does_not_raise_the_runtime_minimum(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'library.dylib').write_bytes(binary((26, 0)))
            self.assertEqual(audit_module.audit(root, '26.4')['counts'], {'26.0.0': 1})

    def test_newer_transitive_library_blocks_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'ffmpeg').write_bytes(binary((26, 0)))
            (root / 'tesseract.dylib').write_bytes(binary((26, 5)))
            with self.assertRaisesRegex(ValueError, 'tesseract.*exceeding 26.4'):
                audit_module.audit(root, '26.4')

    def test_intel_code_is_not_accepted_in_apple_silicon_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'engine').write_bytes(binary((14, 0), cpu=0x1000007))
            with self.assertRaisesRegex(ValueError, 'Not an Apple Silicon'):
                audit_module.audit(root, '26.4')

    def test_app_metadata_must_match_advertised_minimum(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'Contents').mkdir()
            (root / 'app').write_bytes(binary((26, 4)))
            (root / 'Contents/Info.plist').write_bytes(plistlib.dumps({'LSMinimumSystemVersion': '27.0'}))
            with self.assertRaisesRegex(ValueError, 'LSMinimumSystemVersion'):
                audit_module.audit(root, '26.4')


if __name__ == '__main__':
    unittest.main()
