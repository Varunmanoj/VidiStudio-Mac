import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
import wave
import httpx
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'engine'))
import elevenlabs_tts as e

KEY='isolated-elevenlabs-test-key'
MODEL={'model_id':'eleven_multilingual_v2','name':'Multilingual','can_do_text_to_speech':True,'can_use_style':True,'can_use_speaker_boost':True,'maximum_text_length_per_request':30,'languages':[{'language_id':'en','name':'English'}]}
VOICE={'voice_id':'voice-a','name':'Sample','preview_url':'https://storage.googleapis.com/eleven-public-prod/sample.mp3','labels':{'language':'en','accent':'british'},'category':'premade','verified_languages':[{'language':'en','model_id':'eleven_multilingual_v2','preview_url':'https://storage.googleapis.com/eleven-public-prod/en.mp3'}]}

def audio():
    stream=io.BytesIO()
    with wave.open(stream,'wb') as wav:
        wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(24000);wav.writeframes(b'\0\0'*2400)
    return stream.getvalue()

class ElevenLabsTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.folder=Path(self.temp.name)
        self.patcher=patch.object(e,'folder',return_value=self.folder);self.patcher.start();self.addCleanup(self.patcher.stop)
        self.keypatch=patch.dict(os.environ,{e.KEY_ENV:KEY});self.keypatch.start();self.addCleanup(self.keypatch.stop)
        self.requests=[]
    def respond(self,request):
        self.requests.append(request)
        path=request.url.path
        if path=='/v1/user':return httpx.Response(200,json={'user_id':'private-user','xi_api_key_preview':'private-key-hint'})
        if path=='/v1/user/subscription':return httpx.Response(200,json={'tier':'future_tier','status':'active','character_count':1200,'character_limit':1000,'voice_slots_used':2,'voice_limit':10,'open_invoices':[{'private':'billing'}]})
        if path=='/v1/voices/accents':return httpx.Response(200,json={'accents':[{'accent':'british','name':'British','language':'en','code':'en-british'},{'accent':'future_accent','name':'Future Accent','language':'xx','code':'xx-future'}]})
        if path=='/v1/models':return httpx.Response(200,json=[MODEL,dict(MODEL,model_id='future_100',name='Future'),{'model_id':'non-tts'}])
        if path in ('/v2/voices','/v1/shared-voices'):return httpx.Response(200,json={'voices':[VOICE,dict(VOICE,voice_id='different',public_owner_id='owner')],'has_more':True,'next_page_token':'next'})
        if path.startswith('/v1/voices/add/'):return httpx.Response(200,json={'voice_id':'account-copy'})
        if path.startswith('/v1/text-to-speech/'):return httpx.Response(200,content=audio(),headers={'content-type':'audio/wav'})
        if request.url.host=='storage.googleapis.com':return httpx.Response(200,content=audio())
        return httpx.Response(404)
    def api(self,respond=None):return e.API(KEY,httpx.MockTransport(respond or self.respond))
    def profile(self,**extra):return {'elevenlabsSpeech':dict(model=MODEL['model_id'],voice='voice-a',language='en',format='mp3_44100_128',controls=['stability','similarity','speed','style','speakerBoost'],**extra)}
    def seed(self):
        with self.api() as api:e.models(api);e.voices(api,{})
    def test_validation_and_plan_are_read_only_and_minimized(self):
        with self.api() as api:result=e.check(api)
        self.assertEqual(result['keyStatus'],'verified');self.assertEqual(result['plan']['tier'],'future_tier')
        self.assertNotIn('open_invoices',result['plan']);self.assertTrue(all(r.method=='GET' for r in self.requests))
        self.assertNotIn('private-user',str(result));self.assertNotIn('private-key-hint',str(result))
    def test_missing_user_permission_falls_back_to_account_voice_read(self):
        def respond(r):return httpx.Response(403,json={'detail':{'status':'missing_permissions'}}) if r.url.path=='/v1/user' else self.respond(r)
        with self.api(respond) as api:self.assertEqual(e.check(api)['keyStatus'],'verified')
        self.assertTrue(any(r.url.path=='/v2/voices' for r in self.requests))
    def test_subscription_permission_failure_does_not_invalidate_key(self):
        def respond(r):return httpx.Response(403,json={'detail':{'status':'missing_permissions'}}) if r.url.path.endswith('/subscription') else self.respond(r)
        with self.api(respond) as api:result=e.check(api)
        self.assertEqual(result['keyStatus'],'verified');self.assertEqual(result['planMessage'],'Plan details unavailable');self.assertNotIn('plan',result)
    def test_plan_cache_is_scoped_to_key_and_not_used_for_permission_denial(self):
        with self.api() as api:e.check(api)
        def respond(r):return httpx.Response(500) if r.url.path.endswith('/subscription') else self.respond(r)
        with patch.object(e.time,'sleep'),self.api(respond) as api:self.assertTrue(e.check(api)['planCached'])
        self.assertEqual(e.read_cache('other-key','plan'),(None,None))
        e.forget(KEY);self.assertEqual(e.read_cache(KEY,'plan'),(None,None))
    def test_deleted_key_cannot_repopulate_its_catalog_cache(self):
        e.write_cache(KEY,'plan',{'tier':'starter'});e.forget(KEY)
        e.write_cache(KEY,'plan',{'tier':'stale'})
        self.assertEqual(e.read_cache(KEY,'plan'),(None,None))
        with self.api() as api:self.assertEqual(e.check(api)['keyStatus'],'verified')
        self.assertIsNotNone(e.read_cache(KEY,'plan')[0])
    def test_invalid_key_is_distinct_from_permissions_and_quota(self):
        for code,kind in [('invalid_api_key','invalid'),('missing_permissions','permissions'),('quota_exceeded','quota')]:
            with self.subTest(code=code):self.assertEqual(e.failure(httpx.Response(401,json={'detail':{'status':code}})).kind,kind)
    def test_dynamic_models_and_unknown_controls(self):
        with self.api() as api:result=e.models(api)
        self.assertEqual([m['id'] for m in result['models']],[MODEL['model_id'],'future_100'])
        self.assertEqual(result['models'][1]['controls'],[])
        cfg=self.profile();cfg['elevenlabsSpeech']['model']='future_100'
        params,_=e.parameters(cfg,KEY);self.assertNotIn('voice_settings',params)
    def test_account_sort_and_cursor_and_all_voice_ids_are_preserved(self):
        with self.api() as api:result=e.voices(api,{'sort':'descending','cursor':'next','search':'sample','language':'en','accent':'british'})
        self.assertEqual(len(result['voices']),2);self.assertTrue(result['hasMore']);self.assertEqual(result['cursor'],'next')
        self.assertEqual(self.requests[-1].url.params['sort_direction'],'desc');self.assertEqual(self.requests[-1].url.params['next_page_token'],'next')
    def test_public_library_filters_and_global_sorts(self):
        with self.api() as api:e.voices(api,{'source':'library','page':2,'sort':'trending','style':'warm','useCase':'narrative_story','gender':'female'})
        request=self.requests[-1];self.assertEqual(request.url.path,'/v1/shared-voices');self.assertEqual(request.url.params['sort'],'trending');self.assertEqual(request.url.params['page'],'2');self.assertEqual(request.url.params['descriptives'],'warm')
    def test_dynamic_accent_dropdown_values_come_from_provider(self):
        with self.api() as api:result=e.models(api)
        self.assertIn({'id':'future_accent','name':'Future Accent'},result['filterOptions']['accent'])
        self.assertTrue(any(r.url.path=='/v1/voices/accents' for r in self.requests))
    def test_metadata_dropdown_choices_accumulate_without_losing_other_values(self):
        previous=e.filter_options([{'accent':'british','style':'calm','useCase':'narrative_story'}])
        updated=e.filter_options([{'accent':'indian','style':'warm','useCase':'future_use'}],previous)
        self.assertEqual([v['id'] for v in updated['style']],['calm','warm'])
        self.assertIn({'id':'future_use','name':'Future Use'},updated['useCase'])
        self.assertEqual(len(updated['accent']),2)
    def test_unavailable_accent_endpoint_uses_saved_choices_without_blocking_models(self):
        with self.api() as api:e.models(api)
        def respond(r):return httpx.Response(404) if r.url.path=='/v1/voices/accents' else self.respond(r)
        with self.api(respond) as api:result=e.models(api)
        self.assertEqual(result['filterOptions']['accent'][0]['name'],'British')
        self.assertTrue(result['models'])
    def test_add_is_explicit_and_uses_returned_account_id(self):
        self.seed()
        with self.api() as api:result=e.add(api,{'voice':'different'})
        self.assertEqual(result['addedVoice']['id'],'account-copy')
        self.assertEqual(self.requests[-1].url.path,'/v1/voices/add/owner/different')
        self.assertEqual(e.selected_voice(KEY,'account-copy')['id'],'account-copy')
    def test_demo_download_does_not_authenticate_cdn_or_synthesize(self):
        self.seed();self.requests.clear()
        with self.api() as api:
            first=e.demo(api,{'voice':'voice-a','model':MODEL['model_id'],'language':'en'})
            second=e.demo(api,{'voice':'voice-a','model':MODEL['model_id'],'language':'en'})
        self.assertEqual(first,second);self.assertEqual(len(self.requests),1);r=self.requests[0]
        self.assertEqual(r.url.host,'storage.googleapis.com');self.assertNotIn('xi-api-key',r.headers);self.assertTrue(r.url.path.endswith('en.mp3'))
    def test_explicit_language_demo_does_not_fall_back_to_a_different_variant(self):
        raw=dict(VOICE,verified_languages=[dict(VOICE['verified_languages'][0],locale='en-GB')])
        e.write_cache(KEY,'voice-index',{'voice-a':e.voice_info(raw)})
        with self.api() as api:
            with self.assertRaises(e.ElevenLabsError):e.demo(api,{'voice':'voice-a','model':MODEL['model_id'],'language':'en','locale':'en-US'})
            self.assertEqual(self.requests,[])
            e.demo(api,{'voice':'voice-a','model':MODEL['model_id'],'language':'en','locale':'en-GB'})
        self.assertEqual(len(self.requests),1);self.assertTrue(self.requests[0].url.path.endswith('en.mp3'))
    def test_missing_or_untrusted_demo_never_generates(self):
        for url in ['', 'http://127.0.0.1/private','https://attacker.example/demo']:
            voice=e.voice_info(dict(VOICE,preview_url=url,verified_languages=[]));e.write_cache(KEY,'voice-index',{'voice-a':voice});self.requests.clear()
            with self.api() as api,self.assertRaises(e.ElevenLabsError):e.demo(api,{'voice':'voice-a'})
            self.assertEqual(self.requests,[])
    def test_no_secrets_in_events_or_caches(self):
        emit=Mock();e.execute('check',{},emit,httpx.MockTransport(self.respond))
        self.assertNotIn(KEY,str(emit.call_args));self.assertNotIn(KEY,''.join(p.read_text(errors='ignore') for p in self.folder.rglob('*.json')))
    def test_capabilities_omit_unsupported_controls_and_enforcement(self):
        self.seed();params,_=e.parameters(self.profile(),KEY);self.assertNotIn('language_code',params);self.assertEqual(params['voice_settings']['speed'],1)
        with self.assertRaises(e.ElevenLabsError):e.parameters(self.profile(speed=10),KEY)
        with self.assertRaises(e.ElevenLabsError):e.parameters(self.profile(stability=float('nan')),KEY)
    def test_v3_and_v4_controls_are_not_sarvam_controls(self):
        models=e.model_options([dict(MODEL,model_id='eleven_v3'),dict(MODEL,model_id='eleven_v4')]);self.assertEqual(models[0]['controls'],['stabilityMode']);self.assertNotIn('speed',models[1]['controls'])
    def test_speed_is_sent_only_for_supported_models_and_future_explicit_capabilities(self):
        for identifier in ['eleven_multilingual_v2','eleven_turbo_v2_5','eleven_flash_v2_5']:
            row=e.model_options([dict(MODEL,model_id=identifier)])[0];self.assertIn('speed',row['controls'])
            e.write_cache(KEY,'models',[row]);cfg=self.profile(speed=1.1);cfg['elevenlabsSpeech']['model']=identifier
            self.assertEqual(e.parameters(cfg,KEY)[0]['voice_settings']['speed'],1.1)
        for identifier in ['eleven_v3','eleven_v4','eleven_v4_turbo']:
            row=e.model_options([dict(MODEL,model_id=identifier)])[0];self.assertNotIn('speed',row['controls'])
        self.assertIn('speed',e.model_options([dict(MODEL,model_id='future_speed_model',can_use_speed=True)])[0]['controls'])
        self.assertNotIn('speed',e.model_options([dict(MODEL,can_use_speed=False)])[0]['controls'])
    def test_signature_uses_effective_controls_only(self):
        cfg=self.profile();base=e.signature(cfg);cfg['elevenlabsSpeech']['pitch']=.5;self.assertEqual(e.signature(cfg),base)
        cfg['elevenlabsSpeech']['speed']=1.1;self.assertNotEqual(e.signature(cfg),base)
    @unittest.skipUnless(shutil.which('ffmpeg'),'requires audio decoding')
    def test_generation_chunks_and_atomic_audio(self):
        self.seed();text='Narration sentence. '*12;out=self.folder/'final.mp3'
        def run(args):subprocess.run(args,check=True,capture_output=True)
        e.synthesize(out,text,self.profile(),run,shutil.which('ffmpeg'),Mock(),httpx.MockTransport(self.respond))
        self.assertGreater(out.stat().st_size,100)
        requests=[r for r in self.requests if r.method=='POST'];self.assertGreater(len(requests),1)
        self.assertEqual(''.join(json.loads(r.content)['text'] for r in requests),text)
        self.assertTrue(all(r.url.path=='/v1/text-to-speech/voice-a' for r in requests))
    def test_synthesis_timeout_is_never_retried_or_replaces_old_audio(self):
        self.seed();out=self.folder/'old.mp3';out.write_bytes(b'previous-audio');calls=[]
        def fail(r):calls.append(r);raise httpx.ReadTimeout('secret transport message',request=r)
        with self.assertRaises(e.ElevenLabsError):e.synthesize(out,'Hello',self.profile(),Mock(),'ffmpeg',Mock(),httpx.MockTransport(fail))
        self.assertEqual(len(calls),1);self.assertEqual(out.read_bytes(),b'previous-audio')
    def test_api_redirects_do_not_forward_credentials(self):
        calls=[]
        def redirect(r):calls.append(r);return httpx.Response(307,headers={'location':'https://attacker.example'})
        with self.api(redirect) as api:
            with self.assertRaises(e.ElevenLabsError):api.json('GET','/v1/user')
        self.assertEqual(len(calls),1)
    def test_empty_key_never_constructs_network_client(self):
        with patch.object(e.httpx,'Client') as client,self.assertRaises(e.ElevenLabsError):e.API('')
        client.assert_not_called()

if __name__=='__main__':unittest.main()
