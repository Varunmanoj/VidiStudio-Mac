"""VidiStudio portable local project engine. stdout is newline-delimited JSON."""
from __future__ import annotations
import argparse, contextlib, json, math, os, platform, plistlib, re, shutil, subprocess, sys, tempfile, time, uuid, wave
import signal
import gemini_adapter
import parity
from types import SimpleNamespace
from pathlib import Path


class ProcessingCancelled(Exception):
    pass

def cancel_processing(signum, frame):
    raise ProcessingCancelled("Processing cancelled. Completed results are saved.")

def emit(message, **values):
    print(json.dumps(dict(message=message, **values)), flush=True)


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile('w', encoding='utf-8', dir=path.parent, delete=False) as f:
        json.dump(value, f, ensure_ascii=False, indent=2, allow_nan=False)
        temp = f.name
    os.replace(temp, path)


def config_path():
    base = Path(os.environ.get('APPDATA', Path.home())) if os.name == 'nt' else Path.home() / 'Library/Application Support' if sys.platform == 'darwin' else Path.home() / '.config'
    return base / 'VidiStudio/config.json'


def config():
    p = Path(os.environ.get('VIDISTUDIO_CONFIG', config_path()))
    defaults = json.loads(Path(__file__).with_name('ai-defaults.json').read_text())
    saved = json.loads(p.read_text()) if p.exists() else {}
    for field in ('models','prompts'):
        defaults[field].update(saved.get(field,{}) or {})
    return defaults | {k:v for k,v in saved.items() if k not in ('models','prompts')}


def safe_error(exc):
    message = str(exc)
    try:
        key = config().get('apiKey')
        if key: message = message.replace(key, '[redacted]')
    except Exception: pass
    return message


def tool(name):
    cfg = config()
    suffix = '.exe' if os.name == 'nt' else ''
    bundled = Path(sys.executable).parent / 'media' / (name + suffix)
    candidates = [cfg.get(name + 'Path'), str(bundled), shutil.which(name), '/opt/homebrew/opt/ffmpeg-full/bin/' + name, '/opt/homebrew/bin/' + name]
    for p in candidates:
        if p and Path(p).is_file():
            return p
    raise ValueError(f'{name} is unavailable. Set its path in Settings.')


