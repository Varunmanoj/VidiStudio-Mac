import importlib.util, json, os, subprocess, sys, tempfile, unittest
from pathlib import Path
from unittest.mock import Mock, patch
from copy import deepcopy
from types import SimpleNamespace
ENGINE=Path(__file__).resolve().parents[1]/'engine/vidistudio_engine.py'
sys.path.insert(0,str(ENGINE.parent))
spec=importlib.util.spec_from_file_location('engine',ENGINE); engine=importlib.util.module_from_spec(spec); spec.loader.exec_module(engine)
class Validation(unittest.TestCase):
    def test_local_video_size_limit_accepts_boundary_and_rejects_larger_file(self):
        with tempfile.TemporaryDirectory() as temp:
            video = Path(temp)/'large-video.mp4'
            with video.open('wb') as stream:
                stream.truncate(engine.MAX_LOCAL_VIDEO_SIZE_BYTES)
            self.assertEqual(
                engine.ensure_supported_local_video(video),
                engine.MAX_LOCAL_VIDEO_SIZE_BYTES,
            )
            with video.open('r+b') as stream:
                stream.truncate(engine.MAX_LOCAL_VIDEO_SIZE_BYTES + 1)
            with self.assertRaisesRegex(ValueError, 'up to 2 GB'):
                engine.ensure_supported_local_video(video)

    def test_gemini_upload_rejects_oversized_file_before_network_request(self):
        with tempfile.TemporaryDirectory() as temp:
            video = Path(temp)/'large-video.mp4'
            with video.open('wb') as stream:
                stream.truncate(engine.MAX_LOCAL_VIDEO_SIZE_BYTES + 1)
            client = Mock()
            with self.assertRaisesRegex(ValueError, 'up to 2 GB'):
                engine.gemini_adapter.ready_file(client, video)
            client.files.upload.assert_not_called()

    def test_import_command_rejects_oversized_video_before_project_creation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            video = root/'large-video.mp4'
            with video.open('wb') as stream:
                stream.truncate(engine.MAX_LOCAL_VIDEO_SIZE_BYTES + 1)
            library = root/'library'
            result = subprocess.run(
                [sys.executable, str(ENGINE), 'import-video', '--video', str(video), '--library', str(library)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('up to 2 GB', result.stdout)
            self.assertFalse(library.exists())

    def test_duplicate_local_video_filename_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            library = Path(temp)
            project = library/'existing'
            project.mkdir()
            (project/'project.json').write_text(json.dumps({
                'source': 'source/My Video.MP4',
                'sourceType': 'upload',
            }))
            with self.assertRaisesRegex(ValueError, 'project already exists'):
                engine.ensure_unique_local_video(library, 'my video.mp4')
            engine.ensure_unique_local_video(library, 'another-video.mp4')

    def test_duplicate_youtube_video_url_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            library = Path(temp)
            project = library/'existing'
            project.mkdir()
            (project/'project.json').write_text(json.dumps({
                'source': '',
                'sourceType': 'youtube',
                'youtubeURL': 'https://www.youtube.com/watch?v=4fYlQtcm6qY',
            }))
            with self.assertRaisesRegex(ValueError, 'project already exists'):
                engine.ensure_unique_youtube_video(library, 'https://youtu.be/4fYlQtcm6qY')
            engine.ensure_unique_youtube_video(library, 'https://youtu.be/abcdefghijk')

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

    def test_delete_segment_audio_preserves_descriptions_and_other_audio(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'audio-description').mkdir()
            first_audio = root/'audio-description/first.wav'
            second_audio = root/'audio-description/second.wav'
            first_audio.write_bytes(b'first')
            second_audio.write_bytes(b'second')
            project = {'cues': [
                {'id':'first','start':1,'end':2,'text':'First description','audio':'audio-description/first.wav',
                 'audioText':'First description','audioDuration':1.0,'audioSettings':'voice'},
                {'id':'second','start':3,'end':4,'text':'Second description','audio':'audio-description/second.wav',
                 'audioText':'Second description','audioDuration':1.0,'audioSettings':'voice'},
            ]}

            engine.delete_segment_audio(root, project, 'first')

            self.assertEqual(len(project['cues']), 2)
            self.assertEqual(project['cues'][0], {'id':'first','start':1,'end':2,'text':'First description'})
            self.assertIn('audio', project['cues'][1])
            self.assertFalse(first_audio.exists())
            self.assertTrue(second_audio.exists())
            saved = json.loads((root/'audio-description/cues.json').read_text())
            self.assertEqual(saved, project['cues'])

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
    def test_final_video_ducks_original_only_during_narration(self):
        self.assertEqual(engine.original_audio_filter([]), '[0:a]anull[original]')
        self.assertEqual(
            engine.original_audio_filter([(1.0, 2.25), (4.5, 5.0)]),
            "[0:a]volume=0.2000:enable='between(t,1.000000,2.250000)+between(t,4.500000,5.000000)'[original]",
        )
    def test_export_filename_contains_project_type_and_timestamp(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'exports').mkdir()
            relative = engine.export_relative_path(
                root, {'name':'Dilemma / Episode: 3'}, 'Final Video', 'mp4', '20260909-123456'
            )
            self.assertEqual(relative, 'exports/Dilemma - Episode - 3 - Final Video - 20260909-123456.mp4')
            (root/relative).touch()
            self.assertEqual(
                engine.export_relative_path(root, {'name':'Dilemma / Episode: 3'}, 'Final Video', 'mp4', '20260909-123456'),
                'exports/Dilemma - Episode - 3 - Final Video - 20260909-123456 - 2.mp4',
            )
    def test_youtube_project_cannot_export_final_video_even_with_legacy_source(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            project = {
                'sourceType': 'youtube',
                'source': 'source/legacy-copy.mp4',
                'duration': 10,
                'transcript': [],
                'cues': [],
            }
            with self.assertRaisesRegex(ValueError, 'unavailable for YouTube URL projects'):
                engine.export(root, project, allow_incomplete=True)
            with self.assertRaisesRegex(ValueError, 'unavailable for YouTube URL projects'):
                engine.export(root, project, allow_incomplete=True, selectable=True)
            project['transcript'] = [{'id':'t','start':0,'end':1,'text':'Existing dialogue'}]
            with self.assertRaisesRegex(ValueError, 'unavailable for YouTube URL projects'):
                engine.export_captioned_video(root, project)
            with self.assertRaisesRegex(ValueError, 'unavailable for YouTube URL projects'):
                engine.export_captioned_video(root, project, open_captions=True)

    def test_closed_and_open_caption_video_exports(self):
        with tempfile.TemporaryDirectory(prefix='vidistudio-caption-test-') as temp:
            root = Path(temp)
            (root/'source').mkdir()
            (root/'exports').mkdir()
            source = root/'source/video.mp4'
            engine.run([
                engine.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi',
                '-i', 'testsrc2=size=320x180:rate=24', '-f', 'lavfi',
                '-i', 'sine=frequency=440:sample_rate=48000', '-t', '1.5',
                '-c:v', 'libx264', '-c:a', 'aac', source,
            ])
            project = {
                'name': 'Caption Demo', 'sourceType': 'upload', 'source': 'source/video.mp4',
                'duration': 1.5, 'width': 320, 'height': 180, 'hasAudio': True,
                'transcript': [{'id':'t','start':0.1,'end':1.2,'text':'A caption appears.'}],
                'cues': [{'id':'ad','start':1.2,'end':1.4,'text':'A shape fades.'}], 'exports': [],
            }
            caption_settings = {
                'captionFontSize': 28,
                'captionTextColor': '#112233',
                'captionBackgroundColor': '#445566',
                'adCaptionTextColor': '#AABBCC',
                'adCaptionBackgroundColor': '#DDEEFF',
                'captionBackgroundOpacity': .65,
                'captionPosition': 'top',
            }
            segments = engine.validated_caption_segments(project, content='combined')
            ass_text = engine.ass_caption_text(project, segments, caption_settings)
            self.assertIn('Style: Dialogue,Arial,', ass_text)
            self.assertIn('&H00332211', ass_text)
            self.assertIn('&H59665544', ass_text)
            self.assertIn('Style: AudioDescription,Arial,', ass_text)
            self.assertIn('&H00CCBBAA', ass_text)
            self.assertIn('&H59FFEEDD', ass_text)
            self.assertIn('Dialogue: 0,0:00:00.10,0:00:01.20,Dialogue,', ass_text)
            self.assertIn('Dialogue: 0,0:00:01.20,0:00:01.40,AudioDescription,', ass_text)
            with patch.object(engine, 'config', return_value=caption_settings):
                engine.export_captioned_video(root, project)
                engine.export_captioned_video(root, project, open_captions=True, content='combined')

            self.assertRegex(project['exports'][0], r'^exports/Caption Demo - Transcript Closed Caption Video - \d{8}-\d{6}\.mp4$')
            closed_info = engine.probe(root/project['exports'][0])
            closed_subtitles = [stream for stream in closed_info['streams'] if stream['codec_type'] == 'subtitle']
            self.assertEqual(len(closed_subtitles), 1)
            self.assertEqual(closed_subtitles[0]['codec_name'], 'mov_text')
            self.assertEqual(closed_subtitles[0]['tags']['language'], 'eng')

            self.assertRegex(project['exports'][1], r'^exports/Caption Demo - AD Transcript Open Caption Video - \d{8}-\d{6}\.mp4$')
            open_info = engine.probe(root/project['exports'][1])
            self.assertFalse([stream for stream in open_info['streams'] if stream['codec_type'] == 'subtitle'])
            self.assertEqual(len([stream for stream in open_info['streams'] if stream['codec_type'] == 'video']), 1)
    def test_selectable_export_adds_original_track_for_silent_local_video(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'source').mkdir()
            (root/'exports').mkdir()
            source = root/'source/silent.mp4'
            engine.run([
                engine.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi',
                '-i', 'testsrc2=size=320x180:rate=24', '-t', '1', '-c:v', 'libx264', source,
            ])
            project = {
                'name': 'Silent', 'sourceType': 'upload', 'source': 'source/silent.mp4',
                'duration': 1, 'hasAudio': False, 'transcript': [], 'cues': [], 'exports': [],
            }
            engine.export(root, project, allow_incomplete=True, selectable=True)
            info = engine.probe(root/project['exports'][0])
            audio = [stream for stream in info['streams'] if stream['codec_type'] == 'audio']
            self.assertEqual(len(audio), 2)
            self.assertEqual(audio[0]['tags']['handler_name'], 'Original Audio')
            self.assertEqual(audio[1]['tags']['handler_name'], 'English - Audio Description')
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
            timed_transcript = [{'id':'dialogue','start':6.2,'end':7.5,'text':'The final caption.'}]
            caption_ready = project()
            caption_ready['transcript'] = timed_transcript
            (folder/'project.json').write_text(json.dumps(caption_ready))
            (folder/'transcript/transcript.json').write_text(json.dumps(timed_transcript))
            cli('extract-audio','--project',folder)
            cues=root/'cues.json'; cues.write_text(json.dumps([{'id':'test','start':1,'end':6,'text':'Colorful shapes move.'}]))
            cli('save-cues','--project',folder,'--input',cues)
            cli('synthesize-tts','--project',folder)
            generated_audio=folder/project()['cues'][0]['audio']
            self.assertTrue(generated_audio.exists())
            expected_voice = engine.system_voice_signature({})
            self.assertEqual(project()['cues'][0]['audioSettings'], f'system|{expected_voice}|1.100|1.150|0.700')
            cli('delete-segment-audio','--project',folder,'--segment','test')
            self.assertEqual(project()['cues'][0]['text'],'Colorful shapes move.')
            self.assertNotIn('audio',project()['cues'][0])
            self.assertFalse(generated_audio.exists())
            cli('synthesize-tts','--project',folder,'--segment','test')
            # A later voice/rate change must not invalidate or replace the
            # already-generated file during playback or export.
            (root/'settings.json').write_text(json.dumps({
                'systemSpeechRate': 1.6,
                'systemSpeechPitch': 0.8,
                'systemSpeechVolume': 0.5,
            }))
            cli('export-open-audio-description-video','--project',folder)
            output=folder/project()['exports'][0]
            self.assertRegex(project()['exports'][0],r'^exports/sample video - Open Audio Description - \d{8}-\d{6}\.mp4$')
            self.assertAlmostEqual(float(engine.probe(output)['format']['duration']),8,delta=.2)
            cli('export-closed-audio-description-video','--project',folder)
            selectable=folder/project()['exports'][1]
            self.assertRegex(project()['exports'][1],r'^exports/sample video - Closed Audio Description - \d{8}-\d{6}\.mov$')
            selectable_info=engine.probe(selectable)
            self.assertEqual(len([s for s in selectable_info['streams'] if s['codec_type']=='video']),1)
            selectable_audio=[s for s in selectable_info['streams'] if s['codec_type']=='audio']
            self.assertEqual(len(selectable_audio),2)
            self.assertEqual(selectable_audio[0]['disposition']['default'],1)
            self.assertEqual(selectable_audio[1]['disposition']['default'],0)
            self.assertEqual(selectable_audio[0]['tags']['language'],'eng')
            self.assertEqual(selectable_audio[1]['tags']['language'],'eng')
            self.assertEqual(selectable_audio[0]['tags']['handler_name'],'Original Audio')
            self.assertEqual(selectable_audio[1]['tags']['handler_name'],'English - Audio Description')
            self.assertAlmostEqual(float(selectable_info['format']['duration']),8,delta=.2)
            cli('export-closed-caption-video','--project',folder,'--content','transcript')
            closed_caption=folder/project()['exports'][2]
            closed_info=engine.probe(closed_caption)
            self.assertEqual(len([s for s in closed_info['streams'] if s['codec_type']=='subtitle']),1)
            cli('export-open-caption-video','--project',folder,'--content','combined')
            open_caption=folder/project()['exports'][3]
            open_info=engine.probe(open_caption)
            self.assertFalse([s for s in open_info['streams'] if s['codec_type']=='subtitle'])
            cli('delete-export','--project',folder,'--name',project()['exports'][0])
            self.assertFalse(output.exists())
            cli('delete-export','--project',folder,'--name',project()['exports'][0])
            self.assertFalse(selectable.exists())
            cli('delete-export','--project',folder,'--name',project()['exports'][0])
            self.assertFalse(closed_caption.exists())
            cli('delete-export','--project',folder,'--name',project()['exports'][0])
            self.assertFalse(open_caption.exists())
            self.assertEqual(project()['exports'],[])
            self.assertTrue(any((folder/'metadata/trash').iterdir()))
            stale=project()['cues']; stale[0]['text']='Changed narration.'; cues.write_text(json.dumps(stale))
            cli('save-cues','--project',folder,'--input',cues)
            cli('export-open-audio-description-video','--project',folder,success=False)
            cli('transcribe','--project',folder,success=False)
            self.assertIn('API key',project()['error'])
            cli('delete-generated','--project',folder,'--component','narration')
            self.assertEqual(len(project()['cues']),1)
            self.assertEqual(project()['cues'][0]['text'],'Changed narration.')
            self.assertNotIn('audio',project()['cues'][0])
if __name__=='__main__': unittest.main()
