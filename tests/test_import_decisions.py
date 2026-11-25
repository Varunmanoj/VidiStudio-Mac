"""Consent and cancel regression tests against the source or packaged CLI."""
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


@unittest.skipUnless(shutil.which('ffmpeg'), 'FFmpeg is required')
class ImportDecisions(unittest.TestCase):
    def setUp(self):
        work = tempfile.TemporaryDirectory()
        self.addCleanup(work.cleanup)
        self.root = Path(work.name)
        self.folder = self.root / 'project'
        self.folder.mkdir()
        self.manifest = self.folder / 'project.json'
        self.manifest.write_text(json.dumps(dict(
            id='import-consent-fixture', name='Import consent', sourceType='youtube', source='',
            duration=4, youtubeURL='https://www.youtube.com/watch?v=dQw4w9WgXcQ',
            transcript=[], summary='Existing summary', cues=[dict(id='cue', start=2, end=3, text='A scene.')],
            status='Ready', exports=[], thumbnails=[])), encoding='utf-8')

    def run_cli(self, command, *args, project=True, ok=True):
        argv = [*ENGINE, command, *(['--project', self.folder] if project else []), *args]
        done = subprocess.run(list(map(str, argv)), capture_output=True, encoding='utf-8', timeout=60)
        self.assertEqual(done.returncode == 0, ok, done.stdout + done.stderr)
        return [json.loads(line) for line in done.stdout.splitlines()]

    def warning(self, command, *args):
        original = self.manifest.read_bytes()
        entries = {p for p in self.folder.rglob('*') if p.name != '.engine.lock'}
        issue = self.run_cli(command, *args, ok=False)[-1]['importIssue']
        self.assertRegex(issue['token'], '^[0-9a-f]{64}$')
        self.assertEqual(self.manifest.read_bytes(), original)
        self.assertEqual({p for p in self.folder.rglob('*') if p.name != '.engine.lock'}, entries)
        return issue

    def media(self, target, resource, extra=()):
        subprocess.run(['ffmpeg', '-y', '-v', 'error', '-f', 'lavfi', '-i', resource, '-t', '2',
                        *extra, str(target)], check=True, capture_output=True)
        return target

    def test_partial_youtube_captions_and_scope_of_confirmation(self):
        captions = self.root / 'captions.srt'
        good = '1\n00:00:00,000 --> 00:00:01,500\nKeep this\n'
        invalid = '\n2\n00:00:05,000 --> 00:00:06,000\nBeyond video\n'
        captions.write_text(good + invalid, encoding='utf-8')
        provenance = self.root / 'captions.json'
        provenance.write_text(json.dumps(dict(videoID='dQw4w9WgXcQ', language='en')), encoding='utf-8')
        args = ('--input', captions, '--caption-provenance', provenance)
        warning = self.warning('import-transcript', *args)
        old_token = warning['token']
        self.assertIn('1 usable row(s)', warning['message'])
        captions.write_text(good.replace('Keep this', 'Changed since review') + invalid, encoding='utf-8')
        changed = self.warning('import-transcript', *args, '--accept-import-warning', old_token)
        self.assertNotEqual(changed['token'], old_token)
        self.run_cli('import-transcript', *args, '--accept-import-warning', changed['token'])
        project = json.loads(self.manifest.read_text(encoding='utf-8'))
        self.assertEqual([row['text'] for row in project['transcript']], ['Changed since review'])
        self.assertEqual(project['youtubeCaptionSource']['language'], 'en')
        self.assertEqual(project['lastImportReport']['rowsOmittedAfterVideo'], 1)

    def test_ad_track_and_segment_narration_can_continue_with_known_outcomes(self):
        audio = self.media(self.root / 'ad.wav', 'sine=frequency=440:sample_rate=48000')
        ad = self.warning('import-ad-audio', '--input', audio)
        self.assertIn('padded with silence', ad['message'])
        self.run_cli('import-ad-audio', '--input', audio, '--accept-import-warning', ad['token'])
        args = ('--input', audio, '--segment', 'cue')
        narration = self.warning('import-segment-narration', *args)
        self.assertIn('trimmed', narration['message'])
        self.run_cli('import-segment-narration', *args, '--accept-import-warning', narration['token'])
        project = json.loads(self.manifest.read_text(encoding='utf-8'))
        self.assertAlmostEqual(project['cues'][0]['audioDuration'], 1, places=2)
        self.assertTrue((self.folder / project['cues'][0]['audio']).is_file())
        self.assertEqual(project['importedAudioDescription']['duration'], 2)
        self.assertGreater(audio.stat().st_size, (self.folder / project['cues'][0]['audio']).stat().st_size)

    def test_unusable_summary_and_audio_do_not_offer_override(self):
        for command, filename, data in [('import-summary', 'blank.md', b'  \n'),
                                        ('import-ad-audio', 'bad.wav', b'invalid audio')]:
            with self.subTest(command=command):
                source = self.root / filename
                source.write_bytes(data)
                original = self.manifest.read_bytes()
                issue = self.run_cli(command, '--input', source, ok=False)[-1]['importIssue']
                self.assertIsNone(issue['token'])
                self.assertEqual(self.manifest.read_bytes(), original)

    def test_duplicate_video_override_creates_a_separate_project(self):
        video = self.media(self.root / 'video.mp4', 'color=c=blue:s=160x96:r=24', ('-c:v', 'libx264'))
        library = self.root / 'library'
        args = ('--video', video, '--library', library)
        self.run_cli('import-video', *args, project=False)
        first = next(library.glob('*/project.json'))
        original = first.read_bytes()
        warning = self.run_cli('import-video', *args, project=False, ok=False)[-1]['importIssue']
        self.assertEqual(len(list(library.iterdir())), 1)
        self.assertEqual(warning['title'], 'Project Already Exists')
        self.run_cli('import-video', *args, '--accept-import-warning', warning['token'], project=False)
        self.assertEqual(len(list(library.glob('*/project.json'))), 2)
        self.assertEqual(first.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