def run(args, timeout=3600):
    result = subprocess.run([str(x) for x in args], capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise ValueError(result.stderr[-2000:] or f'Command failed: {Path(args[0]).name}')
    return result.stdout


def probe(video):
    return json.loads(run([tool('ffprobe'), '-v', 'error', '-show_format', '-show_streams', '-of', 'json', video]))


def local(root, relative):
    result = (root / relative).resolve()
    if not result.is_relative_to(root.resolve()):
        raise ValueError('Project contains a path outside its folder.')
    return result


def save(root, p):
    p['updatedAt'] = time.time()
    atomic_json(root / 'project.json', p)


DUPLICATE_PROJECT_MESSAGE = ('This project already exists. Please continue with the existing project '
                             'or delete the existing project before continuing.')
MAX_LOCAL_VIDEO_SIZE_BYTES = 2_000_000_000
LOCAL_VIDEO_SIZE_MESSAGE = ('VidiStudio supports local video files up to 2 GB because larger files '
                            'cannot be uploaded through the Gemini Files API. Choose a smaller video '
                            'or create a YouTube project instead.')


def library_projects(library):
    library = Path(library)
    if not library.exists():
        return []
    projects = []
    for project_file in library.glob('*/project.json'):
        try:
            projects.append(json.loads(project_file.read_text(encoding='utf-8')))
        except (OSError, ValueError, TypeError):
            continue
    return projects


def ensure_unique_local_video(library, filename):
    candidate = Path(filename).name.casefold()
    for project in library_projects(library):
        if project.get('sourceType') == 'youtube':
            continue
        if Path(str(project.get('source', ''))).name.casefold() == candidate:
            raise ValueError(DUPLICATE_PROJECT_MESSAGE)


def ensure_supported_local_video(video):
    try:
        size = Path(video).stat().st_size
    except OSError as exc:
        raise ValueError('VidiStudio could not read the selected video file size.') from exc
    if size > MAX_LOCAL_VIDEO_SIZE_BYTES:
        raise ValueError(LOCAL_VIDEO_SIZE_MESSAGE)
    return size


def ensure_unique_youtube_video(library, url):
    parity.ensure_unique_youtube_video(library, url)


def track_cue_origins(cues, previous):
    """Keep provenance across saves without guessing the origin of legacy cues."""
    existing = {cue['id']: cue for cue in previous}
    for cue in cues:
        old = existing.get(cue['id'])
        if old:
            changed = any(cue.get(key) != old.get(key) for key in ('text', 'start', 'end'))
            if old.get('origin') in ('ai', 'ai_modified'):
                cue['origin'] = 'ai_modified' if changed or old['origin'] == 'ai_modified' else 'ai'
            elif cue.get('origin') != 'ai' or not cue.get('aiOriginalText'):
                cue['origin'] = old.get('origin', 'unknown')
        else:
            cue.setdefault('origin', 'manual')
        if cue.get('origin') == 'ai' and cue.get('aiOriginalText') is not None and cue['text'] != cue['aiOriginalText']:
            cue['origin'] = 'ai_modified'
    return cues


def validate_cues(cues, duration, transcript=()):
    previous = 0.0
    ids = set()
    for c in sorted(cues, key=lambda c: c['start']):
        a, b = float(c['start']), float(c['end'])
        if not math.isfinite(a + b) or a < previous or b <= a or b > duration + .01:
            raise ValueError('AD segments must have finite, non-overlapping times inside the video duration.')
        if not str(c.get('text', '')).strip():
            raise ValueError('Every AD segment needs description text.')
        if any(a < t['end'] and b > t['start'] for t in transcript):
            raise ValueError('An audio description overlaps spoken dialogue. Adjust its timing.')
        c.setdefault('id', str(uuid.uuid4()))
        if c['id'] in ids: raise ValueError('Duplicate AD segment identifier.')
        ids.add(c['id'])
        previous = b
    return sorted(cues, key=lambda c: c['start'])


def thumbnails(root, p):
    paths = []
    for i in range(8):
        emit(f'Generating thumbnail {i+1} of 8', progress=(i+1)/8)
        relative = f'thumbnails/frame-{i:02}.jpg'
        run([tool('ffmpeg'), '-y', '-v', 'error', '-ss', str(p['duration'] * i / 8), '-i', local(root,p['source']), '-frames:v', '1', '-vf', 'scale=480:-2', root/relative])
        paths.append(relative)
    p['thumbnails'] = paths


AI_MAX_ATTEMPTS = 3
AI_RETRY_BASE_DELAY_SECONDS = 2.0
AI_RETRYABLE_STAGES = ('transcribe', 'generate-summary', 'generate-ad-cues')

# Deterministic configuration/validation failures that a retry cannot fix.
AI_NON_RETRYABLE_SUBSTRINGS = (
    'add a gemini api key',
    'choose a gemini model',
    'up to 2 gb',
    'is unavailable. set its path',
    'run transcription first',
    'generate the summary first',
    'read video metadata before',
    'transcript timing is invalid',
    'already processing',
    'project contains a path outside',
)


def ai_retry_delay_seconds(attempt):
    """Exponential backoff between AI attempts (1-indexed failed attempt)."""
    try:
        override = float(os.environ.get('VIDISTUDIO_AI_RETRY_DELAY', ''))
        if math.isfinite(override) and override >= 0:
            return override
    except (TypeError, ValueError):
        pass
    return AI_RETRY_BASE_DELAY_SECONDS * (2 ** max(0, attempt - 1))


def is_retryable_ai_error(exc):
    if isinstance(exc, ProcessingCancelled):
        return False
    message = str(exc).lower()
    return not any(marker in message for marker in AI_NON_RETRYABLE_SUBSTRINGS)


def ai_stage_label(stage):
    return {'transcribe': 'Transcription', 'generate-summary': 'Summary', 'generate-ad-cues': 'AD segment generation'}.get(stage, stage)


def gemini_client():
    from google import genai
    cfg = config()
    if not cfg.get('apiKey'): raise ValueError('Add a Gemini API key in Settings first.')
    return genai.Client(api_key=cfg['apiKey'], http_options={'timeout': 300000, 'api_version':cfg.get('apiVersion','v1beta')})


def client_and_model(kind):
    cfg = config()
    key = {'tts':'tts_audio','transcribe':'transcript','generate-summary':'summary','generate-ad-cues':'audio_descriptions'}.get(kind,kind)
    model = cfg['models'].get(key)
    if not model: raise ValueError('Choose a Gemini model in Settings first.')
    return gemini_client(), model


def list_models():
    client = gemini_client()
    try:
        available = []
        for model in client.models.list():
            name = str(getattr(model, 'name', '') or '').removeprefix('models/')
            actions = [str(action) for action in (getattr(model, 'supported_actions', None) or [])]
            normalized_actions = {action.replace('_', '').lower() for action in actions}
            if not name.startswith('gemini-') or 'generatecontent' not in normalized_actions:
                continue
            available.append({
                'name': name,
                'displayName': str(getattr(model, 'display_name', '') or name),
                'supportedActions': actions,
            })
        available.sort(key=lambda model: (model['displayName'].lower(), model['name']))
        if not available:
            raise ValueError('No compatible Gemini models are available for this API key.')
        emit('Available Gemini models loaded', models=available)
    finally:
        client.close()


def _ai_video_once(root, p, stage):
    cfg=config(); key={'transcribe':'transcript','generate-summary':'summary','generate-ad-cues':'audio_descriptions'}[stage]
    youtube=p.get('sourceType')=='youtube' and not p.get('source')
    if stage=='transcribe' and youtube: key='youtube_transcript'
    client,model=client_and_model(key)
    uploaded=None
    try:
        if stage=='transcribe' and 'transcribe' in model:
            if not p.get('hasAudio'):
                data=[]
            else:
                data=[]
                for start in range(0,math.ceil(p['duration']),1200):
                    chunk=root/'transcript'/f'audio-{start}.wav'
                    emit(f'Transcribing audio from {start//60} minutes')
                    run([tool('ffmpeg'),'-y','-v','error','-ss',str(start),'-i',local(root,p['source']),'-t','1200','-vn','-ac','1','-ar','16000',chunk])
                    data.extend(gemini_adapter.transcribe_audio(client,model,chunk,start,lambda text:emit(text)))
        else:
            if youtube: uri=p['youtubeURL'];mime=None
            else:
                ensure_supported_local_video(local(root,p['source']))
                emit('Uploading a processing copy to Gemini')
                uploaded=gemini_adapter.ready_file(client,local(root,p['source']),lambda text:emit(text));uri=uploaded.uri;mime=uploaded.mime_type
            pair=cfg['prompts'][key]
            prompt=parity.render(pair['user_prompt'],p)
            if stage=='generate-ad-cues':
                prompt+=parity.description_context(p)
            emit('Generating '+stage)
            raw=gemini_adapter.video_interaction(client,model,uri,mime,prompt,pair.get('system_instruction',''),processing=cfg.get('videoProcessing','agentic') if stage!='transcribe' else 'static')
            if stage=='generate-summary': data={'summary':raw}
            else: data=parity.parse_json(raw)
        if stage=='transcribe':
            if isinstance(data,dict):
                if not p['duration'] and data.get('duration'): p['duration']=float(data['duration'])
                data=data.get('transcript',[])
            transcript=[]
            for t in data:
                a=parity.timestamp(t.get('startSeconds',t.get('start',0)));b=parity.timestamp(t.get('endSeconds',t.get('end',0)))
                if not math.isfinite(a+b) or not 0<=a<b<=p['duration']+.1: raise ValueError('Transcript timestamps are outside the video. Existing results were preserved.')
                transcript.append(dict(id=str(uuid.uuid4()),start=a,end=b,text=t['text'],speaker=t.get('speaker','')))
            if not transcript and p.get('hasAudio') and data: raise ValueError('No usable transcript returned.')
            p['transcript']=sorted(transcript,key=lambda t:t['start'])
            atomic_json(root/'transcript/transcript.json',p['transcript'])
        elif stage=='generate-summary':
            p['summary']=data['summary'];atomic_json(root/'metadata/summary.json',data)
        else:
            descriptions=data.get('audioDescriptions',data.get('cues',[])) if isinstance(data,dict) else data
            if not isinstance(descriptions,list):
                raise ValueError('Description generation must return a list of timed text segments.')
            cues=[]
            for c in descriptions:
                if not isinstance(c,dict) or not isinstance(c.get('text'),str):
                    raise ValueError('Every generated description must contain text and valid start/end times.')
                cues.append(dict(id=str(uuid.uuid4()),start=parity.timestamp(c['start']),
                                 end=parity.timestamp(c['end']),text=c['text'],
                                 origin='ai',aiOriginalText=c['text']))
            p['cues']=validate_cues(cues,p['duration'],p['transcript']);atomic_json(root/'audio-description/cues.json',p['cues'])
    finally:
        if uploaded:
            try: client.files.delete(name=uploaded.name)
            except Exception: emit('Temporary Gemini file cleanup failed; the remote file will expire.',warning=True)
        client.close()


def ai_video(root, p, stage, max_attempts=AI_MAX_ATTEMPTS):
    """Run an AI analysis stage with bounded retries for local and YouTube projects.

    Retries transient Gemini/media failures up to ``max_attempts`` (default 3)
    with exponential backoff. The same path covers local videos and YouTube
    URL projects because the branching lives in ``_ai_video_once``.
    """
    if stage not in AI_RETRYABLE_STAGES:
        return _ai_video_once(root, p, stage)
    attempts = max(1, int(max_attempts or 1))
    label = ai_stage_label(stage)
    last_error = None
    for attempt in range(1, attempts + 1):
        try:
            return _ai_video_once(root, p, stage)
        except Exception as exc:
            if isinstance(exc, ProcessingCancelled):
                raise
            last_error = exc
            retryable = is_retryable_ai_error(exc)
            if attempt >= attempts or not retryable:
                if not retryable and attempts > 1 and attempt == 1:
                    raise
                detail = safe_error(exc)
                raise ValueError(f'{label} failed after {attempt} attempt(s): {detail} Please try again manually.') from exc
            emit(f'Retrying {stage} (attempt {attempt + 1} of {attempts}) after error: {safe_error(exc)}',
                 retryStage=stage, retryAttempt=attempt + 1, retryAttempts=attempts)
            time.sleep(ai_retry_delay_seconds(attempt))
    if last_error is not None:
        raise last_error


def gemini_speech(output, text, project):
    from google.genai import types
    cfg = config()
    client, model = client_and_model('tts')
    try:
        response = client.models.generate_content(model=model, contents=parity.render(cfg['prompts']['tts_audio']['user_prompt'], project, text=text), config=types.GenerateContentConfig(response_modalities=['AUDIO'], speech_config=types.SpeechConfig(voice_config=types.VoiceConfig(prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=cfg.get('geminiVoice','Kore'))))))
        parts = [part for candidate in (response.candidates or []) for part in (candidate.content.parts if candidate.content else [])]
        data = next((part.inline_data.data for part in parts if part.inline_data and part.inline_data.data), None)
        if not data: raise ValueError('Gemini returned no audio. Check the TTS model and selected voice in Settings.')
        with wave.open(str(output), 'wb') as f:
            f.setnchannels(1); f.setsampwidth(2); f.setframerate(24000); f.writeframes(data)
    finally:
        client.close()


