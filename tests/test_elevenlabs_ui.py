"""Paired provider contract; native smoke tests verify actual rendered controls."""
from pathlib import Path
import runpy
import unittest

ROOT=Path(__file__).resolve().parents[1]
SPACE=ROOT.parent
MAC=SPACE/'VidiStudio Mac';WIN=SPACE/'Vidi-Studio-Windows'
class ElevenLabsUIContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (MAC.exists() and WIN.exists()):raise unittest.SkipTest('Both desktop sources required')
        cls.check=staticmethod(runpy.run_path(str(ROOT/'script/contextual_menu_contract.py'))['check_elevenlabs_settings'])
        cls.mac=(MAC/'VidiStudio/ElevenLabsVoiceSettingsView.swift').read_text()+(MAC/'VidiStudio/ElevenLabsSpeech.swift').read_text()
        cls.win=(WIN/'Vidi Studio Windows/Views/SettingsDialog.ElevenLabs.cs').read_text()
    def test_every_provider_action_has_both_native_surfaces(self):self.check(self.mac,self.win)
    def test_missing_key_status_or_plan_is_rejected(self):
        for token in ['elevenlabs-key-status','Account Plan','elevenlabs-key-delete-icon']:
            with self.subTest(token=token),self.assertRaises(ValueError):self.check(self.mac.replace(token,'removed'),self.win)
    def test_windows_native_acceptance_retains_geometry_and_identity_checks(self):
        for token in ['statusPoint.X<=keyPoint.X','Math.Abs(statusPoint.Y','Remaining allowance','Distinct voices with the same name','actions.ActualWidth','elevenFixture=true']:
            self.assertIn(token,self.win)
    def test_key_storage_and_request_environment_are_separate_from_projects(self):
        self.assertIn('com.vidistudio.elevenlabs-api',(MAC/'Shared/KeychainStore.swift').read_text())
        self.assertIn('VidiStudio/ElevenLabsApiKey',(WIN/'Vidi Studio Windows/Services/CredentialStore.cs').read_text())
        for source in [(MAC/'VidiStudio/ElevenLabsSpeech.swift').read_text(),(WIN/'Vidi Studio Windows/Services/ElevenLabsSpeech.cs').read_text()]:
            self.assertIn('VIDISTUDIO_ELEVENLABS_API_KEY',source)
            self.assertIn('VIDISTUDIO_SARVAM_API_KEY',source)
        self.assertIn('Data.Remove("elevenlabsApiKey")',(WIN/'Vidi Studio Windows/Services/SettingsStore.cs').read_text())
    def test_synthesis_capability_and_summary_guards_are_mirrored(self):
        self.assertIn('["gemini", "sarvam", "elevenlabs"]',(MAC/'VidiStudio/SpeechProviderSettings.swift').read_text())
        self.assertIn('"gemini" or "sarvam" or "elevenlabs"',(WIN/'Vidi Studio Windows/Services/SarvamSpeech.cs').read_text())
    def test_voice_rows_use_selection_and_demo_icons(self):
        self.assertIn('"checkmark.circle.fill" : "circle"',self.mac)
        self.assertIn('"stop.circle" : "play.circle"',self.mac)
        self.assertIn('var select=new RadioButton',self.win)
        self.assertIn('button.Content=new FontIcon',self.win)
        self.assertIn('voice.variants.filter',self.mac)
        self.assertIn('.GroupBy(v=>ES(v["language"])',self.win)
    def test_only_voice_search_is_a_text_box_and_filters_are_dropdowns(self):
        self.assertNotIn('Search models',self.mac+self.win)
        self.assertNotIn('elevenlabs-model-search',self.mac+self.win)
        self.assertIn('filterChoice("Accent","accent","All accents")',self.mac)
        self.assertIn('return SpeechChoice(title:title,id:"elevenlabs-filter-"+field',self.mac)
        self.assertIn('SpeechChoiceControl(elevenMetadataFilters,title,"elevenlabs-filter-"+key',self.win)
        self.assertIn('Only voice search may be a text box',self.win)
        self.assertIn('RenderElevenMetadataFilters();',self.win)

    def test_speaking_speed_is_an_accessible_model_control_on_both_platforms(self):
        self.assertIn('case "speed": SpeechAdjustment(title:"Speaking speed"',self.mac)
        self.assertIn('range:0.7...1.2,initial:1',self.mac)
        self.assertIn('"speed"=>"Speaking speed"',self.win)
        self.assertIn('ElevenLabs speaking-speed range/default/name regressed.',self.win)
        self.assertIn('ElevenLabs speaking speed did not save.',self.win)

    def test_no_generated_audition_action_exists(self):
        for source in [self.mac,self.win]:
            self.assertNotIn('Generate Sample',source)
            self.assertIn('Play Demo',source)
    def test_adapter_is_mirrored_without_overwriting_platform_engine_code(self):
        self.assertEqual((MAC/'engine/elevenlabs_tts.py').read_bytes(),(WIN/'engine/elevenlabs_tts.py').read_bytes())
        for root in [MAC,WIN]:self.assertTrue('elevenlabs_tts.synthesize' in (root/'engine/vidistudio_engine.py').read_text(),str(root))
