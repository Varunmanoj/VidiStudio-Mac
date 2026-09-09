import importlib.util, json, os, subprocess, sys, tempfile, unittest
from pathlib import Path
from unittest.mock import Mock, patch
from copy import deepcopy
from types import SimpleNamespace
ENGINE=Path(__file__).resolve().parents[1]/'engine/vidistudio_engine.py'
sys.path.insert(0,str(ENGINE.parent))
spec=importlib.util.spec_from_file_location('engine',ENGINE); engine=importlib.util.module_from_spec(spec); spec.loader.exec_module(engine)
class Validation(unittest.TestCase):
    def test_read_and_speak_voice_resolution(self):
        preferences = {
            'SpokenContentDefaultVoiceSelectionsByLanguage': [
                'hi', {'voiceId': 'com.apple.voice.Aman'},
                'en', {'voiceId': 'com.apple.voice.enhanced.en-US.Nathan'},
            ]
        }
        identifier = engine.spoken_content_voice_id(preferences, ['en-IN'])
        self.assertEqual(identifier, 'com.apple.voice.enhanced.en-US.Nathan')
        listing = 'Aman (English (India)) en_IN    # Hello\nNathan (Enhanced)   en_US    # Hello\n'
        self.assertEqual(engine.system_voice_name_from_identifier(identifier, listing), 'Nathan (Enhanced)')

    def test_explicit_voice_overrides_read_and_speak_default(self):
        with patch.object(engine, 'spoken_content_voice_id', return_value='com.apple.voice.enhanced.en-US.Nathan'):
            self.assertEqual(engine.effective_system_voice({'systemVoice': 'Allison (Enhanced)'}), 'Allison (Enhanced)')
            self.assertEqual(
                engine.narration_signature({'systemVoice': 'Allison (Enhanced)'}),
                'system|Allison (Enhanced)|1.000|1.000|1.000',
            )
            self.assertEqual(
                engine.narration_signature({'systemVoice': ''}),
                'system|default:com.apple.voice.enhanced.en-US.Nathan|1.000|1.000|1.000',
            )

    def test_narration_fit_warning_uses_ad_segment_wording(self):
        self.assertEqual(
            engine.narration_fit_error_message(1, 14.8, 10.4),
            'AD segment 1 takes 14.8s but has 10.4s. Shorten its text or extend its gap.',
        )

    def test_description_generation_requires_transcript_and_summary(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'transcript').mkdir()
            with self.assertRaisesRegex(ValueError, 'Run transcription first'):
                engine.validate_analysis_prerequisites('generate-ad-cues', root, {'transcript': [], 'summary': 'Summary'})
            (root/'transcript/transcript.json').write_text('[]')
            with self.assertRaisesRegex(ValueError, 'Generate the summary first'):
                engine.validate_analysis_prerequisites('generate-ad-cues', root, {'transcript': [{'text': 'Dialogue'}], 'summary': '   '})
            engine.validate_analysis_prerequisites(
                'generate-ad-cues',
                root,
                {'transcript': [], 'summary': 'Summary'},
            )

    def test_frame_timestamp_uses_last_valid_frame_at_video_end(self):
        self.assertEqual(engine.parity.frame_timestamp(10, 10), 9.9)
        self.assertEqual(engine.parity.frame_timestamp(4.25, 10), 4.25)
        with self.assertRaises(ValueError): engine.parity.frame_timestamp(10.02, 10)
        with self.assertRaises(ValueError): engine.parity.frame_timestamp(-0.01, 10)

    def test_capture_frame_at_video_end_reaches_text_processing(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'metadata').mkdir()
            p = dict(duration=10, source='', sourceType='youtube', youtubeURL='https://www.youtube.com/watch?v=abcdefghijk')
            args = SimpleNamespace(command='capture-frame', timestamp=10)
            prompts = {'youtube_screen_text': dict(user_prompt='Read {timestamp_seconds}', system_instruction='')}
            client = Mock()
            with patch.object(engine, 'config', return_value={'prompts': prompts, 'videoProcessing': 'agentic'}), \
                 patch.object(engine, 'client_and_model', return_value=(client, 'gemini-video')), \
                 patch.object(engine.gemini_adapter, 'video_interaction', return_value='{"screenText":"Last frame"}'), \
                 patch.object(engine, 'emit') as emit:
                engine.parity.execute(args, root, p, engine)
            self.assertEqual(args.timestamp, 9.9)
            emit.assert_called_once_with('Frame text extracted', screenText='Last frame', timestamp=9.9)
            client.close.assert_called_once()

    def test_regenerate_all_clears_then_recreates_analysis(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            for folder in ('metadata','thumbnails','transcript','audio-description','exports'):
                (root/folder).mkdir()
                (root/folder/'old').write_text('old generated data')
            p=dict(id='keep',name='Keep',source='',sourceType='youtube',youtubeURL='original link',
                   transcript=[1],summary='old',cues=[2],exports=['old'],undoStack=[3])
            stages=[]
            def generate(root,p,stage):
                stages.append(stage)
                if stage=='transcribe':
                    self.assertEqual(p['transcript'],[])
                    self.assertEqual(p['summary'],'')
                    self.assertEqual(p['cues'],[])
                    self.assertEqual(p['exports'],[])
                    self.assertEqual(p['undoStack'],[])
                    self.assertFalse((root/'exports/old').exists())
                    p['transcript']=['new transcript']
                elif stage=='generate-summary': p['summary']='new summary'
                else: p['cues']=['new AD']
            with patch.object(engine,'ai_video',side_effect=generate):
                engine.parity.execute(SimpleNamespace(command='regenerate-all',start_stage='generate-summary'),root,p,engine)
            self.assertEqual(stages,['transcribe','generate-summary','generate-ad-cues'])
            self.assertEqual((p['id'],p['youtubeURL']),('keep','original link'))
            self.assertEqual(p['summary'],'new summary')
            self.assertEqual(p['cues'],['new AD'])

    def test_individual_analysis_preserves_other_content(self):
        original = dict(source='', sourceType='youtube', youtubeURL='https://www.youtube.com/watch?v=abcdefghijk', duration=10,
                        transcript=[dict(id='t', start=1, end=2, text='Old dialogue')], summary='Old summary',
                        cues=[dict(id='ad', start=4, end=5, text='Old AD', audio='audio-description/old.wav')],
                        exports=['exports/old.srt'], undoStack=[[{'text':'prior AD'}]])
        cases = [('transcribe', 'transcript', '[{"start":1,"end":2,"text":"New dialogue"}]'),
                 ('generate-summary', 'summary', 'New summary'),
                 ('generate-ad-cues', 'cues', '[{"start":4,"end":5,"text":"New AD"}]')]
        for stage, changed, response in cases:
            with self.subTest(stage=stage), tempfile.TemporaryDirectory() as temp:
                root=Path(temp)
                for folder in ('transcript','metadata','audio-description','exports'): (root/folder).mkdir()
                (root/'exports/old.srt').write_text('saved subtitles')
                (root/'audio-description/old.wav').write_bytes(b'saved narration')
                p=deepcopy(original)
                prompts={key:dict(user_prompt='Generate',system_instruction='') for key in ('transcript','youtube_transcript','summary','audio_descriptions')}
                with patch.object(engine,'config',return_value={'prompts':prompts}), patch.object(engine,'client_and_model',return_value=(Mock(),'gemini-video')), patch.object(engine.gemini_adapter,'video_interaction',return_value=response):
                    engine.ai_video(root,p,stage)
                self.assertNotEqual(p[changed], original[changed])
                for key in original:
                    if key != changed: self.assertEqual(p[key], original[key], key)
                self.assertEqual((root/'exports/old.srt').read_text(),'saved subtitles')
                self.assertEqual((root/'audio-description/old.wav').read_bytes(),b'saved narration')

    def test_clear_generated_preserves_source(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'source').mkdir()
            (root/'source/video.mp4').write_bytes(b'original')
            p = dict(id='project', name='Keep me', source='source/video.mp4', youtubeURL='https://youtu.be/example', summary='old', hasProcessed=True)
            for name in ['metadata', 'thumbnails', 'transcript', 'audio-description', 'exports']:
                (root/name).mkdir()
                (root/name/'generated').write_text('old')
            engine.clear_generated(root, p)
            self.assertEqual((root/'source/video.mp4').read_bytes(), b'original')
            self.assertEqual(p['id'], 'project')
            self.assertEqual(p['name'], 'Keep me')
            self.assertEqual(p['summary'], '')
            self.assertFalse(p['hasProcessed'])
            self.assertEqual(p['undoStack'], [])
            self.assertFalse(any((root/'exports').iterdir()))
            p['source'] = 'transcript/original.mp4'
            (root/p['source']).write_bytes(b'protected')
            with self.assertRaises(ValueError): engine.clear_generated(root, p)
            self.assertEqual((root/p['source']).read_bytes(), b'protected')

    def test_delete_generated_components_is_selective(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for folder in ('source', 'metadata/history', 'thumbnails', 'transcript', 'audio-description', 'exports'):
                (root/folder).mkdir(parents=True, exist_ok=True)
            (root/'source/video.mp4').write_bytes(b'original')
            (root/'metadata/summary.json').write_text('{"summary":"Summary"}')
            (root/'metadata/history/edit.json').write_text('{}')
            (root/'thumbnails/frame.jpg').write_bytes(b'image')
            (root/'transcript/transcript.json').write_text('[]')
            (root/'transcript/source.wav').write_bytes(b'audio')
            (root/'audio-description/cues.json').write_text('[]')
            (root/'audio-description/cue.wav').write_bytes(b'narration')
            (root/'exports/final.mp4').write_bytes(b'export')
            p = dict(
                source='source/video.mp4', transcript=[{'text': 'Dialogue'}], summary='Summary',
                cues=[{'text': 'Description', 'audio': 'audio-description/cue.wav', 'audioText': 'Description',
                       'audioDuration': 1.0, 'audioSettings': 'voice'}],
                thumbnails=['thumbnails/frame.jpg'], exports=['exports/final.mp4'],
                undoStack=[[{'text': 'Before'}]], redoStack=[], hasProcessed=True,
            )

            engine.delete_generated_components(root, p, ['summary', 'narration'])
            self.assertEqual(p['summary'], '')
            self.assertFalse((root/'metadata/summary.json').exists())
            self.assertEqual(p['cues'][0], {'text': 'Description'})
            self.assertFalse((root/'audio-description/cue.wav').exists())
            self.assertTrue((root/'audio-description/cues.json').exists())
            self.assertTrue((root/'transcript/transcript.json').exists())
            self.assertTrue((root/'source/video.mp4').exists())

            engine.delete_generated_components(root, p, ['transcript', 'descriptions', 'thumbnails', 'exports', 'history'])
            self.assertEqual((p['transcript'], p['cues'], p['thumbnails'], p['exports'], p['undoStack']), ([], [], [], [], []))
            self.assertFalse(p['hasProcessed'])
            self.assertTrue((root/'source/video.mp4').exists())
            self.assertFalse(any((root/'metadata/history').iterdir()))

    def test_overlap_and_boundaries(self):
        for cues in [[{'start':-1,'end':2,'text':'a'}],[{'start':0,'end':11,'text':'a'}],[{'start':0,'end':3,'text':'a'},{'start':2,'end':5,'text':'b'}],[{'start':0,'end':float('nan'),'text':'a'}]]:
            with self.assertRaises(ValueError): engine.validate_cues(cues,10)
    def test_dialogue_overlap(self):
        with self.assertRaises(ValueError): engine.validate_cues([{'start':1,'end':3,'text':'a'}],10,[{'start':2,'end':4}])
        self.assertEqual(len(engine.validate_cues([{'start':0,'end':2,'text':'a'}],10,[{'start':2,'end':4}])),1)
    def test_narration_export_rejects_all_silent_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            p = dict(
                duration=10, transcript=[], exports=[], source='', hasAudio=False,
                cues=[{'id': 'ad', 'start': 1, 'end': 3, 'text': 'A visual description.'}],
            )
            with patch.object(engine, 'config', return_value={}):
                with self.assertRaisesRegex(ValueError, 'Generate narration for at least one AD segment'):
                    engine.export(root, p, audio_only=True, allow_incomplete=True)
    def test_saved_narration_remains_usable_after_voice_change(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'audio-description').mkdir()
            (root/'audio-description/segment.wav').write_bytes(b'generated with an earlier voice')
            cue = {
                'id': 'ad', 'text': 'A visual description.',
                'audioText': 'A visual description.',
                'audio': 'audio-description/segment.wav',
                'audioSettings': 'system|Earlier Voice|1.000|1.000|1.000',
            }
            self.assertTrue(engine.narration_audio_is_usable(root, cue))
            cue['audioText'] = 'Earlier description text.'
            self.assertFalse(engine.narration_audio_is_usable(root, cue))
    def test_path_escape(self):
        with self.assertRaises(ValueError): engine.local(Path('/tmp/project'),'../../etc/passwd')
    def test_pipeline(self):
        with tempfile.TemporaryDirectory(prefix='vidistudio-test-') as temp:
            root=Path(temp); source=root/'sample video.mp4'
            engine.run([engine.tool('ffmpeg'),'-y','-v','error','-f','lavfi','-i','testsrc2=size=640x360:rate=24','-f','lavfi','-i','sine=frequency=440:sample_rate=48000','-t','8','-c:v','libx264','-c:a','aac',source])
            env=os.environ | {'VIDISTUDIO_CONFIG':str(root/'settings.json')}
            (root/'settings.json').write_text(json.dumps({
                'systemSpeechRate': 1.1,
                'systemSpeechPitch': 1.15,
                'systemSpeechVolume': 0.7,
            }))
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
            expected_voice = engine.system_voice_signature({})
            self.assertEqual(project()['cues'][0]['audioSettings'], f'system|{expected_voice}|1.100|1.150|0.700')
            # A later voice/rate change must not invalidate or replace the
            # already-generated file during playback or export.
            (root/'settings.json').write_text(json.dumps({
                'systemSpeechRate': 1.6,
                'systemSpeechPitch': 0.8,
                'systemSpeechVolume': 0.5,
            }))
            cli('export-final-video','--project',folder)
            output=folder/project()['exports'][0]
            self.assertAlmostEqual(float(engine.probe(output)['format']['duration']),8,delta=.2)
            stale=project()['cues']; stale[0]['text']='Changed narration.'; cues.write_text(json.dumps(stale))
            cli('save-cues','--project',folder,'--input',cues)
            cli('export-final-video','--project',folder,success=False)
            cli('transcribe','--project',folder,success=False)
            self.assertIn('API key',project()['error'])
if __name__=='__main__': unittest.main()