def preview_tts(output, text):
    if not output: raise ValueError('Voice preview requires --output.')
    if not text or len(text) > 500: raise ValueError('Use a sample between 1 and 500 characters.')
    if config().get('ttsMode') != 'gemini': raise ValueError('Choose Gemini TTS for a cloud voice preview.')
    output.parent.mkdir(parents=True, exist_ok=True)
    gemini_speech(output, text, {})
    emit('Voice sample ready', audio=str(output))


def speech_controls(cfg):
    def bounded(name, default, low, high):
        try: value = float(cfg.get(name, default))
        except (TypeError, ValueError): value = default
        return min(max(value, low), high)
    return (
        bounded('systemSpeechRate', 1.0, 0.5, 2.0),
        bounded('systemSpeechPitch', 1.0, 0.5, 2.0),
        bounded('systemSpeechVolume', 1.0, 0.0, 1.0),
    )


def spoken_content_voice_id(preferences=None, preferred_languages=None):
    """Return the Read & Speak voice identifier for the Mac's preferred language."""
    if sys.platform != 'darwin' and preferences is None:
        return None
    if preferences is None:
        try:
            with (Path.home() / 'Library/Preferences/com.apple.Accessibility.plist').open('rb') as stream:
                preferences = plistlib.load(stream)
        except (OSError, ValueError, plistlib.InvalidFileException):
            return None
    selections = preferences.get('SpokenContentDefaultVoiceSelectionsByLanguage', [])
    if not isinstance(selections, list):
        return None
    choices = {
        selections[index]: selections[index + 1].get('voiceId')
        for index in range(0, len(selections) - 1, 2)
        if isinstance(selections[index], str)
        and isinstance(selections[index + 1], dict)
        and isinstance(selections[index + 1].get('voiceId'), str)
    }
    if preferred_languages is None:
        try:
            with (Path.home() / 'Library/Preferences/.GlobalPreferences.plist').open('rb') as stream:
                preferred_languages = plistlib.load(stream).get('AppleLanguages', [])
        except (OSError, ValueError, plistlib.InvalidFileException):
            preferred_languages = []
    language_keys = []
    for language in preferred_languages or []:
        normalized = str(language).replace('_', '-')
        language_keys.extend((normalized, normalized.split('-', 1)[0]))
    language_keys.append('en')
    return next((choices[key] for key in language_keys if key in choices), None)


