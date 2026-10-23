import io
import json
import os
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'engine'))
import azure_speech
import vidistudio_engine as engine

KEY = 'azure-secret-key-123'
WAVE = b'RIFF\x24\x00\x00\x00WAVEfmt ' + b'\x00' * 32


class FakeResponse(io.BytesIO):
    def __enter__(self): return self
    def __exit__(self, *args): self.close()


class AzureSpeech(unittest.TestCase):
    def setUp(self):
        patcher = patch.dict(os.environ, {azure_speech.KEY_ENVIRONMENT: KEY})
        patcher.start(); self.addCleanup(patcher.stop)

    def test_ssml_escapes_text_and_maps_rate(self):
        markup = azure_speech.ssml('Tom & <Jerry>', 'en-US-AvaMultilingualNeural', 1.5)
        self.assertIn('Tom &amp; &lt;Jerry&gt;', markup)
        self.assertIn("rate='+50%'", markup)
        self.assertIn('xml:lang="en-US"', markup)
        self.assertIn('name="en-US-Ava:DragonHDLatestNeural"', azure_speech.ssml('x', 'en-US-Ava:DragonHDLatestNeural'))

    def test_invalid_voice_and_region_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'valid Azure voice'):
            azure_speech.ssml('x', "en-US'/><voice name='x")
        with self.assertRaisesRegex(ValueError, 'valid Azure Speech region'):
            azure_speech.region({'azureSpeechRegion': 'east us.evil.com/'})
        self.assertEqual(azure_speech.region({}), 'eastus')

    def test_missing_key_is_reported_without_network(self):
        with patch.dict(os.environ, {azure_speech.KEY_ENVIRONMENT: ''}), \
             patch.object(azure_speech.urllib.request, 'urlopen') as urlopen:
            with self.assertRaisesRegex(ValueError, 'Add an Azure Speech key'):
                azure_speech.list_voices({})
            urlopen.assert_not_called()

    def test_voice_list_keeps_neural_voices_and_sends_key_in_header(self):
        payload = [
            {'ShortName': 'en-US-AvaMultilingualNeural', 'DisplayName': 'Ava Multilingual', 'Locale': 'en-US',
             'LocaleName': 'English (United States)', 'Gender': 'Female', 'VoiceType': 'Neural'},
            {'ShortName': 'en-US-OldStandard', 'DisplayName': 'Old', 'Locale': 'en-US', 'VoiceType': 'Standard'},
        ]
        with patch.object(azure_speech.urllib.request, 'urlopen', return_value=FakeResponse(json.dumps(payload).encode())) as urlopen:
            voices = azure_speech.list_voices({'azureSpeechRegion': 'westeurope'})
        request = urlopen.call_args.args[0]
        self.assertEqual(request.full_url, 'https://westeurope.tts.speech.microsoft.com/cognitiveservices/voices/list')
        self.assertEqual(request.get_header('Ocp-apim-subscription-key'), KEY)
        self.assertEqual([v['id'] for v in voices], ['en-US-AvaMultilingualNeural'])
        self.assertEqual(voices[0]['languageName'], 'English (United States)')

    def test_synthesis_writes_wave_and_rejects_non_audio(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'voice.wav'
            with patch.object(azure_speech.urllib.request, 'urlopen', return_value=FakeResponse(WAVE)) as urlopen:
                azure_speech.synthesize({'azureVoice': 'en-GB-RyanNeural'}, 'Hello', output, rate=1)
            request = urlopen.call_args.args[0]
            self.assertEqual(request.get_header('X-microsoft-outputformat'), azure_speech.OUTPUT_FORMAT)
            self.assertIn(b'en-GB-RyanNeural', request.data)
            self.assertEqual(output.read_bytes(), WAVE)
            with patch.object(azure_speech.urllib.request, 'urlopen', return_value=FakeResponse(b'{}')):
                with self.assertRaisesRegex(ValueError, 'no audio'):
                    azure_speech.synthesize({}, 'Hello', output)

    def test_rejected_key_has_friendly_message(self):
        error = urllib.error.HTTPError('https://example', 401, 'Unauthorized', {}, None)
        with patch.object(azure_speech.urllib.request, 'urlopen', side_effect=error):
            with self.assertRaisesRegex(ValueError, 'rejected the speech key'):
                azure_speech.list_voices({})

    def test_engine_redacts_key_and_tracks_azure_narration(self):
        self.assertNotIn(KEY, engine.safe_error(ValueError('failed with ' + KEY)))
        cfg = {'ttsMode': 'azure', 'azureVoice': 'en-US-JennyNeural'}
        self.assertEqual(engine.narration_engine(cfg), 'azure')
        self.assertEqual(engine.narration_voice(cfg), 'en-US-JennyNeural')
        self.assertTrue(engine.narration_signature(cfg).startswith('azure|en-US-JennyNeural|'))
        self.assertNotEqual(engine.narration_signature(cfg),
                            engine.narration_signature(cfg | {'azureVoice': 'en-US-GuyNeural'}))


if __name__ == '__main__':
    unittest.main()
