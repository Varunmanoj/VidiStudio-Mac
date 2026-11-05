"""Exercise the real request adapter and retry boundary without service access."""
import copy
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch
from test_engine import engine as e


class VideoProcessing(unittest.TestCase):
    def test_default_request_and_bundled_settings_use_agentic(self):
        import json
        defaults = json.loads(Path(e.__file__).with_name('ai-defaults.json').read_text())
        self.assertEqual(defaults['videoProcessing'], 'agentic')
        client = Mock()
        client.interactions.create.return_value = dict(output_text='Summary')
        e.gemini_adapter.video_interaction(client, 'model', 'files/video', 'video/mp4', 'Summarize')
        self.assertEqual(client.interactions.create.call_args.kwargs['input'][0]['processing'], 'agentic')

    def test_legacy_mode_reaches_summary_and_descriptions_as_static_for_both_sources(self):
        for source in ('upload', 'youtube'):
            for stage in ('generate-summary', 'generate-ad-cues'):
                with self.subTest(source=source, stage=stage), tempfile.TemporaryDirectory() as folder:
                    cfg = copy.deepcopy(e.config())
                    cfg['videoProcessing'] = 'standard'
                    project = dict(sourceType=source, source='video.mp4', youtubeURL='https://youtu.be/abcdefghijk',
                                   duration=10, transcript=[dict(start=0, end=1, text='Hello')],
                                   summary='Existing summary', cues=[])
                    transcript = copy.deepcopy(project['transcript'])
                    client = Mock()
                    def respond(**args):
                        self.assertEqual(args['input'][0]['processing'], 'static')
                        self.assertIn('Hello', args['input'][1]['text'])
                        self.assertEqual(args['input'][0]['uri'], project['youtubeURL'] if source == 'youtube' else 'files/video')
                        return dict(output_text='# Summary' if stage == 'generate-summary' else '{"audioDescriptions":[]}')
                    client.interactions.create.side_effect = respond
                    with patch.object(e, 'config', return_value=cfg), \
                         patch.object(e, 'client_and_model', return_value=(client, 'video-model')), \
                         patch.object(e, 'reusable_video', return_value=SimpleNamespace(uri='files/video', mime_type='video/mp4')), \
                         patch.object(e, 'ensure_supported_local_video'), patch.object(e, 'emit'):
                        e.ai_video(Path(folder), project, stage)
                    self.assertEqual(project['transcript'], transcript)
                    client.interactions.create.assert_called_once()
                    client.close.assert_called_once()
                    self.assertEqual(cfg['videoProcessing'], 'standard')

    def test_supported_modes_and_range_options_are_preserved(self):
        for mode in ('static', 'agentic', None, '', dict(type='static', start_offset='2s', end_offset='8s', fps=4)):
            with self.subTest(mode=mode):
                client = Mock()
                client.interactions.create.return_value = dict(output_text='Result')
                e.gemini_adapter.video_interaction(client, 'video-model', 'files/video', 'video/mp4', 'Prompt', processing=mode)
                media = client.interactions.create.call_args.kwargs['input'][0]
                self.assertEqual(media.get('processing'), mode if mode else None)

    def test_invalid_mode_is_rejected_before_network_and_without_retries(self):
        for mode in ('unsupported', dict(type='unsupported')):
            cfg = copy.deepcopy(e.config()); cfg['videoProcessing'] = mode
            project = dict(sourceType='youtube', youtubeURL='https://youtu.be/abcdefghijk', summary='Saved', transcript=[])
            before = copy.deepcopy(project)
            client = Mock()
            with self.subTest(mode=mode), patch.object(e, 'config', return_value=cfg), \
                 patch.object(e, 'client_and_model', return_value=(client, 'model')), \
                 patch.object(e, 'emit'), patch.object(e.time, 'sleep') as sleep:
                with self.assertRaisesRegex(ValueError, 'supported video processing mode'):
                    e.ai_video(Path('.'), project, 'generate-summary')
                client.interactions.create.assert_not_called()
                client.close.assert_called_once()
                sleep.assert_not_called()
                self.assertEqual(project, before)

    def test_permanent_api_rejections_do_not_repeat_but_service_failures_retry(self):
        for status in (400, 401, 403, 404, 408, 429, 500, 503):
            error = RuntimeError('Provider rejected request'); error.status_code = status
            retryable = status in (408, 429, 500, 503)
            with self.subTest(status=status), patch.object(e, '_ai_video_once', side_effect=error) as request, \
                 patch.object(e, 'emit'), patch.object(e.time, 'sleep') as sleep:
                with self.assertRaises(Exception): e.ai_video(Path('.'), {}, 'generate-summary')
                self.assertEqual(request.call_count, 3 if retryable else 1)
                self.assertEqual(sleep.call_count, 2 if retryable else 0)

    def test_google_error_code_is_respected(self):
        error = RuntimeError('Invalid enum value'); error.code = 400
        self.assertFalse(e.is_retryable_ai_error(error))
        self.assertFalse(e.is_retryable_ai_error(ValueError('400 INVALID_ARGUMENT')))

    def test_windows_key_check_preserves_selected_processing_mode(self):
        if not (Path(e.__file__).parents[1] / 'Vidi Studio Windows').exists():
            self.skipTest('Windows key-check selection policy')
        for mode, expected in [('static', 'static'), ('agentic', 'agentic'), ('standard', 'static')]:
            cfg = {'apiKey': 'mock-key', 'videoProcessing': mode}
            client = Mock()
            client.models.list.return_value = [SimpleNamespace(name='models/gemini-3.8-pro', display_name='Pro', supported_actions=['generateContent'])]
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as folder, \
                 patch.dict(e.os.environ, {'VIDISTUDIO_CONFIG': str(Path(folder)/'config.json')}), \
                 patch.object(e, 'config', return_value=cfg), patch.object(e, 'gemini_client', return_value=client), patch.object(e, 'emit') as emit:
                e.check_api_key()
                self.assertEqual(emit.call_args.kwargs['selectedVideoProcessing'], expected)
