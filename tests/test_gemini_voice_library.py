import json
import unittest
from unittest.mock import patch

import httpx
from google import genai
from google.oauth2.credentials import Credentials

from test_engine import engine

voices = engine.gemini_voices


class GeminiVoiceLibraryTests(unittest.TestCase):
    def test_remembers_each_connection_and_uses_legacy_prebuilt_selection(self):
        self.assertEqual(voices.selection({'aiProvider': 'vertex', 'geminiVoice': 'Puck'}), ('Puck', 'Puck'))
        config = {'geminiVoice': 'library-developer', 'geminiVoiceName': 'Developer voice',
                  'vertexGeminiVoice': 'library-vertex', 'vertexGeminiVoiceName': 'Vertex voice'}
        self.assertEqual(voices.selection(config), ('library-developer', 'Developer voice'))
        self.assertEqual(voices.selection(dict(config, aiProvider='vertex')), ('library-vertex', 'Vertex voice'))
        del config['vertexGeminiVoice'], config['vertexGeminiVoiceName']
        self.assertEqual(voices.selection(dict(config, aiProvider='vertex')), ('Kore', 'Kore'))

    def test_new_library_voice_requires_gemini_38_and_uses_the_voice_id_field(self):
        cfg = {'aiProvider': 'vertex', 'vertexGeminiVoice': 'catalog-id', 'vertexGeminiVoiceName': 'Narrator'}
        with self.assertRaisesRegex(ValueError, 'Gemini 3.8 TTS'):
            voices.speech_voice(cfg, 'gemini-3.1-flash-tts-preview')
        self.assertEqual(voices.speech_voice(cfg, 'gemini-3.8-flash-tts').voice, 'catalog-id')
        self.assertEqual(voices.speech_voice({'geminiVoice': 'Achernar'}, 'gemini-3.8-flash-tts')
                         .prebuilt_voice_config.voice_name, 'Achernar')

    def test_search_uses_provider_specific_endpoint_and_prebuilt_catalog_filter(self):
        factory = genai.Client
        requests = []

        def respond(request):
            requests.append(request)
            return httpx.Response(200, json={'voices': [
                {'id': 'Kore', 'display_name': 'Kore'},
                {'id': 'catalog-id', 'display_name': 'Narrator', 'language_code': 'en-GB', 'description': 'Warm'},
            ], 'next_page_token': 'another-page'})

        def connect(**kwargs):
            options = dict(kwargs.pop('http_options'))
            options['httpx_client'] = httpx.Client(transport=httpx.MockTransport(respond))
            return factory(**kwargs, http_options=options)

        for cfg, path in [
            ({'apiKey': 'sample-key'}, '/v1beta/voices'),
            ({'aiProvider': 'vertex', 'vertexProject': 'test-project'},
             '/v1beta1/projects/test-project/locations/global/voices'),
        ]:
            results = []
            with self.subTest(path=path), patch.object(genai, 'Client', side_effect=connect), \
                    patch.object(voices.vertex_ai, 'credentials', return_value=Credentials(token='sample-token')):
                voices.list_catalog(cfg, ' warm ', lambda _, **data: results.append(data))
            self.assertEqual(requests[-1].url.path, path)
            self.assertEqual(requests[-1].url.params.get('search'), 'warm')
            self.assertEqual(requests[-1].url.params.get_list('type'), ['prebuilt'])
            self.assertEqual(results, [{'voices': [
                {'id': 'catalog-id', 'name': 'Narrator', 'language': 'en-GB', 'description': 'Warm'},
            ], 'hasMore': True}])

    def test_express_does_not_query_the_library(self):
        with patch.object(genai, 'Client') as connect, self.assertRaisesRegex(ValueError, 'Google sign-in'):
            voices.list_catalog({'aiProvider': 'vertex', 'vertexAuth': 'express'}, 'voice', None)
        connect.assert_not_called()

    def test_library_voice_id_reaches_the_synthesis_request_on_both_endpoints(self):
        requests = []

        def respond(request):
            requests.append(json.loads(request.content))
            return httpx.Response(200, json={'candidates': [{'content': {'parts': [
                {'inlineData': {'mimeType': 'audio/wav', 'data': 'UklGRg=='}}
            ]}}]})

        for route, cfg in [
            ({'api_key': 'test'}, {'geminiVoice': 'dev-id', 'geminiVoiceName': 'Narrator'}),
            ({'vertexai': True, 'project': 'test-project', 'location': 'global',
              'credentials': Credentials(token='test')},
             {'aiProvider': 'vertex', 'vertexGeminiVoice': 'vertex-id', 'vertexGeminiVoiceName': 'Narrator'}),
        ]:
            model = 'gemini-3.8-flash-tts'
            options = {'api_version': 'v1beta1' if route.get('vertexai') else 'v1beta',
                       'httpx_client': httpx.Client(transport=httpx.MockTransport(respond))}
            with genai.Client(**route, http_options=options) as client:
                client.models.generate_content(model=model, contents='A bird lands.', config=voices.synthesis_config(cfg, model))
            self.assertEqual(requests[-1]['generationConfig']['speechConfig']['voiceConfig'],
                             {'voice': voices.selection(cfg)[0]})
