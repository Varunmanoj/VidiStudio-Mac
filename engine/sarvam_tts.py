"""Sarvam synchronous REST synthesis. Credentials are supplied only by the native host."""
import base64
import binascii
import json
import math
import os
import re
import tempfile
import time
from pathlib import Path

import network_activity

DEFAULT_VOICES = {'bulbul:v4-flash':'shubh_enhi_ads', 'bulbul:v3':'shubh', 'bulbul:v2':'anushka'}
MODEL_REFERENCE = 'https://docs.sarvam.ai/api-reference/text-to-speech/convert.md'

class SarvamError(ValueError):
    def __init__(self, message, kind='service'):
        super().__init__(message)
        self.kind = kind

def catalog():
    return json.loads(Path(__file__).with_name('sarvam-voices.json').read_text(encoding='utf-8'))

def model_cache_path():
    base = Path(os.environ.get('APPDATA', Path.home())) if os.name == 'nt' else Path.home() / 'Library/Application Support'
    return base / 'VidiStudio/sarvam-models.json'

def model_label(identifier):
    family, _, version = identifier.partition(':')
    suffix = ' '.join(word if re.fullmatch(r'v\d+(?:\.\d+)?', word) else word.title() for word in version.replace('_', '-').split('-'))
    return family.replace('_', ' ').title() + (' ' + suffix if suffix else '')

def bundled_models():
    return list(dict.fromkeys(voice['model'] for voice in catalog()['voices']))

def parse_models(markdown):
    # Read only the model parameter's declared values, never examples or arbitrary prose.
    field = re.search(r'^- `model` .*?(?=^- `|^## |\Z)', markdown, re.M | re.S)
    allowed = re.search(r'Allowed values:\s*([^\n]+)', field.group(0)) if field else None
    values = re.findall(r'`([A-Za-z0-9][A-Za-z0-9:._-]{0,79})`', allowed.group(1)) if allowed else []
    if not values: raise ValueError('The published model list could not be read.')
    intro = markdown.split('## Authentication', 1)[0]
    preferred = re.findall(r'^- \*\*([^*]+)\*\*:', intro, re.M)
    return list(dict.fromkeys([value for value in preferred if value in values] + values))

def cached_models(path=None):
    try:
        saved = json.loads((path or model_cache_path()).read_text(encoding='utf-8'))['models']
        if saved and all(isinstance(value, str) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9:._-]{0,79}', value) for value in saved): return saved
    except (OSError, ValueError, KeyError, TypeError): pass
    return bundled_models()

def refresh_models(emit, path=None, fetch=None):
    path = path or model_cache_path()
    cached = False
    try:
        if fetch is None:
            import httpx
            with httpx.Client(timeout=15, follow_redirects=False) as client:
                response = client.get(MODEL_REFERENCE)
                response.raise_for_status()
                if len(response.content) > 1_000_000: raise ValueError('Model reference is too large.')
                markdown = response.text
        else: markdown = fetch(MODEL_REFERENCE)
        models = parse_models(markdown)
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile('w', encoding='utf-8', dir=path.parent, delete=False) as stream:
            json.dump({'source':MODEL_REFERENCE, 'models':models}, stream)
            temporary = Path(stream.name)
        try: temporary.replace(path)
        finally: temporary.unlink(missing_ok=True)
    except Exception as exc:
        if type(exc).__name__ in ('ProcessingCancelled', 'CancelledError'): raise
        models = cached_models(path); cached = True
    emit('Using saved models' if cached else 'Models updated', sarvamModels=[{'id':value,'label':model_label(value)} for value in models], sarvamModelsCached=cached)

def check_key(emit, client_factory=None):
    key = os.environ.get('VIDISTUDIO_SARVAM_API_KEY', '').strip()
    if not key:
        emit('Enter a Sarvam API key.', narrationProvider='sarvam', sarvamKeyStatus='missing', sarvamKeyMessage='No API key entered')
        return
    if client_factory is None:
        from sarvamai import SarvamAI
        client_factory = SarvamAI
    client = client_factory(api_subscription_key=key, timeout=15)
    try:
        # Read-only authenticated metadata: do not synthesize speech or expose IDs.
        with network_activity.activity('sarvam'):
            client.pronunciation_dictionary.list(request_options={'timeout_in_seconds':15, 'max_retries':0})
        emit('Sarvam API key verified', narrationProvider='sarvam', sarvamKeyStatus='verified', sarvamKeyMessage='API key verified')
    except Exception as exc:
        if type(exc).__name__ in ('ProcessingCancelled', 'CancelledError'): raise
        kind = error_kind(exc)
        messages = {'invalid-key':'API key rejected. Enter a valid Sarvam key.',
                    'permissions':'Key check is not permitted for this account.',
                    'rate-limit':'Key check temporarily unavailable. Try again later.',
                    'quota':'Check your Sarvam account credits and try again.',
                    'connectivity':'Could not check the key. Check your connection.'}
        message = messages.get(kind, 'Could not check the key. Try again later.')
        emit(message, narrationProvider='sarvam', sarvamKeyStatus='invalid' if kind == 'invalid-key' else 'unavailable', sarvamKeyMessage=message)
    finally:
        close = getattr(client, 'close', None)
        if close: close()

