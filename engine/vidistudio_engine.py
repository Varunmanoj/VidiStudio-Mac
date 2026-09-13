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


def remove_empty_directory(path):
    try:
        path.rmdir()
    except OSError:
        pass


def migrate_project_schema(root, project):
    """Make project.json the single source of truth for editable project data."""
    if 'transcriptGenerated' not in project:
        project['transcriptGenerated'] = bool(project.get('transcript')) or (root/'transcript/transcript.json').is_file()
    if 'summaryGenerated' not in project:
        project['summaryGenerated'] = bool(str(project.get('summary', '')).strip()) or (root/'metadata/summary.json').is_file()
    if 'descriptionsGenerated' not in project:
        project['descriptionsGenerated'] = bool(project.get('cues')) or (root/'audio-description/cues.json').is_file()
    project['schemaVersion'] = 2
    return project


def cleanup_project_storage(root, project):
    """Delete reproducible, unreferenced, or legacy duplicate project artifacts."""
    root = root.resolve()
    migrate_project_schema(root, project)
    removed_files = 0
    removed_bytes = 0

    def remove(path):
        nonlocal removed_files, removed_bytes
        path = Path(path)
        if not path.exists() and not path.is_symlink():
            return
        lexical = Path(os.path.abspath(path))
        if not lexical.is_relative_to(root):
            raise ValueError('Cleanup encountered a path outside the project folder.')
        if path.is_symlink():
            try: removed_bytes += path.lstat().st_size
            except OSError: pass
            path.unlink(missing_ok=True);removed_files += 1
        elif path.is_file():
            resolved = path.resolve()
            if not resolved.is_relative_to(root):
                raise ValueError('Cleanup encountered a path outside the project folder.')
            try: removed_bytes += path.lstat().st_size
            except OSError: pass
            path.unlink(missing_ok=True);removed_files += 1
        elif path.is_dir():
            for child in list(path.iterdir()): remove(child)
            remove_empty_directory(path)

    # These files repeat project.json or are processing intermediates/audit logs
    # that no current application feature reads or restores.
    remove(root/'transcript')
    for duplicate in ('summary.json', 'source.json'):
        remove(root/'metadata'/duplicate)
    for pattern in ('ocr-*.json',):
        for path in (root/'metadata').glob(pattern): remove(path)
    remove(root/'metadata/history')
    remove(root/'metadata/trash')
    for finder_file in root.rglob('.DS_Store'):
        remove(finder_file)

    referenced_thumbnails = {local(root, path) for path in project.get('thumbnails', [])}
    thumbnail_root = root/'thumbnails'
    if thumbnail_root.exists():
        for path in list(thumbnail_root.iterdir()):
            if path.resolve() not in referenced_thumbnails: remove(path)
        remove_empty_directory(thumbnail_root)

    referenced_audio = {local(root, cue['audio']) for cue in project.get('cues', []) if cue.get('audio')}
    audio_root = root/'audio-description'
    if audio_root.exists():
        for path in list(audio_root.iterdir()):
            if path.resolve() not in referenced_audio: remove(path)
        remove_empty_directory(audio_root)

    referenced_exports = {local(root, path) for path in project.get('exports', [])}
    exports_root = root/'exports'
    if exports_root.exists():
        for path in list(exports_root.iterdir()):
            if path.resolve() not in referenced_exports: remove(path)
        remove_empty_directory(exports_root)

    source_path = local(root, project['source']) if project.get('source') else None
    source_root = root/'source'
    if source_root.exists():
        for path in list(source_root.iterdir()):
            resolved = path.resolve()
            if source_path is None or (resolved != source_path.resolve() and resolved not in source_path.resolve().parents): remove(path)
        remove_empty_directory(source_root)

    remove_empty_directory(root/'metadata')
    return dict(files=removed_files, bytes=removed_bytes)


def save(root, p):
    p['schemaVersion'] = 2
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
    (root/'thumbnails').mkdir(parents=True, exist_ok=True)
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


