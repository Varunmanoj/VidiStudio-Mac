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
        self.assertIn('new("piper", "Piper Voices")', source)
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

    def test_windows_migrates_legacy_engines_without_resetting_preview_choice(self):
        source = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Services/SettingsStore.cs').read_text()
        self.assertNotIn('NormalizeNarrationPlaybackEngine', source)
        self.assertIn('if (key == "narrationPlayback") NormalizeNarrationPlayback();', source)
        self.assertIn('if (Get("ttsMode") == "windows-natural")', source)
        self.assertIn('if (Get("ttsMode") == "azure")', source)
        self.assertIn('Data["ttsMode"] = "windows-core";', source)

    def test_windows_overview_refreshes_after_settings_close(self):
        presentation = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.Presentation.cs').read_text()
        window = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/MainWindow.xaml.cs').read_text()
        self.assertIn('private static string EngineTitle(string mode)', presentation)
        self.assertIn('"gemini" => "Gemini Voices"', presentation)
        self.assertIn('"sapi5" => "Windows SAPI 5"', presentation)
        self.assertIn('"piper" => "Piper Voices"', presentation)
        self.assertIn('_ => "Windows OneCore"', presentation)
        self.assertIn('"Speech engine: " + EngineTitle(Model.Settings.Get("ttsMode", "windows-core"))', presentation)
        self.assertIn('finally { openSettings = null; ApplyTheme(); Model.Reload(); UpdateApiKeyUi(); UpdateSectionPresentation(); }', window)

    def test_windows_bundles_piper_and_removes_the_natural_voice_bridge_promotion(self):
        dialog = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.cs').read_text()
        voices = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Views/SettingsDialog.Voices.cs').read_text()
        host = (ROOT/'Vidi-Studio-Windows/SpeechHost/Program.cs').read_text()
        app = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Vidi Studio Windows.csproj').read_text()
        self.assertNotIn('new("windows-natural"', dialog)
        self.assertNotIn('new("azure", "Azure Voices")', dialog)
        self.assertIn('new("piper", "Piper Voices")', dialog)
        self.assertIn('piperControls.Visibility = provider == "piper" ? Visibility.Visible : Visibility.Collapsed;', voices)
        self.assertIn('new PiperVoicesDialog()', voices)
        self.assertNotIn('sapiHelp', voices)
        self.assertNotIn('GroupSapiVoices', voices)
        self.assertNotIn('NaturalVoiceSAPIAdapter', voices)
        self.assertNotIn('AzureSpeechKey', voices)
        self.assertIn('container.IsEnabled = voice?.Available != false;', voices)
        # A stalled or silent voice must fail clearly instead of hanging or producing empty narration.
        self.assertIn('speech.Speak(r.Text, 1 | 16);', host)
        self.assertIn('speech.WaitUntilDone(SpeakTimeoutMs)', host)
        self.assertIn('The selected voice produced no audio.', host)
        self.assertIn('request.Engine is not ("windows-core" or "sapi5" or "piper")', host)
        self.assertIn('private static void PiperSpeech(Request r)', host)
        self.assertIn('"--length_scale"', host)
        self.assertNotIn('PackageManager', host)
        # The runtime ships with the app and is fetched once, with a checksum, at build time.
        self.assertIn('Content Include="..\\runtime\\piper\\**\\*" Link="piper\\%(RecursiveDir)%(Filename)%(Extension)"', app)
        self.assertIn('Content Include="Assets\\piper-voices.json"', app)
        self.assertIn('<Target Name="FetchPiperRuntime" BeforeTargets="PrepareForBuild"', app)
        self.assertIn('fetch-piper.ps1', app)
        # Visual Studio builds republish a stale speech helper instead of packaging it.
        self.assertIn('<Target Name="PublishSpeechHost" BeforeTargets="PrepareForBuild"', app)
        self.assertIn('Inputs="@(SpeechHostSource)" Outputs="$(SpeechHostPublishDir)\\VidiStudio.SpeechHost.exe"', app)
        self.assertIn('ContinueOnError="WarnAndContinue"', app)
        self.assertIn('the copy in runtime\\speech\\$(Platform) is used', app)

    def test_mac_no_longer_offers_azure_or_piper_generation(self):
        settings = (ROOT/'VidiStudio Mac/VidiStudio/SettingsView.swift').read_text()
        overview = (ROOT/'VidiStudio Mac/VidiStudio/ADOverviewView.swift').read_text()
        model = (ROOT/'VidiStudio Mac/VidiStudio/StudioModel.swift').read_text()
        self.assertNotIn('Azure Voices', settings)
        self.assertNotIn('Azure Voices', overview)
        self.assertNotIn('AzureSpeechKeySettings', settings)
        self.assertNotIn('azureSpeechKey', model)
        self.assertNotIn('KeychainStore.azureSpeech', model)
        self.assertIn('case "piper": return "Piper Voices"', model)
        self.assertIn('if settings.ttsMode == "azure" || settings.ttsMode == "piper" {', model)
        self.assertIn('if settings.ttsMode == "piper" { settings.systemVoice = "" }', model)
        self.assertIn('settings.ttsMode = "system"', model)

    def test_summary_read_aloud_uses_the_narration_voice_only(self):
        mac_settings = (ROOT/'VidiStudio Mac/VidiStudio/SettingsView.swift').read_text()
        mac_reader = (ROOT/'VidiStudio Mac/VidiStudio/SummaryReadback.swift').read_text()
        win_reader = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Services/SummaryReadback.cs').read_text()
        win_live = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Services/OnDeviceNarrator.cs').read_text()
        self.assertNotIn('Read aloud with', mac_settings)
        self.assertNotIn('usesAzure', mac_reader)
        self.assertIn('private func startSpeech(_ text: String) throws', mac_reader)
        self.assertIn('var mode = settings.Get("ttsMode", "windows-core");', win_reader)
        self.assertNotIn('azure', win_reader.lower())
        # Live on-device speech includes Piper and never creates project files.
        self.assertIn('if (mode is "sapi5" or "piper")', win_live)
        self.assertIn('mode == "piper" ? settings.Get("piperVoice", settings.Get("systemVoice"))', win_live)
        self.assertNotIn('preview-tts', win_live)
        self.assertNotIn('engine.RunAsync', win_live)


if __name__ == '__main__':
    unittest.main()
