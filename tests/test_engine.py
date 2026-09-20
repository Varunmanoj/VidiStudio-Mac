import importlib.util, json, os, subprocess, sys, tempfile, unittest
from pathlib import Path
from unittest.mock import Mock, patch
from copy import deepcopy
from types import SimpleNamespace
ENGINE=Path(__file__).resolve().parents[1]/'engine/vidistudio_engine.py'
sys.path.insert(0,str(ENGINE.parent))
spec=importlib.util.spec_from_file_location('engine',ENGINE); engine=importlib.util.module_from_spec(spec); spec.loader.exec_module(engine)
class Validation(unittest.TestCase):
    def test_youtube_validation_uses_configured_video_model_and_closes_client(self):
        client = Mock()
        with patch.object(engine, 'client_and_model', return_value=(client, 'gemini-youtube')), \
             patch.object(engine.gemini_adapter, 'video_interaction', return_value='READY') as interaction:
            engine.validate_youtube_for_gemini('https://www.youtube.com/watch?v=abcdefghijk')
        interaction.assert_called_once_with(
            client,
            'gemini-youtube',
            'https://www.youtube.com/watch?v=abcdefghijk',
            None,
            'Confirm that this public YouTube video is available for video understanding. Return only READY.',
        )
        client.close.assert_called_once()

    def test_youtube_validation_rejects_links_gemini_cannot_read(self):
        client = Mock()
        with patch.object(engine, 'client_and_model', return_value=(client, 'gemini-youtube')), \
             patch.object(engine.gemini_adapter, 'video_interaction', side_effect=RuntimeError('video unavailable')):
            with self.assertRaisesRegex(ValueError, 'Private, Unlisted, and other visibility settings are not supported'):
                engine.validate_youtube_for_gemini('https://www.youtube.com/watch?v=abcdefghijk')
        client.close.assert_called_once()

    def test_transcription_enables_automatic_multilingual_detection(self):
        client = Mock()
        uploaded = SimpleNamespace(uri='files/mixed-language-audio', mime_type='audio/wav', name='files/mixed-language-audio')
        client.interactions.create.return_value = {
            'steps': [{
                'type': 'model_output',
                'content': [{
                    'annotations': [
                        {'type': 'word_info', 'start_offset': '0s', 'end_offset': '0.5s', 'text': 'नमस्ते', 'speaker': 'A'},
                        {'type': 'word_info', 'start_offset': '0.6s', 'end_offset': '1s', 'text': 'hello', 'speaker': 'A'},
                    ],
                }],
            }],
        }
        with patch.object(engine.gemini_adapter, 'ready_file', return_value=uploaded):
            segments = engine.gemini_adapter.transcribe_audio(client, 'gemini-3.5-transcribe', Path('/tmp/audio.wav'))
        transcription = client.interactions.create.call_args.kwargs['generation_config']['transcription_config']
        self.assertEqual(transcription['language_codes'], [])
        self.assertEqual(segments[0]['text'], 'नमस्ते hello')
        client.files.delete.assert_called_once_with(name=uploaded.name)

    def test_saved_prompt_overrides_keep_new_and_unchanged_defaults(self):
        with tempfile.TemporaryDirectory() as temp:
            config = Path(temp) / 'config.json'
            config.write_text(json.dumps({
                'models': {'summary': 'custom-summary'},
                'prompts': {'transcript': {'user_prompt': 'My custom transcript prompt'}},
            }))
            with patch.dict(os.environ, {'VIDISTUDIO_CONFIG': str(config)}):
                merged = engine.config()
        self.assertEqual(merged['models']['summary'], 'custom-summary')
        self.assertEqual(merged['prompts']['transcript']['user_prompt'], 'My custom transcript prompt')
        self.assertIn('expert video transcription analyst', merged['prompts']['transcript']['system_instruction'])
        self.assertIn('multilingual_media', merged['prompts'])

    def test_ai_generation_reports_the_matching_editor_section(self):
        prompts = {
            key: {'system_instruction': '', 'user_prompt': 'Generate'}
            for key in ('youtube_transcript', 'summary', 'audio_descriptions')
        }
        cases = [
            ('transcribe', 'Creating the transcript', 'transcript', '{"transcript":[{"start":0,"end":1,"text":"Hello"}]}'),
            ('generate-summary', 'Creating the summary', 'summary', 'Summary'),
            ('generate-ad-cues', 'Creating Audio Descriptions', 'descriptions', '{"audioDescriptions":[]}'),
        ]
        for stage, message, section, response in cases:
            with self.subTest(stage=stage), tempfile.TemporaryDirectory() as temp:
                project = {
                    'source': '', 'sourceType': 'youtube',
                    'youtubeURL': 'https://www.youtube.com/watch?v=abcdefghijk',
                    'duration': 10, 'hasAudio': True, 'transcript': [], 'summary': 'Summary', 'cues': [],
                }
                client = Mock()
                with patch.object(engine, 'config', return_value={'prompts': prompts}), \
                     patch.object(engine, 'client_and_model', return_value=(client, 'gemini-video')), \
                     patch.object(engine.gemini_adapter, 'video_interaction', return_value=response), \
                     patch.object(engine, 'emit') as emit:
                    engine._ai_video_once(Path(temp), project, stage)
                emit.assert_any_call(message, processingSection=section)
                client.close.assert_called_once()

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

    def test_prepare_video_refreshes_local_metadata_and_thumbnails_without_ai(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for folder in ('source', 'metadata', 'thumbnails'):
                (root/folder).mkdir()
            source = root/'source/video.mp4'
            source.write_bytes(b'video')
            project = dict(source='source/video.mp4', sourceType='upload', duration=1,
                           width=1, height=1, hasAudio=False, thumbnails=[])
            info = {'format': {'duration': '12.5'}, 'streams': [
                {'codec_type': 'video', 'width': 1920, 'height': 1080},
                {'codec_type': 'audio'},
            ]}
            with patch.object(engine, 'ensure_supported_local_video'), \
                 patch.object(engine, 'probe', return_value=info), \
                 patch.object(engine, 'thumbnails') as thumbnails, \
                 patch.object(engine, 'emit'):
                engine.parity.prepare_video(root, project, engine)
            self.assertEqual(project['duration'], 12.5)
            self.assertEqual((project['width'], project['height'], project['hasAudio']), (1920, 1080, True))
            self.assertEqual(json.loads((root/'metadata/probe.json').read_text()), info)
            thumbnails.assert_called_once_with(root, project)

    def test_prepare_youtube_video_refreshes_metadata_without_ai(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'metadata').mkdir()
            (root/'thumbnails').mkdir()
            project = dict(name='YouTube video', source='', sourceType='youtube',
                           youtubeURL='https://youtu.be/abcdefghijk', thumbnails=[])
            response = Mock()
            response.__enter__ = Mock(return_value=response)
            response.__exit__ = Mock(return_value=False)
            response.__iter__ = Mock()
            with patch.object(engine.parity, 'urlopen', return_value=response), \
                 patch.object(engine.parity.json, 'load', return_value={'title': 'Example Video'}), \
                 patch.object(engine.parity, 'download_youtube_thumbnail', return_value='thumbnails/youtube-thumbnail.jpg'), \
                 patch.object(engine, 'emit'):
                engine.parity.prepare_video(root, project, engine)
            self.assertEqual(project['name'], 'Example Video')
            self.assertEqual(project['thumbnails'], ['thumbnails/youtube-thumbnail.jpg'])
            self.assertFalse((root/'metadata/source.json').exists())

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
            with self.assertRaisesRegex(ValueError, 'Generate the summary first'):
                engine.validate_analysis_prerequisites('generate-ad-cues', root, {'transcriptGenerated': True, 'transcript': [{'text': 'Dialogue'}], 'summary': '   '})
            engine.validate_analysis_prerequisites(
                'generate-ad-cues',
                root,
                {'transcriptGenerated': True, 'transcript': [], 'summary': 'Summary'},
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

    def test_individual_analysis_preserves_unrelated_content_and_replaces_description_audio(self):
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
                    if key != changed:
                        self.assertEqual(p[key], original[key], key)
                self.assertEqual((root/'exports/old.srt').read_text(),'saved subtitles')
                if stage == 'generate-ad-cues':
                    self.assertFalse((root/'audio-description/old.wav').exists())
                    self.assertNotIn('audio', p['cues'][0])
                else:
                    self.assertEqual((root/'audio-description/old.wav').read_bytes(),b'saved narration')

    def test_description_reanalysis_deletes_narration_before_generation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for folder in ('transcript', 'metadata', 'audio-description', 'exports'):
                (root/folder).mkdir()
            narration = root/'audio-description/old.wav'
            narration.write_bytes(b'saved narration')
            project = dict(
                source='', sourceType='youtube', youtubeURL='https://www.youtube.com/watch?v=abcdefghijk',
                duration=10, transcriptGenerated=True, transcript=[], summary='Summary', exports=[],
                cues=[dict(id='old', start=1, end=2, text='Old description',
                           audio='audio-description/old.wav', audioText='Old description',
                           audioSettings='system|voice|1|1|1')],
            )
            prompts = {key: dict(user_prompt='Generate', system_instruction='')
                       for key in ('transcript', 'youtube_transcript', 'summary', 'audio_descriptions')}
            client = Mock()
            with patch.object(engine, 'config', return_value={'prompts': prompts}), \
                 patch.object(engine, 'client_and_model', return_value=(client, 'gemini-video')), \
                 patch.object(engine.gemini_adapter, 'video_interaction', side_effect=RuntimeError('generation failed')):
                with self.assertRaisesRegex(ValueError, 'generation failed'):
                    engine.ai_video(root, project, 'generate-ad-cues', max_attempts=1)
            self.assertFalse(narration.exists())
            self.assertEqual(project['cues'][0]['text'], 'Old description')
            self.assertNotIn('audio', project['cues'][0])
            self.assertNotIn('audioText', project['cues'][0])
            self.assertNotIn('audioSettings', project['cues'][0])

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
            self.assertFalse((root/'exports').exists())
            p['source'] = 'transcript/original.mp4'
            (root/'transcript').mkdir()
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
            self.assertFalse((root/'audio-description/cues.json').exists())
            self.assertTrue((root/'transcript/transcript.json').exists())
            self.assertTrue((root/'source/video.mp4').exists())

            engine.delete_generated_components(root, p, ['transcript', 'descriptions', 'thumbnails', 'exports', 'history'])
            self.assertEqual((p['transcript'], p['cues'], p['thumbnails'], p['exports'], p['undoStack']), ([], [], [], [], []))
            self.assertFalse(p['hasProcessed'])
            self.assertTrue((root/'source/video.mp4').exists())
            self.assertFalse((root/'metadata/history').exists())

    def test_cleanup_project_storage_keeps_only_canonical_and_referenced_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for folder in ('source', 'metadata/history', 'metadata/trash', 'thumbnails',
                           'transcript', 'audio-description', 'exports'):
                (root/folder).mkdir(parents=True, exist_ok=True)
            (root/'source/video.mp4').write_bytes(b'original')
            (root/'source/old.mp4').write_bytes(b'old source')
            (root/'metadata/probe.json').write_text('{}')
            (root/'metadata/summary.json').write_text('{"summary":"Summary"}')
            (root/'metadata/source.json').write_text('{}')
            (root/'metadata/ocr-1.json').write_text('{}')
            (root/'metadata/history/edit.json').write_text('{}')
            (root/'metadata/trash/deleted.mp4').write_bytes(b'deleted export')
            (root/'thumbnails/frame.jpg').write_bytes(b'current frame')
            (root/'thumbnails/capture-1.jpg').write_bytes(b'temporary frame')
            (root/'transcript/transcript.json').write_text('[]')
            (root/'transcript/source.wav').write_bytes(b'temporary audio')
            (root/'audio-description/current.wav').write_bytes(b'current narration')
            (root/'audio-description/orphan.wav').write_bytes(b'orphan narration')
            (root/'audio-description/cues.json').write_text('[]')
            (root/'audio-description/speech-input.txt').write_text('private text')
            (root/'exports/current.mp4').write_bytes(b'current export')
            (root/'exports/old.mp4').write_bytes(b'unlisted export')
            (root/'.DS_Store').write_bytes(b'finder')
            project = dict(
                schemaVersion=1, source='source/video.mp4', transcript=[], summary='Summary',
                cues=[{'audio': 'audio-description/current.wav'}],
                thumbnails=['thumbnails/frame.jpg'], exports=['exports/current.mp4'],
            )

            result = engine.cleanup_project_storage(root, project)

            self.assertGreater(result['bytes'], 0)
            self.assertEqual(project['schemaVersion'], 2)
            self.assertTrue(project['transcriptGenerated'])
            self.assertTrue(project['summaryGenerated'])
            self.assertTrue(project['descriptionsGenerated'])
            self.assertTrue((root/'source/video.mp4').exists())
            self.assertTrue((root/'metadata/probe.json').exists())
            self.assertTrue((root/'thumbnails/frame.jpg').exists())
            self.assertTrue((root/'audio-description/current.wav').exists())
            self.assertTrue((root/'exports/current.mp4').exists())
            for removed in ('source/old.mp4', 'metadata/summary.json', 'metadata/source.json',
                            'metadata/ocr-1.json', 'metadata/history', 'metadata/trash',
                            'thumbnails/capture-1.jpg', 'transcript', 'audio-description/orphan.wav',
                            'audio-description/cues.json', 'audio-description/speech-input.txt',
                            'exports/old.mp4', '.DS_Store'):
                self.assertFalse((root/removed).exists(), removed)

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
            self.assertFalse((root/'audio-description/cues.json').exists())

    def test_overlap_and_boundaries(self):
        for cues in [[{'start':-1,'end':2,'text':'a'}],[{'start':0,'end':11,'text':'a'}],[{'start':0,'end':3,'text':'a'},{'start':2,'end':5,'text':'b'}],[{'start':0,'end':float('nan'),'text':'a'}]]:
            with self.assertRaises(ValueError): engine.validate_cues(cues,10)
    def test_dialogue_overlap(self):
        with self.assertRaises(ValueError): engine.validate_cues([{'start':1,'end':3,'text':'a'}],10,[{'start':2,'end':4}])
        self.assertEqual(len(engine.validate_cues([{'start':0,'end':2,'text':'a'}],10,[{'start':2,'end':4}])),1)
    def test_save_segments_edits_transcript_and_deletes_removed_description_audio(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'audio-description').mkdir()
            deleted_audio = root/'audio-description/deleted.wav'
            kept_audio = root/'audio-description/kept.wav'
            deleted_audio.write_bytes(b'deleted')
            kept_audio.write_bytes(b'kept')
            project = dict(
                duration=12,
                transcript=[{'id':'dialogue','start':1,'end':2,'text':'Old dialogue'}],
                cues=[
                    {'id':'deleted','start':3,'end':4,'text':'Deleted description','audio':'audio-description/deleted.wav'},
                    {'id':'kept','start':5,'end':6,'text':'Kept description','audio':'audio-description/kept.wav'},
                ],
                exports=['exports/stale.mp4'], undoStack=[], redoStack=[], summary='', summaryGenerated=False,
            )

            engine.save_segments(
                project,
                [{'id':'dialogue','start':1.25,'end':2.5,'text':'Edited dialogue'}],
                [project['cues'][1]],
            )
            engine.cleanup_project_storage(root, project)

            self.assertEqual(project['transcript'][0]['text'], 'Edited dialogue')
            self.assertEqual([cue['id'] for cue in project['cues']], ['kept'])
            self.assertFalse(deleted_audio.exists())
            self.assertTrue(kept_audio.exists())
            self.assertEqual(project['exports'], [])
            self.assertEqual(len(project['undoStack']), 1)

    def test_transcript_edit_rejects_overlap_with_description(self):
        project = dict(
            duration=10, transcript=[],
            cues=[{'id':'ad','start':2,'end':3,'text':'Description'}],
            exports=[], undoStack=[], redoStack=[], summary='', summaryGenerated=False,
        )
        with self.assertRaisesRegex(ValueError, 'overlaps spoken dialogue'):
            engine.save_segments(
                project,
                [{'id':'dialogue','start':1,'end':2.5,'text':'Dialogue'}],
                project['cues'],
            )
    def test_save_segments_adds_a_new_transcript_segment(self):
        project = dict(
            duration=10,
            transcript=[{'id':'first','start':1,'end':2,'text':'First line'}],
            cues=[{'id':'ad','start':4,'end':5,'text':'Description'}],
            exports=['exports/stale.srt'], exportMediaInfo={'exports/stale.srt': {}},
            undoStack=[], redoStack=[], summary='', summaryGenerated=False,
        )

        engine.save_segments(
            project,
            [
                project['transcript'][0],
                {'id':'manual','start':2.5,'end':3.5,'text':'Manually added line','origin':'manual'},
            ],
            project['cues'],
        )

        self.assertEqual([segment['id'] for segment in project['transcript']], ['first', 'manual'])
        self.assertEqual(project['transcript'][1]['text'], 'Manually added line')
        self.assertEqual(project['transcript'][1]['origin'], 'manual')
        self.assertTrue(project['transcriptGenerated'])
        self.assertEqual(project['exports'], [])
        self.assertEqual(project['exportMediaInfo'], {})
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
    def test_export_filename_is_deterministic_and_requires_confirmed_replacement(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'exports').mkdir()
            relative = engine.export_relative_path(
                root, {'name':'Dilemma / Episode: 3'}, 'Final Video', 'mp4'
            )
            self.assertEqual(relative, 'exports/Dilemma - Episode - 3 - Final Video.mp4')
            project = {'name':'Dilemma / Episode: 3', 'exports': []}
            engine.write_text_export(root, project, 'Transcript', 'txt', 'first')
            target = root/'exports/Dilemma - Episode - 3 - Transcript.txt'
            self.assertEqual(target.read_text(), 'first')
            with self.assertRaisesRegex(ValueError, 'Confirm replacement'):
                engine.write_text_export(root, project, 'Transcript', 'txt', 'second')
            self.assertEqual(target.read_text(), 'first')
            engine.write_text_export(root, project, 'Transcript', 'txt', 'second', replace_existing=True)
            self.assertEqual(target.read_text(), 'second')
            self.assertEqual(project['exports'], ['exports/Dilemma - Episode - 3 - Transcript.txt'])
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
                engine.export_captioned_video(root, project, dual_closed=True)
                engine.export_captioned_video(root, project, open_captions=True, content='combined')

            self.assertEqual(project['exports'][0], 'exports/Caption Demo - Transcript Closed Caption Video.mp4')
            closed_info = engine.probe(root/project['exports'][0])
            source_video_hash = engine.run([
                engine.tool('ffmpeg'), '-v', 'error', '-i', source,
                '-map', '0:v:0', '-c', 'copy', '-f', 'hash', '-hash', 'sha256', '-',
            ])
            closed_video_hash = engine.run([
                engine.tool('ffmpeg'), '-v', 'error', '-i', root/project['exports'][0],
                '-map', '0:v:0', '-c', 'copy', '-f', 'hash', '-hash', 'sha256', '-',
            ])
            self.assertEqual(closed_video_hash, source_video_hash)
            self.assertEqual(project['exportMediaInfo'][project['exports'][0]]['videoProcessing'], 'copied')
            closed_subtitles = [stream for stream in closed_info['streams'] if stream['codec_type'] == 'subtitle']
            self.assertEqual(len(closed_subtitles), 1)
            self.assertEqual(closed_subtitles[0]['codec_name'], 'mov_text')
            self.assertEqual(closed_subtitles[0]['codec_tag_string'], 'tx3g')
            self.assertEqual((closed_subtitles[0]['width'], closed_subtitles[0]['height']), (320, 180))
            self.assertEqual(closed_subtitles[0]['tags']['language'], 'eng')

            self.assertEqual(
                project['exports'][1],
                'exports/Caption Demo - Transcript and Descriptive Transcript Closed Caption Video.mp4',
            )
            dual_output = root/project['exports'][1]
            dual_info = engine.probe(dual_output)
            dual_subtitles = [stream for stream in dual_info['streams'] if stream['codec_type'] == 'subtitle']
            self.assertEqual(len(dual_subtitles), 2)
            self.assertEqual(
                tuple(stream['tags']['handler_name'] for stream in dual_subtitles),
                ('English Transcript', 'English Descriptive Transcript'),
            )
            for stream in dual_subtitles:
                self.assertEqual(stream['codec_tag_string'], 'tx3g')
                self.assertEqual((stream['width'], stream['height']), (320, 180))
                self.assertEqual(stream['tags']['language'], 'eng')
            normal_srt = root/'normal-track.srt'
            descriptive_srt = root/'descriptive-track.srt'
            engine.run([engine.tool('ffmpeg'), '-y', '-v', 'error', '-i', dual_output, '-map', '0:s:0', normal_srt])
            engine.run([engine.tool('ffmpeg'), '-y', '-v', 'error', '-i', dual_output, '-map', '0:s:1', descriptive_srt])
            self.assertIn('A caption appears.', normal_srt.read_text())
            self.assertNotIn('Audio description:', normal_srt.read_text())
            self.assertIn('A caption appears.', descriptive_srt.read_text())
            self.assertIn('Audio description: A shape fades.', descriptive_srt.read_text())

            self.assertEqual(project['exports'][2], 'exports/Caption Demo - AD Transcript Open Caption Video.mp4')
            open_info = engine.probe(root/project['exports'][2])
            self.assertFalse([stream for stream in open_info['streams'] if stream['codec_type'] == 'subtitle'])
            self.assertEqual(len([stream for stream in open_info['streams'] if stream['codec_type'] == 'video']), 1)
            self.assertEqual(project['exportMediaInfo'][project['exports'][2]]['videoProcessing'], 'renderedOpenCaptions')
            self.assertEqual(project['exportMediaInfo'][project['exports'][2]]['width'], 320)
            self.assertEqual(project['exportMediaInfo'][project['exports'][2]]['height'], 180)

    def test_audio_description_video_exports_support_every_caption_choice(self):
        with tempfile.TemporaryDirectory(prefix='vidistudio-described-caption-test-') as temp:
            root = Path(temp)
            (root/'source').mkdir()
            (root/'exports').mkdir()
            (root/'audio-description').mkdir()
            source = root/'source/video.mp4'
            narration = root/'audio-description/narration.wav'
            engine.run([
                engine.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi',
                '-i', 'testsrc2=size=320x180:rate=24', '-f', 'lavfi',
                '-i', 'sine=frequency=440:sample_rate=48000', '-t', '1.5',
                '-c:v', 'libx264', '-c:a', 'aac', source,
            ])
            engine.run([
                engine.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi',
                '-i', 'sine=frequency=880:sample_rate=48000', '-t', '0.2', narration,
            ])
            project = {
                'name': 'Accessible Demo', 'sourceType': 'upload', 'source': 'source/video.mp4',
                'duration': 1.5, 'width': 320, 'height': 180, 'hasAudio': True,
                'transcript': [{'id':'t','start':.8,'end':1.2,'text':'The dialogue.'}],
                'cues': [{
                    'id':'ad', 'start':.1, 'end':.5, 'text':'A shape appears.',
                    'audio':'audio-description/narration.wav', 'audioText':'A shape appears.',
                }],
                'exports': [],
            }
            choices = [
                ('none', 'transcript'),
                ('closed', 'transcript'),
                ('open', 'transcript'),
                ('closed', 'combined'),
                ('open', 'combined'),
                ('dual-closed', 'combined'),
            ]
            with patch.object(engine, 'config', return_value={}):
                for selectable in (True, False):
                    for captions, content in choices:
                        engine.export(
                            root, project, selectable=selectable,
                            captions=captions, content=content,
                        )
                        output = root/project['exports'][-1]
                        info = engine.probe(output)
                        audio = [stream for stream in info['streams'] if stream['codec_type'] == 'audio']
                        subtitles = [stream for stream in info['streams'] if stream['codec_type'] == 'subtitle']
                        self.assertEqual(len(audio), 2 if selectable else 1)
                        expected_subtitle_count = 2 if captions == 'dual-closed' else 1 if captions == 'closed' else 0
                        self.assertEqual(len(subtitles), expected_subtitle_count)
                        if subtitles:
                            for subtitle in subtitles:
                                self.assertEqual(subtitle['codec_name'], 'mov_text')
                                self.assertEqual(subtitle['codec_tag_string'], 'tx3g')
                                self.assertEqual((subtitle['width'], subtitle['height']), (320, 180))
                                self.assertEqual(subtitle['tags']['language'], 'eng')
                        if captions == 'dual-closed':
                            self.assertEqual(
                                tuple(subtitle['tags']['handler_name'] for subtitle in subtitles),
                                ('English Transcript', 'English Descriptive Transcript'),
                            )
                        expected_extension = '.mov' if selectable else '.mp4'
                        self.assertTrue(output.name.endswith(expected_extension), output)
                        media_information = project['exportMediaInfo'][project['exports'][-1]]
                        self.assertEqual(
                            media_information['videoProcessing'],
                            'renderedOpenCaptions' if captions == 'open' else 'copied',
                        )
                        self.assertEqual((media_information['width'], media_information['height']), (320, 180))
                        if captions != 'open':
                            source_hash = engine.run([
                                engine.tool('ffmpeg'), '-v', 'error', '-i', source,
                                '-map', '0:v:0', '-c', 'copy', '-f', 'hash', '-hash', 'sha256', '-',
                            ])
                            output_hash = engine.run([
                                engine.tool('ffmpeg'), '-v', 'error', '-i', output,
                                '-map', '0:v:0', '-c', 'copy', '-f', 'hash', '-hash', 'sha256', '-',
                            ])
                            self.assertEqual(output_hash, source_hash)

    def test_open_caption_render_preserves_hdr_resolution_bit_depth_and_color_signaling(self):
        with tempfile.TemporaryDirectory(prefix='vidistudio-hdr-caption-test-') as temp:
            root = Path(temp)
            (root/'source').mkdir()
            (root/'exports').mkdir()
            source = root/'source/hdr.mp4'
            engine.run([
                engine.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi',
                '-i', 'testsrc2=size=320x180:rate=24', '-t', '0.5',
                '-vf', 'format=yuv420p10le', '-c:v', 'libx265', '-preset', 'ultrafast',
                '-x265-params', 'log-level=error:colorprim=bt2020:transfer=arib-std-b67:colormatrix=bt2020nc', '-color_primaries', 'bt2020',
                '-color_trc', 'arib-std-b67', '-colorspace', 'bt2020nc', source,
            ])
            project = {
                'name': 'HDR Demo', 'sourceType': 'upload', 'source': 'source/hdr.mp4',
                'duration': .5, 'width': 320, 'height': 180, 'hasAudio': False,
                'transcript': [{'id':'t','start':.05,'end':.4,'text':'HDR caption.'}],
                'cues': [], 'exports': [],
            }
            with patch.object(engine, 'config', return_value={}):
                engine.export_captioned_video(root, project, open_captions=True)
            output = root/project['exports'][0]
            source_video = next(stream for stream in engine.probe(source)['streams'] if stream['codec_type'] == 'video')
            output_video = next(stream for stream in engine.probe(output)['streams'] if stream['codec_type'] == 'video')
            self.assertEqual((output_video['width'], output_video['height']), (source_video['width'], source_video['height']))
            self.assertIn('10', output_video['pix_fmt'])
            self.assertEqual(output_video['color_primaries'], 'bt2020')
            self.assertEqual(output_video['color_transfer'], 'arib-std-b67')
            self.assertEqual(output_video['color_space'], 'bt2020nc')
            self.assertEqual(project['exportMediaInfo'][project['exports'][0]]['videoProcessing'], 'renderedOpenCaptions')
            self.assertIn('HDR (HLG)', project['exportMediaInfo'][project['exports'][0]]['color'])

    def test_original_and_described_program_audio_export_as_mp3(self):
        with tempfile.TemporaryDirectory(prefix='vidistudio-audio-export-test-') as temp:
            root = Path(temp)
            (root/'source').mkdir()
            (root/'exports').mkdir()
            (root/'audio-description').mkdir()
            source = root/'source/video.mp4'
            narration = root/'audio-description/narration.wav'
            engine.run([
                engine.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi',
                '-i', 'testsrc2=size=320x180:rate=24', '-f', 'lavfi',
                '-i', 'sine=frequency=440:sample_rate=48000', '-t', '1.5',
                '-c:v', 'libx264', '-c:a', 'aac', source,
            ])
            engine.run([
                engine.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi',
                '-i', 'sine=frequency=880:sample_rate=48000', '-t', '0.2', narration,
            ])
            project = {
                'name': 'Audio Demo', 'sourceType': 'upload', 'source': 'source/video.mp4',
                'duration': 1.5, 'hasAudio': True,
                'transcript': [{'id':'t','start':.8,'end':1.2,'text':'The dialogue.'}],
                'cues': [{
                    'id':'ad', 'start':.1, 'end':.5, 'text':'A shape appears.',
                    'audio':'audio-description/narration.wav', 'audioText':'A shape appears.',
                }],
                'exports': [],
            }
            engine.export_program_audio(root, project)
            engine.export_program_audio(root, project, described=True)
            self.assertEqual(project['exports'][0], 'exports/Audio Demo - Original Video Audio.mp3')
            self.assertEqual(project['exports'][1], 'exports/Audio Demo - Final Audio with Audio Description.mp3')
            original_bytes = (root/project['exports'][0]).read_bytes()
            with self.assertRaisesRegex(ValueError, 'Confirm replacement'):
                engine.export_program_audio(root, project)
            self.assertEqual((root/project['exports'][0]).read_bytes(), original_bytes)
            with patch.object(engine, 'run', side_effect=ValueError('replacement render failed')):
                with self.assertRaisesRegex(ValueError, 'replacement render failed'):
                    engine.export_program_audio(root, project, replace_existing=True)
            self.assertEqual((root/project['exports'][0]).read_bytes(), original_bytes)
            engine.export_program_audio(root, project, replace_existing=True)
            self.assertEqual(len(project['exports']), 2)
            for relative in project['exports']:
                info = engine.probe(root/relative)
                self.assertFalse([stream for stream in info['streams'] if stream['codec_type'] == 'video'])
                audio = [stream for stream in info['streams'] if stream['codec_type'] == 'audio']
                self.assertEqual(len(audio), 1)
                self.assertEqual(audio[0]['codec_name'], 'mp3')

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
            caption_ready['transcriptGenerated'] = True
            (folder/'project.json').write_text(json.dumps(caption_ready))
            cues=root/'cues.json'; cues.write_text(json.dumps([{'id':'test','start':1,'end':6,'text':'Colorful shapes move.'}]))
            cli('save-cues','--project',folder,'--input',cues)
            cli('synthesize-tts','--project',folder)
            generated_audio=folder/project()['cues'][0]['audio']
            self.assertTrue(generated_audio.exists())
            editable_segments = project()
            editable_segments['transcript'][0]['text'] = 'The edited final caption.'
            segments = root/'segments.json'
            segments.write_text(json.dumps({
                'transcript': editable_segments['transcript'],
                'cues': editable_segments['cues'],
            }))
            cli('save-segments','--project',folder,'--input',segments)
            self.assertEqual(project()['transcript'][0]['text'], 'The edited final caption.')
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
            cli('export-open-audio-description-video','--project',folder,'--captions','open','--content','transcript')
            output=folder/project()['exports'][0]
            self.assertEqual(project()['exports'][0],'exports/sample video - Open Audio Description with Transcript Open Captions.mp4')
            self.assertAlmostEqual(float(engine.probe(output)['format']['duration']),8,delta=.2)
            self.assertFalse([stream for stream in engine.probe(output)['streams'] if stream['codec_type']=='subtitle'])
            self.assertEqual(project()['exportMediaInfo'][project()['exports'][0]]['videoProcessing'],'renderedOpenCaptions')
            cli('export-closed-audio-description-video','--project',folder,'--captions','closed','--content','combined')
            selectable=folder/project()['exports'][1]
            self.assertEqual(project()['exports'][1],'exports/sample video - Closed Audio Description with AD Transcript Closed Captions.mov')
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
            selectable_subtitles=[s for s in selectable_info['streams'] if s['codec_type']=='subtitle']
            self.assertEqual(len(selectable_subtitles),1)
            self.assertEqual(selectable_subtitles[0]['codec_name'],'mov_text')
            self.assertEqual(selectable_subtitles[0]['codec_tag_string'],'tx3g')
            self.assertEqual((selectable_subtitles[0]['width'],selectable_subtitles[0]['height']),(640,360))
            self.assertAlmostEqual(float(selectable_info['format']['duration']),8,delta=.2)
            self.assertEqual(project()['exportMediaInfo'][project()['exports'][1]]['videoProcessing'],'copied')
            source_hash=engine.run([engine.tool('ffmpeg'),'-v','error','-i',folder/project()['source'],'-map','0:v:0','-c','copy','-f','hash','-hash','sha256','-'])
            selectable_hash=engine.run([engine.tool('ffmpeg'),'-v','error','-i',selectable,'-map','0:v:0','-c','copy','-f','hash','-hash','sha256','-'])
            self.assertEqual(selectable_hash,source_hash)
            cli('export-closed-caption-video','--project',folder,'--content','transcript')
            closed_caption=folder/project()['exports'][2]
            closed_info=engine.probe(closed_caption)
            self.assertEqual(len([s for s in closed_info['streams'] if s['codec_type']=='subtitle']),1)
            cli('export-dual-closed-caption-video','--project',folder)
            dual_closed_caption=folder/project()['exports'][3]
            dual_closed_info=engine.probe(dual_closed_caption)
            dual_closed_subtitles=[s for s in dual_closed_info['streams'] if s['codec_type']=='subtitle']
            self.assertEqual(len(dual_closed_subtitles),2)
            self.assertEqual(
                tuple(s['tags']['handler_name'] for s in dual_closed_subtitles),
                ('English Transcript','English Descriptive Transcript'),
            )
            cli('export-open-caption-video','--project',folder,'--content','combined')
            open_caption=folder/project()['exports'][4]
            open_info=engine.probe(open_caption)
            self.assertFalse([s for s in open_info['streams'] if s['codec_type']=='subtitle'])
            cli('export-original-audio','--project',folder)
            original_audio=folder/project()['exports'][5]
            self.assertEqual(engine.probe(original_audio)['streams'][0]['codec_name'],'mp3')
            cli('export-original-audio','--project',folder,success=False)
            self.assertTrue(original_audio.exists())
            self.assertEqual(len(project()['exports']),6)
            cli('export-original-audio','--project',folder,'--replace-existing')
            self.assertEqual(project()['exports'][-1],original_audio.relative_to(folder).as_posix())
            self.assertEqual(len(project()['exports']),6)
            cli('export-described-audio','--project',folder)
            described_audio=folder/project()['exports'][6]
            self.assertEqual(engine.probe(described_audio)['streams'][0]['codec_name'],'mp3')
            for expected in [output,selectable,closed_caption,dual_closed_caption,open_caption,original_audio,described_audio]:
                cli('delete-export','--project',folder,'--name',project()['exports'][0])
                self.assertFalse(expected.exists())
            self.assertEqual(project()['exports'],[])
            self.assertFalse((folder/'metadata/trash').exists())
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
