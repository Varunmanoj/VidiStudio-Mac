import array
import contextlib
import math
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from types import SimpleNamespace

from test_engine import engine
import youtube_audio
import audio_sources
from yt_dlp.utils import DownloadError


class YouTubeAudio(unittest.TestCase):
    def test_saved_extraction_is_reused_after_reopen_move_cleanup_and_failed_mix(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'project'
            root.mkdir()
            source = Path(temp) / 'download.wav'
            engine.run([engine.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi',
                        '-i', 'sine=frequency=440', '-t', '1.5', source])
            project = dict(name='Cached', sourceType='youtube', youtubeURL='https://youtu.be/abcdefghijk',
                           duration=1.5, transcript=[], cues=[], exports=[])
            calls = Mock()

            @contextlib.contextmanager
            def download(*args):
                calls()
                yield source

            with patch.object(youtube_audio, 'soundtrack', download):
                with patch.object(engine, 'run_export', side_effect=ValueError('encoder failed')):
                    with self.assertRaisesRegex(ValueError, 'encoder failed'):
                        engine.export_youtube_audio(root, project)
                source.unlink()  # The temporary download is no longer available.
                engine.cleanup_project_storage(root, project)
                engine.save(root, project)
                moved = Path(temp) / 'moved'
                shutil.move(root, moved)
                import json
                reopened = json.loads((moved / 'project.json').read_text())
                # Equivalent links refer to the same saved extraction.
                reopened['youtubeURL'] = 'https://www.youtube.com/watch?v=abcdefghijk'
                engine.export_youtube_audio(moved, reopened)
                engine.export_youtube_audio(moved, reopened, replace_existing=True, media_format='wav')
                engine.validate_audio_export(moved / reopened['exports'][-1], 1.5, 'wav')
            calls.assert_called_once()

    def test_missing_corrupt_or_different_video_audio_is_downloaded_again(self):
        for damage in ('missing', 'corrupt', 'manifest', 'different-video'):
            with self.subTest(damage=damage), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                source = root / 'download.wav'
                engine.run([engine.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi',
                            '-i', 'sine=frequency=440', '-t', '0.5', source])
                project = dict(youtubeURL='https://youtu.be/abcdefghijk')
                core = SimpleNamespace(**vars(engine))
                calls = Mock()

                @contextlib.contextmanager
                def download(*args):
                    calls()
                    yield source

                with patch.object(youtube_audio, 'soundtrack', download):
                    with audio_sources.youtube_soundtrack(root, project, core) as saved:
                        self.assertNotEqual(saved, source)
                    if damage == 'missing': saved.unlink()
                    elif damage == 'corrupt': saved.write_bytes(b'broken')
                    elif damage == 'manifest': saved.with_suffix('.json').write_text('{}')
                    else: project['youtubeURL'] = 'https://youtu.be/01234567890'
                    with audio_sources.youtube_soundtrack(root, project, core) as repaired:
                        self.assertEqual(repaired.read_bytes(), source.read_bytes())
                self.assertEqual(calls.call_count, 2)

    def test_invalid_or_cancelled_extraction_is_never_cached(self):
        for cancelled in (False, True):
            with self.subTest(cancelled=cancelled), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                source = root / 'bad.wav'
                source.write_bytes(b'not audio')

                @contextlib.contextmanager
                def download(*args):
                    if cancelled: raise engine.ProcessingCancelled('Cancelled')
                    yield source

                with patch.object(youtube_audio, 'soundtrack', download):
                    with self.assertRaises(engine.ProcessingCancelled if cancelled else ValueError):
                        with audio_sources.youtube_soundtrack(root, dict(youtubeURL='https://youtu.be/abcdefghijk'), SimpleNamespace(**vars(engine))):
                            self.fail('Invalid extraction must not be used')
                self.assertFalse(list(root.glob('youtube-audio/**/soundtrack.json')))

    def test_youtube_audio_only_needs_no_narration_or_generated_duration(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root/'original.wav'
            engine.run([engine.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi',
                        '-i', 'sine=frequency=440:sample_rate=48000', '-t', '1.5', source])
            project = dict(name='YouTube Original', sourceType='youtube', source='',
                           youtubeURL='https://youtu.be/abcdefghijk', duration=0,
                           transcript=[], cues=[], exports=[])

            @contextlib.contextmanager
            def soundtrack(*args):
                yield source

            with patch.object(youtube_audio, 'soundtrack', soundtrack), \
                 patch.object(engine, 'exportable_narration_cues', side_effect=AssertionError('Narration not needed')):
                engine.export_youtube_audio(root, project)
                self.assertEqual(project['exports'], ['exports/auto/YouTube Original - YouTube Audio Only.mp3'])
                output = root/project['exports'][0]
                engine.validate_audio_export(output, 1.5)
                pcm = subprocess.check_output([engine.tool('ffmpeg'), '-v', 'error', '-i', str(output),
                                               '-f', 'f32le', '-ac', '1', '-ar', '48000', '-'])
                samples = array.array('f', pcm)[4800:19200]
                rms = math.sqrt(sum(value*value for value in samples)/len(samples))
                self.assertGreater(rms, .08)
                before = output.read_bytes()
                with self.assertRaisesRegex(ValueError, 'Confirm replacement'):
                    engine.export_youtube_audio(root, project)
                self.assertEqual(output.read_bytes(), before)
                self.assertFalse(list((root/'exports').glob('.*generating*')))
                project['duration'] = 100
                engine.export_youtube_audio(root, project, replace_existing=True)
                engine.validate_audio_export(output, 1.5)

    def test_prefers_original_audio_over_a_higher_quality_dub(self):
        original = dict(format_id='original', vcodec='none', acodec='opus', format_note='English original')
        dub = dict(format_id='dub', vcodec='none', acodec='opus', format_note='Hindi dubbed')
        video = dict(format_id='video', vcodec='h264', acodec='aac')
        self.assertEqual(list(youtube_audio.original_audio_format({'formats': [original, dub, video]})), [original])

    def test_download_does_not_expose_signed_urls_or_use_browser_credentials(self):
        downloader = Mock()
        downloader.extract_info.side_effect = RuntimeError('403 https://stream.invalid/?token=private')
        with tempfile.TemporaryDirectory() as directory, patch('yt_dlp.YoutubeDL') as provider:
            provider.return_value.__enter__.return_value = downloader
            with self.assertRaises(ValueError) as error:
                youtube_audio.download('https://youtu.be/abcdefghijk', directory, Mock())
            self.assertNotIn('token=', str(error.exception))
            options = provider.call_args.args[0]
            self.assertFalse(options['cachedir'])
            self.assertNotIn('cookiesfrombrowser', options)
            self.assertNotIn('cookiefile', options)
            self.assertFalse(options['remote_components'])

    def test_rejects_live_or_restricted_videos_before_downloading(self):
        for info in ({'is_live': True}, {'availability': 'private'}, {'_type': 'playlist'}):
            with self.subTest(info=info), tempfile.TemporaryDirectory() as directory, \
                 patch('yt_dlp.YoutubeDL') as provider, patch.object(youtube_audio.time, 'sleep') as sleep:
                downloader = provider.return_value.__enter__.return_value
                downloader.extract_info.return_value = info
                with self.assertRaises(ValueError):
                    youtube_audio.download('https://youtu.be/abcdefghijk', directory, Mock())
                downloader.process_info.assert_not_called()
                self.assertEqual(provider.call_count, 1)
                sleep.assert_not_called()

    def test_full_download_retries_refresh_streams_and_discard_failed_outputs(self):
        for failure in ('extraction', 'download', 'missing', 'empty'):
            for failures in (0, 1, 2):
                with self.subTest(failure=failure, failures=failures), tempfile.TemporaryDirectory() as directory:
                    attempts = []

                    def provider(options):
                        destination = Path(options['outtmpl'].replace('%(ext)s', 'webm'))
                        self.assertTrue(all(not path.exists() for path in attempts))
                        attempts.append(destination.parent)
                        downloader = Mock()
                        downloader.extract_info.return_value = {'availability': 'public'}
                        if len(attempts) <= failures and failure == 'extraction':
                            downloader.extract_info.side_effect = DownloadError('403 https://stream.invalid/?token=private')

                        def process(info):
                            if len(attempts) <= failures:
                                destination.with_suffix('.part').write_bytes(b'partial')
                                if failure == 'download':
                                    destination.write_bytes(b'stale output')
                                    raise DownloadError('connection lost')
                                if failure == 'empty':
                                    destination.touch()
                            else:
                                destination.write_bytes(b'complete soundtrack')

                        downloader.process_info.side_effect = process
                        manager = Mock()
                        manager.__enter__ = Mock(return_value=downloader)
                        manager.__exit__ = Mock(return_value=False)
                        return manager

                    emit = Mock()
                    with patch('yt_dlp.YoutubeDL', side_effect=provider) as factory, \
                         patch.object(youtube_audio.time, 'sleep') as sleep:
                        youtube_audio.download('https://youtu.be/abcdefghijk', directory, emit)
                    self.assertEqual(factory.call_count, failures + 1)
                    self.assertEqual([call.args[0] for call in sleep.call_args_list], [2, 4][:failures])
                    self.assertEqual((Path(directory)/'soundtrack.webm').read_bytes(), b'complete soundtrack')
                    self.assertEqual([item.name for item in Path(directory).iterdir()], ['soundtrack.webm'])
                    self.assertEqual(len(emit.call_args_list), failures)
                    for attempt, event in enumerate(emit.call_args_list, start=2):
                        self.assertIn(f'attempt {attempt} of 3', event.args[0])
                        self.assertNotIn('token=', event.args[0])
                        self.assertIsNone(event.kwargs['exportProgress'])

    def test_failed_download_stops_after_three_attempts_with_safe_error(self):
        with tempfile.TemporaryDirectory() as directory, patch('yt_dlp.YoutubeDL') as provider, \
             patch.object(youtube_audio.time, 'sleep') as sleep:
            downloader = provider.return_value.__enter__.return_value
            downloader.extract_info.side_effect = DownloadError('403 https://stream.invalid/?token=private')
            emit = Mock()
            with self.assertRaises(ValueError) as error:
                youtube_audio.download('https://youtu.be/abcdefghijk', directory, emit)
            self.assertEqual(str(error.exception), youtube_audio.DOWNLOAD_ERROR)
            self.assertEqual(provider.call_count, 3)
            self.assertEqual(sleep.call_count, 2)
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_audio_size_limit_does_not_retry(self):
        with tempfile.TemporaryDirectory() as directory, patch('yt_dlp.YoutubeDL') as provider, \
             patch.object(youtube_audio.time, 'sleep') as sleep:
            downloader = provider.return_value.__enter__.return_value
            downloader.extract_info.return_value = {'availability': 'public'}

            def process(info):
                options = provider.call_args.args[0]
                options['progress_hooks'][0]({'status': 'downloading', 'downloaded_bytes': youtube_audio.MAX_AUDIO_BYTES + 1})

            downloader.process_info.side_effect = process
            with self.assertRaises(ValueError):
                youtube_audio.download('https://youtu.be/abcdefghijk', directory, Mock())
            self.assertEqual(provider.call_count, 1)
            sleep.assert_not_called()

    def test_cancelling_retry_wait_starts_no_further_attempt(self):
        with tempfile.TemporaryDirectory() as directory, patch('yt_dlp.YoutubeDL') as provider, \
             patch.object(youtube_audio.time, 'sleep', side_effect=engine.ProcessingCancelled('Cancelled')):
            downloader = provider.return_value.__enter__.return_value
            downloader.extract_info.side_effect = DownloadError('connection lost')
            with self.assertRaises(engine.ProcessingCancelled):
                youtube_audio.download('https://youtu.be/abcdefghijk', directory, Mock())
            self.assertEqual(provider.call_count, 1)
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_invalid_url_starts_no_worker(self):
        with patch.object(youtube_audio.subprocess, 'Popen') as popen:
            with self.assertRaises(ValueError):
                with youtube_audio.soundtrack('https://example.com/file', Mock()):
                    pass
            popen.assert_not_called()

    def test_timeout_and_cancellation_stop_worker_and_remove_download(self):
        real_popen = subprocess.Popen
        for cancelled in (False, True):
            captured = {}

            def start(command, **kwargs):
                directory = Path(command[-1])
                (directory/'soundtrack.part').write_bytes(b'incomplete')
                captured['directory'] = directory
                process = real_popen([sys.executable, '-c', 'import time; time.sleep(60)'], **kwargs)
                captured['process'] = process
                return process

            with patch.object(youtube_audio.subprocess, 'Popen', side_effect=start), \
                 patch.object(youtube_audio, 'DOWNLOAD_TIMEOUT', 0):
                expected = engine.ProcessingCancelled if cancelled else ValueError
                with patch.object(youtube_audio.time, 'monotonic', side_effect=
                                  [0, engine.ProcessingCancelled('Cancelled')] if cancelled else [0, 1]):
                    with self.assertRaises(expected):
                        with youtube_audio.soundtrack('https://youtu.be/abcdefghijk', Mock()):
                            pass
            process = captured['process']
            self.assertIsNotNone(process.poll())
            self.assertFalse(captured['directory'].exists())

    def test_complete_mix_retains_original_audio_and_times_narration(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'audio-description').mkdir()
            source = root/'original.wav'
            narration = root/'audio-description/cue.wav'
            engine.run([engine.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi',
                        '-i', 'sine=frequency=440:sample_rate=48000', '-t', '3', source])
            engine.run([engine.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi',
                        '-i', 'sine=frequency=880:sample_rate=48000', '-t', '0.5', narration])
            project = dict(name='YouTube Demo', sourceType='youtube', source='',
                           youtubeURL='https://youtu.be/abcdefghijk', duration=3, hasAudio=True,
                           transcript=[], exports=[], cues=[dict(id='ad', start=1, end=1.6,
                           text='A shape appears.', audio='audio-description/cue.wav', audioText='A shape appears.')])
            downloads = Mock()

            @contextlib.contextmanager
            def soundtrack(*args):
                downloads()
                yield source

            with patch.object(youtube_audio, 'soundtrack', soundtrack):
                engine.export_youtube_described_audio(root, project)
                output = root/project['exports'][0]
                engine.validate_audio_export(output, 3)
                data = subprocess.check_output([engine.tool('ffmpeg'), '-v', 'error', '-i', str(output),
                                                '-f', 'f32le', '-ac', '1', '-ar', '48000', '-'])
                samples = array.array('f', data)

                def amplitude(frequency, start, end):
                    segment = samples[round(start*48000):round(end*48000)]
                    real = sum(value*math.cos(2*math.pi*frequency*i/48000) for i, value in enumerate(segment))
                    imag = sum(value*math.sin(2*math.pi*frequency*i/48000) for i, value in enumerate(segment))
                    return 2*math.hypot(real, imag)/len(segment)

                original_before = amplitude(440, .2, .7)
                original_during = amplitude(440, 1.1, 1.4)
                self.assertGreater(original_before, .08)
                self.assertAlmostEqual(original_during/original_before, .2, delta=.05)
                self.assertGreater(amplitude(880, 1.1, 1.4), .08)
                self.assertLess(amplitude(880, .2, .7), .002)
                # Narration can be regenerated and exported in another format
                # using the same project soundtrack, without another extraction.
                engine.run([engine.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi',
                            '-i', 'sine=frequency=990:sample_rate=48000', '-t', '0.5', narration])
                engine.export_youtube_described_audio(root, project, media_format='wav')
                engine.validate_audio_export(root/project['exports'][-1], 3, 'wav')
                downloads.assert_called_once()
                before = output.read_bytes()
                with self.assertRaisesRegex(ValueError, 'Confirm replacement'):
                    engine.export_youtube_described_audio(root, project)
                project['duration'] = 6
                with self.assertRaisesRegex(ValueError, 'duration does not match'):
                    engine.export_youtube_described_audio(root, project, replace_existing=True)
                self.assertEqual(output.read_bytes(), before)
                self.assertFalse(list((root/'exports').glob('.*generating*')))
                project['duration'] = 3
                project['cues'][0]['audioText'] = 'Old narration'
                with patch.object(youtube_audio, 'soundtrack') as download:
                    with self.assertRaisesRegex(ValueError, 'missing or outdated'):
                        engine.export_youtube_described_audio(root, project, replace_existing=True)
                    download.assert_not_called()


if __name__ == '__main__':
    unittest.main()
