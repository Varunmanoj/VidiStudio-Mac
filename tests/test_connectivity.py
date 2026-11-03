import io
import json
import os
import socket
import subprocess
import shutil
import tempfile
import sys
from pathlib import Path
import unittest
from contextlib import redirect_stdout
from types import SimpleNamespace
from unittest.mock import patch, Mock
from urllib.error import HTTPError, URLError
from test_engine import engine
import network_activity as network

class NetworkBehavior(unittest.TestCase):
    def test_transport_errors_are_distinct_from_credentials_and_quota(self):
        for error in [ConnectionError('lost'), TimeoutError('slow'), socket.gaierror('dns'), URLError('offline')]:
            with self.subTest(error=error):
                self.assertEqual(network.error_metadata(error), {'failureKind':'connectivity'})
                self.assertFalse(network.credential_rejected(error))
                self.assertFalse(engine.is_retryable_ai_error(error))
        for error in [HTTPError('https://example.test',403,'Forbidden',{},io.BytesIO()), ValueError('429 quota'), ValueError('API_KEY_INVALID')]:
            self.assertFalse(network.transport_failure(error))
        self.assertTrue(network.credential_rejected(ValueError('API_KEY_INVALID')))

    def test_wrapped_transport_error_is_preserved(self):
        try:
            try: raise ConnectionError('lost')
            except ConnectionError as inner: raise ValueError('YouTube unavailable') from inner
        except ValueError as error:
            self.assertTrue(network.transport_failure(error))

    def test_nested_network_stages_end_before_local_work(self):
        output=io.StringIO()
        with patch.dict(os.environ,{'VIDISTUDIO_NETWORK_EVENTS':'1'}),redirect_stdout(output):
            with network.activity('youtube'):
                with network.activity('youtube'): pass
            print(json.dumps({'local':True}))
        events=[json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual([e['networkActive'] for e in events if 'networkActive' in e],[True,False])
        self.assertTrue(events[-1]['local'])

    def test_lazy_catalog_requests_are_observed_during_iteration(self):
        output=io.StringIO()
        def pages():
            raise ConnectionError('lost')
            yield None
        client=network.ClientProxy(SimpleNamespace(models=SimpleNamespace(list=pages)))
        with patch.dict(os.environ,{'VIDISTUDIO_NETWORK_EVENTS':'1'}),redirect_stdout(output):
            with self.assertRaises(ConnectionError): list(client.models.list())
        events=[json.loads(line) for line in output.getvalue().splitlines()]
        self.assertFalse(events[-1]['networkActive'])
        self.assertEqual(sum(e['networkActive'] for e in events),2)

    def test_transport_failure_stops_narration_batch_and_preserves_audio(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'audio-description').mkdir()
            old=root/'audio-description/old.mp3';old.write_bytes(b'existing audio')
            project={'duration':10,'transcript':[],'narrationEngine':'gemini','narrationVoice':'Kore','cues':[
                {'id':'a','start':0,'end':4,'text':'First','audio':'audio-description/old.mp3'},
                {'id':'b','start':5,'end':9,'text':'Second'}]}
            cfg={'ttsMode':'gemini','geminiVoice':'Kore','models':{'tts_audio':'test-model'}}
            with patch.object(engine,'config',return_value=cfg),patch.object(engine,'gemini_speech',side_effect=ConnectionError('lost')) as speech,patch.object(engine,'save'):
                with self.assertRaises(ConnectionError): engine.synthesize(root,project)
            self.assertEqual(speech.call_count,1)
            self.assertEqual(old.read_bytes(),b'existing audio')
            self.assertEqual(project['cues'][0]['audio'],'audio-description/old.mp3')

    def test_local_soundtrack_inspection_skips_optional_online_metadata_offline(self):
        import audio_sources
        with tempfile.TemporaryDirectory() as directory:
            source=Path(directory)/'original.wav';source.write_bytes(b'local audio')
            args=SimpleNamespace(input=source)
            project={'youtubeURL':'https://youtu.be/4fYlQtcm6qY','duration':0}
            core=SimpleNamespace(emit=lambda *a,**k:None)
            with patch.dict(os.environ,{'VIDISTUDIO_YOUTUBE_AVAILABLE':'0'}),patch.object(audio_sources.youtube_audio,'video_duration') as online,patch.object(audio_sources.import_assets,'inspect_audio',return_value={'duration':10}):
                result=audio_sources.inspect(args,project,core)
            online.assert_not_called()
            self.assertEqual(result['status'],'unverified')

    def test_check_failure_preserves_saved_verification(self):
        if not hasattr(engine,'check_api_key'): self.skipTest('macOS uses list_models directly')
        client=Mock();client.models.list.side_effect=ConnectionError('lost')
        with patch.object(engine,'config',return_value={'apiKey':'test'}),patch.object(engine,'gemini_client',return_value=client),patch.object(engine,'atomic_json') as write:
            with self.assertRaises(ConnectionError): engine.check_api_key()
            write.assert_not_called()

if __name__=='__main__': unittest.main()

class NativeConnectivity(unittest.TestCase):
    @unittest.skipUnless(sys.platform == 'darwin', 'requires macOS Swift SDK')
    def test_mac_requirements_and_connection_transitions(self):
        root=Path(__file__).resolve().parents[1]
        mac=root if (root/'VidiStudio').exists() else root.parent/'VidiStudio Mac'
        with tempfile.TemporaryDirectory() as directory:
            source=Path(directory)/'ConnectivityService.swift'
            source.write_text((mac/'VidiStudio/ConnectivityService.swift').read_text().replace('static let shared = ConnectivityService()', 'static let shared = ConnectivityService(monitoring: false)'))
            executable=Path(directory)/'connectivity-harness'
            compiled=subprocess.run(['xcrun','swiftc','-parse-as-library',str(source),str(mac/'VidiStudio/OnlineRequirements.swift'),str(mac/'tests/connectivity_harness.swift'),'-module-cache-path',str(Path(directory)/'modules'),'-o',str(executable)],capture_output=True,text=True)
            self.assertEqual(compiled.returncode,0,compiled.stdout+compiled.stderr)
            completed=subprocess.run([str(executable)],check=True,capture_output=True,text=True,timeout=10)
            self.assertIn('PASS: online requirements',completed.stdout)

class WindowsPolicy(unittest.TestCase):
    @unittest.skipUnless(shutil.which('dotnet'), 'requires .NET SDK')
    def test_real_windows_action_requirements(self):
        from xml.sax.saxutils import escape
        root=Path(__file__).resolve().parents[1]
        windows=root if (root/'Vidi Studio Windows').exists() else root.parent/'Vidi-Studio-Windows'
        version=subprocess.check_output(['dotnet','--version'],text=True).split('.')[0]
        with tempfile.TemporaryDirectory() as directory:
            folder=Path(directory)
            project=folder/'Policy.csproj'
            sources=[windows/'Vidi Studio Windows/Services/OnlineRequirements.cs',windows/'tests/connectivity_policy_harness.cs']
            project.write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net'+version+'.0</TargetFramework><Nullable>enable</Nullable></PropertyGroup><ItemGroup>'+''.join('<Compile Include="'+escape(str(p))+'"/>' for p in sources)+'</ItemGroup></Project>')
            result=subprocess.run(['dotnet','run','--project',str(project),'--verbosity','quiet'],capture_output=True,text=True,timeout=60)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn('PASS: Windows online requirements',result.stdout)
