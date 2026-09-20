import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'engine'))
import vidistudio_engine as e
import parity


class TranscriptRangeTests(unittest.TestCase):
    def project(self):
        return dict(duration=60, source='', sourceType='youtube', youtubeURL='https://www.youtube.com/watch?v=abcdefghijk',
            transcript=[dict(id='far', start=0, end=2, text='Opening', origin='manual'),
                        dict(id='before', start=6, end=8, text='Hello', speaker='A', origin='manual'),
                        dict(id='target', start=10, end=12, text='Old dialogue'),
                        dict(id='after', start=20, end=22, text='Goodbye'),
                        dict(id='last', start=40, end=42, text='Closing')],
            summary='A conversation.', transcriptGenerated=True,
            cues=[dict(id='ad', start=30, end=35, text='She waves.', audio='audio-description/kept.wav',
                       audioText='She waves.', audioDuration=3, origin='manual')],
            exports=['exports/old.mp4'], exportMediaInfo={'exports/old.mp4': {'duration': 60}})

    def rows(self):
        return [dict(id='before', start=6, end=8, text='Hello', speaker='A'),
                dict(id='target', start=10, end=11, text='नमस्ते', speaker='A'),
                dict(start=11.1, end=13, text='Hello दुनिया', speaker='B'),
                dict(id='after', start=20, end=22, text='Goodbye')]

    def analyze(self, p, results=None, draft=None, cfg=None):
        client = Mock()
        with patch.object(e, 'config', return_value=cfg or e.config()), \
             patch.object(e, 'client_and_model', return_value=(client, 'video-model')) as model, \
             patch.object(e.gemini_adapter, 'video_interaction', side_effect=results or [json.dumps({'transcript': self.rows()}, ensure_ascii=False)]) as call, \
             patch.object(e, 'emit'):
            try:
                e.reanalyze_transcript_segment(Path('/tmp'), p, draft or dict(start=10, end=14, text='Manual draft', hint='Hindi and English'))
            finally:
                client.close.assert_called_once()
        return call, model

    def test_multilingual_splitting_context_and_preservation(self):
        p=self.project(); old=copy.deepcopy(p)
        cfg=copy.deepcopy(e.config())
        cfg['prompts']['multilingual_media']={'system_instruction':'SYSTEM MULTILINGUAL', 'user_prompt':'USER MULTILINGUAL'}
        call,model=self.analyze(p,cfg=cfg)
        prompt,system=call.call_args.args[4:6]
        for value in ['USER MULTILINGUAL','Manual draft','Hindi and English','draftTranscript','userHint','She waves.', 'A conversation.', 'Opening', 'original scripts', 'code-switching']:
            self.assertIn(value,prompt)
        self.assertIn('SYSTEM MULTILINGUAL',system)
        model.assert_called_once_with('youtube_transcript')
        self.assertEqual(call.call_args.kwargs['processing'],dict(type='static', start_offset='2s',end_offset='27s',fps=4))
        self.assertEqual(p['cues'],old['cues']);self.assertEqual(p['summary'],old['summary'])
        self.assertEqual(p['transcript'][0],old['transcript'][0]);self.assertEqual(p['transcript'][-1],old['transcript'][-1])
        self.assertEqual(p['transcript'][1],old['transcript'][1])
        self.assertEqual([r['text'] for r in p['transcript'][2:4]],['नमस्ते','Hello दुनिया'])
        self.assertEqual(p['transcript'][3]['speaker'],'B')
        self.assertEqual(p['transcriptUndoStack'],[old['transcript']]);self.assertEqual(p['exports'],[])
        generated=copy.deepcopy(p['transcript']);e.restore_transcript(p)
        self.assertEqual(p['transcript'],old['transcript']);e.restore_transcript(p,redo=True)
        self.assertEqual(p['transcript'],generated);self.assertEqual(p['cues'],old['cues'])

    def test_local_video_reuse_and_audio_model_fallback(self):
        for configured,expected in [('gemini-special-transcribe','youtube_transcript'),('gemini-video','transcript')]:
            p=self.project();p.update(source='video.mp4',sourceType='upload')
            cfg=copy.deepcopy(e.config());cfg['models']['transcript']=configured
            cfg['prompts']['transcript']['system_instruction']='LOCAL TRANSCRIPT SYSTEM'
            with patch.object(e,'reusable_video',return_value=SimpleNamespace(uri='files/reused',mime_type='video/mp4')) as ready:
                call,model=self.analyze(p,cfg=cfg)
            ready.assert_called_once();model.assert_called_once_with(expected)
            self.assertEqual(call.call_args.args[2:4],('files/reused','video/mp4'))
            self.assertIn('LOCAL TRANSCRIPT SYSTEM',call.call_args.args[5])
            self.assertIn('potentially multilingual',call.call_args.args[5])

    def test_initial_transcript_does_not_require_summary(self):
        p=self.project();p.update(transcript=[],summary='',transcriptGenerated=False)
        self.analyze(p,[json.dumps({'transcript':[dict(start=10,end=12,text='नमस्ते hello')]})])
        self.assertTrue(p['transcriptGenerated']);self.assertEqual(len(p['transcript']),1)
        e.restore_transcript(p);self.assertEqual(p['transcript'],[])
        self.assertFalse(p['transcriptGenerated'])

    def test_invalid_proposal_retries_then_commits_once(self):
        p=self.project();bad=self.rows();bad[2]['start']=10.5
        call,_=self.analyze(p,[json.dumps({'transcript':bad}),json.dumps({'transcript':self.rows()})])
        self.assertEqual(call.call_count,2);self.assertIn('rejected',call.call_args.args[4])
        self.assertEqual(len(p['transcriptUndoStack']),1)

    def test_invalid_and_empty_results_preserve_everything(self):
        variants=['bad JSON',json.dumps({'transcript':[]})]
        for patch_row in [dict(start=float('nan')),dict(start=-1),dict(end=61),dict(id='far'),dict(id=['bad']),dict(text=''),dict(speaker=3)]:
            rows=self.rows();rows[1].update(patch_row);variants.append(json.dumps({'transcript':rows}))
        rows=self.rows();rows[2]['id']='target';variants.append(json.dumps({'transcript':rows}))
        for raw in variants:
            with self.subTest(raw=raw):
                p=self.project();old=copy.deepcopy(p)
                with self.assertRaises(ValueError):self.analyze(p,[raw]*3)
                self.assertEqual(p,old)

    def test_ad_conflict_keeps_narration_and_does_not_retime_speech(self):
        p=self.project();p['cues'][0].update(start=12,end=14);old=copy.deepcopy(p)
        with self.assertRaisesRegex(ValueError,'overlaps spoken dialogue'):
            self.analyze(p)
        self.assertEqual(p,old)

    def test_network_error_and_invalid_range_preserve_content(self):
        p=self.project();old=copy.deepcopy(p)
        with self.assertRaises(RuntimeError):self.analyze(p,[RuntimeError('offline')])
        self.assertEqual(p,old)
        with patch.object(e,'client_and_model') as client:
            for start,end in [(2,2),(-1,4),(1,61),(float('nan'),4)]:
                with self.assertRaises(ValueError):e.reanalyze_transcript_segment(Path('/tmp'),p,dict(start=start,end=end))
            client.assert_not_called()

    def test_manual_edits_history_and_conflicting_undo_are_atomic(self):
        p=self.project();old=copy.deepcopy(p['transcript']);edited=copy.deepcopy(old);edited[2]['text']='Edited'
        e.save_segments(p,edited,copy.deepcopy(p['cues']))
        self.assertEqual(p['transcriptUndoStack'],[old])
        p['cues'][0].update(start=10,end=12);before=copy.deepcopy(p)
        with self.assertRaises(ValueError):e.restore_transcript(p)
        self.assertEqual(p,before)

    def test_deleted_transcript_rows_cannot_return_from_history(self):
        p=self.project();e.remember_transcript(p)
        p['transcriptRedoStack']=[copy.deepcopy(p['transcript'])]
        e.save_segments(p,p['transcript'][1:],copy.deepcopy(p['cues']))
        self.assertEqual(p['transcriptUndoStack'],[]);self.assertEqual(p['transcriptRedoStack'],[])
        with self.assertRaises(ValueError):e.restore_transcript(p)

    def test_ad_undo_checks_new_transcript(self):
        p=self.project();p['undoStack']=[[dict(id='old',start=10,end=12,text='Old AD')]];old=copy.deepcopy(p)
        with self.assertRaises(ValueError):parity.execute(SimpleNamespace(command='undo-cues'),Path('/tmp'),p,e)
        self.assertEqual(p,old)

    def test_cli_transcript_history_and_delete(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);p=self.project();p.update(id='test',name='History test',thumbnails=[],sourceType='upload')
            p['transcriptUndoStack']=[[]];p['transcriptRedoStack']=[]
            (root/'audio-description').mkdir();audio=root/'audio-description/kept.wav';audio.write_bytes(b'preserve narration')
            project=root/'project.json';project.write_text(json.dumps(p))
            packaged=os.environ.get('VIDISTUDIO_TEST_ENGINE')
            command=[packaged] if packaged else [sys.executable,str(Path(e.__file__).resolve())]
            for action in ['undo-transcript','redo-transcript']:
                result=subprocess.run(command+[action,'--project',str(root)],capture_output=True,text=True)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                current=json.loads(project.read_text());self.assertEqual(current['cues'],p['cues'])
                self.assertEqual(audio.read_bytes(),b'preserve narration')
            self.assertEqual(current['transcript'],p['transcript'])
            e.delete_generated_components(root,current,['history'])
            self.assertEqual(current['transcriptUndoStack'],[]);self.assertEqual(current['transcriptRedoStack'],[])

if __name__=='__main__':unittest.main()