def preferences(cfg):
    saved = cfg.get('sarvamSpeech') or {}
    model = saved.get('model', bundled_models()[0])
    if model not in cached_models(): raise SarvamError('Refresh Models in Settings → Narration and choose an available Sarvam model.', 'validation')
    return model, (saved.get('profiles') or {}).get(model, {})

def parameters(cfg):
    model, saved = preferences(cfg)
    language = saved.get('language', 'en-IN')
    known_model = model in bundled_models()
    if not known_model:
        if language not in catalog()['languages']: raise SarvamError('Choose a supported narration language.', 'validation')
        # Newly advertised models use provider defaults; do not assume compatibility
        # with another model's speakers or optional voice controls.
        return dict(model=model, language_code=language)
    speaker = saved.get('voice', DEFAULT_VOICES.get(model, ''))
    voice = next((v for v in catalog()['voices'] if v['model'] == model and v['id'] == speaker), None)
    if voice is None or language not in voice['languages']:
        raise SarvamError('Choose a Sarvam voice matching the model and language in Settings.', 'validation')
    def number(key, default, low, high):
        try: value = float(saved.get(key, default))
        except (TypeError, ValueError): raise SarvamError('Check the Sarvam voice controls in Settings.', 'validation')
        if not math.isfinite(value) or not low <= value <= high:
            raise SarvamError('Check the Sarvam voice controls in Settings.', 'validation')
        return value
    rates = [8000, 16000, 22050, 24000] + ([] if model == 'bulbul:v2' else [32000, 44100, 48000])
    rate = saved.get('sampleRate', 22050)
    codec = saved.get('codec', 'wav')
    if rate not in rates or codec not in ('wav', 'mp3', 'aac', 'flac'):
        raise SarvamError('Choose a supported Sarvam sample rate and audio format.', 'validation')
    result = dict(model=model, language_code=language, speaker=speaker, speech_sample_rate=rate,
                  output_audio_codec=codec, pace=number('pace', 1, .3 if model == 'bulbul:v2' else .5, 3 if model == 'bulbul:v2' else 2))
    if model == 'bulbul:v2':
        result.update(pitch=number('pitch', 0, -.75, .75), loudness=number('loudness', 1, .3, 3),
                      enable_preprocessing=bool(saved.get('preprocessing', False)))
    else:
        result['temperature'] = number('temperature', .6, .01, 1)
    return result

def signature(cfg):
    params = parameters(cfg)
    if 'speaker' not in params: return 'sarvam|Default voice|' + params['model'] + '|' + params['language_code'] + '|provider-defaults'
    fields = ['sarvam', params['speaker'], params['model'], params['language_code'], f"{params['pace']:.3f}", str(params['speech_sample_rate']), params['output_audio_codec']]
    if params['model'] == 'bulbul:v2': fields += [f"{params['pitch']:.3f}", f"{params['loudness']:.3f}", str(int(params['enable_preprocessing']))]
    else: fields += [f"{params['temperature']:.3f}"]
    return '|'.join(fields)

def chunks(text, limit):
    """Keep every character while preferring sentence and whitespace boundaries."""
    while len(text) > limit:
        part = text[:limit]
        boundaries = list(re.finditer(r'[.!?।]\s+|\s+', part))
        end = boundaries[-1].end() if boundaries else limit
        yield text[:end]
        text = text[end:]
    if text: yield text

