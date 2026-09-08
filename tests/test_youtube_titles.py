import io, json, tempfile, unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from test_engine import engine
import parity
class YouTubeTitles(unittest.TestCase):
    def import_project(self, title=None, fail=False, custom=None):
        with tempfile.TemporaryDirectory() as tmp:
            args=SimpleNamespace(command='import-youtube',url='https://youtu.be/hYaQffYszuM',library=Path(tmp),name=custom,duration=0)
            with patch.object(parity,'urlopen',side_effect=OSError('offline') if fail else None,return_value=io.StringIO(json.dumps({'title':title}))):
                parity.execute(args,None,None,SimpleNamespace(save=engine.save,emit=lambda *a,**k:None))
            return json.loads(next(Path(tmp).glob('*/project.json')).read_text())
    def test_display_title(self): self.assertEqual(self.import_project('The video display title')['name'],'The video display title')
    def test_offline_placeholder_has_no_id(self): self.assertEqual(self.import_project(fail=True)['name'],'YouTube video')
    def test_custom_name_preserved(self): self.assertEqual(self.import_project('Title',custom='My edit')['name'],'My edit')
