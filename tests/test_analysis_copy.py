"""Verify which bytes are sent to each provider and when a reduced project becomes visible."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'engine'))
import vidistudio_engine as engine


class AnalysisCopyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name).resolve()
        self.library = self.work / 'library'
        self.original = self.work / 'original.mp4'
        self.original.write_bytes(b'original video payload')
        self.cfg = dict(vertexProject='dest-project', vertexBucket='dest', vertexAuth='signin')
        for name, options in [
            ('config', dict(return_value=self.cfg)), ('emit', {}), ('thumbnails', {}),
            ('probe', dict(return_value={'streams': [dict(codec_type='video', width=640, height=360)],
                                        'format': {'duration': '8'}})),
            ('encode_analysis_copy', dict(side_effect=self.encode))
        ]:
            setattr(self, name, self.enterContext(patch.object(engine, name, **options)))

    def encode(self, root, project):
        self.assertEqual((root / project['source']).read_bytes(), self.original.read_bytes())
        self.assertEqual(list(self.library.glob('*/project.json')), [])
        path = 'analysis/reduced.mp4'
        (root / path).parent.mkdir()
        (root / path).write_bytes(b'AI video')
        return dict(path=path, size=8, duration=8, width=320, height=180, audio='None', codec='h264')

    def command(self, *args):
        with patch.object(sys, 'argv', ['engine', *map(str, args)]):
            engine.main()

    def result(self):
        manifest, = self.library.glob('*/project.json')
        return manifest.parent, json.loads(manifest.read_text())

    def test_bucket_generation_is_provenance_and_both_providers_read_encoded_bytes(self):
        ref = dict(project='origin', bucket='source', object='priv/large.mp4', generation='7', ownership='referenced')
        with patch.object(engine.cloud_video, 'download', return_value=(self.original, ref)) as download:
            self.command('cloud-import', '--source-project', 'origin', '--source-bucket', 'source', '--name', ref['object'],
                         '--source-generation', '7', '--library', self.library, '--smaller-ai-copy')
        self.assertIsNone(download.call_args.args[3])
        self.assertEqual(download.call_args.kwargs, dict(generation='7', source_project='origin'))
        root, project = self.result()
        self.assertEqual(project['originalCloudVideo'], ref)
        self.assertNotIn('cloudVideo', project)
        reduced = root / project['analysisCopy']['path']
        self.assertFalse(project.get('useAnalysisCopy'))
        ready = SimpleNamespace(name='files/1', uri='https://example.test/files/1', mime_type='video/mp4')
        with patch.object(engine.gemini_adapter, 'ready_file', return_value=ready) as upload:
            engine.reusable_video(root, project, Mock())
        self.assertEqual(upload.call_args.args[1], reduced)
        self.assertTrue(project['geminiVideo']['fingerprint'].startswith('analysis/'))
        self.cfg.update(vertexAuth='express')
        vertex = engine.vertex_ai.VertexSession(Mock())
        self.assertEqual(engine.reusable_video(root, project, vertex).uri, reduced)
        self.assertEqual((root/project['source']).read_bytes(), self.original.read_bytes())

    def fake_bucket(self):
        bucket = Mock()
        bucket.name = 'dest'
        remote = self.work / 'uploaded.mp4'
        def blob_for(name, **kwargs):
            blob.name = name
            return blob
        blob = Mock(generation=4, content_type='video/mp4', storage_class=None, time_created=None, updated=None)
        def upload(stream, *, size, content_type, if_generation_match, checksum):
            self.assertEqual(if_generation_match, 0)
            self.assertEqual(size, 8)
            remote.write_bytes(stream.read())
            blob.size, blob.crc32c = size, engine.cloud_video.crc32c(remote)
        blob.upload_from_file.side_effect = upload
        bucket.blob.side_effect = blob_for
        self.enterContext(patch.object(engine.cloud_video, 'thumbnail', return_value=None))
        self.enterContext(patch.object(engine.cloud_video, 'bucket_for', return_value=bucket))
        return remote

    def test_cloud_create_uploads_only_reduced_file_and_serves_signed_in_vertex(self):
        remote = self.fake_bucket()
        self.command('cloud-create', '--library', self.library, '--video', self.original, '--smaller-ai-copy')
        root, project = self.result()
        self.assertEqual(remote.read_bytes(), b'AI video')
        self.assertEqual((root/project['source']).read_bytes(), self.original.read_bytes())
        cloud = project['cloudVideo']
        self.assertEqual(cloud['size'], '8')
        self.assertEqual(cloud['generation'], '4')
        vertex = engine.vertex_ai.VertexSession(Mock())
        self.assertEqual(engine.reusable_video(root, project, vertex).uri, 'gs://dest/' + cloud['object'])
        self.cfg.update(vertexAuth='express')
        self.assertEqual(engine.reusable_video(root, project, vertex).uri, root/project['analysisCopy']['path'])

    def test_failed_commit_rolls_back_owned_upload_and_discards_staging(self):
        self.fake_bucket()
        with patch.object(Path, 'rename', side_effect=OSError('Failed to publish')), patch.object(
                engine.cloud_video, 'delete_project_object') as delete, self.assertRaisesRegex(OSError, 'Failed to publish'):
            self.command('cloud-create', '--library', self.library, '--video', self.original, '--smaller-ai-copy')
        self.assertEqual(delete.call_args.args[2]['generation'], '4')
        self.assertEqual(list(self.library.iterdir()), [])
        self.assertTrue(self.original.is_file())

    def test_cancelled_conversion_discards_local_project(self):
        self.encode_analysis_copy.side_effect = engine.ProcessingCancelled('cancelled')
        with self.assertRaises(engine.ProcessingCancelled):
            self.command('import-video', '--library', self.library, '--video', self.original, '--smaller-ai-copy')
        self.assertEqual(list(self.library.iterdir()), [])
        self.assertTrue(self.original.is_file())

    def test_local_project_can_create_its_first_ai_copy_and_keep_saved_results(self):
        self.command('import-video', '--library', self.library, '--video', self.original)
        root, before = self.result()
        before['transcript'] = [{'id': 't', 'start': 0, 'end': 1, 'text': 'Original transcript'}]
        before['geminiVideo'] = {'fingerprint': 'old'}
        engine.save(root, before)
        def encode_existing(path, project):
            self.assertEqual(path, root)
            self.assertEqual((path/project['source']).read_bytes(), self.original.read_bytes())
            (path/'analysis').mkdir()
            (path/'analysis/new.mp4').write_bytes(b'AI copy')
            return dict(path='analysis/new.mp4', size=7, duration=8, width=320, height=180, audio='None', codec='h264')
        self.encode_analysis_copy.side_effect = encode_existing
        self.command('regenerate-ai-copy', '--project', root)
        _, after = self.result()
        self.assertEqual(after['analysisCopy']['path'], 'analysis/new.mp4')
        self.assertEqual(after['transcript'], before['transcript'])
        self.assertEqual(after['source'], before['source'])
        self.assertNotIn('geminiVideo', after)
        self.assertFalse(after.get('useAnalysisCopy'))

    def test_failed_regeneration_keeps_prior_local_and_cloud_copy(self):
        self.fake_bucket()
        self.command('cloud-create', '--library', self.library, '--video', self.original, '--smaller-ai-copy')
        root, project = self.result()
        original_copy = root/project['analysisCopy']['path']
        def encode_different(root, project):
            replacement = root/'analysis/replacement.mp4'
            replacement.write_bytes(b'new encode')
            return dict(project['analysisCopy'], path='analysis/replacement.mp4')
        self.encode_analysis_copy.side_effect = encode_different
        with self.assertRaisesRegex(engine.import_assets.ImportIssue, 'differs from the uploaded AI copy'):
            self.command('regenerate-ai-copy', '--project', root)
        self.assertEqual(self.result()[1]['analysisCopy'], project['analysisCopy'])
        self.assertEqual(self.result()[1]['cloudVideo'], project['cloudVideo'])
        self.assertTrue(original_copy.is_file())
        self.assertFalse((root/'analysis/replacement.mp4').exists())

    def test_regeneration_validates_and_saves_before_retiring_managed_copies(self):
        self.command('import-video', '--library', self.library, '--video', self.original, '--smaller-ai-copy')
        root, before = self.result()
        old = root / before['analysisCopy']['path']
        orphan = root / 'analysis/ai-000000000000.mp4'
        orphan.write_bytes(b'older copy')
        unrelated = root / 'analysis/user-video.mp4'
        unrelated.write_bytes(b'user file')
        fresh = root / 'analysis/ai-000000000001.mp4'

        def encode(path, project):
            self.assertTrue(old.is_file())
            fresh.write_bytes(b'new AI copy')
            return dict(before['analysisCopy'], path=fresh.relative_to(root).as_posix(), size=fresh.stat().st_size)

        unlink = Path.unlink

        def check_committed(path, *args, **kwargs):
            if path in (old, orphan):
                self.assertEqual(self.result()[1]['analysisCopy']['path'], fresh.relative_to(root).as_posix())
                self.assertTrue(fresh.is_file())
            return unlink(path, *args, **kwargs)

        self.encode_analysis_copy.side_effect = encode
        with patch.object(Path, 'unlink', check_committed):
            self.command('regenerate-ai-copy', '--project', root)
        self.assertFalse(old.exists())
        self.assertFalse(orphan.exists())
        self.assertTrue(unrelated.exists())
        self.assertEqual((root / before['source']).read_bytes(), self.original.read_bytes())

    def test_locked_previous_copy_rolls_back_replacement(self):
        self.command('import-video', '--library', self.library, '--video', self.original, '--smaller-ai-copy')
        root, before = self.result()
        old = root / before['analysisCopy']['path']
        fresh = root / 'analysis/ai-000000000001.mp4'

        def encode(path, project):
            fresh.write_bytes(b'new AI copy')
            return dict(before['analysisCopy'], path=fresh.relative_to(root).as_posix(), size=fresh.stat().st_size)

        unlink = Path.unlink

        def locked(path, *args, **kwargs):
            if path == old:
                raise PermissionError('copy is open')
            return unlink(path, *args, **kwargs)

        self.encode_analysis_copy.side_effect = encode
        with patch.object(Path, 'unlink', locked), self.assertRaisesRegex(engine.import_assets.ImportIssue, 'Close any player'):
            self.command('regenerate-ai-copy', '--project', root)
        self.assertEqual(self.result()[1], before)
        self.assertTrue(old.is_file())
        self.assertFalse(fresh.exists())
