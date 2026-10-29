import contextlib
import importlib.util
import json
import math
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path
from types import SimpleNamespace

ENGINE_DIR = Path(__file__).resolve().parents[1] / 'engine'
sys.path.insert(0, str(ENGINE_DIR))
import import_assets as assets


def write(path, text, encoding='utf-8'):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding=encoding)
    return path


def project(**changes):
    base = dict(
        id='p1', name='Project', source='source/video.mp4', sourceType='local',
        duration=20.0, hasAudio=True, transcript=[], summary='', summaryGenerated=False,
        cues=[], exports=[], exportMediaInfo={}, thumbnails=[],
    )
    base.update(changes)
    return base


def cue(start, end, text='Description', **changes):
    value = dict(id=f'c{start}-{end}', start=start, end=end, text=text)
    value.update(changes)
    return value


def transcript(start, end, text='Dialogue', **changes):
    value = dict(id=f't{start}-{end}', start=start, end=end, text=text)
    value.update(changes)
    return value


class FakeCore:
    def __init__(self, root, durations=None):
        self.root = Path(root)
        self.durations = durations or {}
        self.emitted = []
        self.probed = []

    def local(self, root, relative):
        return Path(root) / relative

    def emit(self, message, **values):
        self.emitted.append(dict(message=message, **values))

    def save(self, root, value):
        (Path(root) / 'project.json').write_text(json.dumps(value), encoding='utf-8')

    def probe(self, path):
        path = Path(path)
        self.probed.append(path)
        if path.name in self.durations and self.durations[path.name] is None:
            raise ValueError('corrupt audio')
        return {
            'streams': [{'codec_type': 'audio', 'duration': str(self.durations.get(path.name, 1.0))}],
            'format': {'duration': str(self.durations.get(path.name, 1.0))},
        }

    def remember_transcript(self, project):
        project.setdefault('transcriptUndoStack', []).append(deepcopy(project.get('transcript', [])))

    def run(self, args, **kwargs):
        self.emitted.append(dict(message='run', args=list(args)))

    def tool(self, name):
        return name

    @property
    def parity(self):
        return SimpleNamespace(remember=lambda p: p.setdefault('cues', []))


class TextImportTests(unittest.TestCase):
    def test_parse_srt_and_vtt_preserve_bom_and_malformed_rows(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            srt = root / 'captions.srt'
            srt.write_bytes(b'\xef\xbb\xbf1\r\n00:00:01,000 --> 00:00:02,500\r\nHello\r\n\r\n'
                            b'2\r\nnot a timing line\r\nBroken\r\n\r\n'
                            b'3\r\n00:00:03,000 --> 00:00:04,000\r\nWorld\r\n')
            rows = assets.parse_text(srt)
            self.assertIn('Broken', rows[1]['text'])
            self.assertEqual(rows[1]['parseError'], 'Missing subtitle timing line.')
            vtt = write(root / 'captions.vtt', 'WEBVTT\n\nNOTE ignore me\n\n00:00:01.000 --> 00:00:02.000\nHi\n')
            rows = assets.parse_text(vtt)
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]['text'], 'Hi')
            txt = write(root / 'lines.txt', 'First line\n\nSecond line\n')
            rows = assets.parse_text(txt)
            self.assertEqual([row['text'] for row in rows], ['First line', 'Second line'])
            self.assertIsNone(rows[0]['start'])

    def test_timing_validation_omits_invalid_rows_and_keeps_the_rest(self):
        rows = [
            dict(sourceLine=1, text='good', start=0, end=2),
            dict(sourceLine=2, text='after video', start=19, end=21),
            dict(sourceLine=3, text='starts after', start=25, end=26),
            dict(sourceLine=4, text='reversed', start=3, end=2),
            dict(sourceLine=5, text='', start=3, end=4),
            dict(sourceLine=6, text='overlap', start=1, end=3),
        ]
        accepted, omitted = assets.validate_rows(rows, 20.0, 'transcript')
        self.assertEqual([row['text'] for row in accepted], ['good'])
        self.assertEqual([row['sourceLine'] for row in omitted], [2, 3, 4, 5, 6])
        self.assertEqual([row['code'] for row in omitted], ['afterVideo', 'afterVideo', 'invalid', 'invalid', 'transcriptOverlap'])
        self.assertIn('Ends at 00:00:21.000', omitted[0]['reason'])

    def test_ad_rows_may_overlap_dialogue_but_are_flagged_later(self):
        rows = [dict(sourceLine=1, text='AD', start=1, end=3)]
        accepted, omitted = assets.validate_rows(rows, 20.0, 'narration')
        self.assertEqual(len(accepted), 1)
        self.assertEqual(omitted, [])

    def test_distribute_evenly_requires_duration_and_rows(self):
        rows = [dict(text='a'), dict(text='b')]
        timed = assets.distribute_evenly(rows, 10)
        self.assertEqual([(row['start'], row['end']) for row in timed], [(0.0, 5.0), (5.0, 10.0)])
        with self.assertRaises(ValueError):
            assets.distribute_evenly([], 10)
        with self.assertRaises(ValueError):
            assets.distribute_evenly(rows, None)


