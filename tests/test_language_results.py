"""Behavioral regressions for portable language results and safe alternatives."""
import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'engine'))
import language_results as lr


class LanguageResultsTests(unittest.TestCase):
    def setUp(self):
        self.p = dict(id='project', schemaVersion=2, name='Example', duration=10,
                      transcript=[dict(id='t', start=0, end=1, text='Original')],
                      summary='Original summary', cues=[dict(id='a', start=2, end=4, text='Scene', audio='audio-description/old.mp3')],
                      exports=['exports/old.txt'], undoStack=[[dict(audio='audio-description/history.mp3')]])
        lr.migrate(self.p)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.core = SimpleNamespace(atomic_json=lambda path, value: path.write_text(json.dumps(value)),
                                    save=lambda root, value: lr.checkpoint(root, value, self.core.atomic_json) or self.core.atomic_json(root/'project.json', value),
                                    emit=lambda *a, **k: None)

    def args(self, command, **kwargs):
        return SimpleNamespace(command=command, replace_existing=False, source_transcript_id=None,
                               source_summary_id=None, **kwargs)

    def test_migration_is_idempotent_and_keeps_history(self):
        first = copy.deepcopy(self.p)
        lr.migrate(self.p)
        self.assertEqual(first, self.p)
        self.assertEqual(self.p['schemaVersion'], 3)
        self.assertIn('audio-description/history.mp3', lr.referenced_paths(self.p))

    def test_duplicate_generation_is_recoverable_draft(self):
        old = copy.deepcopy(self.p['summary'])
        def generate(args, root, p):
            p['summary'] = 'New summary'
        ids = lr.produce(self.args('generate-summary'), self.root, self.p, self.core, generate)
        self.assertEqual(self.p['summary'], old)
        result = lr.find(self.p, ids['summary'])
        self.assertEqual(result['state'], 'draft')
        self.assertEqual(result['payload']['summary'], 'New summary')
        self.assertEqual(json.loads((self.root/'project.json').read_text())['summary'], old)

    def test_new_language_is_saved_without_changing_auto(self):
        self.p['selectedLanguage'] = 'hi'; lr.project(self.p)
        ids = lr.produce(self.args('generate-summary'), self.root, self.p, self.core,
                         lambda args, root, p: p.update(summary='Hindi'))
        self.assertEqual(lr.find(self.p, ids['summary'])['state'], 'saved')
        self.assertEqual(self.p['summary'], 'Hindi')
        self.p['selectedLanguage'] = 'auto'; lr.project(self.p)
        self.assertEqual(self.p['summary'], 'Original summary')

    def test_generation_failure_never_changes_saved_result(self):
        def fail(args, root, p):
            p['summary'] = 'Partial'; self.core.save(root, p)
            raise ValueError('Unavailable')
        with self.assertRaises(ValueError):
            lr.produce(self.args('generate-summary'), self.root, self.p, self.core, fail)
        self.assertEqual(self.p['summary'], 'Original summary')
        self.assertEqual(len([r for r in self.p['languageResults'] if r['state'] == 'draft']), 1)

    def test_delete_one_result_preserves_other_language_and_audio(self):
        base = lr.active(self.p, 'descriptions')
        other = lr.record(self.p, 'descriptions', 'hi', copy.deepcopy(base['payload']))
        self.p['languageResults'].append(other)
        lr.delete(self.p, dict(resultIDs=[base['id']], components=['descriptions']))
        self.assertEqual(lr.find(self.p, other['id'])['language'], 'hi')
        self.assertIn('audio-description/old.mp3', lr.referenced_paths(self.p))
        self.assertEqual(self.p['cues'], [])

    def test_default_migration_and_language_validation(self):
        self.assertEqual(lr.default_language(dict(outputLanguages=dict(transcript='hi', summary='hi', audio_descriptions='hi'))), 'hi')
        self.assertEqual(lr.default_language(dict(outputLanguages=dict(transcript='hi'))), 'auto')
        with self.assertRaises(ValueError): lr.language('all')

    def test_generation_restores_operation_language_environment(self):
        with patch.dict(os.environ, {'VIDISTUDIO_OUTPUT_LANGUAGE': 'fr'}):
            self.p['sectionLanguages']['summary'] = 'hi'
            def generate(args, root, p):
                self.assertEqual(os.environ['VIDISTUDIO_OUTPUT_LANGUAGE'], 'hi')
                p['summary'] = 'Hindi'
            lr.produce(self.args('generate-summary'), self.root, self.p, self.core, generate)
            self.assertEqual(os.environ['VIDISTUDIO_OUTPUT_LANGUAGE'], 'fr')

    def test_generation_target_does_not_retarget_view_or_edit_history(self):
        self.p['sectionLanguages']['summary'] = 'hi'
        made = lr.produce(self.args('generate-summary'), self.root, self.p, self.core,
            lambda args, root, p: p.update(summary='Hindi alternative'))
        self.assertEqual(self.p['summary'], 'Original summary')
        self.p['summary'] = 'Edited viewed Auto summary'
        lr.capture(self.p)
        self.assertEqual(lr.active(self.p, 'summary')['payload']['summary'], 'Edited viewed Auto summary')
        self.assertEqual(lr.find(self.p, made['summary'])['payload']['summary'], 'Hindi alternative')

    def test_older_schema3_projection_does_not_overwrite_view_language(self):
        p = copy.deepcopy(self.p)
        hi = lr.record(p, 'summary', 'hi', dict(summary='Hindi saved text'))
        p['languageResults'].append(hi)
        p['sectionLanguages']['summary'] = 'hi'
        p['summary'] = 'Hindi saved text'  # Projection from the previous section-target behavior.
        p.pop('languageViewVersion', None)
        lr.migrate(p); lr.capture(p)
        self.assertEqual(p['summary'], 'Original summary')
        self.assertEqual(lr.active(p, 'summary')['payload']['summary'], 'Original summary')
        self.assertEqual(lr.find(p, hi['id'])['payload']['summary'], 'Hindi saved text')
        before = copy.deepcopy(p); lr.migrate(p)
        self.assertEqual(before, p)

    def test_language_folders_move_files_and_web_assets_without_overwrite(self):
        self.core.local = lambda root, relative: (root/relative).resolve()
        (self.root/'exports').mkdir()
        (self.root/'exports/old.txt').write_text('old')
        (self.root/'exports/hi').mkdir()
        (self.root/'exports/hi/old.txt').write_text('retained')
        (self.root/'exports/web/video').mkdir(parents=True)
        (self.root/'exports/web/index.m3u8').write_text('video/stream.m3u8')
        (self.root/'exports/web/video/stream.m3u8').write_text('media')
        self.p['exports'].append('exports/web')
        self.p['exportResults'] = {'exports/old.txt': dict(language='hi'), 'exports/web': dict(language='hi')}
        self.p['exportMediaInfo'] = {'exports/old.txt': dict(duration=2)}
        self.p['exportAudioSources'] = {'exports/old.txt': dict(origin='original')}
        lr.organize_exports(self.root, self.p, self.core)
        self.assertEqual((self.root/'exports/hi/old.txt').read_text(), 'retained')
        self.assertIn('exports/hi/old.txt', self.p['exports'])
        self.assertEqual((self.root/'exports/hi/old (2).txt').read_text(), 'old')
        self.assertEqual((self.root/'exports/hi/web/index.m3u8').read_text(), 'video/stream.m3u8')
        self.assertTrue((self.root/'exports/hi/web/video/stream.m3u8').is_file())
        self.assertIn('exports/hi/old (2).txt', self.p['exportResults'])
        self.assertIn('exports/hi/old (2).txt', self.p['exportMediaInfo'])
        self.assertIn('exports/hi/old (2).txt', self.p['exportAudioSources'])
        before = copy.deepcopy(self.p); lr.organize_exports(self.root, self.p, self.core)
        self.assertEqual(before, self.p)

    def test_export_move_recovers_after_rename_before_manifest_save(self):
        self.core.local = lambda root, relative: (root/relative).resolve()
        (self.root/'exports/auto').mkdir(parents=True)
        (self.root/'exports/auto/old.txt').write_text('kept')
        (self.root/'exports/.language-folders.json').write_text(json.dumps({'exports/old.txt': 'exports/auto/old.txt'}))
        lr.organize_exports(self.root, self.p, self.core, recover_only=True)
        self.assertEqual(self.p['exports'], ['exports/auto/old.txt'])
        self.assertFalse((self.root/'exports/.language-folders.json').exists())

    def test_cleanup_preserves_nested_exports_and_all_web_package_assets(self):
        import vidistudio_engine as engine
        (self.root/'exports/hi/web/video').mkdir(parents=True)
        (self.root/'exports/hi/keep.mp4').write_bytes(b'kept')
        (self.root/'exports/hi/web/video/media.ts').write_bytes(b'kept media')
        (self.root/'exports/hi/orphan.tmp').write_bytes(b'orphan')
        project = dict(id='nested', schemaVersion=2, source='', transcript=[], summary='', cues=[], thumbnails=[], exports=['exports/hi/keep.mp4', 'exports/hi/web'])
        engine.cleanup_project_storage(self.root, project)
        self.assertTrue((self.root/'exports/hi/keep.mp4').is_file())
        self.assertTrue((self.root/'exports/hi/web/video/media.ts').is_file())
        self.assertFalse((self.root/'exports/hi/orphan.tmp').exists())

    def test_combined_imported_audio_export_remains_tracked(self):
        self.core.local = lambda root, relative: (root/relative).resolve()
        self.core.cleanup_project_storage = lambda root, project: None
        args = self.args('combine-imported-audio', language=None)
        def combine(args, root, project):
            project['exports'].append('exports/auto/combined.mp4')
        lr.run(args, self.root, self.p, self.core, combine)
        self.assertIn('exports/auto/combined.mp4', self.p['exports'])

    def test_export_move_journal_cannot_move_project_source_files(self):
        self.core.local = lambda root, relative: (root/relative).resolve()
        (self.root/'exports').mkdir()
        (self.root/'source').mkdir()
        source = self.root/'source/video.mp4'; source.write_bytes(b'original')
        (self.root/'exports/.language-folders.json').write_text(json.dumps({'exports/../source/video.mp4': 'exports/auto/video.mp4'}))
        with self.assertRaisesRegex(ValueError, 'exports folder'):
            lr.organize_exports(self.root, self.p, self.core, recover_only=True)
        self.assertEqual(source.read_bytes(), b'original')
        self.assertFalse((self.root/'exports/auto/video.mp4').exists())

    def test_container_language_is_never_assumed_english(self):
        with patch.object(lr, '_export_language', 'auto'): self.assertEqual(lr.track_language(), 'und')
        with patch.object(lr, '_export_language', 'hi'): self.assertEqual(lr.track_language(), 'hin')


