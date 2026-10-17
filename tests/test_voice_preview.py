import io
import json
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

    def test_preview_requires_bounded_text_and_gemini(self):
        for value in ['', 'x'*501]:
            with self.assertRaises(ValueError): engine.preview_tts(Path('/tmp/not-created-preview.wav'), value)
        with patch.object(engine, 'config', return_value={'ttsMode':'system'}):
            with self.assertRaisesRegex(ValueError, 'Choose Gemini'):
                engine.preview_tts(Path('/tmp/not-created-preview.wav'), 'Hello')

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