class AuditTests(unittest.TestCase):
    def test_audit_flags_transcript_and_ad_overlaps_without_moving_rows(self):
        value = project(
            transcript=[transcript(1, 4)],
            cues=[cue(3, 6, 'First'), cue(5, 7, 'Second')],
        )
        audit = assets.audit_timing(value)
        self.assertEqual(audit['count'], 2)
        self.assertEqual([row['text'] for row in audit['segments']], ['First', 'Second'])
        self.assertEqual(value['cues'][0]['start'], 3)
        conflicts = audit['segments'][0]['conflicts']
        self.assertTrue(any(item['kind'] == 'transcript' for item in conflicts))
        self.assertTrue(any(item['kind'] == 'description' for item in conflicts))

    def test_audit_flags_invalid_and_out_of_duration_cues(self):
        value = project(cues=[cue(0, 30), cue(5, 5.0)])
        audit = assets.audit_timing(value)
        self.assertEqual(audit['count'], 2)
        self.assertTrue(all(any(item['kind'] == 'invalidTiming' for item in row['conflicts'])
                            for row in audit['segments']))

    def test_resolved_timing_is_required_for_described_exports(self):
        value = project(transcript=[transcript(1, 4)], cues=[cue(5, 6)])
        assets.require_resolved_timing(value)
        value['cues'][0]['start'] = 3.5
        with self.assertRaisesRegex(ValueError, 'Description timing needs attention'):
            assets.require_resolved_timing(value)

    def test_unknown_duration_records_warning_in_report(self):
        value = project(duration=0)
        report = assets.report_for(value, 'transcript', Path('/tmp/captions.srt'))
        self.assertIsNone(report['videoDuration'])
        self.assertIn('Video duration is unknown', report['warnings'][0])


class ProvenanceTests(unittest.TestCase):
    def test_imported_rows_become_modified_only_after_edits(self):
        previous = [transcript(0, 1, 'Dialogue', origin='imported', originSource='talk.srt')]
        rows = deepcopy(previous)
        assets.track_origins(rows, previous)
        self.assertEqual(rows[0]['origin'], 'imported')
        rows[0]['text'] = 'Edited dialogue'
        assets.track_origins(rows, previous)
        self.assertEqual(rows[0]['origin'], 'imported_modified')
        self.assertEqual(rows[0]['originSource'], 'talk.srt')

    def test_explicit_provenance_choice_is_kept(self):
        previous = [transcript(0, 1, 'Dialogue', origin='imported')]
        rows = deepcopy(previous)
        rows[0].update(origin='manual', originOverride=True)
        assets.track_origins(rows, previous)
        self.assertEqual(rows[0]['origin'], 'manual')
        rows[0]['text'] = 'Edited'
        assets.track_origins(rows, previous)
        self.assertEqual(rows[0]['origin'], 'manual')

    def test_new_rows_default_to_manual_and_legacy_rows_stay_unknown(self):
        rows = [transcript(0, 1)]
        assets.track_origins(rows, [])
        self.assertEqual(rows[0]['origin'], 'manual')
        legacy = [transcript(0, 1)]
        assets.track_origins(legacy, [dict(legacy[0])])
        self.assertEqual(legacy[0]['origin'], 'unknown')

    def test_unknown_origin_can_be_edited(self):
        previous = [transcript(0, 1, 'Dialogue')]
        rows = deepcopy(previous)
        rows[0].update(origin='ai', originOverride=True)
        assets.track_origins(rows, previous)
        self.assertEqual(rows[0]['origin'], 'ai')


