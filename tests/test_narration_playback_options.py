from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NarrationPlaybackOptions(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (ROOT/'VidiStudio Mac/VidiStudio/StudioModel.swift').is_file() or not (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Services/SettingsStore.cs').is_file():
            raise unittest.SkipTest('Playback option checks require both desktop checkouts.')

    def test_mac_keeps_engine_selection_independent_of_playback_mode(self):
        settings = (ROOT/'VidiStudio Mac/VidiStudio/SettingsView.swift').read_text()
        overview = (ROOT/'VidiStudio Mac/VidiStudio/ADOverviewView.swift').read_text()
        for source in (settings, overview):
            self.assertNotIn('allowsGeminiNarration', source)
        self.assertIn('Label("Apple Voices", systemImage: "speaker.wave.2").tag("system")', settings)
        self.assertIn('Label("Gemini Voices", systemImage: "sparkles").tag("gemini")', settings)
        self.assertIn('Text("Apple Voices").tag("system")', overview)
        self.assertIn('Text("Gemini Voices").tag("gemini")', overview)
        self.assertIn('if studio.settings.ttsMode == "gemini" {\n                    GeminiVoiceBrowser(studio: studio)', settings)
        self.assertIn('if studio.settings.ttsMode != "gemini" {', settings)
        self.assertNotIn('studio.settings.ttsMode != "gemini" || studio.settings.narrationPlayback == "device"', settings)

    def test_mac_no_longer_resets_the_engine_for_preview_playback(self):
        source = (ROOT/'VidiStudio Mac/VidiStudio/StudioModel.swift').read_text()
        self.assertNotIn('normalizeNarrationPlaybackEngine', source)
        self.assertNotIn('allowsGeminiNarration', source)
        self.assertIn('var ttsMode = "system"\n    var narrationPlayback = "generated"', source)
        self.assertIn('case "gemini": return "Gemini Voices"', source)
        self.assertIn('case "system": return "Apple Voices"', source)

    def test_windows_keeps_gemini_selectable_in_preview_playback(self):
        source = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.cs').read_text()
        self.assertNotIn('LocalNarrationPreview', source)
        self.assertIn('new("windows-core", "Windows OneCore")', source)
        self.assertIn('new("sapi5", "Windows SAPI 5")', source)
        self.assertIn('new("gemini", "Gemini Voices")', source)
        self.assertIn('draft["ttsMode"] = selected.Id;', source)

    def test_windows_gemini_voices_show_only_voice_names_and_hide_local_sliders(self):
        gemini = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.Gemini.cs').read_text()
        dialog = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.cs').read_text()
        self.assertIn('"Aoede", "Callirrhoe", "Charon", "Fenrir", "Kore", "Leda", "Orus", "Puck", "Zephyr"', gemini)
        self.assertIn('Names.Select(name => new Voice(name, name, "", "")).ToArray()', gemini)
        self.assertNotIn('LoadGeminiVoicesAsync', dialog)
        self.assertIn('search.Visibility = provider == "gemini" ? Visibility.Collapsed : Visibility.Visible;', dialog)
        self.assertIn('localSpeechControls.Visibility = provider == "gemini" ? Visibility.Collapsed : Visibility.Visible;', dialog)
        self.assertIn('samplePlayButton.IsEnabled = sampleState != SampleState.Generating && (provider != "gemini" || HasDraftApiKey);', dialog)

    def test_windows_never_resets_the_saved_engine(self):
        source = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Services/SettingsStore.cs').read_text()
        self.assertNotIn('Data["ttsMode"] = "windows-core"', source)
        self.assertNotIn('NormalizeNarrationPlaybackEngine', source)
        self.assertIn('if (key == "narrationPlayback") NormalizeNarrationPlayback();', source)

    def test_windows_overview_refreshes_after_settings_close(self):
        presentation = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.Presentation.cs').read_text()
        window = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.xaml.cs').read_text()
        self.assertIn('private static string EngineTitle(string mode)', presentation)
        self.assertIn('"gemini" => "Gemini Voices"', presentation)
        self.assertIn('"sapi5" => "Windows SAPI 5"', presentation)
        self.assertIn('_ => "Windows OneCore"', presentation)
        self.assertIn('"Speech engine: " + EngineTitle(Model.Settings.Get("ttsMode", "windows-core"))', presentation)
        self.assertIn('finally { openSettings = null; ApplyTheme(); Model.Reload(); UpdateApiKeyUi(); UpdateSectionPresentation(); }', window)


if __name__ == '__main__':
    unittest.main()