def system_voice_name_from_identifier(identifier, voice_listing=None):
    if not identifier:
        return None
    if voice_listing is None:
        try:
            voice_listing = run(['/usr/bin/say', '-v', '?'], timeout=30)
        except (OSError, ValueError, subprocess.SubprocessError):
            return None
    normalized_identifier = re.sub(r'[^a-z0-9]', '', identifier.lower())
    candidates = []
    for line in voice_listing.splitlines():
        match = re.match(r'^(.+?)\s+([a-z]{2,3}_[A-Za-z_]+)\s+#', line)
        if not match:
            continue
        name, language = match.groups()
        base_name = re.sub(r'\s*\([^)]*(?:\([^)]*\)[^)]*)?\)\s*$', '', name).strip()
        if re.sub(r'[^a-z0-9]', '', base_name.lower()) in normalized_identifier:
            candidates.append((name.strip(), language))
    if not candidates:
        return None
    language_match = re.search(r'([a-z]{2,3})[-_]([a-z]{2})', identifier, re.IGNORECASE)
    if language_match:
        expected = f'{language_match.group(1)}_{language_match.group(2)}'.lower()
        localized = next((name for name, language in candidates if language.lower() == expected), None)
        if localized:
            return localized
    return candidates[0][0]


def effective_system_voice(cfg):
    selected = str(cfg.get('systemVoice', '') or '').strip()
    if selected:
        return selected
    return system_voice_name_from_identifier(spoken_content_voice_id())


def system_voice_signature(cfg):
    selected = str(cfg.get('systemVoice', '') or '').strip()
    if selected:
        return selected
    return 'default:' + (spoken_content_voice_id() or 'automatic')


