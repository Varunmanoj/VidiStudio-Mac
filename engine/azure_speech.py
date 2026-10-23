"""Azure AI Speech neural voices through the official REST API.

The subscription key is provided per process in VIDISTUDIO_AZURE_SPEECH_KEY by the
desktop app, which keeps it in the OS credential store. It is never read from or
written to config.json, argv, logs or project files.
"""
import json
import os
import re
import ssl
import urllib.error
import urllib.request
from xml.sax.saxutils import escape, quoteattr

DEFAULT_REGION = 'eastus'
DEFAULT_VOICE = 'en-US-AvaMultilingualNeural'
KEY_ENVIRONMENT = 'VIDISTUDIO_AZURE_SPEECH_KEY'
OUTPUT_FORMAT = 'riff-24khz-16bit-mono-pcm'
_REGION = re.compile(r'^[a-z0-9]{2,40}$')
_VOICE = re.compile(r'^[A-Za-z]{2,3}(-[A-Za-z0-9]+)+(:[A-Za-z0-9]+)?$')


def key():
    return (os.environ.get(KEY_ENVIRONMENT) or '').strip()


def region(cfg):
    value = str(cfg.get('azureSpeechRegion', '') or DEFAULT_REGION).strip().lower().replace(' ', '')
    if not _REGION.match(value):
        raise ValueError('Enter a valid Azure Speech region in Settings, such as eastus or westeurope.')
    return value


def voice(cfg):
    return str(cfg.get('azureVoice', '') or DEFAULT_VOICE).strip() or DEFAULT_VOICE


def redact(message):
    secret = key()
    message = str(message)
    return message.replace(secret, '[redacted]') if secret else message


def _context():
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except Exception:
        return ssl.create_default_context()


def _request(url, data=None, headers=None, timeout=60):
    secret = key()
    if not secret:
        raise ValueError('Add an Azure Speech key in Settings → Narration to use online voices.')
    request = urllib.request.Request(url, data=data, method='POST' if data is not None else 'GET',
                                     headers={'Ocp-Apim-Subscription-Key': secret, 'User-Agent': 'VidiStudio', **(headers or {})})
    try:
        with urllib.request.urlopen(request, timeout=timeout, context=_context()) as response:
            return response.read()
    except urllib.error.HTTPError as exc:
        if exc.code in (401, 403):
            raise ValueError('Azure rejected the speech key. Check the key and region in Settings → Narration.') from None
        if exc.code == 429:
            raise ValueError('Azure Speech is rate limiting requests. Wait a moment, then try again.') from None
        if exc.code == 400:
            raise ValueError('Azure Speech could not use the selected voice. Refresh Azure voices and choose another voice.') from None
        raise ValueError(f'Azure Speech returned HTTP {exc.code}.') from None
    except urllib.error.URLError as exc:
        raise ValueError('Could not reach Azure Speech. Check the internet connection and region. ' + redact(exc.reason)) from None


def list_voices(cfg):
    payload = json.loads(_request(f'https://{region(cfg)}.tts.speech.microsoft.com/cognitiveservices/voices/list').decode('utf-8'))
    voices = []
    for item in payload if isinstance(payload, list) else []:
        short_name = str(item.get('ShortName') or '')
        if not short_name or str(item.get('VoiceType') or 'Neural') != 'Neural':
            continue
        voices.append({
            'id': short_name,
            'name': str(item.get('DisplayName') or item.get('LocalName') or short_name),
            'language': str(item.get('Locale') or ''),
            'languageName': str(item.get('LocaleName') or item.get('Locale') or ''),
            'gender': str(item.get('Gender') or ''),
        })
    voices.sort(key=lambda v: (v['languageName'].lower(), v['name'].lower()))
    if not voices:
        raise ValueError('Azure Speech returned no neural voices for this region.')
    return voices


def ssml(text, voice_name, rate=1.0):
    if not _VOICE.match(voice_name):
        raise ValueError('Choose a valid Azure voice in Settings → Narration.')
    language = '-'.join(voice_name.split('-')[:2])
    percent = round((min(max(float(rate), 0.5), 2.0) - 1.0) * 100)
    return (f"<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang={quoteattr(language)}>"
            f"<voice name={quoteattr(voice_name)}><prosody rate='{percent:+d}%'>{escape(text)}</prosody></voice></speak>")


def synthesize(cfg, text, output, rate=1.0):
    """Write a 24 kHz 16-bit mono WAV file for the selected Azure neural voice."""
    if not str(text or '').strip():
        raise ValueError('Enter text to speak.')
    audio = _request(f'https://{region(cfg)}.tts.speech.microsoft.com/cognitiveservices/v1',
                     data=ssml(text, voice(cfg), rate).encode('utf-8'),
                     headers={'Content-Type': 'application/ssml+xml', 'X-Microsoft-OutputFormat': OUTPUT_FORMAT},
                     timeout=120)
    if audio[:4] != b'RIFF' or audio[8:12] != b'WAVE':
        raise ValueError('Azure Speech returned no audio for this text.')
    with open(output, 'wb') as stream:
        stream.write(audio)
