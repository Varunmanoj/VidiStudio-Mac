"""ElevenLabs REST narration and read-only catalogs. Native hosts own credentials."""
import hashlib
import json
import math
import os
from pathlib import Path
import tempfile
import time
from urllib.parse import urlparse, quote

import httpx
import network_activity

ORIGIN = 'https://api.elevenlabs.io'
KEY_ENV = 'VIDISTUDIO_ELEVENLABS_API_KEY'
FORMATS = [('mp3_44100_128', 'MP3 · 44.1 kHz · 128 kbps'),
           ('mp3_44100_192', 'MP3 · 44.1 kHz · 192 kbps (Creator+)'),
           ('mp3_22050_32', 'MP3 · 22.05 kHz · 32 kbps'),
           ('pcm_24000', 'PCM · 24 kHz'), ('wav_44100', 'WAV · 44.1 kHz (Pro+)')]

class ElevenLabsError(ValueError):
    def __init__(self, message, kind='service'):
        super().__init__(message)
        self.kind = kind


def folder():
    base = Path(os.environ.get('APPDATA', Path.home())) if os.name == 'nt' else Path.home() / 'Library/Application Support'
    return base / 'VidiStudio/ElevenLabs'


def credential_id(key):
    return hashlib.sha256(key.encode()).hexdigest()


def cache_file(key, name):
    return folder() / credential_id(key) / (name + '.json')


def read_cache(key, name):
    try:
        value = json.loads(cache_file(key, name).read_text())
        return value['data'], value['updated']
    except (OSError, ValueError, KeyError, TypeError):
        return None, None


def write_cache(key, name, value):
    path = cache_file(key, name)
    if (folder() / (credential_id(key) + '.retired')).exists(): return
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile('w', encoding='utf-8', dir=path.parent, delete=False) as stream:
        json.dump({'updated': time.time(), 'data': value}, stream, ensure_ascii=False)
        temporary = Path(stream.name)
    try:
        if os.name != 'nt': temporary.chmod(0o600)
        temporary.replace(path)
    finally: temporary.unlink(missing_ok=True)


def forget(key):
    import shutil
    if key:
        folder().mkdir(parents=True, exist_ok=True)
        (folder() / (credential_id(key) + '.retired')).touch()
        shutil.rmtree(folder() / credential_id(key), ignore_errors=True)


def failure(response):
    try:
        detail = response.json().get('detail', {})
        code = detail.get('status', '') if isinstance(detail, dict) else ''
    except (ValueError, AttributeError): code = ''
    if code in ('invalid_api_key', 'authentication_error', 'api_key_expired', 'api_key_disabled'):
        return ElevenLabsError('ElevenLabs rejected this API key.', 'invalid')
    if code in ('quota_exceeded', 'insufficient_credits'):
        return ElevenLabsError('ElevenLabs allowance is exhausted. Check your account.', 'quota')
    if code in ('voice_limit_reached','voice_add_edit_limit_reached'): return ElevenLabsError('Your ElevenLabs account has no saved-voice slots available.', 'quota')
    if code == 'missing_permissions' or response.status_code == 403:
        return ElevenLabsError('Your ElevenLabs key does not have permission for this action.', 'permissions')
    if response.status_code == 401: return ElevenLabsError('ElevenLabs rejected this API key.', 'invalid')
    if response.status_code == 429: return ElevenLabsError('ElevenLabs is busy. Try again later.', 'rate-limit')
    if response.status_code in (400, 404, 422):
        return ElevenLabsError('The selected voice, model or settings are unavailable. Refresh ElevenLabs in Settings.', 'validation')
    return ElevenLabsError('ElevenLabs could not complete this request. Try again later.')


class API:
    def __init__(self, key, transport=None):
        if not key.strip(): raise ElevenLabsError('Enter your ElevenLabs API key in Settings → Narration.', 'missing')
        self.key = key.strip()
        self.client = httpx.Client(timeout=httpx.Timeout(120, connect=15), follow_redirects=False, transport=transport)

    def __enter__(self): return self
    def __exit__(self, *args): self.client.close()

    def request(self, method, path, **kwargs):
        # Do not attach credentials to demo/CDN requests or follow API redirects.
        for attempt in range(3 if method == 'GET' else 1):
            try:
                with network_activity.activity('elevenlabs'):
                    response = self.client.request(method, ORIGIN + path, headers={'xi-api-key': self.key}, timeout=15 if method == 'GET' else 120, **kwargs)
            except httpx.TransportError:
                raise ElevenLabsError('Could not reach ElevenLabs. Check your connection.', 'connectivity') from None
            if method == 'GET' and (response.status_code == 429 or response.status_code >= 500) and attempt < 2:
                try: delay = min(10, max(0, float(response.headers.get('retry-after', 2 ** attempt))))
                except ValueError: delay = 2 ** attempt
                time.sleep(delay)
                continue
            if response.is_error: raise failure(response)
            if len(response.content) > 100_000_000: raise ElevenLabsError('The ElevenLabs response is too large.')
            return response

    def json(self, method, path, **kwargs):
        try: return self.request(method, path, **kwargs).json()
        except ValueError as exc:
            if isinstance(exc, ElevenLabsError): raise
            raise ElevenLabsError('ElevenLabs returned an unreadable response.') from None