def delete_description_narration(root, project):
    """Remove saved narration while preserving the current description text and timing."""
    folder = root/'audio-description'
    if folder.is_symlink():
        raise ValueError('Cannot delete narration from a symbolic-link folder.')
    resolved = local(root, 'audio-description')
    if not resolved.exists():
        for cue in project.get('cues', []):
            for key in ('audio', 'audioText', 'audioDuration', 'audioSettings'):
                cue.pop(key, None)
        return False
    removed = False
    for path in resolved.iterdir():
        removed = True
        if path.is_symlink():
            path.unlink()
        elif path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink()
    for cue in project.get('cues', []):
        for key in ('audio', 'audioText', 'audioDuration', 'audioSettings'):
            removed = cue.pop(key, None) is not None or removed
    try:
        resolved.rmdir()
    except OSError:
        pass
    return removed


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
                (root/'transcript').mkdir(parents=True, exist_ok=True)
                for start in range(0,math.ceil(p['duration']),1200):
                    chunk=root/'transcript'/f'audio-{start}.wav'
                    emit(f'Transcribing audio from {start//60} minutes')
                    try:
                        run([tool('ffmpeg'),'-y','-v','error','-ss',str(start),'-i',local(root,p['source']),'-t','1200','-vn','-ac','1','-ar','16000',chunk])
                        data.extend(gemini_adapter.transcribe_audio(client,model,chunk,start,lambda text:emit(text)))
                    finally:
                        chunk.unlink(missing_ok=True)
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
                if delete_description_narration(root, p):
                    emit('Deleted existing narration audio before replacing Audio Descriptions')
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
            p['transcriptGenerated']=True
        elif stage=='generate-summary':
            p['summary']=data['summary'];p['summaryGenerated']=True
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
            p['cues']=validate_cues(cues,p['duration'],p['transcript']);p['descriptionsGenerated']=True
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
                raise ValueError(f'{label} failed after {attempt} attempt(s): {detail} Check the issue, then start the action again.') from exc
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
    (root/'audio-description').mkdir(parents=True, exist_ok=True)
    for i,c in enumerate(cues):
        if segment and c['id']!=segment: continue
        if changed and c.get('audioText')==c['text'] and c.get('audioSettings')==signature and c.get('audio') and local(root,c['audio']).exists(): continue
        emit(f'Synthesizing AD segment {i+1} of {len(cues)}', progress=i/len(cues))
        name = 'audio-description/' + str(uuid.uuid4()) + '.wav'
        output = root/name
        previous_audio = c.get('audio')
        raw = None
        with tempfile.NamedTemporaryFile('w', encoding='utf-8', prefix='vidistudio-speech-', suffix='.txt', delete=False) as text_stream:
            text_stream.write(c['text'])
            textfile = Path(text_stream.name)
        try:
            if cfg.get('ttsMode','system') == 'gemini':
                gemini_speech(output, c['text'], p)
            elif sys.platform == 'darwin':
                raw = output.with_suffix('.aiff')
                args = ['/usr/bin/say', '-f', textfile, '-o', raw]
                rate, _, _ = speech_controls(cfg)
                args += ['-r', str(round(180 * rate))]
                if voice := effective_system_voice(cfg): args += ['-v', voice]
                run(args)
                finish_system_speech(raw, output, cfg)
            elif os.name == 'nt':
                raw = output.with_name(output.stem + '-raw.wav')
                rate, _, volume = speech_controls(cfg)
                script = "$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.Speech; $s=New-Object System.Speech.Synthesis.SpeechSynthesizer; if ($env:VDS_VOICE) { $s.SelectVoice($env:VDS_VOICE) }; $s.Rate=[int]$env:VDS_RATE; $s.Volume=[int]$env:VDS_VOLUME; $s.SetOutputToWaveFile($env:VDS_OUT); $s.Speak([IO.File]::ReadAllText($env:VDS_TEXT)); $s.Dispose()"
                env = os.environ | {'VDS_OUT':str(raw),'VDS_TEXT':str(textfile),'VDS_VOICE':cfg.get('systemVoice',''),'VDS_RATE':str(round((rate-1.0)*10)),'VDS_VOLUME':str(round(volume*100))}
                result = subprocess.run(['powershell','-NoProfile','-NonInteractive','-Command',script],env=env,capture_output=True,text=True)
                if result.returncode: raise ValueError('Windows system speech failed: '+result.stderr[-500:])
                finish_system_speech(raw, output, cfg)
            else: raise ValueError('System voices are supported on macOS and Windows.')
            actual = float(probe(output)['format'].get('duration', 0))
            if actual <= 0:
                raise ValueError('System speech produced no audio. Choose an installed voice in Settings and check macOS speech availability.')
            if actual > c['end']-c['start']:
                raise ValueError(narration_fit_error_message(i+1, actual, c['end']-c['start']))
            c['audio'] = name; c['audioText'] = c['text']; c['audioDuration'] = actual; c['audioSettings'] = signature
            p['cues'] = cues; save(root,p)
            if previous_audio and previous_audio != name and not any(item.get('audio') == previous_audio for item in cues):
                local(root, previous_audio).unlink(missing_ok=True)
        except Exception:
            output.unlink(missing_ok=True)
            raise
        finally:
            textfile.unlink(missing_ok=True)
            if raw is not None: raw.unlink(missing_ok=True)