class LanguageResultCLITests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.project = self.root / 'project.json'
        self.project.write_text(json.dumps(dict(schemaVersion=2, id='cli', name='CLI project', source='',
            duration=10, width=0, height=0, hasAudio=False, createdAt=1, updatedAt=1, thumbnails=[],
            transcript=[dict(id='t', start=0, end=1, text='Original dialogue')],
            summary='Original summary', cues=[], exports=[], status='Ready')))
        self.input = self.root / 'import.md'
        self.input.write_text('Imported alternative')
        self.config = self.root / 'config.json'
        self.config.write_text('{}')

    def cli(self, command, *arguments, succeeds=True):
        env = dict(os.environ, VIDISTUDIO_CONFIG=str(self.config))
        env.pop('VIDISTUDIO_API_KEY', None)
        env.pop('VIDISTUDIO_OUTPUT_LANGUAGE', None)
        prefix = [os.environ['VIDISTUDIO_TEST_ENGINE']] if os.environ.get('VIDISTUDIO_TEST_ENGINE') else [sys.executable, str(Path(lr.__file__).with_name('vidistudio_engine.py'))]
        result = subprocess.run([*prefix, command, '--project', str(self.root), *map(str, arguments)], env=env, capture_output=True, text=True)
        if succeeds:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def read(self):
        return json.loads(self.project.read_text())

    def test_import_review_keep_replace_discard_and_reopen(self):
        for disposition in ('keep', 'replace', 'discard'):
            self.cli('import-summary', '--input', self.input)
            p = self.read()
            self.assertEqual(p['summary'], 'Original summary' if disposition == 'keep' else self.expected)
            draft = next(r for r in p['languageResults'] if r['state'] == 'draft')
            self.cli('review-result', '--result-id', draft['id'], '--disposition', disposition)
            p = self.read()
            self.expected = 'Imported alternative'
            self.assertEqual(p['summary'], self.expected)
            self.assertFalse(any(r['state'] == 'draft' for r in p['languageResults']))
        self.assertGreaterEqual(len([r for r in self.read()['languageResults'] if r['kind'] == 'summary']), 2)

    def test_batch_export_has_frozen_language_selections_and_provenance(self):
        self.cli('import-summary', '--input', self.input, '--language', 'hi')
        p = self.read()
        self.cli('select-language', '--language', 'auto')
        jobs = []
        for code in ('auto', 'hi'):
            rid = next(r['id'] for r in p['languageResults'] if r['kind'] == 'summary' and r['language'] == code)
            jobs.append(dict(language=code, resultIDs=dict(summary=rid), command='export-subtitles', options=dict(content='summary', format='md')))
        request = self.root/'batch.json'; request.write_text(json.dumps(dict(jobs=jobs)))
        self.cli('export-batch', '--input', request)
        p = self.read()
        self.assertEqual(p['selectedLanguage'], 'auto')
        self.assertEqual(len(p['exports']), 2)
        self.assertEqual({Path(path).parts[1] for path in p['exports']}, {'auto', 'hi'})
        self.assertEqual({v['language'] for v in p['exportResults'].values()}, {'auto', 'hi'})
        self.assertEqual({(self.root/path).read_text().strip() for path in p['exports']}, {'# Summary\n\nOriginal summary', '# Summary\n\nImported alternative'})

    def test_invalid_batch_selection_writes_no_exports(self):
        self.cli('select-language', '--language', 'auto')
        p = self.read(); rid = next(r['id'] for r in p['languageResults'] if r['kind'] == 'summary')
        request = self.root/'batch.json'
        request.write_text(json.dumps(dict(jobs=[
            dict(language='auto', resultIDs=dict(summary=rid), command='export-subtitles', options=dict(content='summary', format='md')),
            dict(language='hi', resultIDs=dict(summary=rid), command='export-subtitles', options=dict(content='summary', format='md'))])))
        self.cli('export-batch', '--input', request, succeeds=False)
        self.assertEqual(self.read()['exports'], [])

    def test_deletion_preview_is_read_only_and_scoped(self):
        self.cli('import-summary', '--input', self.input, '--language', 'hi')
        p = self.read(); original = self.project.read_bytes()
        rid = next(r['id'] for r in p['languageResults'] if r['kind'] == 'summary' and r['language'] == 'hi')
        request = self.root/'delete.json'; request.write_text(json.dumps(dict(resultIDs=[rid], components=['summary'])))
        preview = self.root/'preview.json'
        self.cli('preview-delete-results', '--input', request, '--output', preview)
        self.assertEqual(self.project.read_bytes(), original)
        self.assertEqual(json.loads(preview.read_text())['resultCount'], 1)
        self.cli('delete-results', '--input', request)
        self.cli('select-language', '--language', 'auto')
        self.cli('sync-section-languages')
        self.assertEqual(self.read()['summary'], 'Original summary')

    def test_view_language_switches_content_without_changing_generation_targets(self):
        self.cli('import-summary', '--input', self.input, '--language', 'hi')
        self.assertEqual(self.read()['summary'], 'Original summary')
        self.assertEqual(self.read()['sectionLanguages'], {})
        self.cli('select-section-language', '--section', 'summary', '--language', 'hi')
        self.cli('select-section-language', '--section', 'transcript', '--language', 'en')
        self.assertEqual(self.read()['transcript'][0]['text'], 'Original dialogue')
        self.cli('select-language', '--language', 'hi')
        self.assertEqual(self.read()['summary'], 'Imported alternative')
        self.assertEqual(self.read()['transcript'], [])
        self.cli('select-language', '--language', 'ta')
        self.assertEqual(self.read()['summary'], '')
        self.assertEqual(self.read()['sectionLanguages'], dict(summary='hi', transcript='en'))
        self.cli('sync-section-languages')
        self.assertEqual(self.read()['sectionLanguages'], {})
        self.cli('select-language', '--language', 'auto')
        self.assertEqual(self.read()['summary'], 'Original summary')
        self.cli('select-section-language', '--section', 'summary', '--language', 'auto')
        self.cli('select-language', '--language', 'hi')
        self.assertEqual(self.read()['summary'], 'Imported alternative')
        self.assertEqual(self.read()['sectionLanguages']['summary'], 'auto')

    def test_edit_targets_captured_result_id(self):
        self.cli('import-summary', '--input', self.input)
        draft = next(r for r in self.read()['languageResults'] if r['state'] == 'draft')
        old_id = draft['replacesResultID']
        self.cli('review-result', '--result-id', draft['id'], '--disposition', 'keep')
        edit = self.root/'edit.json'; edit.write_text(json.dumps(dict(summary='Edited older result')))
        self.cli('save-summary', '--input', edit, '--selected-summary-id', old_id)
        results = {r['id']: r for r in self.read()['languageResults']}
        self.assertEqual(results[old_id]['payload']['summary'], 'Edited older result')
        self.assertEqual(results[draft['id']]['payload']['summary'], 'Imported alternative')


    def test_review_another_language_does_not_change_generation_target(self):
        self.cli('select-section-language', '--section', 'summary', '--language', 'hi')
        self.cli('import-summary', '--input', self.input)
        self.cli('import-summary', '--input', self.input)
        draft = next(r for r in json.loads(self.project.read_text())['languageResults'] if r['state'] == 'draft')
        self.cli('select-section-language', '--section', 'summary', '--language', 'auto')
        self.cli('review-result', '--result-id', draft['id'], '--disposition', 'keep')
        saved = json.loads(self.project.read_text())
        self.assertEqual(saved['sectionLanguages']['summary'], 'auto')
        self.assertEqual(saved['summary'], 'Original summary')
        self.assertEqual(next(r for r in saved['languageResults'] if r['id'] == draft['id'])['state'], 'saved')
        self.cli('select-language', '--language', 'hi')
        self.assertEqual(json.loads(self.project.read_text())['summary'], 'Imported alternative')


    def test_reopening_uses_saved_results_before_capturing_stale_projection(self):
        p = self.read(); lr.migrate(p)
        p['sectionLanguages']['summary'] = 'hi'
        p['summary'] = 'Stale top-level text'
        self.project.write_text(json.dumps(p))
        self.cli('select-overview-language', '--language', 'project')
        self.assertEqual(self.read()['summary'], 'Original summary')
        self.assertEqual(next(r for r in self.read()['languageResults'] if r['kind'] == 'summary')['payload']['summary'], 'Original summary')

    def test_shared_view_language_ignores_legacy_overview_override(self):
        p = self.read(); p['overviewLanguage'] = 'hi'
        self.project.write_text(json.dumps(p))
        self.cli('select-language', '--language', 'auto')
        self.assertNotIn('overviewLanguage', self.read())
        self.assertEqual(self.read()['summary'], 'Original summary')
        self.assertEqual(self.read()['sectionLanguages'], {})

    def test_export_organizes_legacy_files_and_updates_metadata_links(self):
        self.cli('select-language', '--language', 'auto')
        p = self.read()
        (self.root/'exports').mkdir(exist_ok=True)
        (self.root/'exports/legacy.txt').write_text('older export')
        p['exports'] = ['exports/legacy.txt']
        p['exportResults'] = {'exports/legacy.txt': dict(language='hi', resultIDs={}, createdAt=1)}
        p['exportMediaInfo'] = {'exports/legacy.txt': dict(duration=1)}
        self.project.write_text(json.dumps(p))
        rid = next(r['id'] for r in p['languageResults'] if r['kind'] == 'summary')
        request = self.root/'export.json'
        request.write_text(json.dumps(dict(jobs=[dict(language='auto', resultIDs=dict(summary=rid), command='export-subtitles', options=dict(content='summary', format='md'))])))
        self.cli('export-batch', '--input', request)
        saved = self.read()
        self.assertFalse((self.root/'exports/legacy.txt').exists())
        self.assertEqual((self.root/'exports/hi/legacy.txt').read_text(), 'older export')
        self.assertIn('exports/hi/legacy.txt', saved['exportResults'])
        self.assertIn('exports/hi/legacy.txt', saved['exportMediaInfo'])
        self.assertEqual(saved['selectedLanguage'], 'auto')
        self.assertFalse((self.root/'exports/.language-folders.json').exists())

    def test_overview_results_use_shared_view_language_without_changing_targets(self):
        p = self.read(); lr.migrate(p)
        result = lr.record(p, 'descriptions', 'hi', dict(cues=[dict(id='h', start=2, end=3, text='Hindi scene')]))
        p['languageResults'].append(result)
        p['sectionLanguages']['descriptions'] = 'en'
        self.project.write_text(json.dumps(p))
        self.cli('select-language', '--language', 'hi')
        self.cli('select-result', '--result-id', result['id'])
        saved = self.read()
        self.assertEqual(saved['cues'][0]['text'], 'Hindi scene')
        self.assertEqual(saved['sectionLanguages']['descriptions'], 'en')
        self.cli('select-language', '--language', 'auto')
        self.assertEqual(self.read()['cues'], [])
        self.cli('select-result', '--result-id', result['id'], succeeds=False)