class SummaryTests(unittest.TestCase):
    def test_manual_summary_origin_and_delete(self):
        value = project()
        assets.save_summary(value, 'Hand written')
        self.assertEqual(value['summaryOrigin'], 'manual')
        self.assertEqual(value['summaryGenerated'], True)
        assets.save_summary(value, '')
        self.assertNotIn('summaryOrigin', value)
        self.assertFalse(value['summaryGenerated'])

    def test_imported_and_generated_summary_origins(self):
        value = project()
        assets.save_summary(value, 'Imported', 'imported', 'notes.md')
        self.assertEqual(value['summaryOrigin'], 'imported')
        self.assertEqual(value['summaryOriginSource'], 'notes.md')
        assets.save_summary(value, 'Generated', 'ai')
        self.assertEqual(value['summaryOrigin'], 'ai')
        self.assertNotIn('summaryOriginSource', value)
        value['summaryOriginOverride'] = False
        assets.save_summary(value, 'Manual edit')
        self.assertEqual(value['summaryOrigin'], 'ai')


class NarrationSourceTests(unittest.TestCase):
    def test_generated_and_imported_sources_are_grouped(self):
        value = project(cues=[
            cue(0, 1, 'One', audio='a.mp3', audioOrigin='generated', audioEngine='Piper', audioVoice='A'),
            cue(1, 2, 'Two', audio='b.mp3', audioOrigin='generated', audioEngine='Piper', audioVoice='B'),
            cue(2, 3, 'Three', audio='c.mp3', audioOrigin='imported', audioSourceName='one.wav'),
            cue(3, 4, 'Four', audio='d.mp3', audioOrigin='imported', audioSourceName='two.wav'),
            cue(4, 5, 'Five', audio='e.mp3', audioOrigin='unknown'),
        ])
        sources = assets.narration_sources(value)
        self.assertEqual(sources['counts'], dict(generated=2, imported=2, unknown=1))
        self.assertTrue(sources['hasMixedSources'])
        self.assertTrue(sources['hasDifferentVoices'])
        self.assertEqual(sources['importedFiles'], {'one.wav': [3], 'two.wav': [4]})
        self.assertTrue(any('mixes AI-generated narration' in warning for warning in sources['warnings']))
        self.assertTrue(any('2 different audio files' in warning for warning in sources['warnings']))

    def test_all_imported_and_all_generated_warnings(self):
        imported = project(cues=[cue(0, 1, audio='a.mp3', audioOrigin='imported', audioSourceName='a.wav')])
        sources = assets.narration_sources(imported)
        self.assertTrue(any('All narration audio in this project is imported' in warning for warning in sources['warnings']))
        generated = project(cues=[cue(0, 1, audio='a.mp3', audioOrigin='generated', audioEngine='Piper', audioVoice='A')])
        sources = assets.narration_sources(generated)
        self.assertTrue(any('only AI-generated narration' in warning for warning in sources['warnings']))
        self.assertFalse(sources['hasMixedSources'])


class ImportCommandTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / 'source').mkdir()
        (self.root / 'source/video.mp4').write_bytes(b'fake')
        self.core = FakeCore(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def args(self, command='import-transcript', **changes):
        values = dict(command=command, ad_transcript_mode='narration', replace_existing=False,
                      input=None, timing_input=None, audio_mode='narration',
                      audio_presentation='selectable', audio_only=False, media_format='mov',
                      captions='none', content='transcript')
        values.update(changes)
        return SimpleNamespace(**values)

    def test_import_transcript_replaces_rows_and_sets_provenance(self):
        source = write(self.root / 'talk.srt', '1\n00:00:01,000 --> 00:00:03,000\nHello\n')
        value = project()
        created = []
        report = assets.import_text(self.args(input=source), self.root, value, self.core, created)
        self.assertEqual(len(value['transcript']), 1)
        self.assertEqual(value['transcript'][0]['origin'], 'imported')
        self.assertEqual(value['transcript'][0]['originSource'], 'talk.srt')
        self.assertEqual(report['rowsImported'], 1)
        self.assertEqual(len(created), 1)
        self.assertTrue((value['transcript'][0].get('start') == 1.0))
        self.assertEqual(value['transcriptGenerated'], True)

    def test_import_ad_narration_requires_a_transcript(self):
        source = write(self.root / 'ad.srt', '1\n00:00:01,000 --> 00:00:02,000\nDescribed\n')
        value = project()
        with self.assertRaisesRegex(ValueError, 'transcript before importing AD-only'):
            assets.import_text(self.args('import-ad-transcript', input=source), self.root, value, self.core, [])

    def test_import_ad_narration_populates_cues_and_imported_transcript(self):
        source = write(self.root / 'ad.srt', '1\n00:00:01,000 --> 00:00:02,000\nDescribed\n')
        value = project(transcript=[transcript(0, 1)])
        report = assets.import_text(self.args('import-ad-transcript', input=source), self.root, value, self.core, [])
        self.assertEqual(value['cues'][0]['text'], 'Described')
        self.assertEqual(value['importedADTranscript']['mode'], 'narration')
        self.assertEqual(value['importedADTranscript']['segments'][0]['origin'], 'imported')
        self.assertEqual(report['rowsImported'], 1)
        self.assertTrue(value['descriptionsGenerated'])

    def test_combined_ad_transcript_is_not_overlap_checked_but_duration_checked(self):
        source = write(self.root / 'combined.vtt',
                       'WEBVTT\n\n00:00:01.000 --> 00:00:03.000\nDialogue\n\n00:00:04.000 --> 00:00:30.000\nToo long\n')
        value = project(transcript=[transcript(1, 3)])
        report = assets.import_text(self.args('import-ad-transcript', input=source, ad_transcript_mode='combined'),
                                    self.root, value, self.core, [])
        self.assertEqual(report['rowsImported'], 1)
        self.assertEqual(report['rowsOmittedAfterVideo'], 1)
        self.assertEqual(value['cues'], [])
        self.assertEqual(value['importedADTranscript']['mode'], 'combined')
        self.assertEqual(value['importedADTranscript']['segments'][0]['text'], 'Dialogue')

    def test_zero_valid_rows_preserves_existing_content(self):
        source = write(self.root / 'bad.srt', '1\n00:00:01,000 --> 00:00:40,000\nOutside\n')
        original = [transcript(0, 1, 'Keep me', origin='imported')]
        value = project(transcript=original)
        report = assets.import_text(self.args(input=source, replace_existing=True), self.root, value, self.core, [])
        self.assertEqual(value['transcript'], original)
        self.assertEqual(report['rowsImported'], 0)
        self.assertEqual(report['rowsOmittedAfterVideo'], 1)

    def test_imported_transcript_marks_conflicting_description_for_retiming(self):
        source = write(self.root / 'talk.srt', '1\n00:00:01,000 --> 00:00:05,000\nNew dialogue\n')
        value = project(cues=[cue(4, 6, 'Existing AD')])
        report = assets.import_text(self.args(input=source), self.root, value, self.core, [])
        self.assertEqual(value['transcript'][0]['text'], 'New dialogue')
        self.assertEqual(value['descriptionTimingAudit']['count'], 1)
        self.assertEqual(report['rowsFlagged'], 1)


    def test_reviewed_timing_applies_to_srt_rows(self):
        source = write(self.root / 'talk.srt', '1\n00:00:01,000 --> 00:00:03,000\nHello\n')
        timing = self.root / 'reviewed.json'
        timing.write_text(json.dumps({'reviewed': True, 'rows': [
            {'sourceLine': 2, 'text': 'Hello', 'start': 4, 'end': 6},
        ]}), encoding='utf-8')
        value = project()
        assets.import_text(self.args(input=source, timing_input=timing), self.root, value, self.core, [])
        self.assertEqual((value['transcript'][0]['start'], value['transcript'][0]['end']), (4, 6))

    def test_txt_import_requires_reviewed_timing_json(self):
        source = write(self.root / 'lines.txt', 'Line one\nLine two\n')
        value = project()
        with self.assertRaisesRegex(ValueError, 'requires reviewed start and end times'):
            assets.import_text(self.args(input=source), self.root, value, self.core, [])
        timing = self.root / 'timing.json'
        timing.write_text(json.dumps({'reviewed': True, 'rows': [
            {'sourceLine': 1, 'text': 'Line one', 'start': 0, 'end': 2},
            {'sourceLine': 2, 'text': 'Line two', 'start': 2, 'end': 4},
        ]}), encoding='utf-8')
        value = project()
        report = assets.import_text(self.args(input=source, timing_input=timing), self.root, value, self.core, [])
        self.assertEqual(report['rowsImported'], 2)

    def test_unreviewed_ai_timing_is_rejected(self):
        source = write(self.root / 'lines.txt', 'Line one\n')
        timing = self.root / 'timing.json'
        timing.write_text(json.dumps({'aiGenerated': True, 'reviewed': False, 'rows': [
            {'sourceLine': 1, 'text': 'Line one', 'start': 0, 'end': 2},
        ]}), encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'Review the AI timing'):
            assets.import_text(self.args(input=source, timing_input=timing), self.root, project(), self.core, [])


    def test_imported_combined_ad_transcript_is_the_caption_source(self):
        import vidistudio_engine as engine
        value = project(
            transcript=[transcript(0, 1, 'Dialogue')],
            cues=[cue(1, 2, 'Description')],
            importedADTranscript=dict(mode='combined', segments=[
                dict(id='c1', start=0, end=1, text='Dialogue and description'),
            ]),
        )
        captions = engine.validated_caption_segments(value, 'combined')
        self.assertEqual([row['text'] for row in captions], ['Dialogue and description'])
        self.assertNotIn('Audio description:', captions[0]['text'])

    def test_summary_import_works_without_a_transcript(self):
        source = write(self.root / 'summary.md', '# Heading\n\nBody')
        value = project()
        assets.execute(self.args('import-summary', input=source), self.root, value, self.core)
        report = self.core.emitted[-1]['importReport']
        self.assertEqual(value['summary'], '# Heading\n\nBody')
        self.assertEqual(value['summaryOrigin'], 'imported')
        self.assertEqual(value['summaryOriginSource'], 'summary.md')
        self.assertEqual(report['rowsImported'], 1)

    def test_audio_import_records_mode_duration_and_warnings(self):
        source = self.root / 'ad.wav'
        source.write_bytes(b'RIFF')
        self.core.durations['ad.wav'] = 25.0
        value = project()
        assets.execute(self.args('import-ad-audio', input=source), self.root, value, self.core)
        report = self.core.emitted[-1]['importReport']
        self.assertEqual(value['importedAudioDescription']['mode'], 'narration')
        self.assertEqual(value['importedAudioDescription']['duration'], 25.0)
        self.assertEqual(report['rowsImported'], 1)
        self.assertTrue(any('video-length portion' in warning for warning in report['warnings']))

    def test_import_segment_narration_sets_metadata_and_removes_audio_engine(self):
        source = self.root / 'narration.wav'
        source.write_bytes(b'RIFF')
        self.core.durations['narration.wav'] = 1.5
        value = project(cues=[cue(0, 2, 'Described', audio='audio-description/old.mp3',
                                   audioEngine='Piper', audioVoice='Old')])
        args = self.args('import-segment-narration', input=source, replace_existing=True)
        args.segment = 'c0-2'
        created, superseded = [], []
        report = assets.import_segment_audio(args, self.root, value, self.core, created, superseded)
        row = value['cues'][0]
        self.assertEqual(row['audioOrigin'], 'imported')
        self.assertEqual(row['audioSourceName'], 'narration.wav')
        self.assertEqual(row['audioDuration'], 1.5)
        self.assertNotIn('audioEngine', row)
        self.assertIn('audio-description/old.mp3', superseded)
        self.assertEqual(report['kind'], 'segmentNarration')
        self.assertTrue(len(created) == 1)

    def test_import_segment_narration_rejects_audio_longer_than_the_segment(self):
        source = self.root / 'narration.wav'
        source.write_bytes(b'RIFF')
        self.core.durations['narration.wav'] = 2.5
        value = project(cues=[cue(0, 2, 'Described')])
        args = self.args('import-segment-narration', input=source)
        args.segment = 'c0-2'
        with self.assertRaisesRegex(ValueError, 'Available segment duration'):
            assets.import_segment_audio(args, self.root, value, self.core, [], [])
        self.assertNotIn('audio', value['cues'][0])

    def test_import_segment_narration_allows_shorter_audio(self):
        source = self.root / 'narration.wav'
        source.write_bytes(b'RIFF')
        self.core.durations['narration.wav'] = 1.0
        value = project(cues=[cue(0, 2, 'Described')])
        args = self.args('import-segment-narration', input=source)
        args.segment = 'c0-2'
        assets.import_segment_audio(args, self.root, value, self.core, [], [])
        self.assertEqual(value['cues'][0]['audioDuration'], 1.0)

    def test_import_segment_narration_replacement_requires_confirmation(self):
        source = self.root / 'narration.wav'
        source.write_bytes(b'RIFF')
        self.core.durations['narration.wav'] = 1.0
        value = project(cues=[cue(0, 2, 'Described', audio='audio-description/old.mp3')])
        args = self.args('import-segment-narration', input=source)
        args.segment = 'c0-2'
        with self.assertRaisesRegex(ValueError, 'Confirm replacement'):
            assets.import_segment_audio(args, self.root, value, self.core, [], [])
        args.replace_existing = True
        assets.import_segment_audio(args, self.root, value, self.core, [], [])
        self.assertEqual(value['cues'][0]['audioSourceName'], 'narration.wav')

    def test_corrupt_audio_is_rejected_before_project_changes(self):
        source = self.root / 'bad.wav'
        source.write_bytes(b'not audio')
        self.core.durations['bad.wav'] = None
        value = project()
        with self.assertRaisesRegex(ValueError, 'does not contain readable, decodable audio'):
            assets.execute(self.args('import-ad-audio', input=source), self.root, value, self.core)
        self.assertNotIn('importedAudioDescription', value)
        self.assertFalse((self.root / 'imports').exists())


class CombineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / 'source').mkdir()
        (self.root / 'source/video.mp4').write_bytes(b'fake')
        (self.root / 'imports').mkdir()
        (self.root / 'imports/ad.wav').write_bytes(b'RIFF')
        (self.root / 'exports').mkdir()
        self.commands = []
        self.core = self.core_for()

    def tearDown(self):
        self.temp.cleanup()

    def core_for(self):
        commands = self.commands
        root = self.root

        class Core:
            AUDIO_EXPORT_FORMATS = ('wav', 'mp3', 'm4a')
            VIDEO_EXPORT_FORMATS = ('mkv', 'mp4', 'mov', 'm4v')

            def local(self, base, relative):
                return Path(base) / relative

            def emit(self, *args, **kwargs):
                pass

            def save(self, base, value):
                (Path(base) / 'project.json').write_text(json.dumps(value), encoding='utf-8')

            def tool(self, name):
                return name

            def media_export_format(self, value, supported, default):
                result = value or default
                if result not in supported:
                    raise ValueError('bad format')
                return result

            def audio_encoding_args(self, fmt):
                return ['-c:a', 'aac', '-f', 'ipod']

            def video_container_args(self, fmt):
                return ['-f', 'mov']

            def video_audio_metadata(self, described=False, index=0, default=True):
                title = 'English - Audio Description' if described else 'Original Audio'
                return [f'-metadata:s:a:{index}', f'title={title}']

            def caption_export_suffix(self, captions, content):
                return ''

            def caption_input_args(self, captions, path, project):
                return []

            def caption_output_args(self, captions, path, index, content, format='mp4'):
                return []

            def video_render_args(self, source):
                return ['-c:v', 'libx264']

            def prepare_export_target(self, base, project, export_type, fmt, replace_existing):
                return 'exports/out.mov', Path(base) / 'exports/out.mov', Path(base) / 'exports/.tmp.mov'

            @contextlib.contextmanager
            def temporary_video_caption_file(self, project, captions='none', content='transcript'):
                yield Path(root) / 'captions.srt'

            def run_export(self, command, duration, **kwargs):
                commands.append([str(item) for item in command])

            def validate_audio_export(self, *args, **kwargs):
                pass

            def validate_closed_audio_description_export(self, *args, **kwargs):
                pass

            def validate_captioned_video(self, *args, **kwargs):
                pass

            def validate_rendered_video(self, *args, **kwargs):
                pass

            def validate_video_stream_copy(self, *args, **kwargs):
                pass

            def commit_export(self, project, relative, output, temporary, video_processing=None):
                project.setdefault('exports', []).append(relative)

            @property
            def parity(self):
                return SimpleNamespace(remember=lambda p: p)

        return Core()

    def args(self, **changes):
        values = dict(command='combine-imported-audio', audio_presentation='selectable', audio_only=False,
                      captions='none', content='transcript', media_format='mov', replace_existing=False)
        values.update(changes)
        return SimpleNamespace(**values)

    def value(self, **changes):
        values = project(importedAudioDescription=dict(
            path='imports/ad.wav', mode='narration', duration=19.0, sourceName='ad.wav'))
        values.update(changes)
        return values

    def test_selectable_combine_keeps_original_and_adds_described_track(self):
        value = self.value()
        assets.combine_audio(self.args(), self.root, value, self.core)
        command = self.commands[-1]
        self.assertIn('-map', command)
        self.assertIn('0:a:0', command)
        self.assertIn('[mix]', command)
        self.assertIn('sidechaincompress', ' '.join(command))
        self.assertIn('title=Original Audio', command)
        self.assertIn('title=English - Audio Description', command)
        self.assertIn('-c:v', command)
        self.assertEqual(command[command.index('-c:v') + 1], 'copy')
        self.assertEqual(value['exports'], ['exports/out.mov'])

    def test_open_presentation_does_not_keep_a_separate_original_track(self):
        value = self.value()
        assets.combine_audio(self.args(audio_presentation='open'), self.root, value, self.core)
        command = self.commands[-1]
        self.assertNotIn('0:a:0', command)
        self.assertIn('[mix]', ' '.join(command))
        self.assertIn('sidechaincompress', ' '.join(command))

    def test_full_mix_uses_the_supplied_file_without_ducking(self):
        value = self.value()
        value['importedAudioDescription']['mode'] = 'fullMix'
        assets.combine_audio(self.args(), self.root, value, self.core)
        joined = ' '.join(self.commands[-1])
        self.assertNotIn('sidechaincompress', joined)
        self.assertIn('[1:a:0]apad,atrim', joined)
        self.assertIn('0:a:0', self.commands[-1])

    def test_video_without_audio_makes_the_described_track_the_only_one(self):
        value = self.value(hasAudio=False)
        assets.combine_audio(self.args(), self.root, value, self.core)
        command = self.commands[-1]
        self.assertNotIn('0:a:0', command)
        self.assertIn('[mix]', command)

    def test_audio_only_uses_the_same_selected_source(self):
        value = self.value()
        assets.combine_audio(self.args(audio_only=True, media_format='m4a'), self.root, value, self.core)
        command = self.commands[-1]
        self.assertNotIn('0:v:0', command)
        self.assertIn('-c:a', command)
        self.assertEqual(value['exports'], ['exports/out.mov'])

    def test_combine_is_blocked_when_description_timing_needs_attention(self):
        value = self.value(transcript=[transcript(1, 4)], cues=[cue(3, 6)])
        with self.assertRaisesRegex(ValueError, 'Description timing needs attention'):
            assets.combine_audio(self.args(), self.root, value, self.core)

    def test_combine_requires_a_local_source(self):
        value = self.value(sourceType='youtube', source='')
        with self.assertRaisesRegex(ValueError, 'requires a local source video'):
            assets.combine_audio(self.args(), self.root, value, self.core)


