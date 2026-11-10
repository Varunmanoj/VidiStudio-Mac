import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'engine'))
import parity


class EmptyTextExports(unittest.TestCase):
    def test_empty_and_whitespace_only_results_never_write_exports(self):
        for kind in ['transcript', 'descriptions', 'combined', 'summary']:
            for rows in [[], [{'id':'blank','start':0,'end':1,'text':' \n\t'}]]:
                with self.subTest(kind=kind,rows=rows):
                    project=dict(transcript=rows, cues=rows, summary=' \n', transcriptGenerated=True, summaryGenerated=True)
                    core=SimpleNamespace(write_text_export=Mock())
                    args=SimpleNamespace(command='export-subtitles',content=kind,format='md' if kind=='summary' else 'srt',replace_existing=False)
                    with self.assertRaisesRegex(ValueError,'No (text|summary) available'):
                        parity.execute(args,Path('/unused'),project,core)
                    core.write_text_export.assert_not_called()

    def test_real_text_still_exports_and_empty_generation_marker_is_not_enough(self):
        core=SimpleNamespace(write_text_export=Mock())
        project=dict(transcript=[dict(start=0,end=1,text='Dialogue')],cues=[],summary='',transcriptGenerated=True)
        args=SimpleNamespace(command='export-subtitles',content='transcript',format='srt',replace_existing=False)
        parity.execute(args,Path('/unused'),project,core)
        self.assertIn('Dialogue',core.write_text_export.call_args.args[4])

    @unittest.skipUnless(os.environ.get('VIDISTUDIO_TEST_ENGINE'), 'Packaged engine must be configured')
    def test_packaged_cli_rejects_empty_generated_transcript(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            (root/'project.json').write_text(json.dumps(dict(schemaVersion=2,id='empty',name='Empty',source='',sourceType='youtube',youtubeURL='https://www.youtube.com/watch?v=abcdefghijk',duration=10,transcript=[],transcriptGenerated=True,summary='',cues=[],exports=[])))
            result=subprocess.run([os.environ['VIDISTUDIO_TEST_ENGINE'],'export-subtitles','--project',str(root),'--content','transcript','--format','srt'],capture_output=True,text=True,timeout=60,env=os.environ|{'VIDISTUDIO_CONFIG':str(root/'settings.json')})
            self.assertNotEqual(result.returncode,0)
            self.assertIn('No text available',result.stdout+result.stderr)
            self.assertFalse(list(root.rglob('*.srt')))
