"""Regression checks for the automatic desktop menu icon gate."""
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('menu_icons', ROOT / 'script/check_menu_icons.py')
ICONS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ICONS)


class MenuIconContract(unittest.TestCase):
    def test_desktop_source_has_menu_icons(self):
        self.assertEqual([], ICONS.check(ROOT))
        sibling = ROOT.parent / ('Vidi-Studio-Windows' if (ROOT / 'VidiStudio').is_dir() else 'VidiStudio Mac')
        if sibling != ROOT and sibling.is_dir():
            self.assertEqual([], ICONS.check(sibling))

    def test_mac_rejects_iconless_menu_bar_and_context_actions(self):
        for scope in ('.contextMenu', 'CommandMenu("Project")'):
            with self.subTest(scope=scope):
                broken = scope + ' { Button("Rename Cloud Video…") { rename() } }'
                self.assertEqual(1, len(list(ICONS.mac_missing_icons(broken, set()))))
                self.assertEqual([], list(ICONS.mac_missing_icons(broken, {'Rename Cloud Video…'})))
                fixed = broken.replace('Video…")', 'Video…", systemImage: "pencil")')
                self.assertEqual([], list(ICONS.mac_missing_icons(fixed, set())))

    def test_mac_rejects_text_only_and_iconless_native_rows(self):
        broken = '.contextMenu { Button { rename() } label: { Text("Rename") } }'
        self.assertEqual(1, len(list(ICONS.mac_missing_icons(broken, set()))))
        fixed = broken.replace('Text("Rename")', 'Label("Rename", systemImage: "pencil")')
        self.assertEqual([], list(ICONS.mac_missing_icons(fixed, set())))
        native = 'let row = NSMenuItem(title: "Rename", action: selector, keyEquivalent: ""); menu.addItem(row)'
        self.assertEqual(1, len(list(ICONS.mac_missing_icons(native, set()))))
        fixed = native.replace('menu.addItem', 'row.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil); menu.addItem')
        self.assertEqual([], list(ICONS.mac_missing_icons(fixed, set())))

    def test_windows_rejects_missing_and_null_icons(self):
        for row in ('MenuFlyoutItem', 'MenuFlyoutSubItem', 'ToggleMenuFlyoutItem'):
            with self.subTest(row=row):
                broken = 'new ' + row + ' { Text = "Cloud Storage", IsEnabled = false };'
                self.assertEqual(1, len(list(ICONS.windows_missing_icons(broken))))
                self.assertEqual(1, len(list(ICONS.windows_missing_icons(broken.replace('false', 'false, Icon = null')))))
                self.assertEqual(1, len(list(ICONS.windows_missing_icons(broken.replace('false', 'false, Icon = new FontIcon { }')))))
                fixed = broken.replace('false', 'false, Icon = MenuIcons.Create("Cloud Storage")')
                self.assertEqual([], list(ICONS.windows_missing_icons(fixed)))

    def test_windows_rejects_iconless_xaml_commands(self):
        self.assertEqual(['Retry'], list(ICONS.xaml_missing_icons('<MenuFlyout><MenuFlyoutItem Text="Retry"/></MenuFlyout>')))
        self.assertEqual([], list(ICONS.xaml_missing_icons(
            '<MenuFlyout><MenuFlyoutItem Text="Retry"><MenuFlyoutItem.Icon><FontIcon Glyph="&#xE72C;"/>'
            '</MenuFlyoutItem.Icon></MenuFlyoutItem></MenuFlyout>'
        )))
