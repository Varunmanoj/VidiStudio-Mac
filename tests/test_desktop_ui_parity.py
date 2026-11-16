"""Reject regressions on either desktop, including mutations of the owning source."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('desktop_ui_contract', ROOT / 'script/check_desktop_ui_parity.py')
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)

class DesktopUILayoutParityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not all((ROOT.parent / name).is_dir() for name in ['VidiStudio Mac','Vidi-Studio-Windows']):
            raise unittest.SkipTest('Paired desktop source checks need both checkouts; native parity remains unverified.')
        cls.source = contract.sources(ROOT.parent)

    def test_both_desktops_preserve_the_layout_contract(self): contract.validate(self.source)

    def mutated(self, path, before, after, expected):
        self.assertIn(before, self.source[path])
        changed = dict(self.source); changed[path] = changed[path].replace(before, after)
        with self.assertRaisesRegex(ValueError, expected): contract.validate(changed)

    def test_mac_settings_cannot_drop_grouped_forms(self):
        self.mutated('Mac/SettingsView.swift', '.formStyle(.grouped)', '.formStyle(.columns)', 'grouped forms')
    def test_mac_import_cannot_drop_grouped_forms(self):
        self.mutated('Mac/ImportAssetsView.swift', '.formStyle(.grouped)', '.formStyle(.columns)', 'grouped forms')
    def test_mac_export_cannot_drop_grouped_forms(self):
        self.mutated('Mac/ExportOptionsMenu.swift', '.formStyle(.grouped)', '.formStyle(.columns)', 'grouped forms')
    def test_mac_key_and_timing_actions_cannot_stack(self):
        for file in ['GeminiAPISettingsView.swift','SarvamVoiceSettingsView.swift','ImportAssetsView.swift']:
            with self.subTest(file=file): self.mutated('Mac/'+file, 'HStack', 'VStack', 'horizontal row')
    def test_windows_forms_cannot_bypass_shared_layout(self):
        self.mutated('Windows/Views/WindowAppearance.cs', 'CompactDialogLayout.PrepareDialog(dialog);', '', 'shared presentation')
    def test_windows_wide_dialogs_cannot_inherit_the_narrow_style_cap(self):
        self.mutated('Windows/Views/WindowAppearance.cs', 'dialog.ReadLocalValue(FrameworkElement.MaxWidthProperty)', 'dialog.MaxWidth', 'native style defaults')
        self.mutated('Windows/Views/WindowAppearance.cs', 'LocalSize(dialog.Resources,"ContentDialogMaxWidth")', 'dialog.Resources["ContentDialogMaxWidth"]', 'global theme defaults')
    def test_windows_cards_cannot_use_a_fixed_light_background(self):
        self.mutated('Windows/Views/SettingsDialog.Compact.cs', 'ThemeResource CardBackgroundFillColorDefaultBrush', 'StaticResource LightBackground', 'follow light/dark')
    def test_windows_actions_cannot_drop_width_based_arrangement(self):
        self.mutated('Windows/Views/SettingsDialog.SpeechLayout.cs', 'Fits(finalSize.Width)', 'false', 'actual width')
    def test_windows_cannot_drop_native_alignment_assertions(self):
        self.mutated('Windows/MainWindow.DialogLayoutSmoke.cs', 'TransformToVisual(row)', 'TransformToVisual(dialog)', 'rendered field positions')
    def test_windows_cannot_drop_value_preservation_assertions(self):
        self.mutated('Windows/MainWindow.DialogLayoutSmoke.cs', 'picker.SelectedIndex!=1 || events!=0', 'false', 'values/events')
    def test_windows_cannot_remove_accessible_grouping(self):
        self.mutated('Windows/Views/SettingsDialog.Compact.cs', 'new AccessibilityGroup', 'new ContentControl', 'named UI Automation')
    def test_windows_cannot_remove_narrow_window_reflow(self):
        self.mutated('Windows/Views/SettingsDialog.Layout.cs', 'args.NewSize.Width < stackBelow', 'false', 'available width')
