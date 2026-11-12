import runpy
from pathlib import Path
import unittest


class ExportCompletionSoundMenus(unittest.TestCase):
    def test_shared_checked_toggle_and_default(self):
        workspace = Path(__file__).resolve().parents[2]
        check = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'script/contextual_menu_contract.py'))['check_export_completion_sound']
        mac = (workspace / 'VidiStudio Mac/VidiStudio/SettingsView.swift').read_text() + (workspace / 'VidiStudio Mac/VidiStudio/SettingsSoundPreview.swift').read_text()
        windows = (workspace / 'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.cs').read_text() + (workspace / 'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.Appearance.cs').read_text()
        check(mac, windows)
        for a, b in [(mac.replace('export-completion-sound-menu', ''), windows),
                     (mac.replace('$studio.settings.soundAfterExport', '$studio.settings.soundWhenTimingInvalid', 1), windows),
                     (mac, windows.replace('choice.IsChecked = toggle.IsOn', 'choice.IsChecked = false')),
                     (mac, windows.replace('previewItem.Click += (_, _) => ToggleSoundPreview(resource);', ''))]:
            with self.assertRaises(ValueError): check(a, b)