def model_options(rows):
    result = []
    for row in rows:
        if not row.get('can_do_text_to_speech') or not row.get('model_id'): continue
        identifier = row['model_id']
        # Catalog discovery is dynamic. Optional settings for unrecognized families are omitted.
        controls = []
        if identifier in ('eleven_multilingual_v2', 'eleven_turbo_v2', 'eleven_turbo_v2_5', 'eleven_flash_v2', 'eleven_flash_v2_5', 'eleven_monolingual_v1', 'eleven_multilingual_v1'):
            controls = ['stability', 'similarity', 'speed']
            if row.get('can_use_style'): controls.append('style')
            if row.get('can_use_speaker_boost'): controls.append('speakerBoost')
        elif identifier.startswith('eleven_v3'): controls = ['stabilityMode']
        elif identifier in ('eleven_v4', 'eleven_v4_turbo'): controls = ['stability', 'similarity', 'cloneStrength']
        if row.get('can_use_speed') is True and 'speed' not in controls: controls.append('speed')
        if row.get('can_use_speed') is False: controls = [control for control in controls if control != 'speed']
        result.append(dict(id=identifier, name=row.get('name') or identifier, controls=controls,
                           languages=[dict(id=v['language_id'], name=v.get('name') or v['language_id']) for v in row.get('languages', []) if v.get('language_id')],
                           limit=row.get('maximum_text_length_per_request') or 2500,
                           proVoices=bool(row.get('serves_pro_voices')), alpha=bool(row.get('requires_alpha_access')),
                           languageEnforcement=identifier != 'eleven_multilingual_v2'))
    return result


def plan_info(row):
    # Explicit allowlist: never emit user IDs, key previews, invoices or payment information.
    return {key: row[key] for key in ('tier', 'status', 'character_count', 'character_limit',
            'next_character_count_reset_unix', 'voice_slots_used', 'voice_limit', 'billing_period') if key in row}


def voice_info(row):
    labels = row.get('labels') or {}
    sharing = row.get('sharing') or {}
    def label(key): return str(row.get(key) or labels.get(key) or '')
    variants = [dict(language=v.get('language') or '', model=v.get('model_id') or '',
                     accent=v.get('accent') or '', locale=v.get('locale') or '', preview=v.get('preview_url') or '')
                for v in row.get('verified_languages') or []]
    return dict(id=row['voice_id'], name=row.get('name') or 'Unnamed voice', description=row.get('description') or '',
                owner=row.get('public_owner_id') or sharing.get('public_owner_id') or '',
                original=sharing.get('original_voice_id') or row['voice_id'], category=row.get('category') or '',
                language=label('language'), accent=label('accent'), gender=label('gender'), age=label('age'),
                style=label('descriptive') or labels.get('description') or '', useCase=label('use_case'),
                preview=row.get('preview_url') or '', variants=variants,
                tuning=(row.get('fine_tuning') or {}).get('state') or {},
                freeAllowed=row.get('free_users_allowed', sharing.get('free_users_allowed')),
                rate=row.get('rate', sharing.get('rate')))


def check(api):
    (folder() / (credential_id(api.key) + '.retired')).unlink(missing_ok=True)
    result = dict(keyStatus='verified', message='API key verified', planMessage='')
    try:
        api.json('GET', '/v1/user')
    except ElevenLabsError as exc:
        if exc.kind != 'permissions': raise
        # Restricted user_read is not an invalid key. Verify with authenticated account voices.
        api.json('GET', '/v2/voices', params={'page_size': 1, 'include_total_count': 'false'})
    try:
        plan = plan_info(api.json('GET', '/v1/user/subscription'))
        write_cache(api.key, 'plan', plan)
        result.update(plan=plan, planCached=False)
    except ElevenLabsError as exc:
        if exc.kind == 'invalid': raise
        cached, updated = read_cache(api.key, 'plan')
        if cached is not None and exc.kind != 'permissions': result.update(plan=cached, planCached=True)
        result['planMessage'] = 'Plan details unavailable' if not result.get('planCached') else 'Out of date'
    return result