def narration_audio_is_usable(root, cue):
    """A saved narration file stays usable until its segment text changes."""
    return bool(cue.get('audio') and cue.get('audioText') == cue.get('text')
                and local(root, cue['audio']).is_file())


def export_relative_path(root, project, export_type, extension, stamp=None):
    """Create a portable, descriptive, collision-safe path for a new export."""
    (root/'exports').mkdir(parents=True, exist_ok=True)
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


def validated_caption_segments(project, content='transcript'):
    """Return caption-safe Transcript or AD Transcript rows without changing the project."""
    if content not in ('transcript', 'combined'):
        raise ValueError('Captioned video can use the Transcript or AD Transcript.')
    duration = float(project.get('duration', 0))
    segments = []
    source = [(segment, False) for segment in project.get('transcript', [])]
    if content == 'combined':
        source += [(segment, True) for segment in project.get('cues', [])]
    for segment, is_description in source:
        start, end = float(segment['start']), float(segment['end'])
        text = str(segment.get('text', '')).strip()
        if not math.isfinite(start + end) or start < 0 or end <= start or end > duration + .1:
            raise ValueError('Transcript timing is invalid. Correct or regenerate the transcript before exporting captions.')
        if not text:
            raise ValueError('Every transcript caption needs text.')
        if is_description:
            text = 'Audio description: ' + text
        segments.append(dict(
            segment,
            start=start,
            end=min(end, duration),
            text=text,
            _captionKind='description' if is_description else 'dialogue',
        ))
    if not segments:
        raise ValueError('Generate a transcript before exporting captioned video.')
    return sorted(segments, key=lambda segment: (segment['start'], segment['end'], str(segment.get('id', ''))))


def srt_caption_text(segments):
    text = ''
    for index, segment in enumerate(segments, 1):
        text += (
            f"{index}\n{parity.clock(segment['start'], ',')} --> {parity.clock(segment['end'], ',')}\n"
            f"{segment['text']}\n\n"
        )
    return text


def ass_time(seconds):
    centiseconds = max(0, int(round(float(seconds) * 100)))
    return f'{centiseconds // 360000}:{centiseconds // 6000 % 60:02}:{centiseconds // 100 % 60:02}.{centiseconds % 100:02}'


def ass_color(hex_color, alpha=0):
    match = re.fullmatch(r'#?([0-9A-Fa-f]{6})', str(hex_color).strip())
    rgb = match.group(1) if match else 'FFFFFF'
    red, green, blue = rgb[0:2], rgb[2:4], rgb[4:6]
    return f'&H{min(max(int(alpha), 0), 255):02X}{blue}{green}{red}'


def ass_caption_text(project, segments, settings):
    width = max(320, int(project.get('width') or 1920))
    height = max(180, int(project.get('height') or 1080))
    configured_size = min(max(float(settings.get('captionFontSize', 24)), 14), 48)
    font_size = max(14, round(configured_size * height / 720))
    opacity = min(max(float(settings.get('captionBackgroundOpacity', .75)), 0), 1)
    background_alpha = round((1 - opacity) * 255)
    alignment = 8 if settings.get('captionPosition') == 'top' else 2
    margin = max(18, round(height * .04))
    dialogue_primary = ass_color(settings.get('captionTextColor', '#FFFFFF'))
    dialogue_background = ass_color(settings.get('captionBackgroundColor', '#000000'), background_alpha)
    description_primary = ass_color(settings.get('adCaptionTextColor', '#FFD60A'))
    description_background = ass_color(settings.get('adCaptionBackgroundColor', '#3A2F00'), background_alpha)
    header = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {width}
