import contextlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path
from unittest.mock import patch

from test_engine import engine, ENGINE
import youtube_audio


class ExportFormats(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='vidistudio-format-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root/'source').mkdir()
        (self.root/'audio-description').mkdir()
        engine.run([engine.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi',
                    '-i', 'testsrc2=size=192x108:rate=24', '-f', 'lavfi',
                    '-i', 'sine=frequency=440:sample_rate=48000', '-t', '2',
                    '-c:v', 'libx264', '-c:a', 'aac', self.root/'source/video.mp4'])
        engine.run([engine.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi',
                    '-i', 'sine=frequency=880:sample_rate=48000', '-t', '0.3',
                    self.root/'audio-description/narration.wav'])
        self.project = dict(name='Format Demo', sourceType='upload', source='source/video.mp4',
                            duration=2, width=192, height=108, hasAudio=True,
                            transcript=[dict(id='t', start=.2, end=.5, text='Hello.')],
                            cues=[dict(id='ad', start=1, end=1.5, text='A shape moves.',
                                       audioText='A shape moves.', audio='audio-description/narration.wav')],
                            exports=[])

    def test_local_audio_choices_encode_each_selected_format_and_replace_safely(self):
        for format in engine.AUDIO_EXPORT_FORMATS:
            for choice in ('original', 'described', 'narration'):
                with self.subTest(format=format, choice=choice):
                    if choice == 'narration':
                        engine.export(self.root, self.project, audio_only=True, media_format=format)
                    else:
                        engine.export_program_audio(self.root, self.project, described=choice == 'described', media_format=format)
                    path = self.root/self.project['exports'][-1]
                    self.assertEqual(path.suffix, '.' + format)
                    engine.validate_audio_export(path, 2, format)
        self.assertEqual(len(self.project['exports']), 9)
        output = self.root/'exports/Format Demo - Original Video Audio.wav'
        before = output.read_bytes()
        with self.assertRaisesRegex(ValueError, 'Confirm replacement'):
            engine.export_program_audio(self.root, self.project, media_format='wav')
        with patch.object(engine, 'run', side_effect=ValueError('encoder failed')):
            with self.assertRaisesRegex(ValueError, 'encoder failed'):
                engine.export_program_audio(self.root, self.project, media_format='wav', replace_existing=True)
        self.assertEqual(output.read_bytes(), before)
        self.assertFalse(list((self.root/'exports').glob('.*generating*')))

    def test_youtube_original_and_combined_accept_every_audio_format(self):
        soundtrack_path = self.root/'soundtrack.wav'
        engine.run([engine.tool('ffmpeg'), '-y', '-v', 'error', '-i', self.root/'source/video.mp4',
                    '-map', '0:a:0', soundtrack_path])
        project = deepcopy(self.project)
        project.update(sourceType='youtube', source='', youtubeURL='https://youtu.be/abcdefghijk')

        @contextlib.contextmanager
        def soundtrack(*args):
            yield soundtrack_path

        with patch.object(youtube_audio, 'soundtrack', soundtrack):
            for format in engine.AUDIO_EXPORT_FORMATS:
                for described in (False, True):
                    with self.subTest(format=format, described=described):
                        engine.export_youtube_audio(self.root, project, described=described, media_format=format)
                        path = self.root/project['exports'][-1]
                        self.assertEqual(path.suffix, '.' + format)
                        engine.validate_audio_export(path, 2, format)
        self.assertEqual(len(project['exports']), 6)

    def test_video_containers_preserve_selectable_tracks_and_open_caption_modes(self):
        for format in engine.VIDEO_EXPORT_FORMATS:
            for captions in ('none', 'closed', 'dual-closed', 'open'):
                with self.subTest(format=format, captions=captions):
                    engine.export(self.root, self.project, selectable=True, captions=captions, media_format=format)
                    path = self.root/self.project['exports'][-1]
                    self.assertEqual(path.suffix, '.' + format)
                    engine.validate_closed_audio_description_export(path, 2, captions)
                    if captions != 'open':
                        engine.validate_video_stream_copy(self.root/self.project['source'], path)
                    info = engine.probe(path)
                    self.assertIn('matroska' if format == 'mkv' else 'mov', info['format']['format_name'])
            engine.export(self.root, self.project, captions='dual-closed', media_format=format)
            engine.validate_captioned_video(self.root/self.project['exports'][-1], 2, 'dual-closed')
            engine.export_captioned_video(self.root, self.project, dual_closed=True, media_format=format)
            engine.validate_captioned_video(self.root/self.project['exports'][-1], 2, 'dual-closed')
            engine.export_captioned_video(self.root, self.project, open_captions=True, media_format=format)
            engine.validate_captioned_video(self.root/self.project['exports'][-1], 2, 'open')
        self.assertEqual(len(self.project['exports']), 28)

    def test_cli_selected_formats_reach_packaged_dispatch_and_reject_wrong_category(self):
        (self.root/'project.json').write_text(json.dumps(self.project))
        config = self.root/'settings.json'
        config.write_text('{}')
        env = os.environ | {'VIDISTUDIO_CONFIG': str(config)}
        prefix = ([os.environ['VIDISTUDIO_TEST_ENGINE']] if os.environ.get('VIDISTUDIO_TEST_ENGINE')
                  else [sys.executable, str(ENGINE)])
        for command, format, caption_args in (
            ('export-closed-audio-description-video', 'mkv', ['--captions', 'dual-closed']),
            ('export-open-audio-description-video', 'mp4', ['--captions', 'closed']),
            ('export-dual-closed-caption-video', 'mov', []),
            ('export-open-caption-video', 'm4v', []),
            ('export-audio', 'wav', []),
            ('export-original-audio', 'm4a', []),
            ('export-described-audio', 'mp3', []),
        ):
            with self.subTest(command=command, format=format):
                result = subprocess.run([*prefix, command, '--project', str(self.root),
                                         '--media-format', format, '--content', 'transcript', *caption_args],
                                        capture_output=True, text=True, env=env)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                project = json.loads((self.root/'project.json').read_text())
                self.assertTrue(project['exports'][-1].endswith('.' + format))
        for command, format in (('export-audio', 'mkv'), ('export-closed-caption-video', 'wav')):
            result = subprocess.run([*prefix, command, '--project', str(self.root), '--media-format', format],
                                    capture_output=True, text=True, env=env)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('supported export format', result.stdout)


if __name__ == '__main__':
    unittest.main()
