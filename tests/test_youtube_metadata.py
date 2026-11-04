import json, math, sys, tempfile, unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'engine'))
import youtube_metadata as metadata
import parity

class YouTubeMetadataTests(unittest.TestCase):
    def sample(self, **changes):
        return dict(videoID='jNQXAC9IVRw', title='Video', duration=18.0, visibility='public', liveStatus='none', uploadStatus='processed', **changes)
    def test_private_is_blocked_and_unlisted_is_accepted(self):
        value=self.sample(); value['visibility']='private'
        with self.assertRaisesRegex(ValueError,'Private Video Cannot Be Opened'): metadata.validate(value, value['videoID'])
        value['visibility']='unlisted'
        self.assertEqual(metadata.validate(value)['visibility'], 'unlisted')
    def test_unavailable_and_nonfinite_duration(self):
        for duration in (0, -1, math.inf, math.nan, True, '18'):
            value=self.sample(); value['duration']=duration
            with self.subTest(duration=duration), self.assertRaises(ValueError): metadata.validate(value)
        for status in ('live','upcoming'):
            value=self.sample(); value['liveStatus']=status
            with self.assertRaises(ValueError): metadata.validate(value)
    def test_mismatched_id_and_credentials_rejected(self):
        value=self.sample(); value['access_token']='secret'; value['accountEmail']='private@example.org'
        with self.assertRaises(ValueError): metadata.validate(value,'different')
        clean=metadata.validate(value)
        self.assertNotIn('access_token', clean); self.assertNotIn('accountEmail',clean)
    def test_import_uses_api_duration_without_oembed(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); file=root/'metadata.json'; file.write_text(json.dumps(self.sample()))
            saved=[]
            args=SimpleNamespace(command='import-youtube',url='https://youtu.be/jNQXAC9IVRw',library=root,name=None,duration=0,youtube_metadata=file)
            core=SimpleNamespace(save=lambda root,p:saved.append(p),emit=lambda *a,**k:None)
            with patch.object(parity,'urlopen',side_effect=AssertionError('oEmbed must not be called')), patch.object(parity,'download_youtube_thumbnail',return_value=None):
                parity.execute(args,None,None,core)
            self.assertEqual(saved[0]['duration'],18); self.assertEqual(saved[0]['youtubeMetadata']['videoID'],'jNQXAC9IVRw')
    def test_private_import_creates_no_project(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); file=root/'metadata.json'; value=self.sample(); value['visibility']='private'; file.write_text(json.dumps(value))
            args=SimpleNamespace(command='import-youtube',url='https://youtu.be/jNQXAC9IVRw',library=root,name=None,duration=0,youtube_metadata=file)
            with self.assertRaisesRegex(ValueError,'Private Video'), patch.object(parity,'download_youtube_thumbnail',return_value=None): parity.execute(args,None,None,None)
            self.assertEqual(list(root.glob('YouTube-*')),[])
    def test_refresh_preserves_user_project_content(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); file=root/'metadata.json'; file.write_text(json.dumps(self.sample()))
            project=dict(name='My name',youtubeURL='https://www.youtube.com/watch?v=jNQXAC9IVRw',duration=1,transcript=[dict(text='Edited')],summary='Summary')
            parity.execute(SimpleNamespace(command='update-youtube-metadata',youtube_metadata=file),root,project,SimpleNamespace(save=lambda *a:None))
            self.assertEqual(project['name'],'My name'); self.assertEqual(project['transcript'][0]['text'],'Edited'); self.assertEqual(project['duration'],18)