def filter_options(rows, previous=None):
    result = {field: {item['id']: item['name'] for item in (previous or {}).get(field, [])} for field in ('accent', 'useCase', 'style')}
    for row in rows:
        for field in result:
            value = row.get(field) or ''
            if value: result[field][value] = value.replace('_', ' ').title()
    return {field: [dict(id=key, name=name) for key, name in sorted(values.items(), key=lambda item: item[1].casefold())] for field, values in result.items()}


def accents(api):
    try:
        rows = api.json('GET', '/v1/voices/accents').get('accents', [])
        values = {row['accent']: row.get('name') or row['accent'].replace('_', ' ').title() for row in rows if row.get('accent')}
        options = dict(accent=[dict(id=key, name=name) for key, name in sorted(values.items(), key=lambda item: item[1].casefold())])
        write_cache(api.key, 'accents', options)
        return options
    except ElevenLabsError as exc:
        if exc.kind == 'invalid': raise
        saved, _ = read_cache(api.key, 'accents')
        return saved or {}


def models(api):
    try:
        rows = model_options(api.json('GET', '/v1/models'))
        if not rows: raise ElevenLabsError('No text-to-speech models are available.')
        write_cache(api.key, 'models', rows)
        return dict(models=rows, modelsCached=False, formats=[dict(id=i, name=n) for i, n in FORMATS], filterOptions=accents(api))
    except ElevenLabsError as exc:
        if exc.kind == 'invalid': raise
        rows, _ = read_cache(api.key, 'models')
        if rows: return dict(models=rows, modelsCached=True, formats=[dict(id=i, name=n) for i, n in FORMATS], filterOptions=read_cache(api.key, 'accents')[0] or {}, message='Using saved models')
        raise


def voices(api, request):
    library = request.get('source') == 'library'
    params = {'page_size': 100}
    mapping = {'search': 'search', 'gender': 'gender', 'age': 'age', 'accent': 'accent', 'category': 'category',
               'useCase': 'use_cases', 'style': 'descriptives'}
    for field, param in mapping.items():
        if request.get(field) and request[field] != 'all' and (field != 'style' or library): params[param] = request[field]
    if request.get('language') and request['language'] != 'auto': params['language'] = request['language']
    if library:
        params.update(page=max(0, int(request.get('page', 0))), sort=request.get('sort') if request.get('sort') in ('created_date', 'trending', 'usage_character_count_1y', 'cloned_by_count') else 'trending',
                      include_custom_rates='true', include_live_moderated='true')
        endpoint = '/v1/shared-voices'
    else:
        sort = request.get('sort', 'name')
        params.update(sort='created_at_unix' if sort == 'newest' else 'name', sort_direction='desc' if sort in ('descending', 'newest') else 'asc', include_total_count='false')
        if request.get('cursor'): params['next_page_token'] = request['cursor']
        endpoint = '/v2/voices'
    cache_name = 'voices-' + hashlib.sha256(json.dumps(request, sort_keys=True).encode()).hexdigest()
    try:
        response = api.json('GET', endpoint, params=params)
        result = dict(voices=[voice_info(row) for row in response.get('voices', []) if row.get('voice_id')],
                      hasMore=bool(response.get('has_more')), cursor=response.get('next_page_token') or '', page=params.get('page', 0), voicesCached=False)
        previous, _ = read_cache(api.key, 'filters-' + ('library' if library else 'account'))
        result['filterOptions'] = filter_options(result['voices'], previous)
        write_cache(api.key, 'filters-' + ('library' if library else 'account'), result['filterOptions'])
        write_cache(api.key, cache_name, result)
        # ID index supports validation and demos without trusting arbitrary file paths from UI.
        index, _ = read_cache(api.key, 'voice-index'); index = index or {}
        for row in result['voices']: index[row['id']] = row
        write_cache(api.key, 'voice-index', index)
        return result
    except ElevenLabsError as exc:
        if exc.kind == 'invalid': raise
        saved, _ = read_cache(api.key, cache_name)
        if saved: return dict(saved, voicesCached=True, hasMore=False, message='Using saved voices')
        raise