@unittest.skipUnless(sys.platform == 'darwin', 'AVFoundation metadata verification requires macOS')
class AppleLanguageExportTests(unittest.TestCase):
    def test_hindi_language_survives_native_mov_accessibility_finalization(self):
        import vidistudio_engine as engine
        repo = Path(__file__).resolve().parents[1]
        mac = repo if (repo/'VidiStudio/AccessibilityMetadataWriter.swift').exists() else repo.parent/'VidiStudio Mac'
        with tempfile.TemporaryDirectory() as temporary, patch.object(engine, 'config', return_value={}), patch.object(lr, '_export_language', 'hi'):
            root = Path(temporary)
            helper = root/'inspect'
            compiled = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(root/'modules'),
                str(mac/'VidiStudio/AccessibilityMetadataWriter.swift'), str(mac/'tests/export_track_inspector.swift'),
                '-o', str(helper)], capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            ffmpeg = engine.tool('ffmpeg')
            engine.run([ffmpeg, '-y', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=64x64:rate=24',
                '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000', '-t', '2', '-c:v', 'libx264', '-c:a', 'aac', root/'source.mp4'])
            (root/'audio-description').mkdir()
            engine.run([ffmpeg, '-y', '-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=880:sample_rate=48000',
                '-t', '0.3', root/'audio-description/ad.mp3'])
            p = dict(name='Hindi', source='source.mp4', duration=2, width=64, height=64, hasAudio=True, exports=[],
                transcript=[dict(id='t', start=1, end=1.5, text='नमस्ते')],
                cues=[dict(id='ad', start=.1, end=.8, text='दृश्य', audio='audio-description/ad.mp3',
                    audioText='दृश्य', audioDuration=.3, audioSettings='imported', audioOrigin='imported')])
            engine.export(root, p, selectable=True, captions='closed', content='transcript', media_format='mov')
            output = root/p['exports'][0]
            inspected = subprocess.run([str(helper), str(output), '--finalize', '--described'], capture_output=True, text=True)
            self.assertEqual(inspected.returncode, 0, inspected.stdout + inspected.stderr)
            data = json.loads(inspected.stdout)
            self.assertTrue(data['playable'])
            self.assertIn(data['tracks']['audio'][-1]['language'], ('hi', 'hin'))
            self.assertTrue(data['tracks']['audio'][-1]['describesVideo'])
            self.assertIn(data['tracks']['subtitles'][0]['language'], ('hi', 'hin'))
            self.assertTrue(data['tracks']['subtitles'][0]['spokenDialog'])


if __name__ == '__main__':
    unittest.main()
