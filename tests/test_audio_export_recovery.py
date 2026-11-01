"""Offer a replacement soundtrack for retrieval failures, never later export errors."""
import contextlib
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

from test_engine import engine
import audio_sources


class AudioExportRecovery(unittest.TestCase):
    def setUp(self):
        self.project = dict(sourceType='youtube', youtubeURL='https://youtu.be/abcdefghijk')
        self.core = SimpleNamespace(emit=Mock())

    def test_failed_download_marks_recovery_after_worker_cleanup(self):
        cleaned = Mock()

        @contextlib.contextmanager
        def failed(*args):
            try:
                raise ValueError('download blocked')
                yield
            finally:
                cleaned()

        with patch.object(audio_sources.youtube_audio, 'soundtrack', failed):
            with self.assertRaises(audio_sources.YouTubeAudioUnavailable) as error:
                with audio_sources.soundtrack(Path('.'), self.project, self.core):
                    self.fail('No soundtrack should be yielded')
        cleaned.assert_called_once()
        self.assertEqual(audio_sources.error_metadata(error.exception), {'recovery': 'choose-original-audio'})

    def test_worker_start_failure_offers_replacement(self):
        with patch.object(audio_sources.youtube_audio, 'soundtrack', side_effect=OSError('cannot start worker')):
            with self.assertRaises(audio_sources.YouTubeAudioUnavailable):
                with audio_sources.soundtrack(Path('.'), self.project, self.core):
                    self.fail('No soundtrack should be yielded')

    def test_mix_failure_is_not_a_download_failure_and_cleans_up(self):
        cleaned = Mock()

        @contextlib.contextmanager
        def downloaded(*args):
            try:
                yield Path('soundtrack.wav')
            finally:
                cleaned()

        with patch.object(audio_sources.youtube_audio, 'soundtrack', downloaded):
            with self.assertRaises(ValueError) as error:
                with audio_sources.soundtrack(Path('.'), self.project, self.core):
                    raise ValueError('encoder failed')
        self.assertEqual(audio_sources.error_metadata(error.exception), {})
        cleaned.assert_called_once()

    def test_cancellation_has_no_recovery_action(self):
        for cancelled in (engine.ProcessingCancelled('Cancelled'), RuntimeError('Processing cancelled.')):
            with self.subTest(type=type(cancelled)), patch.object(audio_sources.youtube_audio, 'soundtrack', side_effect=cancelled):
                with self.assertRaises(type(cancelled)) as error:
                    with audio_sources.soundtrack(Path('.'), self.project, self.core):
                        self.fail('Cancelled download must not continue')
                self.assertEqual(audio_sources.error_metadata(error.exception), {})

    def test_imported_source_does_not_download_or_offer_download_recovery(self):
        self.project['audioSources'] = dict(export='imported')
        with patch.object(audio_sources, 'original_path', return_value=Path('creator.wav')), \
             patch.object(audio_sources.youtube_audio, 'soundtrack') as download:
            with audio_sources.soundtrack(Path('.'), self.project, self.core) as source:
                self.assertEqual(source, Path('creator.wav'))
            download.assert_not_called()


if __name__ == '__main__':
    unittest.main()
