"""Configured source models must reach full and range Gemini requests."""
import copy
import contextlib
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

from test_engine import engine as e


class AudioSourceModelRouting(unittest.TestCase):
    def setUp(self):
        self.cfg = copy.deepcopy(e.config())
        self.cfg['models'].update(transcript='local-speech', audio_descriptions='local-visual',
                                  youtube_transcript='youtube-visual', summary='shared-summary')
        self.cfg['prompts']['audio_descriptions']['system_instruction'] = 'DESCRIPTION TASK INSTRUCTIONS'
        self.client = Mock()
        self.settings = patch.object(e, 'config', return_value=self.cfg)
        self.settings.start()
        self.addCleanup(self.settings.stop)
        self.clients = patch.object(e, 'gemini_client', return_value=self.client)
        self.clients.start()
        self.addCleanup(self.clients.stop)

    def project(self, source='youtube', audio='youtube'):
        return dict(sourceType=source, source='video.mp4', youtubeURL='https://youtu.be/abcdefghijk',
                    duration=5, hasAudio=True, transcript=[], transcriptGenerated=True, summary='A scene.', cues=[],
                    audioSources=dict(transcription=audio, playback='youtube', export='youtube'),
                    originalAudio=dict(sourceName='sound.wav', path='imports/sound.wav', sha256='test'))

    def test_source_matrix_and_legacy_projects(self):
        for source, audio in [('upload', 'youtube'), ('upload', 'imported'),
                              ('youtube', 'youtube'), ('youtube', 'imported')]:
            project = self.project(source, audio)
            before = copy.deepcopy(project)
            use_youtube = source == 'youtube' and audio == 'youtube'
            for kind, expected in [('transcribe', 'youtube-visual' if use_youtube else 'local-speech'),
                                   ('generate-ad-cues', 'youtube-visual' if use_youtube else 'local-visual'),
                                   ('generate-summary', 'shared-summary')]:
                with self.subTest(source=source, audio=audio, kind=kind):
                    self.assertEqual(e.client_and_model(kind, project)[1], expected)
            self.assertEqual(project, before)
        legacy = self.project(); legacy.pop('audioSources')
        self.assertEqual(e.client_and_model('audio_descriptions', legacy)[1], 'youtube-visual')

    def test_playback_and_export_do_not_select_analysis_model(self):
        project = self.project()
        project['audioSources'].update(playback='imported', export='imported')
        self.assertEqual(e.client_and_model('audio_descriptions', project)[1], 'youtube-visual')
        self.assertEqual(e.client_and_model('transcript', project)[1], 'youtube-visual')

    def test_full_and_range_descriptions_keep_visual_input_and_task_prompts(self):
        for source, audio in [('upload', 'youtube'), ('youtube', 'youtube'), ('youtube', 'imported')]:
            for ranged in (False, True):
                with self.subTest(source=source, audio=audio, ranged=ranged), tempfile.TemporaryDirectory() as folder:
                    project = self.project(source, audio)
                    response = json.dumps(dict(audioDescriptions=[dict(start=1, end=2, text='She waves.')]))
                    with patch.object(e.gemini_adapter, 'video_interaction', return_value=response) as call, \
                         patch.object(e, 'reusable_video', return_value=Mock(uri='files/video', mime_type='video/mp4')), \
                         patch.object(e, 'ensure_supported_local_video'), patch.object(e, 'emit'):
                        if ranged:
                            e.reanalyze_segment(Path(folder), project, dict(start=1, end=2, text=''))
                        else:
                            e._ai_video_once(Path(folder), project, 'generate-ad-cues')
                    self.assertEqual(call.call_args.args[1], 'youtube-visual' if source == 'youtube' and audio == 'youtube' else 'local-visual')
                    self.assertEqual(call.call_args.args[2], project['youtubeURL'] if source == 'youtube' else 'files/video')
                    self.assertIn('DESCRIPTION TASK INSTRUCTIONS', call.call_args.args[5])
                    self.assertIn('She waves.', project['cues'][0]['text'])

    def test_full_transcription_passes_selected_model_to_correct_adapter(self):
        for audio in ('youtube', 'imported'):
            with self.subTest(audio=audio), tempfile.TemporaryDirectory() as folder:
                project = self.project(audio=audio)
                rows = [dict(start=0, end=1, text='Hello')]
                with patch.object(e.audio_sources, 'transcribe', return_value=rows) as audio_call, \
                     patch.object(e.gemini_adapter, 'video_interaction', return_value=json.dumps(dict(transcript=rows))) as video_call, \
                     patch.object(e, 'emit'):
                    e._ai_video_once(Path(folder), project, 'transcribe')
                if audio == 'imported':
                    self.assertEqual(audio_call.call_args.args[3], 'local-speech')
                    video_call.assert_not_called()
                else:
                    self.assertEqual(video_call.call_args.args[1], 'youtube-visual')
                    audio_call.assert_not_called()

    def test_range_transcription_matches_local_file_models_and_fallback(self):
        for speech_model in ('local-speech', 'gemini-special-transcribe'):
            self.cfg['models']['transcript'] = speech_model
            expected = 'youtube-visual' if 'transcribe' in speech_model else speech_model
            for source in ('upload', 'youtube'):
                with self.subTest(model=speech_model, source=source), tempfile.TemporaryDirectory() as folder:
                    project = self.project(source, 'imported')
                    uploaded = SimpleNamespace(uri='files/audio', mime_type='audio/wav')
                    response = json.dumps(dict(transcript=[dict(start=1, end=2, text='Hello')]))
                    with patch.object(e.audio_sources, 'upload_range', return_value=contextlib.nullcontext(uploaded)), \
                         patch.object(e, 'reusable_video', return_value=SimpleNamespace(uri='files/video', mime_type='video/mp4')), \
                         patch.object(e.gemini_adapter, 'audio_interaction', return_value=response) as audio_call, \
                         patch.object(e.gemini_adapter, 'video_interaction', return_value=response) as video_call, \
                         patch.object(e, 'emit'):
                        e.reanalyze_transcript_segment(Path(folder), project, dict(start=1, end=2, text=''))
                    call = audio_call if source == 'youtube' else video_call
                    self.assertEqual(call.call_args.args[1], expected)
                    (video_call if source == 'youtube' else audio_call).assert_not_called()

    def test_missing_or_speech_only_youtube_model_fails_before_client_creation(self):
        for model in ('', 'gemini-3.5-transcribe', 'gemini-flash-tts'):
            with self.subTest(model=model):
                self.cfg['models']['youtube_transcript'] = model
                e.gemini_client.reset_mock()
                with self.assertRaisesRegex(ValueError, 'Choose a .*model'):
                    e.client_and_model('audio_descriptions', self.project())
                e.gemini_client.assert_not_called()


if __name__ == '__main__':
    unittest.main()
