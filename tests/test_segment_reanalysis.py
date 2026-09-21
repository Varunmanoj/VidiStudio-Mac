import copy, json, sys, tempfile, time, unittest
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'engine'))
import vidistudio_engine as e
import gemini_adapter as adapter

class ReanalysisTests(unittest.TestCase):
    def project(self):
        return dict(source='',sourceType='youtube',youtubeURL='https://www.youtube.com/watch?v=abcdefghijk',duration=60,
            transcriptGenerated=True,transcript=[dict(start=15,end=18,text='Dialogue')],summary='A person opens a box.',
            cues=[dict(id='far',start=0,end=2,text='Opening',origin='manual',audio='far.wav'),
                  dict(id='before',start=6,end=8,text='A box',origin='manual',audio='before.wav'),
                  dict(id='target',start=10,end=12,text='Opens it',origin='ai',audio='old.wav'),
                  dict(id='after',start=20,end=22,text='Looks inside',origin='ai',audio='after.wav'),
                  dict(id='far-end',start=40,end=42,text='Closing',origin='manual')],exports=['old.mp4'])
    def result(self,overlap=False):
        return json.dumps(dict(audioDescriptions=[dict(id='before',start=6,end=8,text='A box'),
            dict(id='target',start=10,end=16 if overlap else 14,text='She lifts the lid, revealing a red scarf.'),
            dict(id='after',start=20,end=22,text='Looks inside')]))
    def run_analysis(self,p,results):
        client=Mock()
        with tempfile.TemporaryDirectory() as folder, patch.object(e,'client_and_model',return_value=(client,'video-model')), patch.object(adapter,'video_interaction',side_effect=results) as call, patch.object(e,'emit'):
            e.reanalyze_segment(Path(folder),p,dict(id='target',start=10,end=14,
                text='More detail about the box',hint='Look closely at the person lifting the lid'))
        return call,client
    def test_context_clipping_reconciliation_and_undo(self):
        p=self.project();old=copy.deepcopy(p['cues'])
        call,client=self.run_analysis(p,[self.result()])
        args=call.call_args
        self.assertEqual(args.kwargs['processing'],dict(type='static',start_offset='2s',end_offset='27s',fps=4))
        for text in ('Opening','A person opens a box.','Dialogue','More detail about the box',
                     'Look closely at the person lifting the lid','draftDescription','userHint','dialogueFreeRanges'):
            self.assertIn(text,args.args[4])
        self.assertEqual(p['undoStack'],[old]);self.assertEqual(p['cues'][0],old[0]);self.assertEqual(p['cues'][-1],old[-1])
        self.assertEqual(p['cues'][1],old[1]);self.assertNotIn('audio',p['cues'][2]);self.assertEqual(p['exports'],[])
        self.assertEqual(p['cues'][2]['end'],14);client.close.assert_called_once()
    def test_overlap_corrected_before_commit(self):
        p=self.project();call,_=self.run_analysis(p,[self.result(True),self.result()])
        self.assertEqual(call.call_count,2);self.assertIn('rejected',call.call_args.args[4]);self.assertEqual(len(p['undoStack']),1)
    def test_exhausted_proposal_preserves_all_existing_content(self):
        p=self.project();old=copy.deepcopy(p)
        with self.assertRaisesRegex(ValueError,'preserved'):self.run_analysis(p,[self.result(True)]*3)
        self.assertEqual(p,old)
    def test_outside_window_and_frozen_id_rejected(self):
        for row in [dict(start=45,end=49,text='Outside'),dict(id='far',start=10,end=14,text='Overwrite')]:
            p=self.project();old=copy.deepcopy(p)
            with self.assertRaises(ValueError):self.run_analysis(p,[json.dumps(dict(audioDescriptions=[row]))]*3)
            self.assertEqual(p,old)
    def test_malformed_empty_and_nonfinite_results_preserve_content(self):
        for raw in ['not JSON','{"audioDescriptions":[]}','{"audioDescriptions":[{"start":NaN,"end":14,"text":"Bad"}]}']:
            p=self.project();old=copy.deepcopy(p)
            with self.assertRaises(ValueError):self.run_analysis(p,[raw]*3)
            self.assertEqual(p,old)
    def test_range_validation_precedes_network(self):
        p=self.project()
        with patch.object(e,'client_and_model') as client:
            for start,end in [(5,5),(-1,4),(10,61),(float('nan'),14)]:
                with self.assertRaises(ValueError): e.reanalyze_segment(Path('/tmp'),p,dict(start=start,end=end))
            client.assert_not_called()
    def test_network_error_preserves_content(self):
        p=self.project();old=copy.deepcopy(p)
        with self.assertRaises(RuntimeError):self.run_analysis(p,[RuntimeError('offline')])
        self.assertEqual(p,old)
    def test_local_video_uses_reusable_file(self):
        p=self.project();p['source']='source/video.mp4';p['sourceType']='upload'
        f=SimpleNamespace(uri='remote',mime_type='video/mp4')
        with patch.object(e,'reusable_video',return_value=f) as ready:
            call,_=self.run_analysis(p,[self.result()])
        ready.assert_called_once();self.assertEqual(call.call_args.args[2:4],('remote','video/mp4'))