def narration_signature(cfg):
    if cfg.get('ttsMode', 'system') == 'gemini':
        return f"gemini|{cfg.get('geminiVoice', 'Kore')}|{cfg.get('models', {}).get('tts_audio', '')}"
    rate, pitch, volume = speech_controls(cfg)
    return f"system|{system_voice_signature(cfg)}|{rate:.3f}|{pitch:.3f}|{volume:.3f}"


def finish_system_speech(raw, output, cfg):
    _, pitch, volume = speech_controls(cfg)
    stream = next((item for item in probe(raw).get('streams', []) if item.get('codec_type') == 'audio'), {})
    sample_rate = int(stream.get('sample_rate') or 24000)
    filters = []
    if abs(pitch - 1.0) > .0001:
        filters += [f'asetrate={sample_rate}*{pitch:.4f}', f'atempo={1.0 / pitch:.4f}', f'aresample={sample_rate}']
    if abs(volume - 1.0) > .0001:
        filters.append(f'volume={volume:.4f}')
    args = [tool('ffmpeg'), '-y', '-v', 'error', '-i', raw]
    if filters: args += ['-af', ','.join(filters)]
    run([*args, output])


def narration_fit_error_message(index, actual, available):
    return f'AD segment {index} takes {actual:.1f}s but has {available:.1f}s. Shorten its text or extend its gap.'


def synthesize(root,p,segment=None,changed=False):
    cues = validate_cues(p['cues'],p['duration'],p['transcript'])
    if not cues: raise ValueError('Create audio description segments first.')
    cfg = config()
    signature = narration_signature(cfg)
    for i,c in enumerate(cues):
        if segment and c['id']!=segment: continue
        if changed and c.get('audioText')==c['text'] and c.get('audioSettings')==signature and c.get('audio') and local(root,c['audio']).exists(): continue
        emit(f'Synthesizing AD segment {i+1} of {len(cues)}', progress=i/len(cues))
        name = 'audio-description/' + str(uuid.uuid4()) + '.wav'
        output = root/name
        textfile = root/'audio-description/speech-input.txt'
        textfile.write_text(c['text'],encoding='utf-8')
        if cfg.get('ttsMode','system') == 'gemini':
            gemini_speech(output, c['text'], p)
        elif sys.platform == 'darwin':
            raw = output.with_suffix('.aiff')
            args = ['/usr/bin/say', '-f', textfile, '-o', raw]
            rate, _, _ = speech_controls(cfg)
            args += ['-r', str(round(180 * rate))]
            if voice := effective_system_voice(cfg): args += ['-v', voice]
            run(args)
            finish_system_speech(raw, output, cfg); raw.unlink()
        elif os.name == 'nt':
            raw = output.with_name(output.stem + '-raw.wav')
            rate, _, volume = speech_controls(cfg)
            script = "$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.Speech; $s=New-Object System.Speech.Synthesis.SpeechSynthesizer; if ($env:VDS_VOICE) { $s.SelectVoice($env:VDS_VOICE) }; $s.Rate=[int]$env:VDS_RATE; $s.Volume=[int]$env:VDS_VOLUME; $s.SetOutputToWaveFile($env:VDS_OUT); $s.Speak([IO.File]::ReadAllText($env:VDS_TEXT)); $s.Dispose()"
            env = os.environ | {'VDS_OUT':str(raw),'VDS_TEXT':str(textfile),'VDS_VOICE':cfg.get('systemVoice',''),'VDS_RATE':str(round((rate-1.0)*10)),'VDS_VOLUME':str(round(volume*100))}
            result = subprocess.run(['powershell','-NoProfile','-NonInteractive','-Command',script],env=env,capture_output=True,text=True)
            if result.returncode: raise ValueError('Windows system speech failed: '+result.stderr[-500:])
            finish_system_speech(raw, output, cfg); raw.unlink()
        else: raise ValueError('System voices are supported on macOS and Windows.')
        actual = float(probe(output)['format'].get('duration', 0))
        if actual <= 0:
            output.unlink(missing_ok=True)
            raise ValueError('System speech produced no audio. Choose an installed voice in Settings and check macOS speech availability.')
        if actual > c['end']-c['start']:
            output.unlink(missing_ok=True)
            raise ValueError(narration_fit_error_message(i+1, actual, c['end']-c['start']))
        c['audio'] = name; c['audioText'] = c['text']; c['audioDuration'] = actual; c['audioSettings'] = signature
        p['cues'] = cues; save(root,p)
    atomic_json(root/'audio-description/cues.json',cues)


def narration_audio_is_usable(root, cue):
    """A saved narration file stays usable until its segment text changes."""
    return bool(cue.get('audio') and cue.get('audioText') == cue.get('text')
                and local(root, cue['audio']).is_file())