PlayResY: {height}
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Dialogue,Arial,{font_size},{dialogue_primary},{dialogue_primary},{dialogue_background},{dialogue_background},-1,0,0,0,100,100,0,0,3,5,0,{alignment},{margin},{margin},{margin},1
Style: AudioDescription,Arial,{font_size},{description_primary},{description_primary},{description_background},{description_background},-1,0,0,0,100,100,0,0,3,5,0,{alignment},{margin},{margin},{margin},1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    events = []
    for segment in segments:
        style = 'AudioDescription' if segment.get('_captionKind') == 'description' else 'Dialogue'
        caption = str(segment['text']).replace('\\', r'\\').replace('{', r'\{').replace('}', r'\}')
        caption = caption.replace('\r\n', r'\N').replace('\r', r'\N').replace('\n', r'\N')
        events.append(f"Dialogue: 0,{ass_time(segment['start'])},{ass_time(segment['end'])},{style},,0,0,0,,{caption}")
    return header + '\n'.join(events) + '\n'


def ffmpeg_filter_path(path):
    return str(path).replace('\\', r'\\').replace(':', r'\:').replace("'", r"\'").replace(',', r'\,').replace('[', r'\[').replace(']', r'\]')


def validate_captioned_video(output, expected_duration, open_captions):
    info = probe(output)
    videos = [stream for stream in info.get('streams', []) if stream.get('codec_type') == 'video']
    subtitles = [stream for stream in info.get('streams', []) if stream.get('codec_type') == 'subtitle']
    if len(videos) != 1:
        raise ValueError('Captioned video export did not contain exactly one video track.')
    if open_captions:
        if subtitles:
            raise ValueError('Open-caption video unexpectedly contains a switchable subtitle track.')
    else:
        if len(subtitles) != 1 or subtitles[0].get('codec_name') != 'mov_text':
            raise ValueError('Closed-caption video is missing its switchable caption track.')
        tags = subtitles[0].get('tags', {})
        if tags.get('language') != 'eng':
            raise ValueError('Closed-caption video is missing caption language metadata.')
    duration = float(info.get('format', {}).get('duration', videos[0].get('duration', 0)))
    if abs(duration - expected_duration) > .25:
        raise ValueError('Captioned video export duration does not match the project.')


def export_captioned_video(root, project, open_captions=False, content='transcript'):
    """Create either switchable closed captions or permanently burned open captions."""
    if project.get('sourceType') == 'youtube':
        raise ValueError('Captioned video export is unavailable for YouTube URL projects. Export subtitle text instead.')
    if not project.get('source'):
        raise ValueError('A local source video is required to export captioned video.')
    segments = validated_caption_segments(project, content)
    settings = config()
    source_title = 'AD Transcript' if content == 'combined' else 'Transcript'
    export_type = source_title + (' Open Caption Video' if open_captions else ' Closed Caption Video')
    relative = export_relative_path(root, project, export_type, 'mp4')
    output = root / relative
    temporary_path = None
    try:
        if open_captions:
            with tempfile.NamedTemporaryFile('w', encoding='utf-8', suffix='.ass', delete=False) as subtitle:
                subtitle.write(ass_caption_text(project, segments, settings))
                temporary_path = Path(subtitle.name)
            common = [
                tool('ffmpeg'), '-y', '-v', 'error', '-i', local(root, project['source']),
                '-map', '0:v:0', '-map', '0:a:0?', '-vf', f"ass=filename='{ffmpeg_filter_path(temporary_path)}'",
                '-c:v', 'libx264', '-preset', 'fast', '-crf', '20', '-movflags', '+faststart',
                '-t', str(project['duration']),
            ]
            attempts = [['-c:a', 'copy'], ['-c:a', 'aac']]
        else:
            with tempfile.NamedTemporaryFile('w', encoding='utf-8', suffix='.srt', delete=False) as subtitle:
                subtitle.write(srt_caption_text(segments))
                temporary_path = Path(subtitle.name)
            common = [
                tool('ffmpeg'), '-y', '-v', 'error', '-i', local(root, project['source']),
                '-f', 'srt', '-i', temporary_path,
                '-map', '0:v:0', '-map', '0:a:0?', '-map', '1:s:0',
                '-c:s', 'mov_text', '-metadata:s:s:0', 'language=eng',
                '-metadata:s:s:0', 'handler_name=English Transcript', '-disposition:s:0', '0',
                '-movflags', '+faststart', '-t', str(project['duration']),
            ]
            attempts = [
                ['-c:v', 'copy', '-c:a', 'copy'],
                ['-c:v', 'copy', '-c:a', 'aac'],
                ['-c:v', 'libx264', '-preset', 'fast', '-crf', '20', '-c:a', 'aac'],
            ]
        last_error = None
        for codecs in attempts:
            output.unlink(missing_ok=True)
            try:
                run([*common, *codecs, output])
                validate_captioned_video(output, float(project['duration']), open_captions)
                project['exports'].append(relative)
                return
            except ValueError as error:
                last_error = error
        output.unlink(missing_ok=True)
        raise last_error or ValueError('Captioned video export failed.')
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


