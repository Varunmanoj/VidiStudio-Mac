import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
ENGINE = [os.environ['VIDISTUDIO_TEST_ENGINE']] if os.environ.get('VIDISTUDIO_TEST_ENGINE') else [
    sys.executable, str(ROOT / 'engine' / 'vidistudio_engine.py')
]
URL = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'


@unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'FFmpeg and FFprobe are required')
class YouTubePlayback(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.project = self.directory / 'project'
        self.project.mkdir()
        self.original = self.directory / 'original.mp4'
        self.make_media('-f', 'lavfi', '-i', 'color=c=blue:s=160x96:r=24',
                               '-f', 'lavfi', '-i', 'sine=frequency=220:sample_rate=48000',
                               '-t', '4', '-c:v', 'libx264', '-c:a', 'aac', self.original)
        audio = self.project / 'audio-description' / 'voice.wav'
        audio.parent.mkdir()
        self.make_media('-f', 'lavfi', '-i', 'sine=frequency=660:sample_rate=48000',
                               '-t', '0.5', audio)
        self.manifest = self.project / 'project.json'
        self.write(dict(id='private-playback-fixture', name='Private video', schemaVersion=3,
                        source='', sourceType='youtube', youtubeURL=URL, duration=4.0, hasAudio=False,
                        youtubeMetadata=dict(visibility='private', channelID='fixture-channel'),
                        youtubePrivateChannelID='fixture-channel', exports=[], thumbnails=[],
                        transcript=[dict(id='t1', start=0, end=1, text='Hello.')],
                        cues=[dict(id='ad1', start=2, end=3, text='Blue screen.', audio=audio.relative_to(self.project).as_posix(),
                                   audioText='Blue screen.', audioStart=2, audioEnd=3, audioDuration=.5)],
                        summary='A screen appears.', status='Ready'))

    def make_media(self, *args):
        subprocess.run(['ffmpeg', '-y', '-v', 'error', *map(str, args)], check=True, capture_output=True)

    def write(self, manifest):
        self.manifest.write_text(json.dumps(manifest), encoding='utf-8')

    def read(self):
        return json.loads(self.manifest.read_text(encoding='utf-8'))

    def run_engine(self, command, *args, error=None):
        completed = subprocess.run([*ENGINE, command, '--project', str(self.project), *map(str, args)],
                                   capture_output=True, text=True, encoding='utf-8', timeout=90)
        details = completed.stdout + completed.stderr
        if error:
            self.assertNotEqual(completed.returncode, 0, details)
            self.assertIn(error, details)
        else:
            self.assertEqual(completed.returncode, 0, details)
        return completed

    def assert_video_export(self, path, audio_tracks):
        media = subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(path)])
        info = json.loads(media)
        kinds = [s['codec_type'] for s in info['streams']]
        self.assertEqual(kinds.count('video'), 1)
        self.assertEqual(kinds.count('audio'), audio_tracks)
        self.assertAlmostEqual(float(info['format']['duration']), 4, delta=.06)

    def test_attach_export_and_delete(self):
        result = self.run_engine('attach-youtube-playback', '--video', self.original)
        events = [json.loads(line) for line in result.stdout.splitlines()]
        progress = [event['contentTransferProgress'] for event in events if 'contentTransferProgress' in event]
        self.assertEqual((progress[0], progress[-1]), (0, 1))
        self.assertEqual(progress, sorted(progress))
        asset = self.read()['youtubePlaybackVideo']
        copied = self.project / asset['path']
        thumbnail = self.project / asset['thumbnail']
        self.assertEqual(copied.read_bytes(), self.original.read_bytes())
        self.assertTrue(thumbnail.read_bytes().startswith(b'\xff\xd8'))
        self.run_engine('attach-youtube-playback', '--video', self.original, error='Confirm replacement')
        self.run_engine('select-youtube-player', '--name', 'youtube', error='requires an accessible YouTube video')
        self.run_engine('export-open-audio-description-video', '--media-format', 'mp4')
        project = self.read()
        self.assertTrue(project['exports'])
        described = self.project / project['exports'][0]
        self.assert_video_export(described, 1)
        desc_id = project['activeResultIDs']['auto']['descriptions']
        request = self.directory / 'request.json'
        request.write_text(json.dumps(dict(jobs=[dict(command='export-selected-tracks',
            trackPlan=dict(media='video', format='mkv', original=True, audioMode='selectable',
                           audio=[dict(language='auto', resultID=desc_id)]))])), encoding='utf-8')
        self.run_engine('export-batch', '--input', request)
        project = self.read()
        selected = self.project / project['exports'][-1]
        self.assert_video_export(selected, 2)
        self.assertEqual((project['sourceType'], project['source'], project['youtubeURL'], project['duration']),
                         ('youtube', '', URL, 4))
        request.write_text(json.dumps(dict(components=['youtubePlaybackVideo'], resultIDs=[], exportPaths=[],
                                          playbackVideoPath=asset['path'])), encoding='utf-8')
        preview = self.directory / 'preview.json'
        self.run_engine('preview-delete-results', '--input', request, '--output', preview)
        self.assertEqual(set(json.loads(preview.read_text())['files']), {asset['path'], asset['thumbnail']})
        self.run_engine('delete-results', '--input', request)
        project = self.read()
        self.assertNotIn('youtubePlaybackVideo', project)
        self.assertTrue(self.original.exists() and selected.exists() and described.exists())
        self.assertFalse(copied.exists() or thumbnail.exists())
        self.assertEqual(project['youtubeURL'], URL)
        self.assertEqual(project['activeResultIDs']['auto']['descriptions'], desc_id)
        self.run_engine('export-open-audio-description-video', error='unavailable for YouTube URL projects')

    def test_wrong_duration_and_local_project(self):
        path = self.directory / 'short.mp4'
        self.make_media('-i', self.original, '-t', '3', '-c', 'copy', path)
        self.run_engine('attach-youtube-playback', '--video', self.original)
        saved = self.manifest.read_bytes()
        self.run_engine('attach-youtube-playback', '--video', path, '--replace-existing', error='Playback video duration does not match.')
        self.assertEqual(self.manifest.read_bytes(), saved)
        self.run_engine('remove-youtube-playback')
        project = self.read()
        project['sourceType'] = 'local'
        self.write(project)
        self.run_engine('attach-youtube-playback', '--video', self.original, error='available for YouTube projects')
        self.assertNotIn('youtubePlaybackVideo', self.read())

    def test_replacement_keeps_only_the_confirmed_copy_and_thumbnail(self):
        replacement = self.directory / 'replacement.mp4'
        self.make_media('-f', 'lavfi', '-i', 'color=c=red:s=160x96:r=24',
                        '-t', '4', '-c:v', 'libx264', replacement)
        self.run_engine('attach-youtube-playback', '--video', self.original)
        first = self.read()['youtubePlaybackVideo']
        original_paths = {first['path'], first['thumbnail']}
        saved = self.manifest.read_bytes()
        self.run_engine('attach-youtube-playback', '--video', replacement, error='Confirm replacement')
        self.assertEqual(self.manifest.read_bytes(), saved)
        self.assertTrue(all((self.project / path).is_file() for path in original_paths))

        self.run_engine('attach-youtube-playback', '--video', replacement, '--replace-existing')
        current = self.read()['youtubePlaybackVideo']
        self.assertEqual(current['sourceName'], replacement.name)
        self.assertEqual((self.project / current['path']).read_bytes(), replacement.read_bytes())
        self.assertEqual(
            {path.relative_to(self.project).as_posix() for path in (self.project / 'playback').iterdir()},
            {current['path'], current['thumbnail']},
        )
        self.assertTrue(self.original.is_file() and replacement.is_file())

    def test_audio_exports_use_copy_without_overwriting_saved_audio_preferences(self):
        project = self.read()
        preferences = {'export': 'imported', 'playback': 'imported', 'transcription': 'imported'}
        project['audioSources'] = preferences
        self.write(project)
        self.run_engine('attach-youtube-playback', '--video', self.original)
        audio = self.directory / 'soundtrack.wav'
        self.make_media('-i', self.original, '-vn', audio)
        self.run_engine('inspect-original-audio', '--input', audio, error='Remove the local playback video')
        self.run_engine('export-original-audio', '--media-format', 'wav')
        self.run_engine('export-youtube-described-audio', '--media-format', 'm4a')
        exported = self.read()
        self.assertEqual(exported['audioSources'], preferences)
        self.assertEqual(exported['youtubeURL'], URL)
        for path in exported['exports']:
            data = subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-of', 'json', str(self.project / path)])
            self.assertEqual([s['codec_type'] for s in json.loads(data)['streams']], ['audio'])
        self.assertEqual(len(exported['exports']), 2)
        self.run_engine('remove-youtube-playback')
        self.run_engine('inspect-original-audio', '--input', audio)
        self.assertEqual(self.read()['audioSources'], preferences)

    def test_video_and_original_audio_require_explicit_removal_before_switching(self):
        audio = self.directory / 'original.wav'
        self.make_media('-i', self.original, '-vn', audio)
        self.run_engine('import-original-audio', '--input', audio)
        imported = self.read()['originalAudio']
        audio_copy = self.project / imported['path']
        self.run_engine('attach-youtube-playback', '--video', self.original, '--replace-existing',
                        error='Remove the original audio file')
        self.assertEqual(self.read()['originalAudio'], imported)
        self.assertTrue(audio_copy.is_file())

        self.run_engine('remove-original-audio')
        self.assertNotIn('originalAudio', self.read())
        self.assertFalse(audio_copy.exists())
        self.assertTrue(audio.is_file())
        self.run_engine('attach-youtube-playback', '--video', self.original)
        attached = self.read()['youtubePlaybackVideo']
        self.run_engine('import-original-audio', '--input', audio, '--replace-existing',
                        error='Remove the local playback video')
        self.assertEqual(self.read()['youtubePlaybackVideo'], attached)
        self.assertNotIn('originalAudio', self.read())

        # A retained attachment still blocks import when its file is missing.
        (self.project / attached['path']).unlink()
        self.run_engine('inspect-original-audio', '--input', audio, error='Remove the local playback video')
        self.run_engine('remove-youtube-playback')
        self.run_engine('import-original-audio', '--input', audio)
        self.assertIn('originalAudio', self.read())

    def test_public_and_unlisted_attach_export_and_remove(self):
        for visibility in ('public', 'unlisted'):
            with self.subTest(visibility=visibility):
                project = self.read()
                project.pop('youtubePrivateChannelID', None)
                project['youtubeMetadata']['visibility'] = visibility
                self.write(project)
                self.run_engine('attach-youtube-playback', '--video', self.original)
                saved = self.read()
                copy = self.project / saved['youtubePlaybackVideo']['path']
                self.assertEqual(copy.read_bytes(), self.original.read_bytes())
                self.run_engine('select-youtube-player', '--name', 'youtube')
                self.assertIs(self.read()['youtubePlaybackVideo']['useYouTubePlayer'], True)
                self.run_engine('export-closed-audio-description-video', '--media-format', 'mov', '--replace-existing')
                current = self.read()
                self.assert_video_export(self.project / current['exports'][-1], 2)
                self.assertEqual((current['sourceType'], current['source'], current['youtubeURL']), ('youtube', '', URL))
                self.assertEqual(current['youtubeMetadata']['visibility'], visibility)
                self.assertIs(current['youtubePlaybackVideo']['useYouTubePlayer'], True)
                self.run_engine('select-youtube-player', '--name', 'local')
                self.assertIs(self.read()['youtubePlaybackVideo']['useYouTubePlayer'], False)
                self.run_engine('remove-youtube-playback')
                self.assertFalse(copy.exists())
                self.assertTrue(self.original.exists())
                self.assertNotIn('youtubePlaybackVideo', self.read())