def error_kind(exc):
    body = getattr(exc, 'body', None)
    if isinstance(body, dict):
        detail = body.get('error', body)
        code = detail.get('code', '') if isinstance(detail, dict) else ''
    else: code = ''
    if code in ('invalid_api_key_error', 'authentication_error'): return 'invalid-key'
    if code == 'insufficient_quota_error': return 'quota'
    if code in ('invalid_request_error', 'unprocessable_entity_error'): return 'validation'
    if getattr(exc, 'status_code', None) == 403: return 'permissions'
    if getattr(exc, 'status_code', None) == 429: return 'rate-limit'
    return 'connectivity' if network_activity.transport_failure(exc) else 'service'

def synthesize(output, text, cfg, run, ffmpeg, emit, client_factory=None):
    key = os.environ.get('VIDISTUDIO_SARVAM_API_KEY', '').strip()
    if not key: raise SarvamError('Enter your Sarvam API key in Settings → Narration.', 'missing-key')
    params = parameters(cfg)
    if not text or not text.strip(): raise SarvamError('Narration requires text.', 'validation')
    if client_factory is None:
        from sarvamai import SarvamAI
        client_factory = SarvamAI
    # Disable SDK retries so the bounded policy below is the only retry layer.
    client = client_factory(api_subscription_key=key, timeout=120)
    try:
        with tempfile.TemporaryDirectory(prefix='vidistudio-sarvam-') as temporary:
            folder = Path(temporary)
            wavs = []
            for index, part in enumerate(chunks(text, 1500 if params['model'] == 'bulbul:v2' else 2500)):
                response = None
                for attempt in range(3):
                    try:
                        with network_activity.activity('sarvam'):
                            response = client.text_to_speech.convert(text=part, **params,
                                request_options={'timeout_in_seconds':120, 'max_retries':0})
                        break
                    except Exception as exc:
                        if type(exc).__name__ in ("ProcessingCancelled", "CancelledError"): raise
                        kind = error_kind(exc)
                        status = getattr(exc, 'status_code', 0) or 0
                        if attempt < 2 and kind not in ('invalid-key', 'quota', 'permissions', 'validation') and (status == 429 or 500 <= status < 600):
                            headers = getattr(exc, 'headers', {}) or {}
                            try: delay = min(30, max(0, float(headers.get('retry-after', 2 ** attempt))))
                            except (TypeError, ValueError): delay = 2 ** attempt
                            time.sleep(delay)
                            continue
                        messages = {'invalid-key':'Sarvam rejected the API key. Replace it in Settings → Narration.',
                                    'quota':'Sarvam credits or quota are exhausted. Check your Sarvam account.',
                                    'permissions':'Your Sarvam key does not have access to this request.',
                                    'rate-limit':'Sarvam is rate limiting requests. Try again later.',
                                    'validation':'Sarvam rejected the selected voice settings. Check Settings → Narration.',
                                    'connectivity':'Cannot reach Sarvam. Check your connection and try again.'}
                        emit(messages.get(kind, 'Sarvam could not generate narration. Try again later.'),
                             narrationProvider='sarvam', sarvamKeyStatus='invalid' if kind == 'invalid-key' else 'unverified', sarvamFailureKind=kind)
                        raise SarvamError(messages.get(kind, 'Sarvam could not generate narration. Try again later.'), kind) from None
                try:
                    encoded = response.audios
                    if not encoded or not all(isinstance(a, str) and a for a in encoded): raise ValueError()
                    data = base64.b64decode(''.join(encoded), validate=True)
                    if not data: raise ValueError()
                except (ValueError, TypeError, AttributeError, binascii.Error):
                    raise SarvamError('Sarvam returned invalid or empty audio.') from None
                source = folder / f'{index}.{params.get("output_audio_codec", "wav")}'
                source.write_bytes(data)
                wav = folder / f'{index}-decoded.wav'
                run([ffmpeg, '-y', '-v', 'error', '-i', source, '-ac', '1', '-ar', str(params.get('speech_sample_rate', 22050)), '-c:a', 'pcm_s16le', wav])
                wavs.append(wav)
            listing = folder / 'parts.txt'
            listing.write_text(''.join(f"file '{p.name}'\n" for p in wavs))
            finished = folder / ('finished' + output.suffix)
            run([ffmpeg, '-y', '-v', 'error', '-f', 'concat', '-safe', '0', '-i', listing, finished])
            output.parent.mkdir(parents=True, exist_ok=True)
            # Output is committed only after every REST chunk and media decode succeeds.
            import shutil
            shutil.copyfile(finished, output)
            emit('Sarvam narration generated', narrationProvider='sarvam', sarvamKeyStatus='verified')
    finally:
        close = getattr(client, 'close', None)
        if close: close()