EXPORT_DUCKING_LEVEL = 0.2


def original_audio_filter(narration_intervals, input_label='[0:a]'):
    """Duck the source only while saved narration is actually audible."""
    if not narration_intervals:
        return f'{input_label}anull[original]'
    expression = '+'.join(
        f'between(t,{start:.6f},{end:.6f})'
        for start, end in narration_intervals
    )
    return f"{input_label}volume={EXPORT_DUCKING_LEVEL:.4f}:enable='{expression}'[original]"


def audio_description_mix(root, p, cues, audio_only=False, program_audio_input=None, narration_input_offset=1):
    """Build the complete program-audio-plus-description mix."""
    args = []
    filters=[]; tracks=[]; narration_intervals=[]
    for i,c in enumerate(cues,1):
        if not narration_audio_is_usable(root, c): raise ValueError('Synthesize all changed AD segments before exporting.')
        audio = local(root,c['audio'])
        audio_duration = float(probe(audio)['format']['duration'])
        if audio_duration > c['end']-c['start']+.02: raise ValueError('Narration exceeds its AD segment. Adjust timing or regenerate.')
        args += ['-i',audio]
        input_index = narration_input_offset + i - 1
        filters.append(f'[{input_index}:a]adelay={round(c["start"]*1000)}:all=1[n{i}]'); tracks.append(f'[n{i}]')
        narration_intervals.append((c['start'], min(c['end'], c['start'] + audio_duration)))
    if not audio_only and (p.get('hasAudio') or program_audio_input is not None):
        source_index = 0 if program_audio_input is None else program_audio_input
        filters.append(original_audio_filter(narration_intervals, f'[{source_index}:a]')); tracks.insert(0,'[original]')
    if not tracks:
        filters.append('anullsrc=r=48000:cl=stereo[silence]');tracks.append('[silence]')
    filters.append(''.join(tracks)+f'amix=inputs={len(tracks)}:duration=longest:normalize=0,alimiter=limit=0.95,apad,atrim=duration={p["duration"]}[mix]')
    return args, filters


def validate_closed_audio_description_export(output, expected_duration):
    """Verify the switchable tracks used for closed audio description."""
    info = probe(output)
    videos = [stream for stream in info['streams'] if stream.get('codec_type') == 'video']
    audio = [stream for stream in info['streams'] if stream.get('codec_type') == 'audio']
    if len(videos) != 1 or len(audio) != 2:
        raise ValueError('Closed Audio Description export did not contain one video and two audio tracks.')
    if audio[0].get('disposition', {}).get('default') != 1 or audio[1].get('disposition', {}).get('default') != 0:
        raise ValueError('Closed Audio Description export has incorrect default audio-track ordering.')
    expected = [('Original Audio', 'eng'), ('English - Audio Description', 'eng')]
    for stream, (title, language) in zip(audio, expected):
        tags = stream.get('tags', {})
        actual_title = tags.get('title') or tags.get('handler_name')
        if actual_title != title or tags.get('language') != language:
            raise ValueError('Closed Audio Description export is missing audio-track titles or language metadata.')
        start = float(stream.get('start_time', 0))
        duration = float(stream.get('duration', info.get('format', {}).get('duration', 0)))
        if abs(start) > .05 or abs(duration - expected_duration) > .25:
            raise ValueError('Closed Audio Description audio tracks do not match the video timeline.')
    duration = float(info.get('format', {}).get('duration', videos[0].get('duration', 0)))
    if abs(duration - expected_duration) > .25:
        raise ValueError('Closed Audio Description export duration does not match the project.')