def add(api, request):
    voice = selected_voice(api.key, request.get('voice', ''))
    if not voice['owner']: raise ElevenLabsError('This voice cannot be added to the account.', 'validation')
    response = api.json('POST', '/v1/voices/add/' + quote(voice['owner'], safe='') + '/' + quote(voice['original'], safe=''), json={'new_name': voice['name']})
    identifier = response.get('voice_id')
    if not identifier: raise ElevenLabsError('The voice could not be added. Refresh My Voices before trying again.')
    # Response may map a library ID to a different account-owned ID.
    saved = dict(voice, id=identifier)
    index, _ = read_cache(api.key, 'voice-index'); index = index or {}; index[identifier] = saved
    write_cache(api.key, 'voice-index', index)
    return dict(addedVoice=saved, message='Voice added')


def selected_voice(key, identifier):
    index, _ = read_cache(key, 'voice-index')
    if not index or identifier not in index: raise ElevenLabsError('Refresh voices and select an available ElevenLabs voice.', 'validation')
    return index[identifier]


def demo(api, request):
    voice = selected_voice(api.key, request.get('voice', ''))
    variant = next((v for v in voice['variants'] if v['language'] == request.get('language') and v['model'] == request.get('model') and (not request.get('locale') or v['locale'] == request['locale']) and v['preview']), None)
    if request.get('locale') and not variant: raise ElevenLabsError('Sample unavailable.', 'validation')
    url = variant['preview'] if variant else voice['preview'] or next((v['preview'] for v in voice['variants'] if v['preview']), '')
    if not url: raise ElevenLabsError('Sample unavailable.', 'validation')
    parsed = urlparse(url)
    # Provider previews are HTTPS cloud-storage recordings. No API key goes to the CDN.
    if parsed.scheme != 'https' or parsed.username or parsed.password or not parsed.hostname or not (parsed.hostname in ('storage.googleapis.com', 'api.elevenlabs.io') or parsed.hostname.endswith('.elevenlabs.io')):
        raise ElevenLabsError('This demo address is unavailable.', 'validation')
    path = folder() / credential_id(api.key) / 'demos' / (hashlib.sha256(url.encode()).hexdigest() + '.mp3')
    if not path.exists():
        try:
            with network_activity.activity('elevenlabs'), api.client.stream('GET', url) as response:
                response.raise_for_status()
                path.parent.mkdir(parents=True, exist_ok=True)
                with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as out:
                    temporary = Path(out.name); size = 0
                    try:
                        for part in response.iter_bytes():
                            size += len(part)
                            if size > 20_000_000: raise ElevenLabsError('This demo is too large.')
                            out.write(part)
                    except BaseException:
                        temporary.unlink(missing_ok=True); raise
                if size < 20: temporary.unlink(missing_ok=True); raise ElevenLabsError('Sample unavailable.')
                if (folder() / (credential_id(api.key) + '.retired')).exists():
                    temporary.unlink(missing_ok=True)
                    raise ElevenLabsError('This demo request was cancelled.')
                temporary.replace(path)
        except httpx.HTTPError: raise ElevenLabsError('Could not download this demo. Try again later.') from None
    return dict(demoPath=str(path), message='Demo ready')


def execute(action, request, emit, transport=None):
    key = os.environ.get(KEY_ENV, '').strip()
    if action == 'forget': forget(key); emit('ElevenLabs cache cleared', elevenlabs={}); return
    try:
        with API(key, transport) as api:
            result = {'check': lambda: check(api), 'models': lambda: models(api), 'voices': lambda: voices(api, request),
                      'add': lambda: add(api, request), 'demo': lambda: demo(api, request)}[action]()
        emit(result.get('message', 'ElevenLabs updated'), elevenlabs=result)
    except ElevenLabsError as exc:
        emit(str(exc), elevenlabs=dict(error=str(exc), kind=exc.kind, keyStatus='invalid' if exc.kind == 'invalid' else 'missing' if exc.kind == 'missing' else 'unavailable'))


def preferences(cfg):
    saved = cfg.get('elevenlabsSpeech') or {}
    return saved.get('model', ''), saved