def export_relative_path(root, project, export_type, extension, stamp=None):
    """Create a portable, descriptive, collision-safe path for a new export."""
    project_name = str(project.get('name') or 'Project').strip()
    project_name = re.sub(r'[<>:"/\\|?*\x00-\x1f]+', '-', project_name)
    project_name = re.sub(r'\s*-\s*', ' - ', project_name)
    project_name = re.sub(r'\s+', ' ', project_name).strip(' .-') or 'Project'
    project_name = project_name[:100].rstrip(' .-') or 'Project'
    timestamp = stamp or time.strftime('%Y%m%d-%H%M%S')
    base = f'{project_name} - {export_type} - {timestamp}'
    relative = Path('exports') / f'{base}.{extension}'
    suffix = 2
    while (root / relative).exists():
        relative = Path('exports') / f'{base} - {suffix}.{extension}'
        suffix += 1
    return relative.as_posix()


EXPORT_DUCKING_LEVEL = 0.2


def original_audio_filter(narration_intervals):
    """Duck the source only while saved narration is actually audible."""
    if not narration_intervals:
        return '[0:a]anull[original]'
    expression = '+'.join(
        f'between(t,{start:.6f},{end:.6f})'
        for start, end in narration_intervals
    )
    return f"[0:a]volume={EXPORT_DUCKING_LEVEL:.4f}:enable='{expression}'[original]"


def export(root,p,audio_only=False,allow_incomplete=False):
    if not audio_only and p.get('sourceType') == 'youtube':
        raise ValueError('Final video export is unavailable for YouTube URL projects. Export text or narration audio instead.')
    cues = validate_cues(p['cues'],p['duration'],p['transcript'])
    if not cues and not allow_incomplete: raise ValueError('Create and synthesize AD segments before exporting.')
    available=[]
    for cue in cues:
        if not narration_audio_is_usable(root, cue):
            if not allow_incomplete:
                raise ValueError('Some descriptions have missing or outdated narration. Synthesize narration or confirm an incomplete export.')
            emit('Omitting description without synchronized narration: '+cue['id'],warning=True)
            continue
        available.append(cue)
    cues=available
    if audio_only and not cues:
        raise ValueError('Generate narration for at least one AD segment before exporting narration audio.')
    args = [tool('ffmpeg'),'-y','-v','error']
    if p.get('source'): args += ['-i',local(root,p['source'])]
    elif audio_only: args += ['-f','lavfi','-i','anullsrc=r=48000:cl=stereo']
    else: raise ValueError('A local source video is required to render a final video. Narration-only export is available now.')
    filters=[]; tracks=[]; narration_intervals=[]
    for i,c in enumerate(cues,1):
        if not narration_audio_is_usable(root, c): raise ValueError('Synthesize all changed AD segments before exporting.')
        audio = local(root,c['audio'])
        audio_duration = float(probe(audio)['format']['duration'])
        if audio_duration > c['end']-c['start']+.02: raise ValueError('Narration exceeds its AD segment. Adjust timing or regenerate.')
        args += ['-i',audio]
        filters.append(f'[{i}:a]adelay={round(c["start"]*1000)}:all=1[n{i}]'); tracks.append(f'[n{i}]')
        narration_intervals.append((c['start'], min(c['end'], c['start'] + audio_duration)))
    if p.get('hasAudio') and not audio_only:
        filters.append(original_audio_filter(narration_intervals)); tracks.insert(0,'[original]')
    if not tracks:
        filters.append('anullsrc=r=48000:cl=stereo[silence]');tracks.append('[silence]')
    filters.append(''.join(tracks)+f'amix=inputs={len(tracks)}:duration=longest:normalize=0,alimiter=limit=0.95,apad,atrim=duration={p["duration"]}[mix]')
    relative = export_relative_path(
        root,
        p,
        'Narration Audio' if audio_only else 'Final Video',
        'm4a' if audio_only else 'mp4',
    )
    output = root/relative
    args += ['-filter_complex',';'.join(filters)]
    if not audio_only: args += ['-map','0:v:0','-c:v','libx264','-preset','fast','-crf','20']
    args += ['-map','[mix]','-c:a','aac','-movflags','+faststart','-t',str(p['duration']),output]
    emit('Mixing narration and rendering final video')
    run(args)
    p['exports'].append(relative)


@contextlib.contextmanager
def project_lock(root):
    lock=root/'.engine.lock'
    # OS lock is automatically released when the process dies.
    with open(lock,'a+b') as f:
        if os.name == 'nt':
            import msvcrt
            f.seek(0); f.write(b'0'); f.flush(); f.seek(0)
            try: msvcrt.locking(f.fileno(),msvcrt.LK_NBLCK,1)
            except OSError: raise ValueError('This project is already processing.')
        else:
            import fcntl
            try: fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError: raise ValueError('This project is already processing.')
        yield


def clear_generated(root, p):
    folders = ['metadata', 'thumbnails', 'transcript', 'audio-description', 'exports']
    source = local(root, p['source']).resolve() if p.get('source') else None
    for name in folders:
        folder = root / name
        if folder.is_symlink() or (source and (folder.resolve() == source or folder.resolve() in source.parents)):
            raise ValueError('Cannot clear generated content: a generated folder contains the source video or is a symbolic link.')
    for name in folders:
        folder = root / name
        if folder.exists(): shutil.rmtree(folder)
        folder.mkdir()
    for key in ('thumbnails', 'transcript', 'cues', 'exports', 'undoStack', 'redoStack'):
        p[key] = []
    p['summary'] = ''
    p['hasProcessed'] = False
    p.pop('error', None)