def mux_closed_audio_description(root, p, cues):
    """Mux original and described program mixes as switchable MOV tracks."""
    source = local(root,p['source'])
    has_program_audio = bool(p.get('hasAudio'))
    program_audio_input = 0 if has_program_audio else 1
    silent_program_input = [] if has_program_audio else [
        '-f','lavfi','-i','anullsrc=r=48000:cl=stereo'
    ]
    narration_args, filters = audio_description_mix(
        root, p, cues,
        program_audio_input=program_audio_input,
        narration_input_offset=program_audio_input + 1,
    )
    relative = export_relative_path(root, p, 'Closed Audio Description', 'mov')
    output = root/relative
    common = [
        tool('ffmpeg'),'-y','-v','error','-i',source,*silent_program_input,*narration_args,
        '-filter_complex',';'.join(filters),
        '-map','0:v:0','-map',f'{program_audio_input}:a:0','-map','[mix]',
        '-metadata:s:a:0','language=eng','-metadata:s:a:0','handler_name=Original Audio',
        '-metadata:s:a:1','language=eng','-metadata:s:a:1','handler_name=English - Audio Description',
        '-disposition:a:0','default','-disposition:a:1','visual_impaired',
        '-c:a:1','aac','-movflags','+faststart','-t',str(p['duration']),
    ]
    # Preserve compatible source streams first. If the container rejects a
    # source codec, transcode only audio and then video as bounded fallbacks.
    original_audio_codec = 'copy' if has_program_audio else 'aac'
    attempts = [
        ['-c:v','copy','-c:a:0',original_audio_codec],
        ['-c:v','copy','-c:a:0','aac'],
        ['-c:v','libx264','-preset','fast','-crf','20','-c:a:0','aac'],
    ]
    last_error = None
    for codecs in attempts:
        output.unlink(missing_ok=True)
        try:
            run([*common,*codecs,output])
            validate_closed_audio_description_export(output, float(p['duration']))
            p['exports'].append(relative)
            return
        except ValueError as error:
            last_error = error
    output.unlink(missing_ok=True)
    raise last_error or ValueError('Closed Audio Description export failed.')


def export(root,p,audio_only=False,allow_incomplete=False,selectable=False):
    if not audio_only and p.get('sourceType') == 'youtube':
        raise ValueError('Audio Description video export is unavailable for YouTube URL projects. Export text or narration audio instead.')
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
    if selectable:
        if not p.get('source'):
            raise ValueError('A local source video is required for Closed Audio Description export.')
        emit('Creating video with closed Audio Description')
        mux_closed_audio_description(root, p, cues)
        return
    args = [tool('ffmpeg'),'-y','-v','error']
    if p.get('source'): args += ['-i',local(root,p['source'])]
    elif audio_only: args += ['-f','lavfi','-i','anullsrc=r=48000:cl=stereo']
    else: raise ValueError('A local source video is required to render an Open Audio Description video. Narration-only export is available now.')
    narration_args, filters = audio_description_mix(root, p, cues, audio_only=audio_only)
    args += narration_args
    relative = export_relative_path(
        root,
        p,
        'Narration Audio' if audio_only else 'Open Audio Description',
        'm4a' if audio_only else 'mp4',
    )
    output = root/relative
    args += ['-filter_complex',';'.join(filters)]
    if not audio_only: args += ['-map','0:v:0','-c:v','libx264','-preset','fast','-crf','20']
    args += ['-map','[mix]','-c:a','aac','-movflags','+faststart','-t',str(p['duration']),output]
    emit('Mixing narration and rendering Open Audio Description')
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
    for key in ('thumbnails', 'transcript', 'cues', 'exports', 'undoStack', 'redoStack'):
        p[key] = []
    p['summary'] = ''
    p['transcriptGenerated'] = False
    p['summaryGenerated'] = False
    p['descriptionsGenerated'] = False
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

def delete_generated_components(root, p, components):
    selected = set(components)
    allowed = {'transcript', 'summary', 'descriptions', 'narration', 'thumbnails', 'exports', 'history'}
    if not selected or not selected.issubset(allowed):
        raise ValueError('Choose at least one valid generated-content component.')

    if 'transcript' in selected:
        reset_generated_directory(root, p, 'transcript')
        p['transcript'] = []
        p['transcriptGenerated'] = False
    if 'summary' in selected:
        summary = root/'metadata/summary.json'
        if summary.is_symlink(): raise ValueError('Cannot delete a symbolic-link summary.')
        local(root, 'metadata/summary.json').unlink(missing_ok=True)
        p['summary'] = ''
        p['summaryGenerated'] = False
    if 'descriptions' in selected:
        reset_generated_directory(root, p, 'audio-description')
        p['cues'] = []
        p['descriptionsGenerated'] = False
        p['undoStack'] = []
        p['redoStack'] = []
    elif 'narration' in selected:
        delete_description_narration(root, p)
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

    p['hasProcessed'] = bool(p.get('transcriptGenerated') or p.get('summaryGenerated') or p.get('descriptionsGenerated')
                             or p.get('transcript') or p.get('summary') or p.get('cues') or p.get('exports'))


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
    remove_empty_directory(audio_root)

