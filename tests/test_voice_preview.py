import io
import json
import os
import tempfile
import unittest
import wave
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch, Mock
from test_engine import engine

class VoicePreview(unittest.TestCase):
    def test_model_catalog_comes_from_available_generate_content_models(self):
        client = Mock()
        client.models.list.return_value = [
            SimpleNamespace(name='models/gemini-3.8-flash', display_name='Gemini 3.8 Flash', supported_actions=['generateContent', 'countTokens']),
            SimpleNamespace(name='models/gemini-3.8-flash-lite-tts', display_name='Gemini 3.8 Flash-Lite TTS', supported_actions=['generateContent']),
            SimpleNamespace(name='models/gemini-2.5-flash-preview-tts', display_name='Gemini 2.5 Flash TTS', supported_actions=['generateContent']),
            SimpleNamespace(name='models/gemini-embedding-001', display_name='Gemini Embedding', supported_actions=['embedContent']),
            SimpleNamespace(name='models/imagen-4.0-generate-001', display_name='Imagen 4', supported_actions=['predict']),
        ]
        output = io.StringIO()
        with patch.object(engine, 'gemini_client', return_value=client), redirect_stdout(output):
            engine.list_models()
        event = json.loads(output.getvalue())
        self.assertEqual([model['name'] for model in event['models']], [
            'gemini-2.5-flash-preview-tts',
            'gemini-3.8-flash',
            'gemini-3.8-flash-lite-tts',
        ])
        self.assertTrue(event.get('valid'))
        self.assertEqual(event.get('plan'), 'free')
        client.close.assert_called_once()

    def test_check_api_key_detects_paid_plan_when_paid_model_available(self):
        client = Mock()
        client.models.list.return_value = [
            SimpleNamespace(name='models/gemini-3.8-flash', display_name='Gemini 3.8 Flash', supported_actions=['generateContent']),
            SimpleNamespace(name='models/gemini-omni-1.1-flash', display_name='Gemini Omni Flash', supported_actions=['generateContent']),
        ]
        output = io.StringIO()
        with patch.object(engine, 'gemini_client', return_value=client), \
             redirect_stdout(output):
            engine.list_models()
        event = json.loads(output.getvalue())
        self.assertTrue(event.get('valid'))
        self.assertEqual(event.get('plan'), 'paid')

    def test_check_api_key_detects_paid_plan_when_cache_access_available(self):
        client = Mock()
        client.models.list.return_value = [
            SimpleNamespace(name='models/gemini-3.8-flash', display_name='Gemini 3.8 Flash', supported_actions=['generateContent']),
        ]
        client.models.get.side_effect = Exception("Not available")
        client.caches.list.return_value = []
        output = io.StringIO()
        with patch.object(engine, 'gemini_client', return_value=client), \
             redirect_stdout(output):
            engine.list_models()
        event = json.loads(output.getvalue())
        self.assertTrue(event.get('valid'))
        self.assertEqual(event.get('plan'), 'paid')

    def test_preview_uses_tts_model_and_voice_without_project(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'sample.wav'
            client = Mock()
            client.models.generate_content.return_value = SimpleNamespace(candidates=[SimpleNamespace(content=SimpleNamespace(parts=[SimpleNamespace(inline_data=SimpleNamespace(data=b'\0\0' * 2400))]))])
            cfg = {'ttsMode':'gemini', 'geminiVoice':'Kore', 'prompts':{'tts_audio':{'user_prompt':'Speak: {text}'}}}
            with patch.object(engine, 'config', return_value=cfg), patch.object(engine, 'client_and_model', return_value=(client, 'configured-tts-model')):
                engine.preview_tts(output, 'Sample narration')
            call = client.models.generate_content.call_args.kwargs
            self.assertEqual(call['model'], 'configured-tts-model')
            self.assertEqual(call['contents'], 'Speak: Sample narration')
            self.assertEqual(call['config'].speech_config.voice_config.prebuilt_voice_config.voice_name, 'Kore')
            client.close.assert_called_once()
            with wave.open(str(output)) as audio:
                self.assertEqual(audio.getframerate(), 24000)
                self.assertEqual(audio.getnframes(), 2400)
            self.assertFalse((Path(directory)/'project.json').exists())

    def test_gemini_38_reads_verbatim_text_and_preserves_complete_wav(self):
        source = io.BytesIO()
        with wave.open(source, 'wb') as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(24000)
            audio.writeframes(b'\0\0' * 2400)
        cfg = {'geminiVoice':'Kore', 'prompts':{'tts_audio':{'user_prompt':'Read clearly and naturally: {text}'}}}
        for model in ('gemini-3.8-flash-tts', 'gemini-3.8-flash-lite-tts'):
            with self.subTest(model=model), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / 'sample.wav'
                client = Mock()
                client.models.generate_content.return_value = SimpleNamespace(candidates=[SimpleNamespace(content=SimpleNamespace(parts=[SimpleNamespace(inline_data=SimpleNamespace(data=source.getvalue(), mime_type='audio/wav'))]))])
                with patch.object(engine, 'config', return_value=cfg), patch.object(engine, 'client_and_model', return_value=(client, model)):
                    engine.gemini_speech(output, 'A woman types.', {})
                self.assertEqual(client.models.generate_content.call_args.kwargs['contents'], 'A woman types.')
                self.assertEqual(output.read_bytes(), source.getvalue())
                with wave.open(str(output)) as audio:
                    self.assertEqual(audio.getnframes(), 2400)

    def test_malformed_wav_is_not_wrapped_as_raw_audio(self):
        client = Mock()
        client.models.generate_content.return_value = SimpleNamespace(candidates=[SimpleNamespace(content=SimpleNamespace(parts=[SimpleNamespace(inline_data=SimpleNamespace(data=b'RIFFbad', mime_type='audio/wav'))]))])
        cfg = {'prompts':{'tts_audio':{'user_prompt':'{text}'}}}
        with tempfile.TemporaryDirectory() as directory, patch.object(engine, 'config', return_value=cfg), patch.object(engine, 'client_and_model', return_value=(client, 'gemini-3.8-flash-tts')):
            output = Path(directory) / 'sample.wav'
            with self.assertRaisesRegex(ValueError, 'invalid WAV'):
                engine.gemini_speech(output, 'Test', {})
            self.assertFalse(output.exists())

    def test_missing_audio_reports_actionable_failure_and_closes_client(self):
        client = Mock()
        client.models.generate_content.return_value = SimpleNamespace(candidates=[])
        cfg = {'prompts':{'tts_audio':{'user_prompt':'{text}'}}}
        with patch.object(engine, 'config', return_value=cfg), patch.object(engine, 'client_and_model', return_value=(client, 'tts')):
            with self.assertRaisesRegex(ValueError, 'no audio'):
                engine.gemini_speech(Path('/tmp/not-created-preview.wav'), 'Test', {})
        client.close.assert_called_once()

    def test_preview_requires_bounded_text_and_a_cloud_or_piper_voice(self):
        for value in ['', 'x'*501]:
            with self.assertRaises(ValueError): engine.preview_tts(Path('/tmp/not-created-preview.wav'), value)
        with patch.object(engine, 'config', return_value={'ttsMode':'system'}):
            with self.assertRaisesRegex(ValueError, 'Choose Gemini Voices or Piper Voices'):
                engine.preview_tts(Path('/tmp/not-created-preview.wav'), 'Hello')

    def test_piper_preview_and_speech_use_the_selected_voice(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'sample.wav'
            raw = output.with_name(output.stem + '-raw.wav')
            cfg = {'ttsMode':'piper', 'piperVoice':'en_US-amy-low', 'systemSpeechRate':1.2}

            def fake_piper(raw_path, text, config):
                self.assertEqual(text, 'Sample narration')
                self.assertEqual(config['piperVoice'], 'en_US-amy-low')
                raw_path.write_bytes(b'RIFFraw')

            def fake_finish(raw_path, output_path, config):
                self.assertTrue(raw_path.exists())
                output_path.write_bytes(b'RIFFencoded')

            with patch.object(engine, 'config', return_value=cfg), \
                 patch.object(engine, 'piper_speech', side_effect=fake_piper), \
                 patch.object(engine, 'finish_system_speech', side_effect=fake_finish), \
                 patch.object(engine, 'gemini_speech') as gemini:
                engine.preview_tts(output, 'Sample narration')
                gemini.assert_not_called()
            self.assertEqual(output.read_bytes(), b'RIFFencoded')
            self.assertFalse(raw.exists())
            self.assertFalse((Path(directory)/'project.json').exists())

    def test_synthesize_speech_supports_piper_and_rejects_other_engines(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'speech.wav'
            cfg = {'ttsMode':'piper', 'piperVoice':'en_US-amy-low'}
            with patch.object(engine, 'config', return_value=cfg), \
                 patch.object(engine, 'piper_speech') as piper, \
                 patch.object(engine, 'finish_system_speech') as finish:
                finish.side_effect = lambda raw, target, config: target.write_bytes(b'RIFFencoded')
                engine.synthesize_speech(output, 'Read the whole summary aloud.')
            piper.assert_called_once()
            self.assertEqual(piper.call_args.args[1], 'Read the whole summary aloud.')
            self.assertEqual(output.read_bytes(), b'RIFFencoded')
            with patch.object(engine, 'config', return_value={'ttsMode':'system'}):
                with self.assertRaisesRegex(ValueError, 'Piper'):
                    engine.synthesize_speech(output, 'Hello')
            with self.assertRaisesRegex(ValueError, 'requires --output'):
                engine.synthesize_speech(None, 'Hello')
            with patch.object(engine, 'config', return_value=cfg):
                with self.assertRaisesRegex(ValueError, 'requires text'):
                    engine.synthesize_speech(output, '   ')

    def test_piper_espeak_data_relocates_deep_bundle_paths(self):
        # espeak-ng reads its data path through a 160-byte buffer, so the app
        # bundle path is mirrored to a short application support folder.
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / ('deep-' + 'x' * 160) / 'espeak-ng-data'
            source.mkdir(parents=True)
            (source / 'phontab').write_text('tab')
            target = Path(directory) / 'short' / 'espeak-ng-data'
            with patch.dict(os.environ, {'VIDISTUDIO_ESPEAK_DATA': str(source)}), \
                 patch.object(engine, 'espeak_data_home', return_value=target):
                engine._ESPEAK_DATA_COPY = None
                try:
                    resolved = engine.piper_espeak_data()
                    self.assertEqual(resolved, target)
                    self.assertTrue((target / 'phontab').is_file())
                    # A later call reuses the copy instead of copying it again.
                    (target / 'reused').write_text('once')
                    engine._ESPEAK_DATA_COPY = None
                    self.assertEqual(engine.piper_espeak_data(), target)
                    self.assertTrue((target / 'reused').is_file())
                finally:
                    engine._ESPEAK_DATA_COPY = None
        # Normal installs keep using the data folder directly.
        self.assertLess(len(str(engine.piper_espeak_data())), 150)

    def test_piper_speech_rejects_punctuation_only_text(self):
        # A horizontal rule yields zero samples, which ffmpeg cannot finish.
        with tempfile.TemporaryDirectory() as directory:
            raw = Path(directory) / 'empty.wav'

            with patch.object(engine, 'piper_locations', return_value=('voice', Path('/models/voice.onnx'), Path('/models/voice.onnx.json'))), \
                 patch.object(engine, 'load_piper_voice') as voice:
                voice.return_value.config.sample_rate = 22050
                # Piper emits no audio chunks for punctuation-only text.
                voice.return_value.synthesize_wav.return_value = None
                with self.assertRaisesRegex(ValueError, 'no words to read aloud'):
                    engine.piper_speech(raw, '⸻', {'piperVoice': 'voice'})

    def test_safe_error_formats_invalid_api_key_cleanly(self):
        exc = Exception("400 INVALID_ARGUMENT. {'error': {'code': 400, 'message': 'API key not valid. Please pass a valid API key.', 'status': 'INVALID_ARGUMENT', 'details': [{'reason': 'API_KEY_INVALID'}]}}")
        msg = engine.safe_error(exc)
        self.assertEqual(msg, "API key not valid. Please check your Gemini API key in Settings.")

    def test_list_models_with_invalid_api_key_raises_sanitized_error(self):
        client = Mock()
        client.models.list.side_effect = Exception("400 API_KEY_INVALID: API key not valid. Please pass a valid API key.")
        with patch.object(engine, 'gemini_client', return_value=client):
            with self.assertRaises(Exception) as ctx:
                engine.list_models()
            self.assertEqual(engine.safe_error(ctx.exception), "API key not valid. Please check your Gemini API key in Settings.")