class AvailabilityTests(unittest.TestCase):
    def uploaded(self,state='ACTIVE'):
        return SimpleNamespace(name='files/video',uri='remote',mime_type='video/mp4',state=SimpleNamespace(name=state),expiration_time=datetime.fromtimestamp(time.time()+1000,tz=timezone.utc))
    def setup_source(self,root):
        (root/'video.mp4').write_bytes(b'video')
        return dict(source='video.mp4',cues=[])
    def test_upload_reuse_and_persisted_server_expiry(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(e,'emit'):
            root=Path(folder);p=self.setup_source(root);client=Mock();f=self.uploaded();client.files.get.return_value=f
            with patch.object(adapter,'ready_file',return_value=f) as upload:
                e.reusable_video(root,p,client);e.reusable_video(root,p,client)
            upload.assert_called_once();client.files.delete.assert_not_called()
            self.assertEqual(p['geminiVideo']['expiresAt'],f.expiration_time.timestamp())
            self.assertEqual(json.loads((root/'project.json').read_text())['geminiVideo']['state'],'ACTIVE')
    def test_upload_emits_live_preparation_and_ready_after_save(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);p=self.setup_source(root);client=Mock();f=self.uploaded();events=[]
            def capture(message, **values):
                if values.get('videoPreparation') == 'ready':
                    self.assertEqual(json.loads((root/'project.json').read_text())['geminiVideo']['state'],'ACTIVE')
                events.append((message,values.get('videoPreparation')))
            def upload(_client,_source,callback):
                callback('Preparing the video for analysis')
                return f
            with patch.object(e,'emit',side_effect=capture),patch.object(adapter,'ready_file',side_effect=upload):
                e.reusable_video(root,p,client)
            self.assertEqual([state for _,state in events],['uploading','processing','ready'])
    def test_missing_and_expired_files_reupload(self):
        for missing in [True,False]:
            with tempfile.TemporaryDirectory() as folder,patch.object(e,'emit'):
                root=Path(folder);p=self.setup_source(root);client=Mock();f=self.uploaded()
                with patch.object(adapter,'ready_file',return_value=f) as upload:
                    e.reusable_video(root,p,client)
                    if missing:
                        error=RuntimeError('missing');error.code=404;client.files.get.side_effect=error
                    else:
                        expired=self.uploaded();expired.expiration_time=datetime.fromtimestamp(time.time()-1,tz=timezone.utc);client.files.get.return_value=expired
                    e.reusable_video(root,p,client)
                    self.assertEqual(upload.call_count,2)
    def test_unknown_network_state_does_not_duplicate_upload(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(e,'emit'):
            root=Path(folder);p=self.setup_source(root);client=Mock()
            with patch.object(adapter,'ready_file',return_value=self.uploaded()) as upload:
                e.reusable_video(root,p,client)
                last_checked=p['geminiVideo']['checkedAt']
                client.files.get.side_effect=RuntimeError('offline')
                with self.assertRaises(RuntimeError):e.reusable_video(root,p,client)
                upload.assert_called_once()
                self.assertEqual(p['geminiVideo']['state'],'ACTIVE')
                self.assertEqual(p['geminiVideo']['checkedAt'],last_checked)
                self.assertEqual(json.loads((root/'project.json').read_text())['geminiVideo']['state'],'ACTIVE')
    def test_forbidden_refresh_keeps_last_confirmed_status(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(e,'emit'):
            root=Path(folder);p=self.setup_source(root);client=Mock()
            with patch.object(adapter,'ready_file',return_value=self.uploaded()):
                e.reusable_video(root,p,client)
            denied=RuntimeError('forbidden');denied.code=403;client.files.get.side_effect=denied
            with self.assertRaises(RuntimeError):e.remote_video_status(root,p,client)
            self.assertEqual(p['geminiVideo']['state'],'ACTIVE')
            self.assertEqual(json.loads((root/'project.json').read_text())['geminiVideo']['state'],'ACTIVE')
    def test_processing_file_is_not_uploaded_again(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(e,'emit'):
            root=Path(folder);p=self.setup_source(root);client=Mock()
            with patch.object(adapter,'ready_file',return_value=self.uploaded()) as upload:
                e.reusable_video(root,p,client);client.files.get.return_value=self.uploaded('PROCESSING')
                with self.assertRaisesRegex(ValueError,'still being prepared'):e.reusable_video(root,p,client)
                upload.assert_called_once();self.assertEqual(p['geminiVideo']['state'],'PROCESSING')
    def test_source_change_uploads_new_video(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(e,'emit'):
            root=Path(folder);p=self.setup_source(root);client=Mock()
            with patch.object(adapter,'ready_file',return_value=self.uploaded()) as upload:
                e.reusable_video(root,p,client);(root/'video.mp4').write_bytes(b'new video');e.reusable_video(root,p,client)
                self.assertEqual(upload.call_count,2);client.files.get.assert_not_called()
    def test_adapter_sends_explicit_clipping_configuration(self):
        client=Mock();client.interactions.create.return_value={'output_text':'ok'}
        processing=dict(type='static',start_offset='10s',end_offset='20s',fps=4)
        adapter.video_interaction(client,'model','uri','video/mp4','prompt',processing=processing)
        media=client.interactions.create.call_args.kwargs['input'][0]
        self.assertEqual(media['processing'],processing)
        from google.genai._gaos.types.interactions.videocontent import VideoContent
        self.assertEqual(VideoContent.model_validate(media).processing.start_offset,'10s')

if __name__=='__main__':unittest.main()
