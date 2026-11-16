"""Auditions persist without repeat billing and never substitute paid public demos."""
import base64
from concurrent.futures import ThreadPoolExecutor
import io
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch
import wave
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'engine'))
import sarvam_tts


def wav_bytes():
    result = io.BytesIO()
    with wave.open(result, 'wb') as audio:
        audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(22050)
        audio.writeframes(b'\0\0' * 2205)
    return result.getvalue()


@unittest.skipUnless(shutil.which('ffmpeg'), 'Requires real audio decode')
class SarvamSampleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.client = Mock()
        self.client.text_to_speech.convert.return_value = SimpleNamespace(audios=[base64.b64encode(wav_bytes()).decode()])
        self.factory = Mock(return_value=self.client)
        self.key = patch.dict(os.environ, {'VIDISTUDIO_SARVAM_API_KEY': 'test-private-key'})
        self.key.start(); self.addCleanup(self.key.stop)

    def preview(self, model='bulbul:v4-flash', voice='shubh_enhi_ads', language='en-IN', **kwargs):
        def run(args): subprocess.run([str(a) for a in args], check=True, capture_output=True)
        return sarvam_tts.preview_sample(model, voice, language, run, shutil.which('ffmpeg'), Mock(),
            directory=self.directory, client_factory=self.factory, **kwargs)

    def test_generated_audio_replays_after_restart_without_key_or_network(self):
        first = self.preview(); original = first.read_bytes(); modified = first.stat().st_mtime_ns
        with patch.dict(os.environ, {'VIDISTUDIO_SARVAM_API_KEY': ''}):
            replay = self.preview()
        self.assertEqual(first, replay); self.assertEqual(replay.read_bytes(), original)
        self.assertEqual(replay.stat().st_mtime_ns, modified)
        self.factory.assert_called_once(); self.client.text_to_speech.convert.assert_called_once()
        request = self.client.text_to_speech.convert.call_args.kwargs
        self.assertEqual(request['text'], sarvam_tts.SAMPLE_TEXT['en-IN'])
        self.assertEqual(request['speaker'], 'shubh_enhi_ads'); self.assertEqual(request['pace'], 1)
        self.assertFalse(any('test-private-key' in p.read_text(errors='ignore') for p in self.directory.rglob('*') if p.is_file()))

    def test_model_voice_and_language_have_distinct_generated_samples(self):
        paths = {self.preview(), self.preview(language='hi-IN'), self.preview(voice='amelia_en_conversational'),
                 self.preview(model='bulbul:v2', voice='anushka')}
        self.assertEqual(len(paths), 4); self.assertEqual(self.client.text_to_speech.convert.call_count, 4)
        self.assertTrue(all(sarvam_tts.valid_sample(p) for p in paths))

    def test_concurrent_windows_only_generate_once(self):
        def convert(**kwargs): time.sleep(.15); return SimpleNamespace(audios=[base64.b64encode(wav_bytes()).decode()])
        self.client.text_to_speech.convert.side_effect = convert
        with ThreadPoolExecutor(max_workers=2) as workers:
            results = list(workers.map(lambda _: self.preview(), range(2)))
        self.assertEqual(results[0], results[1]); self.client.text_to_speech.convert.assert_called_once()

    def test_published_demo_downloads_without_key_and_never_synthesizes(self):
        fetch = Mock(return_value=wav_bytes())
        with patch.dict(os.environ, {'VIDISTUDIO_SARVAM_API_KEY': ''}):
            first = self.preview(model='bulbul:v3', voice='shubh', fetch=fetch)
            replay = self.preview(model='bulbul:v3', voice='shubh', language='hi-IN', fetch=fetch)
        self.assertEqual(first, replay); fetch.assert_called_once(); self.factory.assert_not_called()

    def test_failed_catalog_download_never_falls_back_to_paid_synthesis(self):
        with self.assertRaises(OSError):
            self.preview(model='bulbul:v3', voice='shubh', fetch=Mock(side_effect=OSError('offline')))
        self.factory.assert_not_called(); self.assertFalse(list(self.directory.glob('*.wav')))

    def test_failed_generation_is_not_retried_or_committed(self):
        class Failure(Exception): status_code=503; body={}
        self.client.text_to_speech.convert.side_effect=Failure()
        with self.assertRaises(sarvam_tts.SarvamError): self.preview()
        self.client.text_to_speech.convert.assert_called_once()
        self.assertFalse(list(self.directory.glob('*.wav')))
        self.assertFalse(list(self.directory.glob('pending-*')))

    def test_corrupt_and_empty_files_are_replaced_with_valid_audio(self):
        first = self.preview()
        for data in (b'', b'RIFFbroken'):
            first.write_bytes(data); self.assertEqual(self.preview(), first)
            self.assertTrue(sarvam_tts.valid_sample(first))
        self.assertEqual(self.client.text_to_speech.convert.call_count, 3)

    def test_v3_never_generates_when_catalog_demo_is_missing(self):
        catalog = sarvam_tts.catalog()
        voice = next(v for v in catalog['voices'] if v['model'] == 'bulbul:v3' and v['id'] == 'shubh')
        voice.pop('demoUrl')
        with patch.object(sarvam_tts, 'catalog', return_value=catalog):
            with self.assertRaisesRegex(sarvam_tts.SarvamError, 'published demo'):
                self.preview(model='bulbul:v3', voice='shubh')
        self.factory.assert_not_called()

    def test_invalid_voice_language_fails_before_api(self):
        for kwargs in ({'voice':'../other'}, {'language':'ml-IN'}, {'model':'bulbul:v3','voice':'shubh_enhi_ads'}):
            with self.assertRaises(sarvam_tts.SarvamError): self.preview(**kwargs)
        self.factory.assert_not_called()

if __name__ == '__main__': unittest.main()