class RealCombineTests(unittest.TestCase):
    """Runs FFmpeg so the two-track mux, metadata, and defaults are verified."""

    def setUp(self):
        import shutil as _shutil
        if not _shutil.which('ffmpeg'):
            self.skipTest('ffmpeg is required for the real combine test')
        import vidistudio_engine as engine
        self.engine = engine
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / 'source').mkdir()
        (self.root / 'imports').mkdir()
        (self.root / 'exports').mkdir()
        source = self.root / 'source/video.mp4'
        engine.run([engine.tool('ffmpeg'), '-y', '-v', 'error',
                    '-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=24',
                    '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000',
                    '-t', '2', '-c:v', 'libx264', '-c:a', 'aac', source])
        narration = self.root / 'imports/ad.wav'
        engine.run([engine.tool('ffmpeg'), '-y', '-v', 'error',
                    '-f', 'lavfi', '-i', 'sine=frequency=880:sample_rate=48000',
                    '-t', '2', narration])
        self.project = project(
            source='source/video.mp4', hasAudio=True, duration=2.0,
            transcript=[transcript(0.0, 0.5)],
            cues=[cue(0.5, 1.5, 'Described')],
            importedAudioDescription=dict(path='imports/ad.wav', mode='narration', duration=2.0, sourceName='ad.wav'),
        )

    def tearDown(self):
        self.temp.cleanup()

    def args(self, presentation='selectable', media_format='mov'):
        return SimpleNamespace(command='combine-imported-audio', audio_presentation=presentation,
                               audio_only=False, captions='none', content='transcript',
                               media_format=media_format, replace_existing=False)

    def test_selectable_combine_writes_original_and_described_tracks(self):
        assets.combine_audio(self.args(media_format='mkv'), self.root, self.project, self.engine)
        relative = self.project['exports'][0]
        info = self.engine.probe(self.root / relative)
        audio = [stream for stream in info['streams'] if stream.get('codec_type') == 'audio']
        self.assertEqual(len(audio), 2)
        self.assertEqual(audio[0]['tags'].get('title') or audio[0]['tags'].get('handler_name'), 'Original Audio')
        self.assertEqual(audio[1]['tags'].get('title') or audio[1]['tags'].get('handler_name'), 'English - Audio Description')
        self.assertEqual(audio[0]['disposition'].get('default'), 1)
        self.assertEqual(audio[1]['disposition'].get('default'), 0)
        self.assertEqual(audio[1]['disposition'].get('visual_impaired'), 1)

    def test_open_combine_writes_one_described_mix(self):
        assets.combine_audio(self.args('open'), self.root, self.project, self.engine)
        relative = self.project['exports'][0]
        info = self.engine.probe(self.root / relative)
        audio = [stream for stream in info['streams'] if stream.get('codec_type') == 'audio']
        self.assertEqual(len(audio), 1)
        self.assertEqual(audio[0]['tags'].get('title') or audio[0]['tags'].get('handler_name'), 'English - Audio Description')


if __name__ == '__main__':
    unittest.main()