def validate_analysis_prerequisites(command, root, project):
    if command != 'transcribe' and not (project.get('transcriptGenerated') or project.get('transcript')):
        raise ValueError('Run transcription first.')
    if command == 'generate-ad-cues' and not project['summary'].strip():
        raise ValueError('Generate the summary first.')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['cleanup-project','clear-generated','delete-generated','delete-segment-audio','list-models','preview-tts','import-video','probe-video','generate-thumbnails','transcribe','generate-summary','generate-ad-cues','synthesize-tts','export-final-video','export-selectable-video','export-closed-audio-description-video','export-open-audio-description-video','export-closed-caption-video','export-open-caption-video','save-cues','doctor',*parity.COMMANDS])
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
        for folder in ['source','metadata','thumbnails']: (root/folder).mkdir(parents=True,exist_ok=True)
        source='source/'+args.video.name
        emit('Copying source video into local project')
        shutil.copy2(args.video,root/source)
        p=dict(schemaVersion=2,id=str(uuid.uuid4()),name=args.video.stem,source=source,duration=duration,width=video.get('width',0),height=video.get('height',0),hasAudio=any(s['codec_type']=='audio' for s in streams),createdAt=time.time(),updatedAt=time.time(),thumbnails=[],transcript=[],summary='',cues=[],exports=[],status='Imported',transcriptGenerated=False,summaryGenerated=False,descriptionsGenerated=False)
        atomic_json(root/'metadata/probe.json',info); save(root,p)
        emit('Project imported',project=str(root))
        with project_lock(root): thumbnails(root,p);cleanup_project_storage(root,p);save(root,p)
        emit('Import complete',project=str(root),progress=1); return
    if not args.project: raise ValueError('--project is required.')
    root=args.project.resolve()
    with project_lock(root):
        p=migrate_project_schema(root,json.loads((root/'project.json').read_text()))
        p['status']='Processing '+args.command; save(root,p)
        try:
            if args.command in ('analyze', 'transcribe', 'generate-summary', 'generate-ad-cues', 'synthesize-tts'):
                p['hasProcessed'] = True
            if args.command=='cleanup-project':
                result=cleanup_project_storage(root,p);emit('Project storage cleaned',removedFiles=result['files'],removedBytes=result['bytes'])
            elif args.command=='clear-generated': clear_generated(root,p)
            elif args.command=='delete-generated': delete_generated_components(root,p,args.component)
            elif args.command=='delete-segment-audio': delete_segment_audio(root,p,args.segment)
            elif args.command=='probe-video': atomic_json(root/'metadata/probe.json',probe(local(root,p['source'])))
            elif args.command=='generate-thumbnails': thumbnails(root,p)
            elif args.command in ('transcribe','generate-summary','generate-ad-cues'):
                validate_analysis_prerequisites(args.command, root, p)
                ai_video(root,p,args.command)
            elif args.command=='synthesize-tts': synthesize(root,p,args.segment,args.changed)
            elif args.command in ('export-final-video','export-open-audio-description-video'): export(root,p,allow_incomplete=args.allow_incomplete_narration)
            elif args.command in ('export-selectable-video','export-closed-audio-description-video'): export(root,p,allow_incomplete=args.allow_incomplete_narration,selectable=True)
            elif args.command=='export-closed-caption-video': export_captioned_video(root,p,content=args.content)
            elif args.command=='export-open-caption-video': export_captioned_video(root,p,open_captions=True,content=args.content)
            elif args.command=='save-cues':
                if not args.input: raise ValueError('--input is required.')
                cues=validate_cues(json.loads(args.input.read_text()),p['duration'],p['transcript'])
                track_cue_origins(cues,p['cues']);parity.remember(p);p['cues']=cues
                p['descriptionsGenerated']=True
                p['exports']=[]
            elif args.command in parity.COMMANDS: parity.execute(args,root,p,core)
            cleanup_project_storage(root,p)
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
