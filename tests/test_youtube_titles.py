import io, json, tempfile, unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from test_engine import engine
import parity
class YouTubeTitles(unittest.TestCase):
    def import_project(self, title=None, fail=False, custom=None, url='https://youtu.be/hYaQffYszuM'):
        with tempfile.TemporaryDirectory() as tmp:
            args=SimpleNamespace(command='import-youtube',url=url,library=Path(tmp),name=custom,duration=0)
            validated=[]
            with patch.object(parity,'urlopen',side_effect=OSError('offline') if fail else None,return_value=io.StringIO(json.dumps({'title':title}))), \
                 patch.object(parity,'download_youtube_thumbnail',return_value='thumbnails/youtube-thumbnail.jpg'):
                parity.execute(args,None,None,SimpleNamespace(
                    save=engine.save,
                    emit=lambda *a,**k:None,
                    validate_youtube_for_gemini=validated.append,
                ))
            project=json.loads(next(Path(tmp).glob('*/project.json')).read_text())
            self.assertEqual(validated,[project['youtubeURL']])
            return project
    def test_share_and_watch_urls_create_the_same_canonical_project(self):
        expected='https://www.youtube.com/watch?v=4fYlQtcm6qY'
        for url in ('https://youtu.be/4fYlQtcm6qY','https://www.youtube.com/watch?v=4fYlQtcm6qY'):
            with self.subTest(url=url):
                project=self.import_project('No Cost EMIs (Exposed)',url=url)
                self.assertEqual(project['youtubeURL'],expected)
                self.assertEqual(project['name'],'No Cost EMIs (Exposed)')
                self.assertEqual(project['sourceType'],'youtube')
                self.assertEqual(project['source'],'')
                self.assertEqual(project['thumbnails'],['thumbnails/youtube-thumbnail.jpg'])
    def test_thumbnail_is_downloaded_into_project(self):
        response=MagicMock()
        response.__enter__.return_value=response
        response.headers.get_content_type.return_value='image/jpeg'
        response.read.return_value=b'\xff\xd8\xffstored thumbnail'
        with tempfile.TemporaryDirectory() as tmp, patch.object(parity,'urlopen',return_value=response):
            root=Path(tmp);(root/'thumbnails').mkdir()
            relative=parity.download_youtube_thumbnail(root,'4fYlQtcm6qY')
            self.assertEqual(relative,'thumbnails/youtube-thumbnail.jpg')
            self.assertEqual((root/relative).read_bytes(),b'\xff\xd8\xffstored thumbnail')
    def test_display_title(self): self.assertEqual(self.import_project('The video display title')['name'],'The video display title')
    def test_offline_placeholder_has_no_id(self): self.assertEqual(self.import_project(fail=True)['name'],'YouTube video')
    def test_custom_name_preserved(self): self.assertEqual(self.import_project('Title',custom='My edit')['name'],'My edit')
    def test_gemini_validation_failure_does_not_create_project(self):
        with tempfile.TemporaryDirectory() as tmp:
            args=SimpleNamespace(command='import-youtube',url='https://youtu.be/4fYlQtcm6qY',library=Path(tmp),name=None,duration=0)
            def reject(_url): raise ValueError('not public')
            with self.assertRaisesRegex(ValueError,'not public'):
                parity.execute(args,None,None,SimpleNamespace(
                    save=engine.save,
                    emit=lambda *a,**k:None,
                    validate_youtube_for_gemini=reject,
                ))
            self.assertEqual(list(Path(tmp).glob('*/project.json')),[])