class YouTubeCaptionImportTests(unittest.TestCase):
    def setUp(self):
        from test_import_assets import FakeCore, project, write
        self.temp=tempfile.TemporaryDirectory(); self.root=Path(self.temp.name)
        self.core=FakeCore(self.root)
        self.project=project(sourceType='youtube',youtubeURL='https://www.youtube.com/watch?v=jNQXAC9IVRw',duration=20)
        self.provenance=self.root/'track.json'
        self.provenance.write_text(json.dumps(dict(videoID='jNQXAC9IVRw',trackID='track',language='hi',trackKind='ASR')))
    def tearDown(self): self.temp.cleanup()
    def args(self, source, replace=False):
        return SimpleNamespace(command='import-transcript',input=source,timing_input=None,replace_existing=replace,caption_provenance=self.provenance)
    def test_unicode_timing_source_and_undo(self):
        import import_assets
        source=self.root/'captions.srt'; source.write_text('1\n00:00:01,000 --> 00:00:03,000\nनमस्ते\n',encoding='utf-8')
        import_assets.import_text(self.args(source),self.root,self.project,self.core,[])
        self.assertEqual(self.project['transcript'][0]['text'],'नमस्ते')
        self.assertEqual(self.project['transcript'][0]['start'],1)
        self.assertIn('YouTube captions',self.project['transcript'][0]['originSource'])
        self.assertEqual(self.project['youtubeCaptionSource']['language'],'hi')
        self.assertEqual(self.project['transcriptUndoStack'],[[]])
    def test_invalid_timing_and_replacement_keep_current_transcript(self):
        import import_assets
        self.project['transcript']=[dict(id='old',text='Keep',start=0,end=1)]
        for text in ('1\n00:00:03,000 --> 00:00:02,000\nWrong\n','1\n00:00:01,000 --> 00:00:03,000\nNew\n'):
            source=self.root/'captions.srt'; source.write_text(text)
            with self.assertRaises(ValueError): import_assets.import_text(self.args(source),self.root,self.project,self.core,[])
            self.assertEqual(self.project['transcript'][0]['text'],'Keep')
    def test_clear_data_returns_source_for_removal_after_commit(self):
        import import_assets
        source=self.root/'captions.srt'; source.write_text('1\n00:00:01,000 --> 00:00:03,000\nCaption\n')
        import_assets.import_text(self.args(source),self.root,self.project,self.core,[])
        self.project['transcript'].append(dict(text='My row',origin='manual'))
        paths=metadata.clear(self.root,self.project)
        self.assertTrue(paths[0].is_file())
        self.assertEqual(self.project['transcript'],[dict(text='My row',origin='manual')])
        self.assertNotIn('youtubeCaptionSource',self.project)
        self.assertNotIn('transcriptUndoStack',self.project)


class YouTubeCacheRetentionTests(unittest.TestCase):
    def test_expired_api_snapshots_removed_without_losing_project_edits(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); raw=root/'captions.srt'; raw.write_text('original caption source')
            project=dict(youtubeMetadata=dict(fetchedAt=1),youtubeCaptionSource=dict(fetchedAt=1,trackID='track',name='Caption',language='hi'),
                         importedAssets=dict(transcript=dict(path='captions.srt')),transcript=[dict(text='My saved edit',origin='imported_modified')])
            changed,removed=metadata.expire(root,project,now=31*86400)
            self.assertTrue(changed);self.assertEqual(removed,[raw.resolve()]);self.assertTrue(raw.exists())
            self.assertNotIn('youtubeMetadata',project);self.assertNotIn('trackID',project['youtubeCaptionSource'])
            self.assertEqual(project['transcript'][0]['text'],'My saved edit')
    def test_recent_api_snapshots_unchanged(self):
        project=dict(youtubeMetadata=dict(fetchedAt=100))
        self.assertEqual(metadata.expire(Path('/tmp'),project,now=200),(False,[]))

class PlaylistPersistenceTests(unittest.TestCase):
    def test_normalized_playlist_details_and_basic_refresh_keep_context(self):
        import tempfile
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);file=root/'metadata.json'
            value=dict(videoID='jNQXAC9IVRw',title='YouTube title',visibility='public',duration=19,
                playlists=[dict(id='PL1',title='My playlist',description='Details',visibility='unlisted',count=4,publishedAt='2026-01-01T00:00:00Z',refresh_token='never persist')],
                openedFromPlaylist=dict(id='PL1',title='My playlist',count=4),playlistChannelTitle='Channel')
            normalized=metadata.validate(value)
            self.assertNotIn('refresh_token',normalized['playlists'][0])
            self.assertEqual(normalized['playlists'][0]['title'],'My playlist')
            project=dict(name='My local name',youtubeURL='https://www.youtube.com/watch?v=jNQXAC9IVRw',youtubeMetadata=normalized,transcript=[dict(text='Keep edits')])
            file.write_text(json.dumps(dict(videoID='jNQXAC9IVRw',title='New YouTube title',visibility='public',duration=19)))
            parity.execute(SimpleNamespace(command='update-youtube-metadata',youtube_metadata=file),root,project,SimpleNamespace(save=lambda *args:None))
            self.assertEqual(project['youtubeMetadata']['playlists'][0]['title'],'My playlist')
            self.assertEqual(project['youtubeMetadata']['openedFromPlaylist']['id'],'PL1')
            self.assertEqual(project['name'],'My local name')
            self.assertEqual(project['transcript'][0]['text'],'Keep edits')
    def test_explicit_empty_playlist_list_replaces_old_matches(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);file=root/'metadata.json'
            project=dict(youtubeURL='https://www.youtube.com/watch?v=jNQXAC9IVRw',youtubeMetadata=dict(playlists=[dict(id='old')]))
            file.write_text(json.dumps(dict(videoID='jNQXAC9IVRw',visibility='public',duration=19,playlists=[])))
            parity.execute(SimpleNamespace(command='update-youtube-metadata',youtube_metadata=file),root,project,SimpleNamespace(save=lambda *args:None))
            self.assertEqual(project['youtubeMetadata']['playlists'],[])