def parameters(cfg, key=None):
    model_id, p = preferences(cfg)
    key = key if key is not None else os.environ.get(KEY_ENV, '')
    rows, _ = read_cache(key, 'models')
    model = next((m for m in rows or [] if m['id'] == model_id), None)
    if not model: raise ElevenLabsError('Refresh models and choose an ElevenLabs model in Settings.', 'validation')
    if not p.get('voice'): raise ElevenLabsError('Choose an ElevenLabs voice in Settings.', 'validation')
    result = dict(model_id=model_id)
    language = p.get('language', 'auto')
    if language != 'auto':
        if language not in [v['id'] for v in model['languages']]: raise ElevenLabsError('Choose a language supported by this model.', 'validation')
        if model['languageEnforcement']: result['language_code'] = language
    controls = model['controls']
    voice_settings = {}
    for field, wire, initial, low, high in [('stability', 'stability', .5, 0, 1), ('stabilityMode', 'stability', .5, 0, 1),
            ('similarity', 'similarity_boost', .75, 0, 1), ('style', 'style', 0, 0, 1), ('speed', 'speed', 1, .7, 1.2), ('cloneStrength', 'clone_strength', 0, 0, 1)]:
        if field not in controls: continue
        if field == 'cloneStrength':
            voice = selected_voice(key, p['voice'])
            if voice['category'] != 'professional' or voice['tuning'].get(model_id) != 'fine_tuned': continue
        try: number = float(p.get(field, initial))
        except (TypeError, ValueError): raise ElevenLabsError('Check the ElevenLabs voice controls.', 'validation')
        if not math.isfinite(number) or not low <= number <= high or (field == 'stabilityMode' and number not in (0, .5, 1)):
            raise ElevenLabsError('Check the ElevenLabs voice controls.', 'validation')
        voice_settings[wire] = number
    if 'speakerBoost' in controls: voice_settings['use_speaker_boost'] = bool(p.get('speakerBoost', True))
    if voice_settings: result['voice_settings'] = voice_settings
    return result, model


def signature(cfg):
    _, p = preferences(cfg)
    fields = ['elevenlabs', p.get('voice',''), p.get('model',''), p.get('language','auto'), p.get('format','mp3_44100_128')]
    defaults = dict(stability=.5, stabilityMode=.5, similarity=.75, style=0, speed=1, cloneStrength=0)
    for name in sorted(p.get('controls') or []):
        if name == 'speakerBoost': fields.append(name + '=' + ('1' if p.get(name,True) else '0'))
        elif name in defaults: fields.append(name + '=' + format(float(p.get(name,defaults[name])), '.3f'))
    return '|'.join(fields)



def _synthesize(output, text, cfg, run, ffmpeg, emit, transport=None):
    from sarvam_tts import chunks
    key = os.environ.get(KEY_ENV, '')
    if not key.strip(): raise ElevenLabsError('Enter your ElevenLabs API key in Settings → Narration.', 'missing')
    params, model = parameters(cfg, key)
    _, saved = preferences(cfg)
    fmt = saved.get('format', 'mp3_44100_128')
    if fmt not in dict(FORMATS): raise ElevenLabsError('Choose a supported ElevenLabs audio format.', 'validation')
    if not text.strip(): raise ElevenLabsError('Narration requires text.', 'validation')
    with API(key, transport) as api, tempfile.TemporaryDirectory(prefix='vidistudio-elevenlabs-') as temp:
        paths = []
        for index, part in enumerate(chunks(text, max(1, min(int(model['limit']), 40000)))):
            response = api.request('POST', '/v1/text-to-speech/' + quote(saved['voice'], safe=''), params={'output_format': fmt}, json=dict(params, text=part))
            extension = '.pcm' if fmt.startswith('pcm_') else '.wav' if fmt.startswith('wav_') else '.mp3'
            raw = Path(temp) / (str(index) + extension); raw.write_bytes(response.content)
            wav = Path(temp) / (str(index) + '.wav')
            extra = ['-f', 's16le', '-ar', fmt.split('_')[1], '-ac', '1'] if extension == '.pcm' else []
            run([ffmpeg, '-y', *extra, '-i', str(raw), '-ar', '44100', '-ac', '1', str(wav)])
            paths.append(wav)
        listing = Path(temp) / 'concat.txt'; listing.write_text(''.join("file '" + p.as_posix() + "'\n" for p in paths))
        final = Path(temp) / 'narration.mp3'
        run([ffmpeg, '-y', '-f', 'concat', '-safe', '0', '-i', str(listing), '-c:a', 'libmp3lame', '-b:a', '192k', str(final)])
        if not final.exists() or final.stat().st_size < 20: raise ElevenLabsError('ElevenLabs produced no usable audio.')
        import shutil
        stage = Path(str(output) + '.tmp')
        try: shutil.copyfile(final, stage); stage.replace(output)
        finally: stage.unlink(missing_ok=True)


def synthesize(output, text, cfg, run, ffmpeg, emit, transport=None):
    try:
        return _synthesize(output, text, cfg, run, ffmpeg, emit, transport)
    except ElevenLabsError as exc:
        if exc.kind == 'invalid': emit(str(exc), narrationProvider='elevenlabs', elevenlabsKeyStatus='invalid')
        raise
