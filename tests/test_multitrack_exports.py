import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'engine'))
import language_results as lr
import multitrack_exports as tracks
spec = importlib.util.spec_from_file_location('track_core', ROOT/'engine/vidistudio_engine.py')
core = importlib.util.module_from_spec(spec); spec.loader.exec_module(core)


class SelectedTracks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(); cls.root = Path(cls.tmp.name)
        subprocess.run([core.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi', '-i', 'color=c=blue:s=320x180:r=24', '-f', 'lavfi', '-i', 'sine=frequency=220:sample_rate=48000', '-t', '4', '-c:v', 'libx264', '-c:a', 'aac', str(cls.root/'source.mp4')], check=True)
        subprocess.run([core.tool('ffmpeg'), '-y', '-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=660:sample_rate=48000', '-t', '0.6', str(cls.root/'voice.wav')], check=True)

    @classmethod
    def tearDownClass(cls): cls.tmp.cleanup()

    def setUp(self):
        self.project = dict(id='multitrack', name='Multilingual Example', schemaVersion=3, duration=4, source='source.mp4', sourceType='local', hasAudio=True, width=320, height=180, exports=[])
        lr.migrate(self.project)
        self.ids = {}
        for code, word in [('auto', 'Mixed'), ('en', 'Hello'), ('hi', 'नमस्ते')]:
            cue = dict(id='c-'+code, start=2, end=3, text=word, audio='voice.wav', audioText=word, audioStart=2, audioEnd=3, audioDuration=.6)
            transcript = lr.record(self.project, 'transcript', code, dict(transcript=[dict(id='t-'+code, start=0, end=1, text=word)]))
            description = lr.record(self.project, 'descriptions', code, dict(cues=[cue]))
            self.project['languageResults'] += [transcript, description]
            self.ids[code] = (transcript['id'], description['id'])
        self.project['selectedLanguage'] = 'hi'
        lr.project(self.project)
        self.plan = dict(media='video', format='mkv', original=True, audioMode='selectable', captionMode='closed',
                         audio=[dict(language=c, resultID=self.ids[c][1]) for c in ('auto','en','hi')],
                         captions=[dict(language=c, transcriptID=self.ids[c][0], descriptionsID=self.ids[c][1] if c == 'en' else '') for c in ('auto','en','hi')])

    def run_plan(self, plan):
        selected = tracks.validate(self.root, self.project, plan, core)
        with patch.object(core, 'save'), patch.object(core, 'emit'):
            tracks.execute(self.root, self.project, selected, core, replace=True)
        path = self.root/self.project['exports'][-1]
        return path, core.probe(path)

    def test_video_tracks_labels_defaults_and_auto(self):
        for format in ('mkv', 'mp4', 'mov', 'm4v'):
            with self.subTest(format=format):
                self.plan['format'] = format
                path, info = self.run_plan(self.plan)
                audio = [s for s in info['streams'] if s['codec_type'] == 'audio']
                captions = [s for s in info['streams'] if s['codec_type'] == 'subtitle']
                self.assertEqual(len(audio), 4); self.assertEqual(len(captions), 3)
                self.assertEqual([s.get('tags', {}).get('language','und') for s in audio], ['und','und','eng','hin'])
                self.assertEqual([s.get('tags', {}).get('language','und') for s in captions], ['und','eng','hin'])
                self.assertEqual([s['disposition']['default'] for s in audio], [1,0,0,0])
                if format == 'mkv': self.assertTrue(all(s['disposition']['default'] == 0 for s in captions))
                self.assertIn('Auto + English + Hindi', path.name)
                self.assertEqual(self.project['selectedLanguage'], 'hi')
                text = subprocess.check_output([core.tool('ffmpeg'), '-v','error','-i',str(path),'-map','0:s:2','-f','srt','-']).decode()
                self.assertIn('नमस्ते', text)

    def test_both_transcript_types_in_each_language(self):
        plan = copy.deepcopy(self.plan)
        plan['captions'] = [dict(language=code, transcriptID=self.ids[code][0], descriptionsID=description)
                            for code in ('en', 'hi') for description in ('', self.ids[code][1])]
        for format in ('mkv', 'mp4', 'mov', 'm4v'):
            with self.subTest(format=format):
                path, info = self.run_plan(dict(plan, format=format))
                streams = [s for s in info['streams'] if s['codec_type'] == 'subtitle']
                self.assertEqual(len(streams), 4)
                self.assertEqual([s['tags'].get('title') or s['tags'].get('handler_name') for s in streams],
                                 ['English Transcript', 'English AD Transcript', 'Hindi Transcript', 'Hindi AD Transcript'])
                self.assertEqual([s['tags'].get('language') for s in streams], ['eng', 'eng', 'hin', 'hin'])
                for index in range(4):
                    text = subprocess.check_output([core.tool('ffmpeg'), '-v', 'error', '-i', str(path), '-map', f'0:s:{index}', '-f', 'srt', '-']).decode()
                    self.assertEqual('Audio description' in text, bool(index % 2))
        with self.assertRaisesRegex(ValueError, 'Burned-in'):
            tracks.validate(self.root, self.project, dict(plan, captionMode='open'), core)
        bad = copy.deepcopy(plan); bad['captions'].append(dict(plan['captions'][0]))
        with self.assertRaisesRegex(ValueError, 'one Transcript'):
            tracks.validate(self.root, self.project, bad, core)

    def test_single_burned_caption_and_mixed_audio(self):
        plan = dict(self.plan, audioMode='mixed', captionMode='open', audio=[self.plan['audio'][1]], captions=[self.plan['captions'][1]])
        _, info = self.run_plan(plan)
        self.assertEqual(sum(s['codec_type']=='audio' for s in info['streams']), 1)
        self.assertFalse(any(s['codec_type']=='subtitle' for s in info['streams']))

    def test_multitrack_audio_containers(self):
        for format in ('m4a','mka'):
            _, info = self.run_plan(dict(self.plan, media='audio', format=format, captions=[]))
            self.assertEqual(len(info['streams']), 4)
            self.assertTrue(all(s['codec_type']=='audio' for s in info['streams']))
            self.assertNotIn(self.project['exports'][-1], self.project.get('exportMediaInfo', {}))

    def test_duplicate_language_and_open_multiples_rejected(self):
        alternatives = lr.record(self.project,'descriptions','en',copy.deepcopy(lr.find(self.project,self.ids['en'][1])['payload']))
        self.project['languageResults'].append(alternatives)
        bad = copy.deepcopy(self.plan); bad['audio'].append(dict(language='en', resultID=alternatives['id']))
        for plan in [bad, dict(self.plan, audioMode='mixed'), dict(self.plan, captionMode='open')]:
            with self.assertRaises(ValueError): tracks.validate(self.root,self.project,plan,core)
        chosen = dict(self.plan, audio=[dict(language='en',resultID=alternatives['id'])],captions=[dict(self.plan['captions'][1],descriptionsID='')])
        with self.assertRaisesRegex(ValueError,'same description result'):
            tracks.validate(self.root,self.project,dict(chosen,captions=[self.plan['captions'][1]]),core)
        validated = tracks.validate(self.root,self.project,chosen,core)
        self.assertEqual(list(validated['resultIDs'].values()).count(alternatives['id']),1)
        self.assertNotIn(self.ids['en'][1],validated['resultIDs'])
        _, info = self.run_plan(chosen)
        audio = [s for s in info['streams'] if s['codec_type']=='audio']
        self.assertEqual(len(audio),2)
        self.assertEqual(audio[1]['tags']['title'],'English - Audio Description')
        bad = copy.deepcopy(self.plan); bad['captions'].append(bad['captions'][1])
        with self.assertRaisesRegex(ValueError,'one Transcript and one AD Transcript'): tracks.validate(self.root,self.project,bad,core)

    def test_batch_preflight_provenance_skip_and_cancellation(self):
        request = self.root/'request.json'
        before = copy.deepcopy(self.project)
        args = SimpleNamespace(input=request, content='transcript', captions='none')
        request.write_text(json.dumps(dict(jobs=[dict(command='export-selected-tracks',trackPlan=self.plan),dict(command='export-selected-tracks',trackPlan=dict(self.plan,audioMode='mixed'))])))
        with self.assertRaises(ValueError), patch.object(tracks,'execute') as execute:
            lr.export_batch(args,self.root,self.project,core,lambda *a:None)
        execute.assert_not_called(); self.assertEqual(before,self.project)
        request.write_text(json.dumps(dict(jobs=[dict(command='export-selected-tracks',trackPlan=self.plan,replaceExisting=True)])))
        with patch.object(core,'save'), patch.object(core,'emit'):
            lr.export_batch(args,self.root,self.project,core,lambda *a:None)
        relative = self.project['exports'][-1]
        self.assertEqual(self.project['exportResults'][relative]['languages'],['auto','en','hi'])
        self.assertEqual(len(self.project['exportResults'][relative]['resultIDs']),6)
        provenance = copy.deepcopy(self.project['exportResults'][relative])
        english = dict(self.plan, audio=[self.plan['audio'][1]], captions=[self.plan['captions'][1]])
        request.write_text(json.dumps(dict(jobs=[dict(command='export-selected-tracks',trackPlan=english,replaceExisting=True)])))
        with patch.object(core,'save'), patch.object(core,'emit'):
            lr.export_batch(args,self.root,self.project,core,lambda *a:None)
        self.assertEqual(self.project['exportResults'][relative],provenance, 'Replacing another output relabelled an existing multilingual export.')
        content = (self.root/relative).read_bytes()
        request.write_text(json.dumps(dict(jobs=[dict(command='export-selected-tracks',trackPlan=self.plan)])))
        with patch.object(core,'save'),patch.object(core,'emit'):
            lr.export_batch(args,self.root,self.project,core,lambda *a:None)
            lr.organize_exports(self.root,self.project,core)
        self.assertEqual((self.root/relative).read_bytes(),content)
        with patch.object(core,'run_export',side_effect=core.ProcessingCancelled()),patch.object(core,'save'):
            with self.assertRaises(core.ProcessingCancelled): tracks.execute(self.root,self.project,tracks.validate(self.root,self.project,self.plan,core),core,replace=True)
        self.assertEqual((self.root/relative).read_bytes(),content)
        self.assertFalse(list((self.root/relative).parent.glob('*.generating-*')))

    def test_imported_audio_and_independent_timing_validation(self):
        imported = lr.record(self.project,'adAudio','en',dict(importedAudioDescription=dict(path='source.mp4',mode='fullMix',sourceName='Imported English')))
        self.project['languageResults'].append(imported)
        plan = dict(self.plan, audio=[dict(language='en',resultID=imported['id'])],captions=[])
        _, info = self.run_plan(plan)
        self.assertEqual(sum(s['codec_type']=='audio' for s in info['streams']),2)
        bad = copy.deepcopy(self.project)
        transcript = lr.find(bad,self.ids['hi'][0]); transcript['payload']['transcript'][0].update(start=2,end=3)
        with self.assertRaises(ValueError): tracks.validate(self.root,bad,self.plan,core)

    def test_original_source_language_is_preserved_independently(self):
        core.run([core.tool('ffmpeg'),'-y','-v','error','-i',self.root/'source.mp4','-map','0','-c','copy','-metadata:s:a:0','language=fra',self.root/'french.mp4'])
        self.project['source']='french.mp4'
        plan=dict(self.plan,audio=[self.plan['audio'][1]],captions=[self.plan['captions'][1]])
        for format in ('mov','mp4','mkv'):
            _,info=self.run_plan(dict(plan,format=format))
            audio=[s for s in info['streams'] if s['codec_type']=='audio']
            self.assertEqual(audio[0]['tags'].get('title') or audio[0]['tags'].get('handler_name'),'Original Audio')
            self.assertEqual(audio[0]['tags']['language'],'fra')
            self.assertEqual(audio[1]['tags']['language'],'eng')
            self.assertEqual(audio[1]['tags'].get('title') or audio[1]['tags'].get('handler_name'),'English - Audio Description')

        selected=dict(self.project,cues=lr.find(self.project,self.ids['en'][1])['payload']['cues'],transcript=lr.find(self.project,self.ids['en'][0])['payload']['transcript'])
        with patch.object(lr,'_export_language','en'),patch.object(core,'emit'):
            core.export(self.root,selected,selectable=True,media_format='mov')
            audio=[s for s in core.probe(self.root/selected['exports'][-1])['streams'] if s['codec_type']=='audio']
            self.assertEqual(audio[0]['tags']['title'],'Original Audio')
            self.assertEqual(audio[0]['tags']['language'],'fra')
            self.assertEqual(audio[1]['tags']['title'],'English - Audio Description')
            for described in (False,True):
                core.export_program_audio(self.root,selected,described=described,media_format='m4a')
                stream=core.probe(self.root/selected['exports'][-1])['streams'][0]
                self.assertEqual(stream['tags']['title'],'English - Audio Description' if described else 'Original Audio')
                self.assertEqual(stream['tags']['language'],'eng' if described else 'fra')

    def test_z_packaged_cli_when_configured(self):
        executable = os.environ.get('VIDISTUDIO_TEST_ENGINE')
        if not executable: self.skipTest('Set VIDISTUDIO_TEST_ENGINE to exercise the packaged CLI.')
        (self.root/'project.json').write_text(json.dumps(self.project))
        request = self.root/'cli.json'
        plan = dict(self.plan, format='mkv')
        request.write_text(json.dumps(dict(jobs=[dict(command='export-selected-tracks',trackPlan=plan,replaceExisting=True)])))
        output = subprocess.run([executable,'export-batch','--project',str(self.root),'--input',str(request)],capture_output=True,text=True,timeout=90)
        self.assertEqual(output.returncode,0,output.stdout+output.stderr)
        saved = json.loads((self.root/'project.json').read_text())
        self.assertEqual(saved['selectedLanguage'],'hi')
        self.assertTrue(any(r.get('languages')==['auto','en','hi'] for r in saved['exportResults'].values()))
        relative=next(path for path,r in saved['exportResults'].items() if r.get('languages')==['auto','en','hi'])
        audio=[s for s in core.probe(self.root/relative)['streams'] if s['codec_type']=='audio']
        self.assertEqual([s['tags'].get('title') or s['tags'].get('handler_name') for s in audio],['Original Audio','Auto - Audio Description','English - Audio Description','Hindi - Audio Description'])
