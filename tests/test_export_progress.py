"""Real media progress, packaged CLI events, and bounded worker cleanup."""
import json
import os
import subprocess
import sys
import unittest
from unittest.mock import patch

from test_engine import engine, ENGINE
import test_export_formats as fixtures


class ExportProgress(unittest.TestCase):
    setUp = fixtures.ExportFormats.setUp

    def test_encoding_emits_intermediate_media_time_and_drains_verbose_errors(self):
        events = []
        with patch.object(engine, 'emit', side_effect=lambda message, **values: events.append(values)):
            engine.run_export([engine.tool('ffmpeg'), '-v', 'error', '-re', '-i', self.root/'source/video.mp4',
                               '-vn', self.root/'paced.wav'], 2, start=0.25, end=0.92)
        fractions = [event['exportProgress'] for event in events]
        self.assertEqual(fractions[0], 0.25)
        self.assertEqual(fractions[-1], 0.92)
        self.assertTrue(any(0.25 < value < 0.90 for value in fractions), fractions)
        self.assertEqual(fractions, sorted(fractions))
        with self.assertRaises(ValueError):
            engine.run_export([engine.tool('ffmpeg'), '-loglevel', 'debug', '-i', self.root/'missing.mp4',
                               self.root/'bad.wav'], 2, timeout=5)
        with self.assertRaises(subprocess.TimeoutExpired):
            engine.run_export([engine.tool('ffmpeg'), '-v', 'error', '-re', '-i', self.root/'source/video.mp4',
                               '-vn', self.root/'timed-out.wav'], 2, timeout=0.3)

    def test_packaged_video_audio_and_web_progress_precedes_completion(self):
        (self.root/'project.json').write_text(json.dumps(self.project))
        prefix = [os.environ['VIDISTUDIO_TEST_ENGINE']] if os.environ.get('VIDISTUDIO_TEST_ENGINE') else [sys.executable, str(ENGINE)]
        for args in (
            ['export-closed-caption-video', '--media-format', 'mkv'],
            ['export-original-audio', '--media-format', 'wav'],
            ['export-hls', '--web-audio', 'original'],
        ):
            with self.subTest(command=args[0]):
                result = subprocess.run([*prefix, *args, '--content', 'transcript', '--project', str(self.root)], capture_output=True, text=True,
                                        env=os.environ | {'VIDISTUDIO_CONFIG': str(self.root/'settings.json')}, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                events = [json.loads(line) for line in result.stdout.splitlines()]
                fractions = [event['exportProgress'] for event in events if 'exportProgress' in event]
                self.assertGreaterEqual(len(fractions), 4, events)
                self.assertTrue(all(0 <= value < 1 for value in fractions), fractions)
                self.assertEqual(fractions, sorted(fractions))
                self.assertEqual(fractions[-1], 0.99)
                self.assertEqual(events[-1]['progress'], 1)
                if args[0] == 'export-hls':
                    self.assertTrue(any('Packaging Web Playback' == event['message'] for event in events))
