from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NarrationPlaybackOptions(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (ROOT/'VidiStudio Mac/VidiStudio/StudioModel.swift').is_file() or not (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Services/SettingsStore.cs').is_file():
            raise unittest.SkipTest('Playback option checks require both desktop checkouts.')

    def test_mac_gates_both_engine_pickers_and_gemini_voice_browser(self):
        settings = (ROOT/'VidiStudio Mac/VidiStudio/SettingsView.swift').read_text()
        overview = (ROOT/'VidiStudio Mac/VidiStudio/ADOverviewView.swift').read_text()
        for source in (settings, overview):
            self.assertIn('if studio.settings.allowsGeminiNarration {', source)
        self.assertIn('if studio.settings.allowsGeminiNarration && studio.settings.ttsMode == "gemini"', settings)

    def test_mac_normalizes_setting_changes_loading_and_external_updates(self):
        source = (ROOT/'VidiStudio Mac/VidiStudio/StudioModel.swift').read_text()
        self.assertEqual(source.count('didSet { normalizeNarrationPlaybackEngine() }'), 2)
        self.assertIn('decoded.normalizeNarrationPlaybackEngine()', source)
        self.assertIn('updated.normalizeNarrationPlaybackEngine()', source)
        self.assertNotIn('settings.normalizeNarrationPlaybackEngine()', source)
        self.assertIn('seededCaptionDisplayMode || normalizedNarration', source)

    def test_windows_filters_gemini_when_local_preview_is_selected(self):
        source = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.cs').read_text()
        self.assertIn('if (!LocalNarrationPreview) options.Add(new("gemini", "Gemini voices"));', source)
        self.assertIn('if (LocalNarrationPreview && provider == "gemini")', source)
        self.assertIn('draft["narrationPlayback"] = option.Id;\n            UpdateNarrationEngineOptions();', source)

    def test_windows_normalizes_load_reload_save_and_programmatic_changes(self):
        source = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Services/SettingsStore.cs').read_text()
        self.assertEqual(source.count('if (NormalizeNarrationPlaybackEngine()) Save();'), 2)
        self.assertIn('if (key is "narrationPlayback" or "ttsMode") NormalizeNarrationPlaybackEngine();', source)
        self.assertIn('public void Save()\n    {\n        NormalizeNarrationPlaybackEngine();', source)


if __name__ == '__main__':
    unittest.main()
