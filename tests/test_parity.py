import json, sys, unittest, tempfile
from pathlib import Path
from types import SimpleNamespace
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'engine'))
import parity
import vidistudio_engine as engine
class Parity(unittest.TestCase):
    def test_url_validation(self):
        self.assertEqual(parity.youtube_url('https://youtu.be/hYaQffYszuM?t=3'),'https://www.youtube.com/watch?v=hYaQffYszuM')
        for url in ['https://youtube.com.evil.test/watch?v=hYaQffYszuM','file:///tmp/test','https://youtube.com/watch?v=bad']:
            with self.assertRaises(ValueError):parity.youtube_url(url)
    def test_subtitles_and_undo(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'exports').mkdir();(root/'audio-description').mkdir()
            old={'id':'a','start':1.,'end':2.5,'text':'Hello'}
            project={'transcript':[old.copy()],'cues':[old.copy()],'exports':[]}
            parity.remember(project);project['cues'][0]['text']='Edited'
            e=SimpleNamespace(atomic_json=engine.atomic_json)
            args=SimpleNamespace(command='undo-cues')
            parity.execute(args,root,project,e)
            self.assertEqual(project['cues'][0]['text'],'Hello')
            args.command='redo-cues';parity.execute(args,root,project,e)
            self.assertEqual(project['cues'][0]['text'],'Edited')
            args=SimpleNamespace(command='export-subtitles',content='transcript',format='vtt')
            parity.execute(args,root,project,e)
            text=(root/project['exports'][0]).read_text()
            self.assertIn('00:00:01.000 --> 00:00:02.500',text)
            self.assertTrue(text.startswith('WEBVTT'))
if __name__=='__main__':unittest.main()
