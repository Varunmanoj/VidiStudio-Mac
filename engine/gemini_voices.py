"""Gemini narration catalog and provider-specific voice choices."""

import json
from pathlib import Path

import network_activity
import vertex_ai


PREBUILT = frozenset(json.loads(Path(__file__).with_name('ai-defaults.json').read_text(encoding='utf-8'))['geminiPrebuiltVoices'])
LIBRARY_MODELS = ('gemini-3.8-flash-tts', 'gemini-3.8-flash-lite-tts')


def selection(cfg):
    legacy = str(cfg.get('geminiVoice') or '').strip() or 'Kore'
    if cfg.get('aiProvider') == 'vertex':
        key = 'vertexGeminiVoice'
        default = legacy if legacy in PREBUILT else 'Kore'
    else:
        key, default = 'geminiVoice', legacy
    voice = str(cfg.get(key) or '').strip() or default
    return voice, str(cfg.get(key + 'Name') or '').strip() or voice


def speech_voice(cfg, model):
    from google.genai import types

    voice, _ = selection(cfg)
    if voice not in PREBUILT and cfg.get(('vertexGeminiVoice' if cfg.get('aiProvider') == 'vertex' else 'geminiVoice') + 'Name'):
        if model not in LIBRARY_MODELS:
            raise ValueError('Choose a Gemini 3.8 TTS model for this library voice, or select a prebuilt voice.')
        return types.VoiceConfig(voice=voice)
    return types.VoiceConfig(prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=voice))


def synthesis_config(cfg, model):
    from google.genai import types

    voice = speech_voice(cfg, model)
    if voice.voice and cfg.get('aiProvider') != 'vertex':
        # The Developer API accepts this field, but the SDK's Developer API
        # converter omits it. Send the documented REST field in the body.
        return types.GenerateContentConfig(response_modalities=['AUDIO'],
                                           http_options=types.HttpOptions(api_version='v1beta', extra_body={
                                               'generationConfig': {'speechConfig': {'voiceConfig': {'voice': voice.voice}}}
                                           }))
    return types.GenerateContentConfig(response_modalities=['AUDIO'],
                                       speech_config=types.SpeechConfig(voice_config=voice))


def list_catalog(cfg, query, emit):
    from google import genai

    query = query.strip()
    if not query or len(query.encode('utf-8')) > 2048:
        raise ValueError('Enter a voice search of up to 2,048 bytes.')
    if cfg.get('aiProvider') == 'vertex':
        if vertex_ai.express(cfg):
            raise ValueError('Use Google sign-in for the Vertex AI voice library.')
        project = cfg.get('vertexProject', '').strip()
        sdk = genai.Client(vertexai=True, credentials=vertex_ai.credentials(project), project=project, location='global',
                           http_options={'api_version': 'v1beta1', 'timeout': 15000})
    else:
        key = cfg.get('apiKey')
        if not key:
            raise ValueError('Connect Gemini Developer API in Settings > AI.')
        sdk = genai.Client(api_key=key, http_options={'api_version': 'v1beta', 'timeout': 15000})
    with sdk:
        catalog = network_activity.call('gemini', sdk.voices.list, search=query, type_=['prebuilt'], page_size=50, timeout=15)
        voices = {}
        for voice in catalog.voices or []:
            ident = str(voice.id or '').strip()
            if ident and ident not in PREBUILT:
                voices[ident] = dict(id=ident, name=voice.display_name or ident, language=voice.language_code or '',
                                     description=voice.description or '')
        emit('Voice library searched', voices=list(voices.values()), hasMore=bool(catalog.next_page_token))