def reset_generated_directory(root, p, relative):
    folder = root / relative
    source = local(root, p['source']).resolve() if p.get('source') else None
    if folder.is_symlink():
        raise ValueError(f'Cannot delete generated content: {relative} is a symbolic link.')
    resolved = local(root, relative)
    if source and (resolved == source or resolved in source.parents):
        raise ValueError('Cannot delete generated content because it contains the source video.')
    if resolved.exists():
        shutil.rmtree(resolved)
    resolved.mkdir(parents=True)

def delete_generated_components(root, p, components):
    selected = set(components)
    allowed = {'transcript', 'summary', 'descriptions', 'narration', 'thumbnails', 'exports', 'history'}
    if not selected or not selected.issubset(allowed):
        raise ValueError('Choose at least one valid generated-content component.')

    if 'transcript' in selected:
        reset_generated_directory(root, p, 'transcript')
        p['transcript'] = []
    if 'summary' in selected:
        summary = root/'metadata/summary.json'
        if summary.is_symlink(): raise ValueError('Cannot delete a symbolic-link summary.')
        local(root, 'metadata/summary.json').unlink(missing_ok=True)
        p['summary'] = ''
    if 'descriptions' in selected:
        reset_generated_directory(root, p, 'audio-description')
        p['cues'] = []
        p['undoStack'] = []
        p['redoStack'] = []
    elif 'narration' in selected:
        folder = root/'audio-description'
        if folder.is_symlink(): raise ValueError('Cannot delete narration from a symbolic-link folder.')
        resolved = local(root, 'audio-description')
        resolved.mkdir(parents=True, exist_ok=True)
        for path in resolved.iterdir():
            if path.name == 'cues.json': continue
            if path.is_symlink(): path.unlink()
            elif path.is_dir(): shutil.rmtree(path)
            else: path.unlink()
        for cue in p.get('cues', []):
            for key in ('audio', 'audioText', 'audioDuration', 'audioSettings'):
                cue.pop(key, None)
        atomic_json(resolved/'cues.json', p.get('cues', []))
    if 'thumbnails' in selected:
        reset_generated_directory(root, p, 'thumbnails')
        p['thumbnails'] = []
    if 'exports' in selected:
        reset_generated_directory(root, p, 'exports')
        p['exports'] = []
    if 'history' in selected:
        reset_generated_directory(root, p, 'metadata/history')
        p['undoStack'] = []
        p['redoStack'] = []

    p['hasProcessed'] = bool(p.get('transcript') or p.get('summary') or p.get('cues') or p.get('exports'))


def delete_segment_audio(root, p, segment_id):
    cue = next((candidate for candidate in p.get('cues', []) if candidate.get('id') == segment_id), None)
    if cue is None:
        raise ValueError('Select an audio description segment.')
    audio = cue.get('audio')
    if not audio:
        raise ValueError('This audio description segment has no generated audio.')
    audio_root = local(root, 'audio-description')
    audio_path = local(root, audio)
    if audio_path != audio_root and audio_root not in audio_path.parents:
        raise ValueError('The segment audio path is outside the audio-description folder.')
    shared = any(
        candidate.get('id') != segment_id and candidate.get('audio') == audio
        for candidate in p.get('cues', [])
    )
    if not shared:
        if audio_path.is_dir() and not audio_path.is_symlink():
            raise ValueError('The segment audio path is not an audio file.')
        audio_path.unlink(missing_ok=True)
    for key in ('audio', 'audioText', 'audioDuration', 'audioSettings'):
        cue.pop(key, None)
    atomic_json(audio_root/'cues.json', p.get('cues', []))

