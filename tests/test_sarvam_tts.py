import base64
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'engine'))
import sarvam_tts


def wave_bytes():
    stream = io.BytesIO()
    with wave.open(stream, 'wb') as audio:
        audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(22050)
        audio.writeframes(b'\x00\x00' * 2205)
    return stream.getvalue()


class SarvamSpeechTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.model_cache = Path(temporary.name) / 'models.json'
        patcher = patch.object(sarvam_tts, 'model_cache_path', return_value=self.model_cache)
        patcher.start(); self.addCleanup(patcher.stop)
    def settings(self, model='bulbul:v4-flash', **values):
        return {'sarvamSpeech': {'model': model, 'profiles': {model: values}}}

    def test_only_supported_parameters_are_sent(self):
        for model in sarvam_tts.bundled_models():
            params = sarvam_tts.parameters(self.settings(model, pitch=.5, loudness=2, temperature=.8, preprocessing=True))
            self.assertEqual(params['language_code'], 'en-IN')
            self.assertEqual(params['speaker'], sarvam_tts.DEFAULT_VOICES[model])
            self.assertEqual('pitch' in params, model == 'bulbul:v2')
            self.assertEqual('loudness' in params, model == 'bulbul:v2')
            self.assertEqual('enable_preprocessing' in params, model == 'bulbul:v2')
            self.assertEqual('temperature' in params, model != 'bulbul:v2')
            self.assertNotIn('target_language_code', params)
            self.assertNotIn('output_audio_bitrate', params)

    def test_catalog_models_and_demos_do_not_cross_model_boundaries(self):
        voices = sarvam_tts.catalog()['voices']
        self.assertEqual(len({(v['model'],v['id']) for v in voices}), len(voices))
        self.assertGreaterEqual(sum(v['model'] == 'bulbul:v4-flash' for v in voices), 200)
        self.assertEqual(sum('demoUrl' in v for v in voices), 37)
        self.assertTrue(all(v['model'] == 'bulbul:v3' for v in voices if v.get('demoUrl')))

    def test_mismatched_voices_and_invalid_controls_fail_before_network(self):
        for cfg in (self.settings(voice='shubh'), self.settings(language='ml-IN'), self.settings(pace=3),
                    self.settings(sampleRate=96000), self.settings(codec='opus'), self.settings(temperature=float('nan'))):
            with self.assertRaises(sarvam_tts.SarvamError): sarvam_tts.parameters(cfg)

    def test_long_multilingual_text_is_preserved_and_bounded(self):
        text = 'मराठी. English narration! ' * 400
        for limit in (1500, 2500):
            parts = list(sarvam_tts.chunks(text, limit))
            self.assertEqual(''.join(parts), text)
            self.assertTrue(all(0 < len(p) <= limit for p in parts))
        self.assertEqual(''.join(sarvam_tts.chunks('क'*6000,2500)), 'क'*6000)

    def test_signature_changes_with_effective_settings_only(self):
        original = sarvam_tts.signature(self.settings())
        self.assertNotEqual(original,sarvam_tts.signature(self.settings(pace=1.5)))
        self.assertEqual(original,sarvam_tts.signature(self.settings(pitch=.5,loudness=2)))
        self.assertEqual(original, 'sarvam|shubh_enhi_ads|bulbul:v4-flash|en-IN|1.000|22050|wav|0.600')

    def synthesize(self, output, text, factory, cfg=None):
        def run(args): subprocess.run([str(a) for a in args], check=True, capture_output=True)
        with patch.dict(os.environ, {'VIDISTUDIO_SARVAM_API_KEY':'test-secret'}):
            sarvam_tts.synthesize(output,text,cfg or self.settings(),run,shutil.which('ffmpeg') or 'ffmpeg',Mock(),factory)

    def test_new_published_models_appear_and_use_provider_defaults(self):
        source = '''**Available Models:**
- **bulbul:v99-future**: New model
- **bulbul:v4-flash**: Current model
## Authentication
- `model` (enum, optional) — Available models.
  - Allowed values: `bulbul:v4-flash`, `bulbul:v99-future`
- `speaker` (enum, optional)
'''
        emit=Mock()
        sarvam_tts.refresh_models(emit, fetch=lambda url: source)
        event=emit.call_args.kwargs
        self.assertEqual([model['id'] for model in event['sarvamModels']],['bulbul:v99-future','bulbul:v4-flash'])
        self.assertEqual(event['sarvamModels'][0]['label'],'Bulbul v99 Future')
        self.assertFalse(event['sarvamModelsCached'])
        self.assertEqual(sarvam_tts.parameters(self.settings('bulbul:v99-future')),{'model':'bulbul:v99-future','language_code':'en-IN'})
        self.assertIn('provider-defaults',sarvam_tts.signature(self.settings('bulbul:v99-future')))
        sarvam_tts.refresh_models(emit, fetch=lambda url: 'Unexpected HTML or changed documentation')
        self.assertTrue(emit.call_args.kwargs['sarvamModelsCached'])
        self.assertEqual(emit.call_args.kwargs['sarvamModels'],event['sarvamModels'])

    def test_read_only_key_check_does_not_generate_audio_or_expose_metadata(self):
        import httpx
        from sarvamai import SarvamAI
        requests=[]
        def respond(request):
            requests.append(request)
            return httpx.Response(200,json={'dictionary_count':1,'dictionaries':['private-dictionary-id']})
        client=SarvamAI(api_subscription_key='test-secret',httpx_client=httpx.Client(transport=httpx.MockTransport(respond)))
        emit=Mock()
        with patch.dict(os.environ,{'VIDISTUDIO_SARVAM_API_KEY':'test-secret'}):
            sarvam_tts.check_key(emit,lambda **kwargs:client)
        self.assertEqual(len(requests),1)
        self.assertEqual(requests[0].method,'GET')
        self.assertEqual(requests[0].url.path,'/text-to-speech/pronunciation-dictionary')
        self.assertEqual(emit.call_args.kwargs['sarvamKeyStatus'],'verified')
        self.assertNotIn('private-dictionary-id',str(emit.call_args))
        self.assertNotIn('test-secret',str(emit.call_args))

    def test_key_check_distinguishes_invalid_from_unavailable(self):
        class Failure(Exception): status_code=403
        for code,status in [('invalid_api_key_error','invalid'),('forbidden_error','unavailable')]:
            error=Failure('test-secret');error.body={'error':{'code':code}}
            client=Mock();client.pronunciation_dictionary.list.side_effect=error;emit=Mock()
            with patch.dict(os.environ,{'VIDISTUDIO_SARVAM_API_KEY':'test-secret'}):
                sarvam_tts.check_key(emit,lambda **kwargs:client)
            self.assertEqual(emit.call_args.kwargs['sarvamKeyStatus'],status)
            client.text_to_speech.convert.assert_not_called()
            client.close.assert_called_once()

    @unittest.skipUnless(shutil.which('ffmpeg'), 'Requires ffmpeg')
    def test_actual_sdk_rest_body_decoding_and_multi_chunk_audio(self):
        import httpx
        from sarvamai import SarvamAI
        requests = []
        def respond(request):
            requests.append(request)
            return httpx.Response(200,json={'request_id':'fixture','audios':[base64.b64encode(wave_bytes()).decode()]})
        client = SarvamAI(api_subscription_key='test-secret',httpx_client=httpx.Client(transport=httpx.MockTransport(respond)))
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)/'narration.mp3'
            self.synthesize(output,'A sentence. '*400,lambda **kwargs:client)
            self.assertGreater(output.stat().st_size,100)
            self.assertGreater(len(requests),1)
            for request in requests:
                self.assertEqual(request.url.path,'/text-to-speech')
                self.assertEqual(request.headers['api-subscription-key'],'test-secret')
                payload=json.loads(request.content)
                self.assertEqual(payload['model'],'bulbul:v4-flash')
                self.assertLessEqual(len(payload['text']),2500)
                self.assertNotIn('pitch',payload)

    def test_missing_key_never_constructs_client(self):
        factory=Mock()
        with patch.dict(os.environ, {'VIDISTUDIO_SARVAM_API_KEY':''}):
            with self.assertRaises(sarvam_tts.SarvamError):
                sarvam_tts.synthesize(Path('/tmp/unused.wav'),'Text',self.settings(),Mock(),'ffmpeg',Mock(),factory)
        factory.assert_not_called()

    def test_invalid_audio_preserves_existing_output_and_closes_client(self):
        client=Mock(); client.text_to_speech.convert.return_value=SimpleNamespace(audios=['not base64'])
        with tempfile.TemporaryDirectory() as folder:
            output=Path(folder)/'existing.wav'; output.write_bytes(b'existing audio')
            with self.assertRaises(sarvam_tts.SarvamError): self.synthesize(output,'Hello',lambda **kwargs:client)
            self.assertEqual(output.read_bytes(),b'existing audio')
        client.close.assert_called_once()

    def test_authentication_quota_and_permissions_are_not_retried_or_leaked(self):
        class Failure(Exception):
            status_code=403
        for code, expected in [('invalid_api_key_error','invalid-key'),('insufficient_quota_error','quota'),('forbidden_error','permissions')]:
            error=Failure('test-secret'); error.body={'error':{'code':code}}
            client=Mock(); client.text_to_speech.convert.side_effect=error
            with self.assertRaises(sarvam_tts.SarvamError) as result: self.synthesize(Path('/tmp/unused.wav'),'Hello',lambda **kwargs:client)
            self.assertEqual(result.exception.kind,expected)
            self.assertNotIn('test-secret',str(result.exception))
            self.assertEqual(client.text_to_speech.convert.call_count,1)

    def test_server_failure_has_only_three_attempts(self):
        class Failure(Exception):
            status_code=503; body={}; headers={'retry-after':'0'}
        client=Mock(); client.text_to_speech.convert.side_effect=Failure()
        with patch.object(sarvam_tts.time,'sleep') as sleep:
            with self.assertRaises(sarvam_tts.SarvamError): self.synthesize(Path('/tmp/unused.wav'),'Hello',lambda **kwargs:client)
        self.assertEqual(client.text_to_speech.convert.call_count,3)
        self.assertEqual(sleep.call_count,2)

    def test_cancellation_propagates(self):
        class ProcessingCancelled(Exception): pass
        client=Mock(); client.text_to_speech.convert.side_effect=ProcessingCancelled()
        with self.assertRaises(ProcessingCancelled): self.synthesize(Path('/tmp/unused.wav'),'Hello',lambda **kwargs:client)
        client.close.assert_called_once()

if __name__ == '__main__': unittest.main()
