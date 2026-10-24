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

    def test_natural_voices_live_in_sapi5_with_plain_groups_on_windows(self):
        dialog = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.cs').read_text()
        voices = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.Voices.cs').read_text()
        store = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Services/SettingsStore.cs').read_text()
        host = (ROOT/'Vidi-Studio-Windows/SpeechHost/Program.cs').read_text()
        self.assertNotIn('new("windows-natural"', dialog)
        self.assertIn('new("azure", "Azure Voices")', dialog)
        self.assertIn('Add("bridge-offline", "Natural voices — work offline", offline);', voices)
        self.assertIn('Add("bridge-online", "Online natural voices — need the internet", online);', voices)
        self.assertIn('Add("standard", "Standard voices", standard);', voices)
        self.assertIn('sapiHelp.Visibility = provider == "sapi5" ? Visibility.Visible : Visibility.Collapsed;', voices)
        self.assertIn('azureControls.Visibility = provider == "azure" ? Visibility.Visible : Visibility.Collapsed;', voices)
        self.assertIn('container.IsEnabled = voice?.Available != false;', voices)
        self.assertIn('if (Get("ttsMode") != "windows-natural") return false;', store)
        self.assertIn('Data.Remove(AzureSpeechKey);', store)
        # A stalled or silent voice must fail clearly instead of hanging or producing empty narration.
        self.assertIn('speech.Speak(r.Text, 1 | 16);', host)
        self.assertIn('speech.WaitUntilDone(SpeakTimeoutMs)', host)
        self.assertIn('The selected voice produced no audio.', host)
        self.assertNotIn('PackageManager', host)

    def test_mac_lists_azure_voices_and_shows_its_key_only_when_selected(self):
        settings = (ROOT/'VidiStudio Mac/VidiStudio/SettingsView.swift').read_text()
        overview = (ROOT/'VidiStudio Mac/VidiStudio/ADOverviewView.swift').read_text()
        model = (ROOT/'VidiStudio Mac/VidiStudio/StudioModel.swift').read_text()
        self.assertIn('Label("Azure Voices", systemImage: "cloud").tag("azure")', settings)
        self.assertNotIn('if studio.settings.hasAzureSpeechKey {\n                        Label("Azure Voices"', settings)
        self.assertIn('Text("Azure Voices").tag("azure")', overview)
        self.assertIn('if studio.settings.ttsMode == "azure" {\n                    AzureSpeechKeySettings(studio: studio)', settings)
        self.assertEqual(settings.count('AzureSpeechKeySettings(studio: studio)'), 1)
        self.assertIn('case "azure": return "Azure Voices"', model)
        self.assertIn('get { KeychainStore.azureSpeech.read() ?? "" }', model)

    def test_summary_read_aloud_offers_azure_but_live_preview_never_does(self):
        mac_settings = (ROOT/'VidiStudio Mac/VidiStudio/SettingsView.swift').read_text()
        mac_reader = (ROOT/'VidiStudio Mac/VidiStudio/SummaryReadback.swift').read_text()
        mac_model = (ROOT/'VidiStudio Mac/VidiStudio/StudioModel.swift').read_text()
        win_voices = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.Voices.cs').read_text()
        win_reader = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Services/SummaryReadback.cs').read_text()
        win_live = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Services/OnDeviceNarrator.cs').read_text()
        self.assertIn('Picker("Read aloud with", selection: $studio.settings.summaryReadbackVoice)', mac_settings)
        self.assertIn('if studio.settings.hasAzureSpeechKey {\n                                Text("Azure online voice").tag("azure")', mac_settings)
        self.assertIn('var usesAzureSummaryVoice: Bool { summaryReadbackVoice == "azure" && hasAzureSpeechKey }', mac_model)
        self.assertIn('private var usesAzure: Bool { settings.usesAzureSummaryVoice }', mac_reader)
        self.assertIn('if (DraftAzureKey.Length > 0) options.Add(new("azure", "Azure online voice"));', win_voices)
        self.assertIn('var useAzure = settings.Get("summaryReadbackVoice", "narration") == "azure" && settings.HasAzureSpeechKey;', win_reader)
        # Live on-device speech uses local voices only: the bridge for downloaded voices, never Azure.
        self.assertIn('if (mode == "sapi5")', win_live)
        self.assertIn('var voiceId = mode is "windows-core" or "system" ? settings.Get("systemVoice") : "";', win_live)
        self.assertNotIn('preview-tts', win_live)
        self.assertNotIn('engine.RunAsync', win_live)


if __name__ == '__main__':
    unittest.main()
