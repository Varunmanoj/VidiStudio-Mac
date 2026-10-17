import importlib.util
from pathlib import Path
import unittest


class DesktopMenuParity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[2]
        checker = root / 'script/check_menu_parity.py'
        if not checker.is_file():
            raise unittest.SkipTest('Cross-platform menu checks require the combined workspace.')
        spec = importlib.util.spec_from_file_location('desktop_menu_parity', checker)
        cls.checker = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.checker)
        cls.mac = (root / 'VidiStudio Mac/VidiStudio/KeyboardShortcuts.swift').read_text()
        cls.app = (root / 'VidiStudio Mac/VidiStudio/VidiStudioApp.swift').read_text()
        cls.windows = (root / 'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.Menus.cs').read_text()

    def test_actual_menus_and_shortcuts_match(self):
        self.assertGreater(self.checker.compare_sources(self.mac, self.app, self.windows), 30)

    def test_missing_menu_item_is_detected(self):
        changed = self.windows.replace('Command("review-narration-issues"), ', '', 1)
        self.assertNotEqual(changed, self.windows)
        with self.assertRaisesRegex(ValueError, 'hierarchy/order'):
            self.checker.compare_sources(self.mac, self.app, changed)

    def test_moved_or_renamed_submenu_is_detected(self):
        changed = self.windows.replace('Submenu("Narration",', 'Submenu("Narration Tools",', 1)
        with self.assertRaisesRegex(ValueError, 'hierarchy/order'):
            self.checker.compare_sources(self.mac, self.app, changed)

    def test_shortcut_conflict_is_detected(self):
        changed = self.windows.replace('["narration"] = (VirtualKey.D,', '["narration"] = (VirtualKey.V,', 1)
        with self.assertRaisesRegex(ValueError, 'Conflicting Windows shortcut'):
            self.checker.compare_sources(self.mac, self.app, changed)

    def test_wrong_label_is_detected(self):
        changed = self.windows.replace('"summary-pause" => "Pause Summary Reading"', '"summary-pause" => "Pause Video"', 1)
        with self.assertRaisesRegex(ValueError, 'menu label'):
            self.checker.compare_sources(self.mac, self.app, changed)

    def test_unwired_action_is_detected(self):
        changed = self.windows.replace('case "summary-read-selection":', 'case "unused-action":', 1)
        with self.assertRaisesRegex(ValueError, 'no handler'):
            self.checker.compare_sources(self.mac, self.app, changed)


if __name__ == '__main__':
    unittest.main()
