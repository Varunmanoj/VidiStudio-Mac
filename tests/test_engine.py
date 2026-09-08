import importlib.util, json, os, subprocess, sys, tempfile, unittest
from pathlib import Path
ENGINE=Path(__file__).resolve().parents[1]/'engine/vidistudio_engine.py'
sys.path.insert(0,str(ENGINE.parent))
spec=importlib.util.spec_from_file_location('engine',ENGINE); engine=importlib.util.module_from_spec(spec); spec.loader.exec_module(engine)
class Validation(unittest.TestCase):
    def test_overlap_and_boundaries(self):
        for cues in [[{'start':-1,'end':2,'text':'a'}],[{'start':0,'end':11,'text':'a'}],[{'start':0,'end':3,'text':'a'},{'start':2,'end':5,'text':'b'}],[{'start':0,'end':float('nan'),'text':'a'}]]:
            with self.assertRaises(ValueError): engine.validate_cues(cues,10)
    def test_dialogue_overlap(self):
        with self.assertRaises(ValueError): engine.validate_cues([{'start':1,'end':3,'text':'a'}],10,[{'start':2,'end':4}])
        self.assertEqual(len(engine.validate_cues([{'start':0,'end':2,'text':'a'}],10,[{'start':2,'end':4}])),1)
    def test_path_escape(self):
        with self.assertRaises(ValueError): engine.local(Path('/tmp/project'),'../../etc/passwd')
    def test_pipeline(self):
        with tempfile.TemporaryDirectory(prefix='vidistudio-test-') as temp:
            root=Path(temp); source=root/'sample video.mp4'
            engine.run([engine.tool('ffmpeg'),'-y','-v','error','-f','lavfi','-i','testsrc2=size=640x360:rate=24','-f','lavfi','-i','sine=frequency=440:sample_rate=48000','-t','8','-c:v','libx264','-c:a','aac',source])
            env=os.environ | {'VIDISTUDIO_CONFIG':str(root/'settings.json')}
            (root/'settings.json').write_text('{}')
            def cli(*args,success=True):
                prefix=[os.environ['VIDISTUDIO_TEST_ENGINE']] if os.environ.get('VIDISTUDIO_TEST_ENGINE') else [sys.executable,str(ENGINE)]
                result=subprocess.run([*prefix,*map(str,args)],capture_output=True,text=True,env=env)
                self.assertEqual(result.returncode,0 if success else 1,result.stdout+result.stderr)
                return result
            cli('import-video','--video',source,'--library',root/'library')
            folder=next((root/'library').iterdir())
            project=lambda:json.loads((folder/'project.json').read_text())
            self.assertEqual(len(project()['thumbnails']),8)
            self.assertTrue((folder/project()['source']).exists())
            cli('extract-audio','--project',folder)
            cues=root/'cues.json'; cues.write_text(json.dumps([{'id':'test','start':1,'end':6,'text':'Colorful shapes move.'}]))
            cli('save-cues','--project',folder,'--input',cues)
            cli('synthesize-tts','--project',folder)
            self.assertTrue((folder/project()['cues'][0]['audio']).exists())
            cli('export-final-video','--project',folder)
            output=folder/project()['exports'][0]
            self.assertAlmostEqual(float(engine.probe(output)['format']['duration']),8,delta=.2)
            stale=project()['cues']; stale[0]['text']='Changed narration.'; cues.write_text(json.dumps(stale))
            cli('save-cues','--project',folder,'--input',cues)
            cli('export-final-video','--project',folder,success=False)
            cli('transcribe','--project',folder,success=False)
            self.assertIn('API key',project()['error'])
if __name__=='__main__': unittest.main()
