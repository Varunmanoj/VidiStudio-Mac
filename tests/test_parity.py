import json, sys, unittest, tempfile
from pathlib import Path
from types import SimpleNamespace
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'engine'))
import parity
import vidistudio_engine as engine
class Parity(unittest.TestCase):
    def test_url_validation(self):
        expected='https://www.youtube.com/watch?v=4fYlQtcm6qY'
        self.assertEqual(parity.youtube_url('https://youtu.be/4fYlQtcm6qY'),expected)
        self.assertEqual(parity.youtube_url('https://www.youtube.com/watch?v=4fYlQtcm6qY'),expected)
        for url in ['https://youtube.com.evil.test/watch?v=hYaQffYszuM','file:///tmp/test','https://youtube.com/watch?v=bad']:
            with self.assertRaises(ValueError):parity.youtube_url(url)
    def test_subtitles_and_undo(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'exports').mkdir();(root/'audio-description').mkdir()
            old={'id':'a','start':1.,'end':2.5,'text':'Hello'}
            project={'name':'Dilemma / Episode: 3','transcript':[old.copy()],'cues':[old.copy()],'exports':[]}
            parity.remember(project);project['cues'][0]['text']='Edited'
            e=SimpleNamespace(atomic_json=engine.atomic_json,local=engine.local,export_relative_path=engine.export_relative_path)
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
            self.assertRegex(project['exports'][0],r'^exports/Dilemma - Episode - 3 - Transcript - \d{8}-\d{6}\.vtt$')
            project['summary']='A concise project summary.'
            args=SimpleNamespace(command='export-subtitles',content='summary',format='md')
            parity.execute(args,root,project,e)
            summary=(root/project['exports'][1]).read_text()
            self.assertEqual(summary,'# Summary\n\nA concise project summary.\n')
            self.assertRegex(project['exports'][1],r'^exports/Dilemma - Episode - 3 - Summary - \d{8}-\d{6}\.md$')
            deleted=project['exports'][0]
            args=SimpleNamespace(command='delete-export',name=deleted)
            parity.execute(args,root,project,e)
            self.assertNotIn(deleted,project['exports'])
            self.assertFalse((root/deleted).exists())
            self.assertFalse((root/'metadata/trash').exists())
if __name__=='__main__':unittest.main()