def validate_analysis_prerequisites(command, root, project):
    if command != 'transcribe' and not (root/'transcript/transcript.json').exists():
        raise ValueError('Run transcription first.')
    if command == 'generate-ad-cues' and not project['summary'].strip():
        raise ValueError('Generate the summary first.')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['clear-generated','delete-generated','delete-segment-audio','list-models','preview-tts','import-video','probe-video','generate-thumbnails','extract-audio','transcribe','generate-summary','generate-ad-cues','synthesize-tts','export-final-video','save-cues','doctor',*parity.COMMANDS])
    parser.add_argument('--project',type=Path); parser.add_argument('--video',type=Path); parser.add_argument('--library',type=Path); parser.add_argument('--input',type=Path)
    parser.add_argument('--content',choices=['transcript','summary','descriptions','combined'],default='descriptions'); parser.add_argument('--url'); parser.add_argument('--name'); parser.add_argument('--timestamp',type=float,default=0); parser.add_argument('--duration',type=float); parser.add_argument('--segment'); parser.add_argument('--format',choices=['srt','vtt','txt','json','md'],default='srt'); parser.add_argument('--changed',action='store_true'); parser.add_argument('--start-stage',default='transcribe')
    parser.add_argument('--output', type=Path); parser.add_argument('--text')
    parser.add_argument('--component', action='append', choices=['transcript','summary','descriptions','narration','thumbnails','exports','history'], default=[])
    parser.add_argument('--allow-incomplete-narration',action='store_true',help='Export video or narration audio omitting missing/outdated narration after explicit confirmation.')
    args=parser.parse_args()
    if args.command == 'preview-tts':
        preview_tts(args.output, args.text); return
    if args.command == 'list-models':
        list_models(); return
    core=SimpleNamespace(**globals())
    if args.command in ('import-youtube','validate-config'):
        parity.execute(args,None,None,core);return
    if args.command=='doctor':
        emit('Engine ready',python=platform.python_version(),ffmpeg=tool('ffmpeg'),ffprobe=tool('ffprobe')); return
    if args.command=='import-video':
        if not args.video or not args.library: raise ValueError('Import requires --video and --library.')
        ensure_supported_local_video(args.video)
        ensure_unique_local_video(args.library, args.video.name)
        info=probe(args.video)
        streams=info['streams']; video=next((s for s in streams if s['codec_type']=='video'),None)
        if not video: raise ValueError('The selected file has no video stream.')
        duration=float(info['format'].get('duration',video.get('duration',0)))
        if not math.isfinite(duration) or duration<=0: raise ValueError('The video duration could not be determined.')
        root=args.library.resolve()/(args.video.stem[:60]+'-'+str(uuid.uuid4())[:8])
        for folder in ['source','metadata','thumbnails','transcript','audio-description','exports']: (root/folder).mkdir(parents=True,exist_ok=True)
        source='source/'+args.video.name
        emit('Copying source video into local project')
        shutil.copy2(args.video,root/source)
        p=dict(schemaVersion=1,id=str(uuid.uuid4()),name=args.video.stem,source=source,duration=duration,width=video.get('width',0),height=video.get('height',0),hasAudio=any(s['codec_type']=='audio' for s in streams),createdAt=time.time(),updatedAt=time.time(),thumbnails=[],transcript=[],summary='',cues=[],exports=[],status='Imported')
        atomic_json(root/'metadata/probe.json',info); save(root,p)
        emit('Project imported',project=str(root))
        with project_lock(root): thumbnails(root,p); save(root,p)
        emit('Import complete',project=str(root),progress=1); return
    if not args.project: raise ValueError('--project is required.')
    root=args.project.resolve()
    with project_lock(root):
        p=json.loads((root/'project.json').read_text())
        atomic_json(root/'metadata/history'/f'{time.time_ns()}-{args.command}.json',p)
        p['status']='Processing '+args.command; save(root,p)
        try:
            if args.command in ('analyze', 'transcribe', 'generate-summary', 'generate-ad-cues', 'synthesize-tts'):
                p['hasProcessed'] = True
            if args.command=='clear-generated': clear_generated(root,p)
            elif args.command=='delete-generated': delete_generated_components(root,p,args.component)
            elif args.command=='delete-segment-audio': delete_segment_audio(root,p,args.segment)
            elif args.command=='probe-video': atomic_json(root/'metadata/probe.json',probe(local(root,p['source'])))
            elif args.command=='generate-thumbnails': thumbnails(root,p)
            elif args.command=='extract-audio':
                if not p['hasAudio']: raise ValueError('This video has no audio track.')
                run([tool('ffmpeg'),'-y','-v','error','-i',local(root,p['source']),'-vn','-ac','1','-ar','16000',root/'transcript/source.wav'])
            elif args.command in ('transcribe','generate-summary','generate-ad-cues'):
                validate_analysis_prerequisites(args.command, root, p)
                ai_video(root,p,args.command)
            elif args.command=='synthesize-tts': synthesize(root,p,args.segment,args.changed)
            elif args.command=='export-final-video': export(root,p,allow_incomplete=args.allow_incomplete_narration)
            elif args.command=='save-cues':
                if not args.input: raise ValueError('--input is required.')
                cues=validate_cues(json.loads(args.input.read_text()),p['duration'],p['transcript'])
                track_cue_origins(cues,p['cues']);parity.remember(p);p['cues']=cues
                p['exports']=[]
                atomic_json(root/'audio-description/cues.json',p['cues'])
            elif args.command in parity.COMMANDS: parity.execute(args,root,p,core)
            p['status']='Ready'; p.pop('error',None); save(root,p)
        except Exception as e:
            p['status']='Needs attention'; p['error']=safe_error(e); save(root,p); raise
    emit('Complete',project=str(root),progress=1)

if __name__=='__main__':
    signal.signal(signal.SIGTERM, cancel_processing)
    signal.signal(signal.SIGINT, cancel_processing)
    try: main()
    except Exception as exc:
        emit(safe_error(exc),error=True)
        sys.exit(1)
