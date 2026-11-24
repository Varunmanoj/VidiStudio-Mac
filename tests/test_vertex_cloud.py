import io
import json
import os
import sys
import tempfile
import unittest
import uuid
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'engine'))
import cloud_video
import vertex_ai


class VertexCloudTests(unittest.TestCase):
    def test_cloud_sign_in_writes_only_the_cloud_credential(self):
        with patch.object(vertex_ai, 'vault') as vault, patch.object(vertex_ai, 'oauth_client', return_value={'client_id': 'test-desktop-client'}):
            vertex_ai.save_google_sign_in('fake-refresh-token')
            vault.return_value.set_password.assert_called_once_with(
                vertex_ai.SERVICE, 'test-desktop-client', 'fake-refresh-token')
            for invalid in ('', 'two words', 'x' * 8193):
                with self.subTest(invalid=invalid[:12]), self.assertRaisesRegex(ValueError, 'Google sign-in could not be saved'):
                    vertex_ai.save_google_sign_in(invalid)
            self.assertEqual(vault.return_value.set_password.call_count, 1)

    def test_private_youtube_requires_the_vertex_account_to_own_the_channel(self):
        details = Mock()
        details.json.return_value = {'items': [{'id': 'jNQXAC9IVRw', 'status': {'privacyStatus': 'private'},
                                               'snippet': {'channelId': 'owner'}}]}
        channels = Mock()
        cfg = {'vertexProject': 'sample-project'}
        with patch('google.auth.transport.requests.AuthorizedSession') as authorized, patch.object(vertex_ai, 'youtube_owner_credentials') as credentials:
            session = authorized.return_value.__enter__.return_value
            session.get.side_effect = [details, channels, details, channels]
            channels.json.side_effect = [{'items': [{'id': 'other-account'}]}, {'items': [{'id': 'owner'}]}]
            with self.assertRaisesRegex(ValueError, 'Private Video Cannot Be Opened'):
                vertex_ai.require_private_youtube_owner(cfg, 'jNQXAC9IVRw', 'owner')
            vertex_ai.require_private_youtube_owner(cfg, 'jNQXAC9IVRw', 'owner')
            credentials.assert_called_with('owner')

    def test_cloud_and_youtube_use_separate_scopes_and_vault_entries(self):
        client = {'client_id': 'test-desktop-client', 'client_secret': 'test-secret'}
        with patch.dict(os.environ, {'VIDISTUDIO_CLOUD_SUBJECT': 'cloud-owner'}), \
                patch.object(vertex_ai, 'vault') as vault, patch.object(vertex_ai, 'oauth_client', return_value=client):
            service_and_account = (('VidiStudio/YouTube/cloud-owner:private-channel', 'YouTube refresh token')
                                   if os.name == 'nt' else ('com.vidistudio.youtube', 'cloud-owner:private-channel'))
            tokens = {
                (vertex_ai.SERVICE, client['client_id']): 'cloud-refresh',
                service_and_account: 'youtube-refresh',
            }
            vault.return_value.get_password.side_effect = lambda service, account: tokens.get((service, account))
            cloud = vertex_ai.credentials('sample-project')
            youtube = vertex_ai.youtube_owner_credentials('private-channel')
            self.assertEqual((cloud.refresh_token, cloud.scopes), ('cloud-refresh', [vertex_ai.SCOPE]))
            self.assertEqual((youtube.refresh_token, youtube.scopes), ('youtube-refresh', [vertex_ai.YOUTUBE_SCOPE]))
            with self.assertRaisesRegex(ValueError, 'Private Video Cannot Be Opened'):
                vertex_ai.youtube_owner_credentials('different-channel')
            vertex_ai.disconnect()
            vault.return_value.delete_password.assert_called_once_with(vertex_ai.SERVICE, client['client_id'])

    def test_accessible_projects_paginates_and_omits_inactive_projects(self):
        first = Mock()
        second = Mock()
        first.json.return_value = {
            'projects': [{'projectId': 'z-project', 'displayName': 'Zulu', 'state': 'ACTIVE'},
                         {'projectId': 'old-project', 'state': 'DELETE_REQUESTED'}],
            'nextPageToken': 'next',
        }
        second.json.return_value = {'projects': [{'projectId': 'a-project', 'displayName': 'Alpha', 'state': 'ACTIVE'}]}
        with patch('google.auth.transport.requests.AuthorizedSession') as authorized, patch.object(vertex_ai, 'credentials'):
            session = authorized.return_value.__enter__.return_value
            session.get.side_effect = [first, second]
            rows = cloud_video.accessible_projects({'vertexProject': 'destination'})
        self.assertEqual(rows, [{'id': 'a-project', 'name': 'Alpha'}, {'id': 'z-project', 'name': 'Zulu'}])
        self.assertEqual(session.get.call_args.kwargs['params']['pageToken'], 'next')

    def test_source_bucket_does_not_change_destination_or_quota_project(self):
        cfg = {'vertexProject': 'destination-project', 'vertexBucket': 'destination-bucket'}
        with patch('google.cloud.storage.Client') as client, patch.object(vertex_ai, 'credentials') as auth:
            session = client.return_value.__enter__.return_value
            session.list_buckets.return_value = [SimpleNamespace(name='source-bucket')]
            self.assertEqual(cloud_video.project_buckets(cfg, 'source-project'), ['source-bucket'])
        auth.assert_called_once_with('destination-project')
        session.list_buckets.assert_called_once_with(project='source-project', timeout=30)
        self.assertEqual(cfg['vertexBucket'], 'destination-bucket')

    def test_first_cloud_sign_in_can_browse_without_a_default_project(self):
        with patch('google.auth.transport.requests.AuthorizedSession') as authorized, patch.object(vertex_ai, 'credentials') as auth:
            response = authorized.return_value.__enter__.return_value.get.return_value
            response.json.return_value = {'projects': [{'projectId': 'source', 'state': 'ACTIVE'}]}
            self.assertEqual(cloud_video.accessible_projects({}), [{'id': 'source', 'name': 'source'}])
            auth.assert_called_once_with(None, allow_missing_project=True)

        with patch('google.cloud.storage.Client') as client, patch.object(vertex_ai, 'credentials') as auth:
            client.return_value.__enter__.return_value.list_buckets.return_value = [SimpleNamespace(name='video-bucket')]
            self.assertEqual(cloud_video.project_buckets({}, 'source'), ['video-bucket'])
            auth.assert_called_once_with('source')

    def test_object_permissions_checks_source_and_candidate_destination(self):
        from google.iam.v1.iam_policy_pb2 import TestIamPermissionsResponse

        with patch('google.auth.transport.grpc.secure_authorized_channel') as channel, patch.object(vertex_ai, 'credentials'):
            call = channel.return_value.__enter__.return_value.unary_unary.return_value
            call.side_effect = [TestIamPermissionsResponse(permissions=['storage.objects.get', 'storage.objects.delete']),
                                TestIamPermissionsResponse(permissions=[])]
            result = cloud_video.object_permissions({'vertexProject': 'destination'}, 'source', 'folder/old.mp4', 'folder/new.mp4')
        self.assertEqual(result, {'rename': False, 'delete': True})
        self.assertEqual([request.args[0].resource for request in call.call_args_list],
                         ['projects/_/buckets/source/objects/folder/old.mp4', 'projects/_/buckets/source/objects/folder/new.mp4'])

    def test_object_mutation_requires_matching_generation_and_permission(self):
        args = SimpleNamespace(source_project='source-project', source_bucket='source-bucket',
                               name='folder/video.mp4', source_generation='9', command='cloud-object-delete')
        blob = Mock(name='blob', generation=9, content_type='video/mp4', metadata={})
        blob.name = args.name
        bucket = Mock()
        bucket.blob.return_value = blob
        with patch.object(cloud_video, 'bucket_for', return_value=bucket), patch.object(
            cloud_video, 'object_permissions', return_value={'delete': False, 'rename': False}
        ) as permissions, self.assertRaises(PermissionError):
            cloud_video.manage_bucket_video({}, args, Mock())
        blob.delete.assert_not_called()
        permissions.assert_called_once()
        blob.generation = 10
        with patch.object(cloud_video, 'bucket_for', return_value=bucket), patch.object(
            cloud_video, 'object_permissions'
        ) as permissions, self.assertRaisesRegex(ValueError, 'changed'):
            cloud_video.manage_bucket_video({}, args, Mock())
        blob.delete.assert_not_called()
        permissions.assert_not_called()

    def test_delete_project_retains_generation_and_ownership_guards(self):
        from google.api_core.exceptions import NotFound, PreconditionFailed

        owner = str(uuid.uuid4())
        cfg = {'vertexProject': 'project', 'vertexBucket': 'bucket'}
        record = dict(project='project', bucket='bucket', object=f'vidistudio/{owner}/clip.mp4', generation='9')
        bucket = Mock()
        bucket.name = 'bucket'
        blob = bucket.blob.return_value
        blob.generation, blob.metageneration = 9, 5
        blob.metadata = {'vidistudio-project': owner}
        with patch.object(cloud_video, 'bucket_for', return_value=bucket), patch.object(
            cloud_video, 'object_permissions', return_value={'delete': True}
        ) as permissions:
            cloud_video.delete_project_object(cfg, owner, record, Mock())
            blob.delete.assert_called_once_with(if_generation_match=9, if_metageneration_match=5)
            blob.delete.reset_mock()
            permissions.return_value = {'delete': False}
            with self.assertRaises(PermissionError):
                cloud_video.delete_project_object(cfg, owner, record, Mock())
            blob.delete.assert_not_called()
            permissions.return_value = {'delete': True}
            blob.generation = 10
            with self.assertRaisesRegex(ValueError, 'newer'):
                cloud_video.delete_project_object(cfg, owner, record, Mock())
            blob.generation = 9
            blob.metadata = {'vidistudio-project': str(uuid.uuid4())}
            with self.assertRaisesRegex(ValueError, 'different project'):
                cloud_video.delete_project_object(cfg, owner, record, Mock())
            blob.delete.assert_not_called()
            blob.metadata = {'vidistudio-project': owner}
            blob.delete.side_effect = PreconditionFailed('raced')
            with self.assertRaisesRegex(ValueError, 'changed'):
                cloud_video.delete_project_object(cfg, owner, record, Mock())
            blob.delete.reset_mock()
            blob.reload.side_effect = NotFound('absent')
            cloud_video.delete_project_object(cfg, owner, record, Mock())
            blob.delete.assert_not_called()

    def test_project_deletion_can_use_recorded_object_without_local_media(self):
        import vidistudio_engine as engine

        owner = str(uuid.uuid4())
        args = SimpleNamespace(cloud_owner=owner, source_project='project', source_bucket='bucket',
                               name=f'vidistudio/{owner}/clip.mp4', source_generation='9')
        record = dict(project='project', bucket='bucket', object=args.name, generation='9')
        with tempfile.TemporaryDirectory() as directory, patch.object(engine, 'config', return_value={}), patch.object(
            cloud_video, 'delete_project_object'
        ) as delete, patch.object(engine, 'emit') as emit:
            args.project = Path(directory) / 'missing'
            engine.delete_cloud_project_video(args)
            delete.assert_called_once_with({}, owner, record, emit)
            emit.assert_called_with('Cloud project video removed', cloudProjectVideoDeleted=True)
            self.assertFalse(args.project.exists())

            delete.reset_mock()
            args.project.mkdir()
            manifest = args.project / 'project.json'
            manifest.write_text(json.dumps({'id': owner, 'sourceType': 'cloud', 'cloudVideo': dict(record, generation='10')}))
            with self.assertRaisesRegex(ValueError, 'changed'):
                engine.delete_cloud_project_video(args)
            delete.assert_not_called()

            manifest.write_text(json.dumps({'id': owner, 'sourceType': 'cloud', 'cloudVideo': record}))
            engine.delete_cloud_project_video(args)
            delete.assert_called_once()
            updated = json.loads(manifest.read_text())
            self.assertEqual(updated['sourceType'], 'local')
            self.assertNotIn('cloudVideo', updated)

    def test_list_files_in_selected_project_bucket(self):
        cfg = {'vertexProject': 'selected-project', 'vertexBucket': 'destination'}
        files = [
            SimpleNamespace(name='folder/', generation=1, content_type=None),
            SimpleNamespace(name='sub/Clip #1.mp4', generation=3, content_type='application/octet-stream'),
            SimpleNamespace(name='notes.txt', generation=4, content_type='text/plain'),
            SimpleNamespace(name='another/video', generation=5, content_type='video/mp4'),
            SimpleNamespace(name='sub/Clip.MKV', generation=6, content_type='VIDEO/X-MATROSKA; charset=binary'),
            SimpleNamespace(name='document.pdf', generation=7, content_type='video/mp4'),
            SimpleNamespace(name='notes.mp4', generation=8, content_type='text/plain'),
            SimpleNamespace(name='unsupported.vob', generation=9, content_type='video/mpeg'),
            SimpleNamespace(name='song.m4a', generation=10, content_type='audio/mp4')]
        from datetime import datetime, timezone
        for file in files:
            file.size = 1024
            file.storage_class = 'STANDARD'
            file.time_created = datetime(2026, 11, 23, tzinfo=timezone.utc)
            file.updated = None
            file.metadata = None
        files[1].metadata = {'vidistudio-thumbnail-jpeg': 'fixture'}
        bucket = Mock()
        bucket.list_blobs.return_value = iter(files)
        with patch.object(cloud_video, 'bucket_for', return_value=bucket) as lookup:
            rows = cloud_video.bucket_files(cfg, 'source')
        lookup.assert_called_once_with({'vertexProject': 'selected-project', 'vertexBucket': 'source'})
        self.assertEqual([(r['name'], r['video'], r['generation']) for r in rows],
                         [('sub/Clip #1.mp4', True, '3'), ('another/video', True, '5'), ('sub/Clip.MKV', True, '6')])
        self.assertEqual(rows[0]['size'], '1024')
        self.assertEqual(rows[0]['storageClass'], 'STANDARD')
        self.assertEqual(rows[0]['created'], '2026-11-23T00:00:00+00:00')
        self.assertEqual(rows[0]['thumbnail'], 'fixture')
        self.assertEqual(cfg['vertexBucket'], 'destination')

    def test_replaced_source_fails_before_download(self):
        bucket = Mock()
        blob = bucket.blob.return_value
        blob.generation = 9
        with patch.object(cloud_video, 'bucket_for', return_value=bucket), self.assertRaisesRegex(ValueError, 'changed'):
            cloud_video.download({}, 'video.mp4', Path('.'), 1000, Mock(), generation='7')
        blob.open.assert_not_called()

    def test_oversized_cloud_import_fails_before_opening_download_stream(self):
        bucket = Mock()
        blob = bucket.blob.return_value
        blob.name, blob.generation, blob.size, blob.content_type = 'video.mp4', 7, 3_260_000_000, 'video/mp4'
        with tempfile.TemporaryDirectory() as temporary, patch.object(
            cloud_video, 'bucket_for', return_value=bucket
        ), self.assertRaisesRegex(ValueError, 'too large for Cloud Storage analysis'):
            directory = Path(temporary)
            progress = Mock()
            cloud_video.download({}, blob.name, directory, vertex_ai.MAX_CLOUD_VIDEO_SIZE_BYTES, progress, generation='7')
        blob.open.assert_not_called()
        progress.assert_called_once_with('Checking Cloud Storage access…')

    def test_download_checks_object_read_permission_before_opening_stream(self):
        bucket = Mock()
        bucket.name = 'source-bucket'
        blob = bucket.blob.return_value
        blob.name = 'folder/clip.mp4'
        blob.generation, blob.size, blob.content_type = 7, 5, 'video/mp4'
        with tempfile.TemporaryDirectory() as temporary, patch.object(cloud_video, 'bucket_for', return_value=bucket), patch.object(
            cloud_video, 'iam_permission_test'
        ) as iam:
            check = Mock(return_value=set())
            iam.return_value.__enter__.return_value = ('projects/_/buckets/source-bucket', check)
            with self.assertRaisesRegex(PermissionError, 'denied permission to download'):
                cloud_video.download({}, blob.name, Path(temporary), 100, Mock(), generation='7')
            check.assert_called_once_with('projects/_/buckets/source-bucket/objects/folder/clip.mp4', 'storage.objects.get')
            blob.open.assert_not_called()
            self.assertEqual(list(Path(temporary).iterdir()), [])

    def test_download_reports_precondition_and_integrity_errors(self):
        from google.api_core.exceptions import PreconditionFailed

        bucket = Mock()
        bucket.name = 'source-bucket'
        blob = bucket.blob.return_value
        blob.name = 'folder/clip.mp4'
        blob.generation, blob.size, blob.content_type = 7, 5, 'video/mp4'
        cfg = {'vertexProject': 'settings-project'}
        with tempfile.TemporaryDirectory() as temporary, patch.object(cloud_video, 'bucket_for', return_value=bucket), patch.object(
            cloud_video, 'iam_permission_test'
        ) as iam:
            iam.return_value.__enter__.return_value = ('projects/_/buckets/source-bucket', Mock(return_value={'storage.objects.get'}))
            blob.open.side_effect = PreconditionFailed('changed')
            with self.assertRaisesRegex(ValueError, 'selected file has changed'):
                cloud_video.download(cfg, blob.name, Path(temporary), 100, Mock(), generation='7', source_project='source-project')
            blob.open.side_effect = None
            blob.open.return_value = io.BytesIO(b'video')
            blob.crc32c = 'wrong'
            with self.assertRaisesRegex(ValueError, 'checksum'):
                cloud_video.download(cfg, blob.name, Path(temporary), 100, Mock(), generation='7', source_project='source-project')
            blob.open.assert_called_with('rb', chunk_size=8 * 1024 * 1024, if_generation_match=7)

    def test_cloud_import_preserves_original_reference_and_does_not_upload(self):
        import vidistudio_engine as engine

        bucket = Mock()
        bucket.name = 'source-bucket'
        blob = bucket.blob.return_value
        blob.name = 'folder/clip.mp4'
        blob.generation, blob.size, blob.content_type = 7, 5, 'video/mp4'
        blob.storage_class = 'STANDARD'
        blob.time_created = blob.updated = None
        blob.open.return_value = io.BytesIO(b'video')
        cfg = {'vertexProject': 'settings-project', 'vertexBucket': 'unused-destination'}
        with tempfile.TemporaryDirectory() as temporary, patch.object(cloud_video, 'bucket_for', return_value=bucket), patch.object(
            cloud_video, 'iam_permission_test'
        ) as iam, patch.object(cloud_video, 'update') as upload, patch.object(
            engine, 'config', return_value=cfg
        ), patch.object(engine, 'probe', return_value={'streams': [{'codec_type': 'video'}], 'format': {'duration': 1}}), patch.object(
            engine, 'thumbnails'
        ), patch.object(engine, 'cleanup_project_storage'), patch.object(engine, 'emit') as emit:
            iam.return_value.__enter__.return_value = ('projects/_/buckets/source-bucket', Mock(return_value={'storage.objects.get'}))
            library = Path(temporary)
            fixture = library / 'checksum'
            fixture.write_bytes(b'video')
            blob.crc32c = cloud_video.crc32c(fixture)
            with patch.object(sys, 'argv', ['engine', 'cloud-import', '--library', str(library), '--source-project', 'source-project',
                                           '--source-bucket', 'source-bucket', '--name', blob.name, '--source-generation', '7']):
                engine.main()
            manifest, = library.glob('*/project.json')
            project = json.loads(manifest.read_text())
            self.assertEqual((manifest.parent / project['source']).read_bytes(), b'video')
            self.assertEqual(project['sourceType'], 'cloud')
            self.assertEqual(project['cloudVideo'], dict(project='source-project', bucket='source-bucket',
                             object=blob.name, generation='7', crc32c=blob.crc32c, ownership='referenced',
                             size='5', contentType='video/mp4', storageClass='STANDARD'))
            upload.assert_not_called()
            blob.open.assert_called_once()
            emit.assert_any_call('Downloading video: 5 of 5 bytes', progress=1.0)
            emit.assert_any_call('Verifying the downloaded video…')
            args = SimpleNamespace(project=manifest.parent, cloud_owner=project['id'], source_project='source-project',
                                   source_bucket='source-bucket', name=blob.name, source_generation='7')
            with patch.object(cloud_video, 'delete_project_object') as delete, self.assertRaises(PermissionError):
                engine.delete_cloud_project_video(args)
            delete.assert_not_called()

    def test_referenced_video_models_use_source_project_original_uri_and_video_transcription(self):
        import vidistudio_engine as engine

        cfg = dict(aiProvider='vertex', vertexAuth='signin', vertexProject='settings-project', vertexBucket='unused-destination',
                   vertexCatalog=['gemini-3.5-transcribe', 'gemini-2.5-flash', 'gemini-2.5-pro'],
                   vertexModels={'cloud_video': 'gemini-2.5-pro', 'youtube_transcript': 'gemini-2.5-flash'})
        record = dict(project='source-project', bucket='source-bucket', object='nested/clip.mp4',
                      generation='3', ownership='referenced', contentType='video/mp4')
        project = dict(id=str(uuid.uuid4()), cloudVideo=record)
        with patch('google.genai.Client') as sdk, patch.object(vertex_ai, 'credentials') as credentials, patch.object(
            cloud_video, 'bucket_for'
        ) as bucket, patch.object(engine, 'config', return_value=cfg):
            bucket.return_value.blob.return_value.generation = 3
            bucket.return_value.blob.return_value.content_type = 'video/mp4'
            bucket.return_value.blob.return_value.metadata = {}
            client, model = engine.client_and_model('transcribe', project)
            self.assertEqual(model, 'gemini-2.5-pro')
            self.assertEqual(vertex_ai.model_for(cfg, 'youtube_transcript'), 'gemini-2.5-flash')
            source = engine.reusable_video(Path('.'), dict(project, source='source/clip.mp4'), client)
            self.assertEqual(source.uri, 'gs://source-bucket/nested/clip.mp4')
            self.assertEqual(source.mime_type, 'video/mp4')
            credentials.assert_called_once_with('source-project')
            self.assertEqual(sdk.call_args.kwargs['project'], 'source-project')
            bucket.assert_called_once_with(dict(cfg, vertexProject='source-project', vertexBucket='source-bucket'))
            cfg['aiProvider'] = 'gemini'
            with self.assertRaisesRegex(ValueError, 'Choose Vertex AI'):
                engine.client_and_model('transcribe', project)

    def test_project_model_groups_route_each_task_to_independent_preferences(self):
        import vidistudio_engine as engine

        local = {'sourceType': 'local'}
        youtube = {'sourceType': 'youtube'}
        imported = dict(youtube, audioSources={'transcription': 'imported'})
        cloud = {'sourceType': 'cloud', 'cloudVideo': {'ownership': 'referenced'}}
        cfg = dict(aiProvider='vertex', vertexAuth='signin',
                   vertexCatalog=['gemini-2.5-flash', 'gemini-2.5-pro', 'gemini-3.5-transcribe', 'gemini-3.8-flash-tts'],
                   vertexModels={'summary': 'gemini-2.5-flash', 'youtube_summary': 'gemini-2.5-pro',
                                 'cloud_summary': 'gemini-2.5-flash', 'youtube_text_rewrite': 'gemini-2.5-pro',
                                 'cloud_tts_audio': 'gemini-3.8-flash-tts'})
        for source, prefix in ((local, ''), (youtube, 'youtube_'), (cloud, 'cloud_')):
            for task in ('summary', 'audio_descriptions', 'screen_text', 'text_rewrite', 'tts_audio'):
                self.assertEqual(engine.project_model_stage(cfg, task, source), prefix + task)
        self.assertEqual(engine.project_model_stage(cfg, 'transcript', imported), 'youtube_imported_transcript')
        self.assertEqual(engine.project_model_stage(cfg, 'youtube_transcript', imported), 'youtube_imported_audio')
        self.assertEqual(engine.project_model_stage(cfg, 'transcript', cloud), 'cloud_video')
        with patch.object(engine, 'config', return_value=cfg), patch.object(engine, 'gemini_client') as connect:
            self.assertEqual(engine.client_and_model('summary', youtube)[1], 'gemini-2.5-pro')
            self.assertEqual(engine.client_and_model('summary', cloud)[1], 'gemini-2.5-flash')
            connect.assert_called_with(cloud)
            self.assertEqual(engine.client_and_model('tts', cloud)[1], 'gemini-3.8-flash-tts')
            connect.assert_called_with(None)
            cfg.update(aiProvider='developer', models={'summary': 'gemini-2.5-flash', 'youtube_summary': 'gemini-2.5-pro'})
            self.assertEqual(engine.client_and_model('summary', local)[1], 'gemini-2.5-flash')
            self.assertEqual(engine.client_and_model('summary', youtube)[1], 'gemini-2.5-pro')
            with self.assertRaisesRegex(ValueError, 'Choose Vertex AI'):
                engine.client_and_model('summary', cloud)

    def test_switch_preserves_task_choices(self):
        cfg = {'vertexCatalog': ['gemini-3.8-flash'], 'vertexModels': {'summary': 'gemini-3.8-flash'},
               'vertexExpressModels': {'summary': 'gemini-3-flash-preview'}}
        self.assertEqual(vertex_ai.model_for(cfg, 'summary'), 'gemini-3.8-flash')
        cfg['vertexAuth'] = 'express'
        self.assertEqual(vertex_ai.model_for(cfg, 'summary'), 'gemini-3-flash-preview')
        with self.assertRaisesRegex(ValueError, 'Google sign-in'):
            vertex_ai.model_for(cfg, 'tts_audio')
        cfg['vertexAuth'] = 'signin'
        self.assertEqual(vertex_ai.model_for(cfg, 'summary'), 'gemini-3.8-flash')

    def test_picker_and_runtime_resolve_only_file_models(self):
        speech = 'gemini-3.5-transcribe'
        preview = speech + '-preview'
        video = 'gemini-4-neon'
        tts = 'gemini-3.8-flash-lite-tts'
        names = [speech, preview, video, tts, speech + '-live', speech + '-live-preview',
                 'gemini-3.1-flash-image', 'gemini-embedding-2', 'gemini-unknown-task', 'gemini-4-carbon-cyber-permissive']
        for catalog in (names, [{'name': name} for name in names]):
            for stage, allowed, preferred in [('transcript', [speech, preview], speech), ('tts_audio', [tts], tts),
                    *[(stage, [video], video) for stage in ('summary', 'screen_text', 'youtube_transcript', 'audio_descriptions', 'text_rewrite')]]:
                for saved in [*names, 'gemini-2.5-pro', None]:
                    cfg = {'vertexCatalog': catalog, 'vertexModels': {stage: saved}}
                    self.assertEqual(vertex_ai.model_for(cfg, stage), saved if saved in allowed else preferred)
            with self.assertRaisesRegex(ValueError, 'Test Connection'):
                vertex_ai.model_for({'vertexCatalog': [tts, speech + '-live']}, 'transcript')

    def test_express_has_video_understanding_and_no_dedicated_speech_models(self):
        cfg = {'vertexAuth': 'express', 'vertexCatalog': ['gemini-3.5-transcribe'],
               'vertexModels': {'transcript': 'gemini-3.5-transcribe'}}
        for stage in ('transcript', 'tts_audio'):
            with self.assertRaisesRegex(ValueError, 'Google sign-in'):
                vertex_ai.model_for(cfg, stage)
        self.assertEqual(vertex_ai.model_for(cfg, 'youtube_transcript'), 'gemini-3-flash-preview')
        self.assertEqual(cfg['vertexAuth'], 'express')

    def test_requests_follow_selected_connection_and_input_type(self):
        import vidistudio_engine as engine
        cfg = {'aiProvider': 'vertex', 'vertexAuth': 'signin',
               'vertexCatalog': ['gemini-3.5-transcribe-preview', 'gemini-4-neon'],
               'vertexModels': {'transcript': 'gemini-3.8-flash'},
               'vertexExpressModels': {'youtube_transcript': 'gemini-2.5-pro'}}
        with patch.object(engine, 'config', return_value=cfg), patch.object(engine, 'gemini_client'):
            self.assertEqual(engine.client_and_model('transcribe')[1], 'gemini-3.5-transcribe-preview')
            self.assertEqual(engine.client_and_model('youtube_transcript')[1], 'gemini-4-neon')
            cfg['outputLanguages'] = {'transcript': 'en'}
            self.assertEqual(engine.client_and_model('transcribe')[1], 'gemini-4-neon')
            cfg['vertexAuth'] = 'express'
            cfg['outputLanguages'] = {}
            self.assertEqual(engine.client_and_model('transcribe')[1], 'gemini-2.5-pro')
            with self.assertRaisesRegex(ValueError, 'Google sign-in'):
                engine.client_and_model('tts')
            self.assertEqual(cfg['vertexAuth'], 'express')

    def test_express_cannot_use_private_object(self):
        with self.assertRaisesRegex(ValueError, 'sign-in'):
            vertex_ai.media({'vertexAuth': 'express'}, {'cloudVideo': {'bucket': 'private'}}, Path('video.mp4'))

    def test_inline_media_stays_local(self):
        path = Path('video.mp4')
        media = vertex_ai.media({'vertexAuth': 'express'}, {}, path)
        self.assertEqual(media.uri, path)

    def test_express_requires_selected_key(self):
        with patch.dict('os.environ', {}, clear=True), self.assertRaisesRegex(ValueError, 'express API key'):
            vertex_ai.client({'vertexAuth': 'express'})

    def test_disconnect_only_removes_current_google_credential(self):
        store = Mock()
        with patch.object(vertex_ai, 'vault', return_value=store), patch.object(vertex_ai, 'oauth_client', return_value={'client_id':'desktop'}):
            vertex_ai.disconnect()
        store.delete_password.assert_called_once_with(vertex_ai.SERVICE, 'desktop')

    def test_delete_protects_replaced_generation_and_local_record(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'v.mp4'
            source.write_bytes(b'original')
            pid = str(uuid.uuid4())
            row = {'bucket': 'private', 'project': 'user-cloud', 'object': f'vidistudio/{pid}/v.mp4',
                   'crc32c': cloud_video.crc32c(source), 'generation': '1'}
            project = {'source': 'v.mp4', 'id': pid, 'cloudVideo': row}
            blob = Mock(generation=2, metadata={'vidistudio-project': pid})
            bucket = Mock()
            bucket.blob.return_value = blob
            core = Mock()
            core.local.return_value = source
            with patch.object(cloud_video, 'bucket_for', return_value=bucket), self.assertRaisesRegex(ValueError, 'newer'):
                cloud_video.update(SimpleNamespace(command='cloud-remove'), root, project,
                                   {'vertexProject': 'user-cloud', 'vertexBucket':'private'}, core)
            blob.delete.assert_not_called()
            core.save.assert_not_called()
            self.assertEqual(project['cloudVideo'], row)

    def test_upload_interruption_keeps_local_project_retryable(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            video = root / 'v.mp4'
            video.write_bytes(b'video')
            project = {'id': str(uuid.uuid4()), 'source': video.name, 'sourceType': 'local'}
            core = Mock()
            core.local.return_value = video
            bucket = Mock()
            blob = bucket.blob.return_value
            blob.upload_from_file.side_effect = OSError('connection interrupted')
            cfg = {'vertexProject': 'user', 'vertexBucket': 'private'}
            with patch.object(cloud_video, 'bucket_for', return_value=bucket), patch.object(cloud_video, 'thumbnail'), self.assertRaises(OSError):
                cloud_video.update(SimpleNamespace(command='cloud-upload'), root, project, cfg, core)
            self.assertEqual(project['sourceType'], 'local')
            self.assertNotIn('cloudVideo', project)
            self.assertEqual(video.read_bytes(), b'video')
            self.assertEqual(blob.upload_from_file.call_args.kwargs['if_generation_match'], 0)
            core.save.assert_not_called()

    def test_signed_media_checks_the_selected_bucket(self):
        cfg = {'vertexProject': 'user', 'vertexBucket': 'different'}
        project = {'cloudVideo': {'project': 'user', 'bucket': 'original'}}
        with patch.object(cloud_video, 'bucket_for') as lookup, self.assertRaisesRegex(ValueError, 'bucket'):
            vertex_ai.media(cfg, project, Path('v.mp4'))
        lookup.assert_not_called()

    def test_numbered_speech_model_returns_timed_segments(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'audio.wav'
            path.write_bytes(b'audio-fixture')
            words = [SimpleNamespace(word='Hello', start_offset='1s', end_offset='1.5s')]
            part = SimpleNamespace(audio_transcription=SimpleNamespace(words=words, speaker_label='A'))
            models = Mock()
            models.generate_content.return_value = SimpleNamespace(candidates=[
                SimpleNamespace(content=SimpleNamespace(parts=[part]))])
            session = object.__new__(vertex_ai.VertexSession)
            session.models = models
            segments = session.transcribe_audio('gemini-3.5-transcribe', path, 5)
            self.assertEqual(segments, [dict(text='Hello', start=6, end=6.5, speaker='A')])
            self.assertTrue(models.generate_content.call_args.kwargs['config'].audio_transcription_config.word_timestamp)

    def test_transfer_reports_actual_bytes(self):
        notify = Mock()
        reader = cloud_video.UploadReader(io.BytesIO(b'abcd'), 4, notify)
        self.assertEqual(reader.read(2), b'ab')
        notify.assert_called_once_with('Uploading video: 2 of 4 bytes', progress=0.5)
        self.assertEqual(reader.read(), b'cd')
        self.assertEqual(notify.call_args.kwargs['progress'], 1)
