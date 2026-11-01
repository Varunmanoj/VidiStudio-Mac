"""Original audio is portable, explicitly approved, and never silently downloaded."""
import copy
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

from test_engine import engine as e
import audio_sources as sources
import import_assets


class AudioSources(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.file = self.root / 'creator soundtrack.wav'
        e.run([e.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi', '-i',
               'sine=frequency=440:sample_rate=48000', '-t', '2', self.file])
        self.project = dict(id='original-audio-test', name='Audio test', sourceType='youtube', source='',
            youtubeURL='https://youtu.be/abcdefghijk', duration=2, hasAudio=True, transcript=[], summary='',
            cues=[], exports=[], exportMediaInfo={}, thumbnails=[])
        e.save(self.root, self.project)
        self.core = SimpleNamespace(**vars(e))

    def args(self, command='import-original-audio', **changes):
        return SimpleNamespace(**(dict(command=command, input=self.file, project=self.root, output=None,
            replace_existing=False, allow_audio_mismatch=False, soundtrack_source=None,
            playback_audio_source=None, transcription_audio_source=None) | changes))

    def execute(self, command='import-original-audio', **changes):
        sources.execute(self.args(command, **changes), self.root, self.project, self.core)

    def test_timing_boundary_and_unknown(self):
        for duration in (1.9, 2, 2.1):
            self.assertEqual(sources.timing(duration, 2)['status'], 'matched')
        for duration in (1.8999, 2.1001):
            self.assertEqual(sources.timing(duration, 2)['status'], 'mismatch')
        for duration in (None, 0, float('nan'), float('inf')):
            self.assertEqual(sources.timing(2, duration)['status'], 'unverified')

    def test_inspection_does_not_mutate_project_or_import(self):
        before = (self.root / 'project.json').read_bytes()
        self.execute('inspect-original-audio', output=self.root/'inspection.json')
        self.assertEqual((self.root/'project.json').read_bytes(), before)
        self.assertFalse((self.root/'imports').exists())
        self.assertEqual(json.loads((self.root/'inspection.json').read_text())['status'], 'matched')

    def test_import_preserves_filename_and_independent_defaults(self):
        self.execute()
        asset = self.project['originalAudio']
        self.assertEqual(asset['sourceName'], self.file.name)
        self.assertTrue((self.root/asset['path']).is_file())
        self.assertFalse(Path(asset['path']).is_absolute())
        self.assertEqual(self.project['audioSources'], dict(export='imported', playback='youtube', transcription='youtube'))
        self.assertEqual(sources.fingerprint(self.file), asset['sha256'])
        loaded = json.loads((self.root/'project.json').read_text())
        self.assertEqual(loaded['originalAudio'], asset)

    def test_mismatch_blocks_then_explicit_approval_and_later_revalidation(self):
        self.project['duration'] = 3
        before = copy.deepcopy(self.project)
        with self.assertRaisesRegex(ValueError, 'confirmation'):
            self.execute()
        self.assertEqual(self.project, before)
        self.assertFalse((self.root/'imports').exists())
        self.execute(allow_audio_mismatch=True)
        self.assertFalse(sources.needs_confirmation(self.project['originalAudio'], 3))
        self.assertTrue(sources.needs_confirmation(self.project['originalAudio'], 4))
        self.project['duration'] = 4
        with self.assertRaisesRegex(ValueError, 'confirmation'):
            sources.original_path(self.root, self.project, self.core)
        self.execute('confirm-original-audio', input=None, allow_audio_mismatch=True)
        self.assertTrue(sources.original_path(self.root, self.project, self.core).is_file())

    def test_unknown_duration_requires_confirmation_then_checks_known_length(self):
        self.project['duration'] = 0
        with patch.object(sources.youtube_audio, 'video_duration', return_value=None):
            with self.assertRaisesRegex(ValueError, 'could not be verified'):
                self.execute()
            self.execute(allow_audio_mismatch=True)
        asset = self.project['originalAudio']
        self.assertIsNone(asset['confirmedVideoDuration'])
        self.assertFalse(sources.needs_confirmation(asset, 0))
        self.assertFalse(sources.needs_confirmation(asset, 2))
        self.assertTrue(sources.needs_confirmation(asset, 5))

    def test_metadata_lookup_does_not_use_audio_length_as_video_length(self):
        self.project['duration'] = 0
        with patch.object(sources.youtube_audio, 'video_duration', return_value=5):
            with self.assertRaisesRegex(ValueError, 'Video duration: 5.000'):
                self.execute()
        self.assertEqual(self.project['duration'], 0)

    def test_corrupt_audio_cannot_be_overridden_and_keeps_existing_asset(self):
        self.execute()
        before = copy.deepcopy(self.project)
        broken = self.root/'broken.mp3'; broken.write_bytes(b'not audio')
        with self.assertRaises(ValueError):
            self.execute(input=broken, replace_existing=True, allow_audio_mismatch=True)
        self.assertEqual(self.project, before)
        self.assertEqual(len(list((self.root/'imports').iterdir())), 1)

    def test_failure_to_commit_rolls_back_copied_file(self):
        with patch.object(self.core, 'save', side_effect=OSError('disk full')):
            with self.assertRaisesRegex(OSError, 'disk full'):
                self.execute()
        self.assertNotIn('originalAudio', self.project)
        self.assertFalse(list((self.root/'imports').iterdir()))

    def test_removal_keeps_external_file_and_resets_all_choices(self):
        self.execute(playback_audio_source='imported', transcription_audio_source='imported')
        self.execute('remove-original-audio', input=None)
        self.assertTrue(self.file.is_file())
        self.assertNotIn('originalAudio', self.project)
        self.assertEqual(self.project['audioSources'], sources.DEFAULTS)

    def test_changed_or_missing_copy_does_not_fall_back_to_youtube(self):
        self.execute()
        path = self.root/self.project['originalAudio']['path']
        path.write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'has changed'), patch.object(sources.youtube_audio, 'soundtrack') as download:
            with sources.soundtrack(self.root, self.project, self.core):
                pass
        download.assert_not_called()
        path.unlink()
        with self.assertRaisesRegex(ValueError, 'missing'):
            sources.original_path(self.root, self.project, self.core)

    def test_regeneration_and_cleanup_keep_imported_soundtrack(self):
        self.execute()
        asset = copy.deepcopy(self.project['originalAudio'])
        e.clear_generated(self.root, self.project)
        e.cleanup_project_storage(self.root, self.project)
        self.assertEqual(self.project['originalAudio'], asset)
        self.assertTrue((self.root/asset['path']).is_file())

    def test_original_export_all_formats_uses_file_and_records_source(self):
        self.execute()
        with patch.object(sources.youtube_audio, 'soundtrack', side_effect=AssertionError('must not download')):
            for format in ('wav', 'mp3', 'm4a'):
                e.export_youtube_audio(self.root, self.project, media_format=format)
                path = self.project['exports'][-1]
                e.validate_audio_export(self.root/path, 2, format)
                self.assertEqual(self.project['exportAudioSources'][path]['sourceName'], self.file.name)

    def test_accepted_short_and_long_files_preserve_video_duration(self):
        for duration in (1, 3):
            with self.subTest(duration=duration):
                self.project['duration'] = duration
                self.execute(replace_existing=True, allow_audio_mismatch=True)
                e.export_youtube_audio(self.root, self.project, media_format='wav', replace_existing=True)
                e.validate_audio_export(self.root/self.project['exports'][-1], duration, 'wav')

    def test_full_ad_mix_does_not_download_or_require_generated_narration(self):
        self.project['importedAudioDescription'] = dict(path=self.file.name, sourceName='full mix.wav', duration=2, mode='fullMix')
        with patch.object(sources.youtube_audio, 'soundtrack', side_effect=AssertionError('must not download')):
            e.export_youtube_audio(self.root, self.project, described=True, ad_source='imported', media_format='wav')
        path = self.project['exports'][-1]
        self.assertEqual(self.project['exportAudioSources'][path]['origin'], 'importedAD')
        e.validate_audio_export(self.root/path, 2, 'wav')

    def test_imported_ad_narration_combines_with_chosen_original(self):
        self.execute()
        self.project['importedAudioDescription'] = dict(path=self.file.name, sourceName='narration.wav', duration=2, mode='narration')
        with patch.object(sources.youtube_audio, 'soundtrack', side_effect=AssertionError('must not download')):
            e.export_youtube_audio(self.root, self.project, described=True, ad_source='imported', media_format='wav')
        e.validate_audio_export(self.root/self.project['exports'][-1], 2, 'wav')

    def test_full_transcription_routes_audio_and_records_actual_source(self):
        self.execute(transcription_audio_source='imported')
        client = Mock()
        with patch.object(e, 'client_and_model', return_value=(client, 'gemini-test-transcribe')) as model, \
             patch.object(e.gemini_adapter, 'transcribe_audio', return_value=[dict(start=0, end=1, text='नमस्ते Hello')]) as transcribe, \
             patch.object(e.gemini_adapter, 'video_interaction', side_effect=AssertionError('must use audio')):
            e._ai_video_once(self.root, self.project, 'transcribe')
        model.assert_called_once()
        self.assertEqual(model.call_args.args[0], 'transcript')
        transcribe.assert_called_once()
        self.assertEqual(self.project['transcriptAudioSource']['sourceName'], self.file.name)
        self.assertEqual(self.project['transcript'][0]['text'], 'नमस्ते Hello')
        client.close.assert_called_once()

    def test_range_transcription_uses_audio_and_cleans_up_upload(self):
        self.execute(transcription_audio_source='imported')
        client = Mock()
        uploaded = SimpleNamespace(uri='files/test-audio', mime_type='audio/wav', name='test-audio')
        with patch.object(e, 'client_and_model', return_value=(client, 'general-model')), \
             patch.object(e.gemini_adapter, 'ready_file', return_value=uploaded), \
             patch.object(e.gemini_adapter, 'audio_interaction', return_value=json.dumps(dict(transcript=[dict(start=0, end=1, text='Hello')]))), \
             patch.object(e.gemini_adapter, 'video_interaction', side_effect=AssertionError('must use audio')):
            e.reanalyze_transcript_segment(self.root, self.project, dict(start=0, end=1, text=''))
        client.files.delete.assert_called_once_with(name='test-audio')
        self.assertEqual(self.project['transcriptAudioSource']['origin'], 'imported')

    def test_source_preferences_do_not_rewrite_existing_results(self):
        self.execute()
        self.project['transcript'] = [dict(start=0, end=1, text='Existing')]
        self.project['transcriptAudioSource'] = dict(origin='youtube')
        self.project['exportAudioSources'] = {'old.mp3': dict(origin='youtube')}
        before = copy.deepcopy(self.project)
        self.execute('set-audio-sources', input=None, transcription_audio_source='imported')
        for field in ('transcript', 'transcriptAudioSource', 'exportAudioSources'):
            self.assertEqual(self.project[field], before[field])

    def test_confirmation_is_bound_to_reviewed_file_and_video_timing(self):
        for changes in (dict(expected_audio_sha256='a different file'), dict(expected_video_duration=9)):
            with self.subTest(changes=changes), self.assertRaisesRegex(ValueError, 'changed during review'):
                self.execute(allow_audio_mismatch=True, **changes)
            self.assertNotIn('originalAudio', self.project)

    def test_generated_description_mixes_with_chosen_original(self):
        self.execute()
        self.project['cues'] = [dict(id='ad', start=0, end=2, text='A description', audio=self.file.name,
            audioText='A description', audioDuration=2, audioStart=0, audioEnd=2)]
        with patch.object(sources.youtube_audio, 'soundtrack', side_effect=AssertionError('must not download')):
            e.export_youtube_audio(self.root, self.project, described=True, media_format='wav')
        e.validate_audio_export(self.root/self.project['exports'][-1], 2, 'wav')

    def test_mixed_transcript_sources_are_not_relabelled_as_one_file(self):
        imported = dict(origin='imported', sourceName=self.file.name, sha256='a')
        rows = [dict(text='YouTube row'), dict(text='File row', transcriptionAudioSource=imported)]
        self.assertEqual(sources.transcript_source_summary(rows)['origin'], 'mixed')
        self.assertEqual(sources.transcript_source_summary(rows[1:]), imported)

    def test_audio_with_cover_art_is_usable(self):
        cover = self.root/'cover.png'
        e.run([e.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi', '-i', 'color=c=blue:s=16x16', '-frames:v', '1', '-update', '1', cover])
        audio = self.root/'soundtrack with art.mp3'
        e.run([e.tool('ffmpeg'), '-y', '-v', 'error', '-i', self.file, '-i', cover, '-map', '0:a:0',
               '-map', '1:v:0', '-c:a', 'libmp3lame', '-c:v', 'copy', '-disposition:v', 'attached_pic', audio])
        self.execute(input=audio)
        e.export_youtube_audio(self.root, self.project, media_format='wav')
        e.validate_audio_export(self.root/self.project['exports'][-1], 2, 'wav')

    def test_metadata_lookup_never_downloads_and_keeps_only_duration(self):
        output = self.root/'metadata.json'
        with patch('yt_dlp.YoutubeDL') as provider:
            downloader = provider.return_value.__enter__.return_value
            downloader.extract_info.return_value = dict(duration=2, title='Video', url='https://private.invalid/?token=secret')
            sources.youtube_audio.read_metadata('https://youtu.be/abcdefghijk', output)
            downloader.extract_info.assert_called_once_with('https://www.youtube.com/watch?v=abcdefghijk', download=False)
            downloader.process_info.assert_not_called()
        self.assertEqual(json.loads(output.read_text()), dict(duration=2))

    def test_metadata_timeout_kills_worker_and_returns_unverified(self):
        process = Mock(); process.poll.return_value = None
        with patch.object(sources.youtube_audio.subprocess, 'Popen', return_value=process), \
             patch.object(sources.youtube_audio, 'stop_worker') as stop, \
             patch.object(sources.youtube_audio.time, 'monotonic', side_effect=[0, 46]):
            self.assertIsNone(sources.youtube_audio.video_duration('https://youtu.be/abcdefghijk', Mock()))
        stop.assert_called_once_with(process)

    def test_imported_full_mix_can_get_video_duration_without_ai(self):
        self.project['duration'] = 0
        self.project['importedAudioDescription'] = dict(path=self.file.name, sourceName='full mix.wav', duration=2, mode='fullMix')
        with patch.object(sources.youtube_audio, 'video_duration', return_value=2), \
             patch.object(sources.youtube_audio, 'soundtrack', side_effect=AssertionError('must not download')):
            e.export_youtube_audio(self.root, self.project, described=True, ad_source='imported', media_format='wav')
        self.assertEqual(self.project['duration'], 2)


if __name__ == '__main__':
    unittest.main()
