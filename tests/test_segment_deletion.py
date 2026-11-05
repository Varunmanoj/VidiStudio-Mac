"""Deletion must not revalidate unrelated saved timing conflicts."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from tests.test_engine import ENGINE, engine


def project_fixture():
    return dict(
        id='deletion-regression', name='Deletion regression', duration=714,
        sourceType='youtube', source='', youtubeURL='https://www.youtube.com/watch?v=abcdefghijk',
        transcript=[
            dict(id='first', start=0, end=5, text='Opening'),
            dict(id='long', start=52, end=103, text='Existing long row'),
            dict(id='overlap', start=66, end=81, text='Existing overlapping row'),
            dict(id='neighbor', start=97, end=109, text='Existing overlapping neighbor'),
            dict(id='song', start=124, end=149, text='Unwanted song'),
            dict(id='last', start=710, end=714, text='Ending'),
        ],
        cues=[
            dict(id='opening-ad', start=6, end=8, text='Opening description'),
            dict(id='conflicting-ad', start=67, end=70, text='Existing dialogue conflict'),
            dict(id='song-ad', start=150, end=155, text='Song description'),
            dict(id='ending-ad', start=700, end=705, text='Closing description'),
        ],
        exports=[], summary='', transcriptUndoStack=[], transcriptRedoStack=[],
        undoStack=[], redoStack=[],
    )


class SegmentDeletion(unittest.TestCase):
    def test_deleting_beginning_middle_end_or_mixed_rows_preserves_remaining_times(self):
        for transcript_ids, cue_ids in [
            ({'first'}, set()), ({'song'}, set()), ({'last'}, set()),
            (set(), {'opening-ad'}), (set(), {'song-ad'}), (set(), {'ending-ad'}),
            ({'song'}, {'song-ad'}),
        ]:
            with self.subTest(transcript_ids=transcript_ids, cue_ids=cue_ids):
                project = project_fixture()
                before = copy.deepcopy(project)
                transcript = [row for row in copy.deepcopy(project['transcript']) if row['id'] not in transcript_ids]
                cues = [row for row in copy.deepcopy(project['cues']) if row['id'] not in cue_ids]
                engine.save_segments(project, transcript, cues)
                self.assertEqual(project['duration'], before['duration'])
                for kind, deleted in (('transcript', transcript_ids), ('cues', cue_ids)):
                    self.assertEqual(
                        [(row['id'], row['start'], row['end'], row['text']) for row in project[kind]],
                        [(row['id'], row['start'], row['end'], row['text']) for row in before[kind] if row['id'] not in deleted],
                    )
                self.assertEqual(project['descriptionTimingAudit']['count'], 1)

    def test_deletion_can_remove_the_conflict_itself_and_refresh_the_audit(self):
        project = project_fixture()
        engine.save_segments(project, project['transcript'], [row for row in project['cues'] if row['id'] != 'conflicting-ad'])
        self.assertEqual(project['descriptionTimingAudit']['count'], 0)

    def test_deleting_all_transcript_rows_preserves_descriptions(self):
        project = project_fixture()
        cues = copy.deepcopy(project['cues'])
        engine.save_segments(project, [], project['cues'])
        self.assertEqual(project['transcript'], [])
        self.assertEqual([(row['id'], row['start'], row['end']) for row in project['cues']],
                         [(row['id'], row['start'], row['end']) for row in cues])
        self.assertEqual(project['duration'], 714)

    def test_existing_out_of_video_row_does_not_block_unrelated_deletion(self):
        project = project_fixture()
        project['transcript'][-1]['end'] = 720
        project['cues'][-1]['end'] = 725
        engine.save_segments(project, [row for row in project['transcript'] if row['id'] != 'song'], project['cues'])
        self.assertEqual(project['duration'], 714)
        self.assertEqual(project['transcript'][-1]['end'], 720)
        self.assertEqual(project['descriptionTimingAudit']['count'], 2)

    def test_added_and_edited_rows_still_reject_invalid_timing_without_changing_project(self):
        for kind, row_id in [('transcript', 'song'), ('cues', 'song-ad')]:
            for added in (True, False):
                for start, end in [(-1, 2), (715, 720), (120, 120), (float('nan'), 149), (float('inf'), 149), (68, 69)]:
                    with self.subTest(kind=kind, added=added, start=start, end=end):
                        project = project_fixture()
                        before = copy.deepcopy(project)
                        transcript, cues = copy.deepcopy(project['transcript']), copy.deepcopy(project['cues'])
                        rows = transcript if kind == 'transcript' else cues
                        if added:
                            rows.append(dict(id='new', start=start, end=end, text='New row'))
                        else:
                            row = next(row for row in rows if row['id'] == row_id)
                            row.update(start=start, end=end)
                        with self.assertRaises(ValueError):
                            engine.save_segments(project, transcript, cues)
                        self.assertEqual(project, before)

    def test_can_retime_one_conflicting_row_while_another_saved_conflict_remains(self):
        project = project_fixture()
        transcript = copy.deepcopy(project['transcript'])
        transcript[2].update(start=110, end=120)
        engine.save_segments(project, transcript, project['cues'])
        self.assertEqual(next(row for row in project['transcript'] if row['id'] == 'overlap')['start'], 110)

    def test_duplicate_transcript_ids_are_rejected(self):
        project = project_fixture()
        transcript = copy.deepcopy(project['transcript'])
        transcript.append(copy.deepcopy(transcript[0]))
        with self.assertRaisesRegex(ValueError, 'Duplicate transcript'):
            engine.save_segments(project, transcript, project['cues'])

    def test_save_segments_cli_deletes_song_and_only_its_narration(self):
        with tempfile.TemporaryDirectory(prefix='vidistudio-deletion-') as temp:
            root = Path(temp)
            project = project_fixture()
            audio = root / 'audio-description'
            audio.mkdir()
            for cue in project['cues']:
                cue['audio'] = f"audio-description/{cue['id']}.wav"
                (root / cue['audio']).write_bytes(b'fixture audio')
            manifest = root / 'project.json'
            manifest.write_text(json.dumps(project))
            payload = root / 'segments.json'
            payload.write_text(json.dumps(dict(
                transcript=[row for row in project['transcript'] if row['id'] != 'song'],
                cues=[row for row in project['cues'] if row['id'] != 'song-ad'],
            )))
            prefix = [os.environ['VIDISTUDIO_TEST_ENGINE']] if os.environ.get('VIDISTUDIO_TEST_ENGINE') else [sys.executable, str(ENGINE)]
            result = subprocess.run(
                [*prefix, 'save-segments', '--project', str(root), '--input', str(payload)],
                env=os.environ | {'VIDISTUDIO_CONFIG': str(root / 'empty-config.json')},
                capture_output=True, text=True, timeout=60,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            saved = json.loads(manifest.read_text())
            self.assertEqual(saved['duration'], 714)
            self.assertNotIn('song', [row['id'] for row in saved['transcript']])
            self.assertEqual([(row['id'], row['start'], row['end']) for row in saved['transcript']],
                             [(row['id'], row['start'], row['end']) for row in project['transcript'] if row['id'] != 'song'])
            historical = next(row['audio'] for snapshot in saved['undoStack'] for row in snapshot if row['id'] == 'song-ad')
            self.assertTrue((root/historical).is_file())
            self.assertEqual((root/historical).read_bytes(), b'fixture audio')
            self.assertIn('/Auto/', historical)
            for name in ('opening-ad.wav', 'conflicting-ad.wav'):
                self.assertTrue(any(path.is_file() for path in audio.rglob(name)))
            self.assertEqual(saved['status'], 'Ready')


if __name__ == '__main__':
    unittest.main()
