import json
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
        self.assertIn('Label("Piper Voices", systemImage: "waveform.circle").tag("piper")', settings)
        self.assertIn('Label("Gemini Voices", systemImage: "sparkles").tag("gemini")', settings)
        self.assertIn('Text("Apple Voices").tag("system")', overview)
        self.assertIn('Text("Piper Voices").tag("piper")', overview)
        self.assertIn('Text("Gemini Voices").tag("gemini")', overview)
        self.assertIn('if studio.settings.ttsMode == "gemini" {\n                    GeminiVoiceBrowser(studio: studio)', settings)
        self.assertIn('if studio.settings.ttsMode == "piper" {', settings)
        self.assertIn('PiperVoiceSettingsView(settings: $studio.settings)', settings)
        self.assertIn('if studio.settings.ttsMode == "system" {', settings)
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

    def test_mac_offers_piper_and_removes_azure(self):
        settings = (ROOT/'VidiStudio Mac/VidiStudio/SettingsView.swift').read_text()
        overview = (ROOT/'VidiStudio Mac/VidiStudio/ADOverviewView.swift').read_text()
        model = (ROOT/'VidiStudio Mac/VidiStudio/StudioModel.swift').read_text()
        catalog = (ROOT/'VidiStudio Mac/VidiStudio/PiperVoiceCatalog.swift').read_text()
        self.assertNotIn('Azure Voices', settings)
        self.assertNotIn('Azure Voices', overview)
        self.assertNotIn('AzureSpeechKeySettings', settings)
        self.assertNotIn('azureSpeechKey', model)
        self.assertNotIn('KeychainStore.azureSpeech', model)
        self.assertIn('case "piper": return "Piper Voices"', model)
        self.assertIn('var piperVoice = ""', model)
        self.assertIn('return piperSpeechSignature', model)
        self.assertIn('if settings.ttsMode == "azure" {', model)
        self.assertNotIn('if settings.ttsMode == "azure" || settings.ttsMode == "piper" {', model)
        self.assertIn('looksLikePiperVoiceIdentifier', model)
        self.assertIn('settings.piperVoice = legacyVoice', model)
        # The macOS catalog mirrors Windows: filters, sorting, hosted samples,
        # per-row download progress, removal progress, and checksum verification.
        self.assertIn('PiperVoiceBrowser', catalog)
        self.assertIn('PiperVoiceManager', catalog)
        self.assertIn('Picker("Language", selection: $language)', catalog)
        self.assertIn('Picker("Quality", selection: $quality)', catalog)
        self.assertIn('Picker("Sort by", selection: $sort)', catalog)
        self.assertIn('"Language (A–Z)"', catalog)
        self.assertIn('"Voice name (A–Z)"', catalog)
        self.assertIn('"Quality (high to low)"', catalog)
        self.assertIn('"Size (smallest first)"', catalog)
        self.assertIn('Play Sample', catalog)
        self.assertIn('deletingIDs', catalog)
        self.assertIn('progress[voice.id]', catalog)
        self.assertIn('Insecure.MD5', catalog)
        self.assertIn('huggingface.co/rhasspy/piper-voices', catalog)
        self.assertIn('piper-voices.json', (ROOT/'VidiStudio Mac/script/xcode_bundle_engine.sh').read_text())
        self.assertIn('piper-tts==1.8.0', (ROOT/'VidiStudio Mac/engine/requirements-build.lock').read_text())
        self.assertIn('--collect-all piper', (ROOT/'VidiStudio Mac/script/prepare_engine.sh').read_text())
        # The frozen engine must find espeak-ng data from its own folder, not the bundle.
        engine = (ROOT/'VidiStudio Mac/engine/vidistudio_engine.py').read_text()
        self.assertIn('def piper_espeak_data():', engine)
        self.assertIn('espeak_data_dir=piper_espeak_data()', engine)

    def test_summary_read_aloud_uses_the_narration_voice_only(self):
        mac_settings = (ROOT/'VidiStudio Mac/VidiStudio/SettingsView.swift').read_text()
        mac_reader = (ROOT/'VidiStudio Mac/VidiStudio/SummaryReadback.swift').read_text()
        win_reader = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Services/SummaryReadback.cs').read_text()
        win_live = (ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Services/OnDeviceNarrator.cs').read_text()
        self.assertNotIn('Read aloud with', mac_settings)
        self.assertNotIn('usesAzure', mac_reader)
        self.assertIn('private func startSpeech(_ text: String) throws', mac_reader)
        self.assertIn('if settings.ttsMode == "piper" {', mac_reader)
        self.assertIn('PiperSpeech.request(text: text, settings: settings)', mac_reader)
        self.assertIn('audioPlayerDidFinishPlaying', mac_reader)
        self.assertIn('.onChange(of: settings.ttsMode) { _, _ in model.updateSettings(settings) }', mac_reader)
        self.assertIn('.onChange(of: settings.piperVoice) { _, _ in model.updateSettings(settings) }', mac_reader)
        # The reader names the engine it actually uses, and Piper errors stay readable.
        self.assertIn('speechEngineLabel', mac_reader)
        self.assertIn('settings.ttsMode == "piper" ? "Piper Speech" : "Apple Speech"', mac_reader)
        self.assertNotIn('Text("Apple Speech")', mac_reader)
        self.assertIn('UserFacingIssueReporter.speechMessage(', mac_reader)
        self.assertIn('var mode = settings.Get("ttsMode", "windows-core");', win_reader)
        self.assertNotIn('azure', win_reader.lower())
        # Live on-device speech includes Piper and never creates project files.
        self.assertIn('if (mode is "sapi5" or "piper")', win_live)
        self.assertIn('mode == "piper" ? settings.Get("piperVoice", settings.Get("systemVoice"))', win_live)
        self.assertNotIn('preview-tts', win_live)
        self.assertNotIn('engine.RunAsync', win_live)

    def test_piper_catalog_is_shared_and_has_published_samples(self):
        mac = json.loads((ROOT/'VidiStudio Mac/VidiStudio/Assets/piper-voices.json').read_text())
        windows = json.loads((ROOT/'Vidi-Studio-Windows/Vidi Studio Windows/Assets/piper-voices.json').read_text())
        self.assertEqual(mac, windows)
        self.assertEqual(len(mac), 178)
        for voice_id, voice in mac.items():
            self.assertEqual(voice['key'], voice_id)
            self.assertIn(voice['quality'], ('x_low', 'low', 'medium', 'high'))
            model = next(path for path in voice['files'] if path.endswith('.onnx'))
            config = next(path for path in voice['files'] if path.endswith('.onnx.json'))
            self.assertEqual(model.rsplit('/', 1)[0], config.rsplit('/', 1)[0])
            self.assertTrue(voice['files'][model]['md5_digest'])
            self.assertTrue(voice['files'][config]['md5_digest'])


if __name__ == '__main__':
    unittest.main()
