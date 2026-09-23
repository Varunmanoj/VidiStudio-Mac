"""VidiStudio portable local project engine. stdout is newline-delimited JSON."""
from __future__ import annotations
import argparse, contextlib, html, json, math, os, platform, plistlib, re, shutil, subprocess, sys, tempfile, time, uuid, wave
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
    defaults['models'].update(saved.get('models',{}) or {})
    for stage,overrides in (saved.get('prompts',{}) or {}).items():
        defaults['prompts'].setdefault(stage,{}).update(overrides or {})
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
    valid_exports = set(project.get('exports', []))
    project['exportMediaInfo'] = {
        path: value for path, value in (project.get('exportMediaInfo') or {}).items()
        if path in valid_exports and isinstance(value, dict)
    }
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


def validate_transcript(segments, duration):
    """Validate user-edited transcript rows before replacing saved project data."""
    previous = 0.0
    ids = set()
    for segment in sorted(segments, key=lambda candidate: candidate['start']):
        start, end = float(segment['start']), float(segment['end'])
        if not math.isfinite(start + end) or start < previous or end <= start or end > duration + .01:
            raise ValueError('Transcript segments must have finite, non-overlapping times inside the video duration.')
        if not str(segment.get('text', '')).strip():
            raise ValueError('Every transcript segment needs text.')
        segment.setdefault('id', str(uuid.uuid4()))
        if segment['id'] in ids:
            raise ValueError('Duplicate transcript segment identifier.')
        ids.add(segment['id'])
        previous = end
    return sorted(segments, key=lambda segment: segment['start'])


def save_segments(p, transcript, cues):
    """Atomically replace editable transcript and AD rows in one project update."""
    transcript = validate_transcript(transcript, p['duration'])
    cues = validate_cues(cues, p['duration'], transcript)
    if cues != p.get('cues', []):
        parity.remember(p)
    if transcript != p.get('transcript', []):
        removed = {row['id'] for row in p.get('transcript', [])} - {row['id'] for row in transcript}
        if removed:
            # Explicit row deletion remains permanent, matching its native warning.
            p['transcriptUndoStack'] = []; p['transcriptRedoStack'] = []
        else:
            remember_transcript(p)
    track_cue_origins(cues, p.get('cues', []))
    p['transcript'] = transcript
    p['cues'] = cues
    p['transcriptGenerated'] = bool(transcript)
    p['descriptionsGenerated'] = bool(cues)
    p['exports'] = []
    p['exportMediaInfo'] = {}
    p['hasProcessed'] = bool(
        p.get('transcriptGenerated') or p.get('summaryGenerated') or p.get('descriptionsGenerated')
        or p.get('transcript') or p.get('summary') or p.get('cues')
    )


def thumbnails(root, p):
    (root/'thumbnails').mkdir(parents=True, exist_ok=True)
    paths = []
    for i in range(8):
        emit(f'Creating timeline picture {i+1} of 8', progress=(i+1)/8)
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


def validate_youtube_for_gemini(url):
    """Prove that Gemini can read a YouTube URL before a project is created."""
    client,model=client_and_model('youtube_transcript')
    try:
        gemini_adapter.video_interaction(
            client,model,url,None,
            'Confirm that this public YouTube video is available for video understanding. Return only READY.'
        )
    except Exception as exc:
        raise ValueError(
            'This YouTube video is not available for Gemini analysis. '
            'Use a publicly available video with visibility set to Public; '
            'Private, Unlisted, and other visibility settings are not supported.'
        ) from exc
    finally:
        client.close()


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


def remote_video_status(root, p, client):
    """Refresh service state without replacing a confirmed state on a failed check."""
    cached=p.get('geminiVideo')
    if not cached: return None
    try:
        f=client.files.get(name=cached['name'])
        state=str(gemini_adapter.value(gemini_adapter.value(f,'state'),'name',gemini_adapter.value(f,'state'))).upper()
        cached['state']=state
        expiry=gemini_adapter.value(f,'expiration_time')
        if expiry: cached['expiresAt']=file_expiry(expiry)
        if cached.get('expiresAt',0)<=time.time(): cached['state']='EXPIRED'
        cached['checkedAt']=time.time()
        save(root,p)
        return f if cached['state']=='ACTIVE' else None
    except Exception as exc:
        code=getattr(exc,'code',None)
        if code != 404: raise
        cached['state']='MISSING'
        cached['checkedAt']=time.time()
        save(root,p)
        return None


def file_expiry(value):
    from datetime import datetime
    if hasattr(value,'timestamp'): return value.timestamp()
    return datetime.fromisoformat(str(value).replace('Z','+00:00')).timestamp()


def reusable_video(root,p,client):
    if p.get('sourceType') == 'youtube':
        raise ValueError('YouTube videos use their public link and do not need a Files API upload.')
    source=local(root,p['source']);ensure_supported_local_video(source)
    stat=source.stat();fingerprint=f"{p['source']}|{stat.st_size}|{stat.st_mtime_ns}"
    cached=p.get('geminiVideo')
    if cached and cached.get('fingerprint')==fingerprint:
        f=remote_video_status(root,p,client)
        if f: return f
        if cached.get('state')=='PROCESSING':
            raise ValueError('The video is still being prepared. Refresh its status in the inspector and try again shortly.')
    started=time.time()
    emit('Uploading video for analysis',videoPreparation='uploading')
    f=gemini_adapter.ready_file(client,source,
        lambda text:emit(text,videoPreparation='processing'))
    expiry=gemini_adapter.value(f,'expiration_time')
    p['geminiVideo']=dict(name=f.name,uri=f.uri,mimeType=f.mime_type,
        expiresAt=file_expiry(expiry) if expiry else started+48*3600,
        state='ACTIVE',checkedAt=time.time(),fingerprint=fingerprint)
    save(root,p)
    emit('Video ready for analysis',videoPreparation='ready')
    return f


def reanalyze_segment(root,p,draft):
    """Ask Gemini to reconcile a bounded neighborhood; commit only a valid proposal."""
    import copy
    validate_analysis_prerequisites('generate-ad-cues',root,p)
    start,end=float(draft['start']),float(draft['end'])
    if not math.isfinite(start+end) or not 0<=start<end<=p['duration']:
        raise ValueError('Choose a start and end time inside the video.')
    existing=sorted(p.get('cues',[]),key=lambda c:c['start'])
    # Include intersecting cues and the immediate neighbors, with room to move.
    affected=[c for c in existing if c['start']<end and c['end']>start]
    before=[c for c in existing if c['end']<=start]
    after=[c for c in existing if c['start']>=end]
    if before: affected.append(before[-1])
    if after: affected.append(after[0])
    editable={c['id'] for c in affected}
    left=max(0,min([start]+[c['start'] for c in affected])-5)
    right=min(p['duration'],max([end]+[c['end'] for c in affected])+5)
    frozen=[copy.deepcopy(c) for c in existing if c['id'] not in editable]
    for c in frozen:
        if c['end']<=start: left=max(left,c['end'])
        elif c['start']>=end: right=min(right,c['start'])
    hint=str(draft.get('hint','')).strip()
    draft_description={key:value for key,value in draft.items() if key!='hint'}
    context=dict(selectedRange=dict(start=start,end=end),editableRange=dict(start=left,end=right),
        editableIDs=sorted(editable),draftDescription=draft_description,userHint=hint,
        existingDescriptions=existing)
    cfg=config();pair=parity.media_prompt_pair(cfg,'audio_descriptions')
    prompt=(parity.render(pair['user_prompt'],p)+parity.description_context(p)
        +'\nRe-analyze the selected range in greater visual detail. Reconcile its descriptions and '
        'immediate neighbors, changing text and timing, merging, shortening or splitting as needed. '
        'Use absolute timestamps from the original video, never clip-relative timestamps. '
        'Only add new visual details from the selected range. Preserve the meaning of manual edits. '
        'Return the complete replacement audioDescriptions list for editableRange ONLY. '
        'Do not return or change frozen descriptions. Keep every replacement inside editableRange '
        'and dialogue-free gaps, without overlaps. Reuse an editable id when retaining a segment; '
        'omit id for new segments. Do not merely append text that cannot fit. '
        'Keep essential existing information; omit low-value detail if necessary. '
        'The draftDescription is optional manual description context, not an extra segment to insert unchanged. '
        'The userHint is optional guidance about what to inspect closely; follow it when supported by the video, '
        'but do not copy it into a description unless it is useful audience-facing visual information.\n'
        +json.dumps(context,ensure_ascii=False))
    client,model=client_and_model('audio_descriptions')
    try:
        if p.get('sourceType')=='youtube':
            uri=p['youtubeURL'];mime=None
        else:
            f=reusable_video(root,p,client);uri=f.uri;mime=f.mime_type
        failure=''
        for attempt in range(3):
            emit('Taking a closer look and fitting descriptions around dialogue',processingSection='descriptions')
            raw=gemini_adapter.video_interaction(client,model,uri,mime,prompt+failure,
                pair.get('system_instruction',''),processing=dict(type='static',start_offset=f'{left:g}s',end_offset=f'{right:g}s',fps=4))
            try:
                data=parity.parse_json(raw)
                rows=data.get('audioDescriptions') if isinstance(data,dict) else None
                if not isinstance(rows,list) or not rows: raise ValueError('Return at least one useful description in audioDescriptions.')
                replacements=[];old_by_id={c['id']:c for c in affected}
                for row in rows:
                    if not isinstance(row,dict) or not isinstance(row.get('text'),str): raise ValueError('Each description needs text and timing.')
                    a,b=parity.timestamp(row['start']),parity.timestamp(row['end'])
                    if not math.isfinite(a+b) or a<left or b>right: raise ValueError('Replacement timing is outside editableRange.')
                    ident=row.get('id') or str(uuid.uuid4())
                    if row.get('id') and ident not in editable: raise ValueError('Only reuse editableIDs; omit id for new segments.')
                    old=old_by_id.get(ident)
                    if old and (a,b,row['text'])==(old['start'],old['end'],old['text']):
                        replacements.append(copy.deepcopy(old))
                    else:
                        replacements.append(dict(id=ident,start=a,end=b,text=row['text'],origin='ai',aiOriginalText=row['text']))
                proposal=validate_cues(frozen+replacements,p['duration'],p.get('transcript',[]))
                if not any(c['start']<end and c['end']>start for c in replacements):
                    raise ValueError('Include a description within the selected range; shorten to fit a dialogue-free gap.')
            except (ValueError,KeyError,TypeError) as exc:
                failure='\nThe previous proposal was rejected: '+str(exc)+'. Return a corrected complete JSON proposal.'
                if attempt==2: raise ValueError('The new detail could not fit safely around existing dialogue and descriptions. Existing segments were preserved. Try a wider selection.') from exc
                continue
            parity.remember(p)
            p['cues']=proposal;p['descriptionsGenerated']=True;p['hasProcessed']=True
            p['exports']=[];p['exportMediaInfo']={}
            return
    finally: client.close()


def remember_transcript(p):
    import copy
    p.setdefault('transcriptUndoStack', []).append(copy.deepcopy(p.get('transcript', [])))
    p['transcriptUndoStack'] = p['transcriptUndoStack'][-50:]
    p['transcriptRedoStack'] = []


def restore_transcript(p, redo=False):
    import copy
    source, target = ('transcriptRedoStack', 'transcriptUndoStack') if redo else ('transcriptUndoStack', 'transcriptRedoStack')
    if not p.get(source):
        raise ValueError('No transcript edit history in this direction.')
    proposal = validate_transcript(copy.deepcopy(p[source][-1]), p['duration'])
    validate_cues(copy.deepcopy(p.get('cues', [])), p['duration'], proposal)
    p.setdefault(target, []).append(copy.deepcopy(p.get('transcript', [])))
    p[target] = p[target][-50:]
    p[source].pop()
    p['transcript'] = proposal
    p['transcriptGenerated'] = bool(proposal)
    p['exports'] = []; p['exportMediaInfo'] = {}


def reanalyze_transcript_segment(root, p, draft):
    """Reconcile transcript rows atomically while preserving all existing AD and narration."""
    import copy
    start, end = float(draft['start']), float(draft['end'])
    if not math.isfinite(start + end) or not 0 <= start < end <= p['duration']:
        raise ValueError('Choose a start and end time inside the video.')
    existing = sorted(copy.deepcopy(p.get('transcript', [])), key=lambda row: row['start'])
    affected = [row for row in existing if row['start'] < end and row['end'] > start]
    before = [row for row in existing if row['end'] <= start]
    after = [row for row in existing if row['start'] >= end]
    if before: affected.append(before[-1])
    if after: affected.append(after[0])
    editable = {row['id'] for row in affected}
    frozen = [row for row in existing if row['id'] not in editable]
    left = max(0, min([start] + [row['start'] for row in affected]) - 5)
    right = min(p['duration'], max([end] + [row['end'] for row in affected]) + 5)
    for row in frozen:
        if row['end'] <= start: left = max(left, row['end'])
        elif row['start'] >= end: right = min(right, row['start'])
    cfg = config()
    key = 'youtube_transcript' if p.get('sourceType') == 'youtube' else 'transcript'
    # Dedicated audio transcription models cannot accept video ranges and editing prompts.
    model_key = 'youtube_transcript' if 'transcribe' in cfg['models'].get(key, '') else key
    pair = parity.media_prompt_pair(cfg, key)
    context = dict(selectedRange=dict(start=start, end=end), editableRange=dict(start=left, end=right),
        editableIDs=sorted(editable), existingTranscript=existing, existingDescriptions=p.get('cues', []),
        summary=p.get('summary', ''), draftTranscript={k:v for k,v in draft.items() if k != 'hint'},
        userHint=str(draft.get('hint', '')).strip())
    prompt = (parity.render(pair['user_prompt'], p)
        + '\nRe-analyze spoken dialogue in selectedRange and reconcile its immediate transcript neighbors. '
        'Return a raw JSON object with the complete replacement transcript list for editableRange ONLY. '
        'Create as many timed segments as needed, splitting or merging naturally at speaker or language changes. '
        'Use absolute original-video start and end times, never clip-relative times. Include text and optional speaker. '
        'Reuse only editableIDs for retained rows; omit id for new rows. Do not change frozen transcript rows. '
        'Preserve accurate manual corrections. The draftTranscript is context, not text to insert automatically. '
        'The userHint is guidance, never invented dialogue. Preserve all spoken languages, original scripts and '
        'code-switching verbatim; do not translate. Never transcribe visual details or AD as source dialogue. '
        'Existing descriptions and their narration are frozen. Do not invent, suppress or move speech to avoid '
        'a conflict with AD; return accurate speech timing so conflicts can be reported safely. '
        'Include at least one spoken segment intersecting selectedRange; if there is no speech return an empty list.\n'
        + json.dumps(context, ensure_ascii=False))
    client, model = client_and_model(model_key)
    try:
        if p.get('sourceType') == 'youtube':
            uri, mime = p['youtubeURL'], None
        else:
            f = reusable_video(root, p, client); uri, mime = f.uri, f.mime_type
        failure = ''
        for attempt in range(3):
            emit('Analyzing dialogue in the selected time range', processingSection='transcript')
            raw = gemini_adapter.video_interaction(client, model, uri, mime, prompt + failure,
                pair.get('system_instruction', ''), processing=dict(type='static', start_offset=f'{left:g}s', end_offset=f'{right:g}s', fps=4))
            try:
                data = parity.parse_json(raw)
                rows = data.get('transcript') if isinstance(data, dict) else None
                if not isinstance(rows, list) or not rows:
                    raise ValueError('No usable spoken transcript was returned for the selected range.')
                replacements = []; old_by_id = {row['id']:row for row in affected}
                for row in rows:
                    if not isinstance(row, dict) or not isinstance(row.get('text'), str):
                        raise ValueError('Each transcript segment needs text and timing.')
                    a = parity.timestamp(row.get('startSeconds', row.get('start')))
                    b = parity.timestamp(row.get('endSeconds', row.get('end')))
                    if not math.isfinite(a + b) or a < left or b > right:
                        raise ValueError('Replacement timing is outside editableRange.')
                    ident = row.get('id') or str(uuid.uuid4())
                    if not isinstance(ident, str) or (row.get('id') and ident not in editable):
                        raise ValueError('Only reuse editableIDs; omit id for new segments.')
                    old = old_by_id.get(ident)
                    speaker = row.get('speaker', old.get('speaker', '') if old else '')
                    if not isinstance(speaker, str): raise ValueError('Speaker must be text.')
                    if old and (a, b, row['text'], speaker) == (old['start'], old['end'], old['text'], old.get('speaker', '')):
                        replacements.append(copy.deepcopy(old))
                    else:
                        replacements.append(dict(id=ident, start=a, end=b, text=row['text'], speaker=speaker,
                            origin='ai', aiOriginalText=row['text']))
                proposal = validate_transcript(frozen + replacements, p['duration'])
                if not any(row['start'] < end and row['end'] > start for row in replacements):
                    raise ValueError('Include spoken dialogue within the selected range.')
            except (ValueError, KeyError, TypeError) as exc:
                failure = '\nThe previous proposal was rejected: ' + str(exc) + '. Return a corrected complete JSON proposal.'
                if attempt == 2:
                    raise ValueError('No valid transcript could be generated. Existing transcript, descriptions and narration were preserved. Try another range.') from exc
                continue
            # Accurate newly discovered speech must never silently overwrite or retime existing AD.
            validate_cues(copy.deepcopy(p.get('cues', [])), p['duration'], proposal)
            remember_transcript(p)
            p['transcript'] = proposal; p['transcriptGenerated'] = True; p['hasProcessed'] = True
            p['exports'] = []; p['exportMediaInfo'] = {}
            return
    finally:
        client.close()


def _ai_video_once(root, p, stage):
    cfg=config(); key={'transcribe':'transcript','generate-summary':'summary','generate-ad-cues':'audio_descriptions'}[stage]
    youtube=p.get('sourceType')=='youtube'
    if stage=='transcribe' and youtube: key='youtube_transcript'
    stage_message,processing_section={
        'transcribe':('Creating the transcript','transcript'),
        'generate-summary':('Creating the summary','summary'),
        'generate-ad-cues':('Creating Audio Descriptions','descriptions'),
    }[stage]
    emit(stage_message,processingSection=processing_section)
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
                    emit(f'Creating the transcript from minute {start//60}')
                    try:
                        run([tool('ffmpeg'),'-y','-v','error','-ss',str(start),'-i',local(root,p['source']),'-t','1200','-vn','-ac','1','-ar','16000',chunk])
                        data.extend(gemini_adapter.transcribe_audio(client,model,chunk,start,lambda text:emit(text)))
                    finally:
                        chunk.unlink(missing_ok=True)
        else:
            if youtube: uri=p['youtubeURL'];mime=None
            else:
                ensure_supported_local_video(local(root,p['source']))
                emit('Preparing the video for analysis')
                uploaded=reusable_video(root,p,client);uri=uploaded.uri;mime=uploaded.mime_type
            pair=parity.media_prompt_pair(cfg,key)
            prompt=parity.render(pair['user_prompt'],p)
            if stage=='generate-ad-cues':
                prompt+=parity.description_context(p)
                if delete_description_narration(root, p):
                    emit('Preparing updated Audio Descriptions')
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
            p['transcriptUndoStack']=[];p['transcriptRedoStack']=[]
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
            print(f'{stage} attempt {attempt} failed: {safe_error(exc)}', file=sys.stderr, flush=True)
            emit(f'Trying {stage} again (attempt {attempt + 1} of {attempts})',
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
        emit(f'Creating narration for description {i+1} of {len(cues)}', progress=i/len(cues))
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


def export_relative_path(root, project, export_type, extension):
    """Return the stable portable path for one export configuration."""
    (root/'exports').mkdir(parents=True, exist_ok=True)
    project_name = str(project.get('name') or 'Project').strip()
    project_name = re.sub(r'[<>:"/\\|?*\x00-\x1f]+', '-', project_name)
    project_name = re.sub(r'\s*-\s*', ' - ', project_name)
    project_name = re.sub(r'\s+', ' ', project_name).strip(' .-') or 'Project'
    project_name = project_name[:100].rstrip(' .-') or 'Project'
    return (Path('exports') / f'{project_name} - {export_type}.{extension}').as_posix()


def prepare_export_target(root, project, export_type, extension, replace_existing=False):
    """Create a temporary sibling path while preserving any existing valid export."""
    relative = export_relative_path(root, project, export_type, extension)
    output = root / relative
    if output.exists() and not replace_existing:
        raise ValueError('An export with these options already exists. Confirm replacement to overwrite it.')
    temporary = output.with_name(f'.{output.stem}.generating-{uuid.uuid4().hex}{output.suffix}')
    return relative, output, temporary


def media_frame_rate(stream):
    """Return a finite frames-per-second value from ffprobe's rational fields."""
    for key in ('avg_frame_rate', 'r_frame_rate'):
        raw = str(stream.get(key) or '')
        try:
            numerator, denominator = raw.split('/', 1)
            value = float(numerator) / float(denominator)
        except (ValueError, ZeroDivisionError):
            try: value = float(raw)
            except ValueError: continue
        if math.isfinite(value) and value > 0:
            return value
    return None


def media_codec_description(stream):
    return stream.get('codec_long_name') or str(stream.get('codec_name') or '').upper() or 'Not available'


def media_color_description(stream):
    transfer = stream.get('color_transfer')
    primaries = stream.get('color_primaries')
    pixel_format = stream.get('pix_fmt')
    side_data = stream.get('side_data_list') or []
    if any('dovi' in str(item.get('side_data_type', '')).lower()
           or 'dolby vision' in str(item.get('side_data_type', '')).lower() for item in side_data):
        dynamic_range = 'Dolby Vision HDR'
    elif transfer == 'smpte2084':
        dynamic_range = 'HDR (PQ)'
    elif transfer == 'arib-std-b67':
        dynamic_range = 'HDR (HLG)'
    elif primaries == 'bt2020':
        dynamic_range = 'BT.2020 wide color'
    else:
        dynamic_range = 'SDR or not reported'
    details = [dynamic_range]
    if pixel_format: details.append(pixel_format)
    if primaries: details.append(primaries)
    return ', '.join(details)


def export_media_information(path, video_processing):
    """Create the compact, portable media summary displayed by the native app."""
    info = probe(path)
    streams = info.get('streams', [])
    video = next((stream for stream in streams if stream.get('codec_type') == 'video'), None)
    if video is None:
        return None
    audio_streams = [stream for stream in streams if stream.get('codec_type') == 'audio']
    audio_parts = []
    for stream in audio_streams:
        title = (stream.get('tags') or {}).get('title') or (stream.get('tags') or {}).get('handler_name')
        channels = stream.get('channels')
        description = media_codec_description(stream)
        if channels: description += f', {channels} ch'
        if title: description += f' ({title})'
        audio_parts.append(description)
    format_info = info.get('format', {})
    duration = format_info.get('duration') or video.get('duration')
    bit_rate = video.get('bit_rate')
    return {
        'duration': float(duration) if duration is not None else None,
        'frameRate': media_frame_rate(video),
        'width': int(video.get('width') or 0),
        'height': int(video.get('height') or 0),
        'videoCodec': media_codec_description(video),
        'videoProfile': video.get('profile'),
        'videoBitRate': int(bit_rate) if bit_rate is not None else None,
        'color': media_color_description(video),
        'audio': '; '.join(audio_parts) if audio_parts else 'No audio track',
        'container': format_info.get('format_long_name') or format_info.get('format_name') or 'Not available',
        'fileSize': path.stat().st_size,
        'videoProcessing': video_processing,
    }


def validate_video_stream_copy(source, output):
    """Reject a claimed stream-copy export if core video/HDR properties changed."""
    source_video = next(stream for stream in probe(source).get('streams', []) if stream.get('codec_type') == 'video')
    output_video = next(stream for stream in probe(output).get('streams', []) if stream.get('codec_type') == 'video')
    compared_fields = ('codec_name', 'profile', 'width', 'height', 'pix_fmt', 'color_space', 'color_transfer', 'color_primaries')
    for field in compared_fields:
        source_value = source_video.get(field)
        if source_value is not None and output_video.get(field) != source_value:
            raise ValueError(f'Video stream-copy validation failed because {field} changed.')


def video_render_args(source):
    """Choose a high-quality encoder without scaling and carry source color signaling forward."""
    info = probe(source)
    video = next(stream for stream in info.get('streams', []) if stream.get('codec_type') == 'video')
    pixel_format = str(video.get('pix_fmt') or '')
    transfer = video.get('color_transfer')
    primaries = video.get('color_primaries')
    is_hdr = transfer in ('smpte2084', 'arib-std-b67') or primaries == 'bt2020'
    try: reported_bit_depth = int(video.get('bits_per_raw_sample') or 0)
    except (TypeError, ValueError): reported_bit_depth = 0
    is_high_bit_depth = is_hdr or '10' in pixel_format or reported_bit_depth > 8
    use_hevc = is_high_bit_depth or video.get('codec_name') in ('hevc', 'h265')
    if use_hevc:
        supported = {'yuv420p', 'yuv420p10le', 'yuv422p10le', 'yuv444p10le'}
        output_pixel_format = pixel_format if pixel_format in supported else ('yuv420p10le' if is_high_bit_depth else 'yuv420p')
        args = ['-c:v', 'libx265', '-preset', 'medium', '-crf', '16', '-pix_fmt', output_pixel_format]
        encoder_parameters = []
        if primaries and primaries != 'unknown': encoder_parameters.append(f'colorprim={primaries}')
        if transfer and transfer != 'unknown': encoder_parameters.append(f'transfer={transfer}')
        if video.get('color_space') and video.get('color_space') != 'unknown':
            encoder_parameters.append(f'colormatrix={video["color_space"]}')
        if encoder_parameters:
            args += ['-x265-params', ':'.join(encoder_parameters)]
    else:
        supported = {'yuv420p', 'yuv422p', 'yuv444p', 'yuv420p10le', 'yuv422p10le', 'yuv444p10le'}
        output_pixel_format = pixel_format if pixel_format in supported else 'yuv420p'
        args = ['-c:v', 'libx264', '-preset', 'medium', '-crf', '16', '-pix_fmt', output_pixel_format]
        encoder_parameters = []
        if primaries and primaries != 'unknown': encoder_parameters.append(f'colorprim={primaries}')
        if transfer and transfer != 'unknown': encoder_parameters.append(f'transfer={transfer}')
        if video.get('color_space') and video.get('color_space') != 'unknown':
            encoder_parameters.append(f'colormatrix={video["color_space"]}')
        if encoder_parameters:
            args += ['-x264-params', ':'.join(encoder_parameters)]
    for option, field in (
        ('-color_range', 'color_range'),
        ('-color_primaries', 'color_primaries'),
        ('-color_trc', 'color_transfer'),
        ('-colorspace', 'color_space'),
    ):
        value = video.get(field)
        if value and value != 'unknown':
            args += [option, str(value)]
    return args


def validate_rendered_video(source, output):
    """Ensure an unavoidable open-caption render retains resolution and HDR base signaling."""
    source_video = next(stream for stream in probe(source).get('streams', []) if stream.get('codec_type') == 'video')
    output_video = next(stream for stream in probe(output).get('streams', []) if stream.get('codec_type') == 'video')
    for field in ('width', 'height'):
        if output_video.get(field) != source_video.get(field):
            raise ValueError('Open-caption rendering changed the source video resolution.')
    for field in ('color_space', 'color_transfer', 'color_primaries'):
        source_value = source_video.get(field)
        if source_value and source_value != 'unknown' and output_video.get(field) != source_value:
            raise ValueError(f'Open-caption rendering did not preserve {field}.')
    source_pixel_format = str(source_video.get('pix_fmt') or '')
    output_pixel_format = str(output_video.get('pix_fmt') or '')
    try: source_bit_depth = int(source_video.get('bits_per_raw_sample') or 0)
    except (TypeError, ValueError): source_bit_depth = 0
    if ('10' in source_pixel_format or source_bit_depth > 8) and '10' not in output_pixel_format:
        raise ValueError('Open-caption rendering reduced the source video bit depth.')


def commit_export(project, relative, output, temporary, video_processing=None):
    """Atomically replace the configured export and keep one project-list entry."""
    media_information = export_media_information(temporary, video_processing) if video_processing else None
    os.replace(temporary, output)
    project['exports'] = [path for path in project.get('exports', []) if path != relative]
    project['exports'].append(relative)
    project.setdefault('exportMediaInfo', {})
    if media_information:
        project['exportMediaInfo'][relative] = media_information
    else:
        project['exportMediaInfo'].pop(relative, None)
    emit('Export created', export=relative)


def commit_directory_export(project, relative, output, temporary):
    """Replace one generated export folder without exposing a partial package."""
    backup = output.with_name(f'.{output.name}.replaced-{uuid.uuid4().hex}')
    try:
        if output.exists():
            os.replace(output, backup)
        os.replace(temporary, output)
    except Exception:
        if backup.exists() and not output.exists():
            os.replace(backup, output)
        raise
    else:
        if backup.exists():
            shutil.rmtree(backup)
    project['exports'] = [path for path in project.get('exports', []) if path != relative]
    project['exports'].append(relative)
    project.setdefault('exportMediaInfo', {}).pop(relative, None)
    emit('Export created', export=relative)


def write_text_export(root, project, export_type, extension, text, replace_existing=False):
    relative, output, temporary = prepare_export_target(
        root, project, export_type, extension, replace_existing
    )
    try:
        temporary.write_text(text, encoding='utf-8')
        commit_export(project, relative, output, temporary)
    finally:
        temporary.unlink(missing_ok=True)


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


@contextlib.contextmanager
def temporary_video_caption_file(project, captions='none', content='transcript'):
    """Yield one caption source, or both closed-caption sources for a dual-track export."""
    if captions not in ('none', 'closed', 'open', 'dual-closed'):
        raise ValueError('Video captions must be none, closed, open, or dual-closed.')
    if captions == 'none':
        yield None
        return
    contents = ('transcript', 'combined') if captions == 'dual-closed' else (content,)
    suffix = '.ass' if captions == 'open' else '.srt'
    paths = []
    try:
        for source_content in contents:
            segments = validated_caption_segments(project, source_content)
            with tempfile.NamedTemporaryFile('w', encoding='utf-8', suffix=suffix, delete=False) as subtitle:
                subtitle.write(
                    ass_caption_text(project, segments, config())
                    if captions == 'open'
                    else srt_caption_text(segments)
                )
                paths.append(Path(subtitle.name))
        yield tuple(paths) if captions == 'dual-closed' else paths[0]
    finally:
        for path in paths:
            path.unlink(missing_ok=True)


def caption_canvas_size(project):
    """Return the source-video canvas required by Apple timed-text renderers."""
    width = int(project.get('width') or 0)
    height = int(project.get('height') or 0)
    if width < 1 or height < 1:
        raise ValueError('Video dimensions are missing. Prepare the project metadata before exporting closed captions.')
    return f'{width}x{height}'


def caption_input_args(captions, path, project):
    if captions not in ('closed', 'dual-closed'):
        return []
    paths = path if captions == 'dual-closed' else (path,)
    result = []
    for caption_path in paths:
        result += ['-canvas_size', caption_canvas_size(project), '-f', 'srt', '-i', caption_path]
    return result


def caption_output_args(captions, path, input_index, content):
    if captions == 'open':
        return ['-vf', f"ass=filename='{ffmpeg_filter_path(path)}'"]
    if captions == 'closed':
        title = 'English AD Transcript' if content == 'combined' else 'English Transcript'
        return [
            '-map', f'{input_index}:s:0', '-c:s', 'mov_text', '-tag:s:0', 'tx3g',
            '-metadata:s:s:0', 'language=eng', '-metadata:s:s:0', f'handler_name={title}',
            '-metadata:s:s:0', f'title={title}',
            '-disposition:s:0', '0',
        ]
    if captions == 'dual-closed':
        titles = ('English Transcript', 'English Descriptive Transcript')
        result = [
            '-map', f'{input_index}:s:0', '-map', f'{input_index + 1}:s:0',
            '-c:s', 'mov_text',
        ]
        for stream_index, title in enumerate(titles):
            result += [
                f'-tag:s:{stream_index}', 'tx3g',
                f'-metadata:s:s:{stream_index}', 'language=eng',
                f'-metadata:s:s:{stream_index}', f'handler_name={title}',
                f'-metadata:s:s:{stream_index}', f'title={title}',
                f'-disposition:s:{stream_index}', '0',
            ]
        return result
    return []


def caption_export_suffix(captions, content):
    if captions == 'none':
        return ''
    if captions == 'dual-closed':
        return ' with Transcript and Descriptive Transcript Closed Captions'
    source = 'AD Transcript' if content == 'combined' else 'Transcript'
    presentation = 'Open Captions' if captions == 'open' else 'Closed Captions'
    return f' with {source} {presentation}'


def validate_video_caption_streams(info, captions):
    subtitles = [stream for stream in info.get('streams', []) if stream.get('codec_type') == 'subtitle']
    if captions in ('closed', 'dual-closed'):
        expected_count = 2 if captions == 'dual-closed' else 1
        if len(subtitles) != expected_count or any(stream.get('codec_name') != 'mov_text' for stream in subtitles):
            raise ValueError(f'Video export is missing its {expected_count} switchable caption track(s).')
        for stream in subtitles:
            if stream.get('codec_tag_string') != 'tx3g':
                raise ValueError('Video export is missing its Apple-compatible timed-text format.')
            if int(stream.get('width') or 0) < 1 or int(stream.get('height') or 0) < 1:
                raise ValueError('Video export is missing the closed-caption presentation canvas.')
            if stream.get('tags', {}).get('language') != 'eng':
                raise ValueError('Video export is missing caption language metadata.')
        if captions == 'dual-closed':
            expected_titles = ('English Transcript', 'English Descriptive Transcript')
            actual_titles = tuple(
                stream.get('tags', {}).get('title') or stream.get('tags', {}).get('handler_name')
                for stream in subtitles
            )
            if actual_titles != expected_titles:
                raise ValueError('Dual closed-caption tracks are missing their distinct transcript titles.')
    elif captions in ('none', 'open'):
        if subtitles:
            raise ValueError('Video export unexpectedly contains a switchable subtitle track.')
    else:
        raise ValueError('Video captions must be none, closed, open, or dual-closed.')


def validate_captioned_video(output, expected_duration, captions):
    info = probe(output)
    videos = [stream for stream in info.get('streams', []) if stream.get('codec_type') == 'video']
    if len(videos) != 1:
        raise ValueError('Captioned video export did not contain exactly one video track.')
    validate_video_caption_streams(info, captions)
    duration = float(info.get('format', {}).get('duration', videos[0].get('duration', 0)))
    if abs(duration - expected_duration) > .25:
        raise ValueError('Captioned video export duration does not match the project.')


def export_captioned_video(root, project, open_captions=False, content='transcript', dual_closed=False, replace_existing=False):
    """Create either switchable closed captions or permanently burned open captions."""
    if project.get('sourceType') == 'youtube':
        raise ValueError('Captioned video export is unavailable for YouTube URL projects. Export subtitle text instead.')
    if not project.get('source'):
        raise ValueError('A local source video is required to export captioned video.')
    captions = 'dual-closed' if dual_closed else ('open' if open_captions else 'closed')
    source_title = (
        'Transcript and Descriptive Transcript'
        if dual_closed
        else 'AD Transcript' if content == 'combined' else 'Transcript'
    )
    export_type = source_title + (' Open Caption Video' if open_captions else ' Closed Caption Video')
    relative, output, export_temporary = prepare_export_target(
        root, project, export_type, 'mp4', replace_existing
    )
    with contextlib.ExitStack() as cleanup:
        cleanup.callback(export_temporary.unlink, missing_ok=True)
        caption_path = cleanup.enter_context(temporary_video_caption_file(project, captions, content))
        if open_captions:
            source = local(root, project['source'])
            common = [
                tool('ffmpeg'), '-y', '-v', 'error', '-i', source,
                '-map', '0:v:0', '-map', '0:a:0?', '-vf', f"ass=filename='{ffmpeg_filter_path(caption_path)}'",
                '-map_metadata', '0', *video_render_args(source), '-movflags', '+faststart',
                '-t', str(project['duration']),
            ]
            attempts = [['-c:a', 'copy'], ['-c:a', 'aac']]
        else:
            common = [
                tool('ffmpeg'), '-y', '-v', 'error', '-i', local(root, project['source']),
                *caption_input_args(captions, caption_path, project),
                '-map', '0:v:0', '-map', '0:a:0?',
                *caption_output_args(captions, caption_path, 1, content),
                '-movflags', '+faststart', '-t', str(project['duration']),
            ]
            attempts = [
                ['-c:v', 'copy', '-c:a', 'copy'],
                ['-c:v', 'copy', '-c:a', 'aac'],
            ]
        last_error = None
        for codecs in attempts:
            export_temporary.unlink(missing_ok=True)
            try:
                run([*common, *codecs, export_temporary])
                validate_captioned_video(export_temporary, float(project['duration']), captions)
                if open_captions:
                    validate_rendered_video(source, export_temporary)
                else:
                    validate_video_stream_copy(local(root, project['source']), export_temporary)
                commit_export(
                    project, relative, output, export_temporary,
                    'renderedOpenCaptions' if open_captions else 'copied',
                )
                return
            except ValueError as error:
                last_error = error
        export_temporary.unlink(missing_ok=True)
        raise last_error or ValueError('Captioned video export failed.')


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


def validate_closed_audio_description_export(output, expected_duration, captions='none'):
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
    validate_video_caption_streams(info, captions)


def mux_closed_audio_description(root, p, cues, captions='none', content='transcript', replace_existing=False):
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
    export_type = 'Closed Audio Description' + caption_export_suffix(captions, content)
    relative, output, export_temporary = prepare_export_target(
        root, p, export_type, 'mov', replace_existing
    )
    with temporary_video_caption_file(p, captions, content) as caption_path:
        caption_index = program_audio_input + 1 + len(cues)
        common = [
            tool('ffmpeg'),'-y','-v','error','-i',source,*silent_program_input,*narration_args,
            *caption_input_args(captions, caption_path, p),
            '-filter_complex',';'.join(filters),
            '-map','0:v:0','-map',f'{program_audio_input}:a:0','-map','[mix]',
            *caption_output_args(captions, caption_path, caption_index, content),
            '-metadata:s:a:0','language=eng','-metadata:s:a:0','handler_name=Original Audio',
            '-metadata:s:a:0','title=Original Audio',
            '-metadata:s:a:1','language=eng','-metadata:s:a:1','handler_name=English - Audio Description',
            '-metadata:s:a:1','title=English - Audio Description',
            '-disposition:a:0','default','-disposition:a:1','visual_impaired',
            '-c:a:1','aac','-movflags','+faststart','-t',str(p['duration']),
        ]
        # Open captions require video encoding. Every other mode requires a
        # validated stream copy and never silently falls back to transcoding.
        original_audio_codec = 'copy' if has_program_audio else 'aac'
        if captions == 'open':
            attempts = [
                [*video_render_args(source),'-map_metadata','0','-c:a:0',original_audio_codec],
                [*video_render_args(source),'-map_metadata','0','-c:a:0','aac'],
            ]
        else:
            attempts = [
                ['-c:v','copy','-c:a:0',original_audio_codec],
                ['-c:v','copy','-c:a:0','aac'],
            ]
        last_error = None
        for codecs in attempts:
            export_temporary.unlink(missing_ok=True)
            try:
                run([*common,*codecs,export_temporary])
                validate_closed_audio_description_export(export_temporary, float(p['duration']), captions)
                if captions == 'open':
                    validate_rendered_video(source, export_temporary)
                else:
                    validate_video_stream_copy(source, export_temporary)
                commit_export(
                    p, relative, output, export_temporary,
                    'renderedOpenCaptions' if captions == 'open' else 'copied',
                )
                return
            except ValueError as error:
                last_error = error
        export_temporary.unlink(missing_ok=True)
        raise last_error or ValueError('Closed Audio Description export failed.')


def exportable_narration_cues(root, project, allow_incomplete=False):
    cues = validate_cues(project['cues'], project['duration'], project['transcript'])
    if not cues and not allow_incomplete:
        raise ValueError('Create and synthesize AD segments before exporting.')
    available = []
    for cue in cues:
        if not narration_audio_is_usable(root, cue):
            if not allow_incomplete:
                raise ValueError('Some descriptions have missing or outdated narration. Synthesize narration or confirm an incomplete export.')
            emit('A description without current narration will not be included in the audio.', warning=True)
            continue
        available.append(cue)
    return available


def validate_audio_export(output, expected_duration):
    info = probe(output)
    audio = [stream for stream in info.get('streams', []) if stream.get('codec_type') == 'audio']
    video = [stream for stream in info.get('streams', []) if stream.get('codec_type') == 'video']
    if len(audio) != 1 or video or audio[0].get('codec_name') != 'mp3':
        raise ValueError('MP3 export did not contain exactly one MP3 audio track.')
    duration = float(info.get('format', {}).get('duration', audio[0].get('duration', 0)))
    if abs(duration - expected_duration) > .25:
        raise ValueError('MP3 export duration does not match the project.')


def export_program_audio(root, project, described=False, allow_incomplete=False, replace_existing=False):
    """Export the original soundtrack or final described mix as a high-quality MP3."""
    if project.get('sourceType') == 'youtube' or not project.get('source'):
        raise ValueError('MP3 audio export requires a local source video.')
    source = local(root, project['source'])
    if not described:
        if not project.get('hasAudio'):
            raise ValueError('The source video has no audio track to export.')
        args = [
            tool('ffmpeg'), '-y', '-v', 'error', '-i', source,
            '-map', '0:a:0', '-vn', '-c:a', 'libmp3lame', '-b:a', '320k',
            '-id3v2_version', '3', '-t', str(project['duration']),
        ]
        export_type = 'Original Video Audio'
    else:
        cues = exportable_narration_cues(root, project, allow_incomplete)
        narration_args, filters = audio_description_mix(root, project, cues, audio_only=False)
        args = [
            tool('ffmpeg'), '-y', '-v', 'error', '-i', source, *narration_args,
            '-filter_complex', ';'.join(filters), '-map', '[mix]',
            '-c:a', 'libmp3lame', '-b:a', '320k', '-id3v2_version', '3',
            '-t', str(project['duration']),
        ]
        export_type = 'Final Audio with Audio Description'
    relative, output, export_temporary = prepare_export_target(
        root, project, export_type, 'mp3', replace_existing
    )
    emit('Creating ' + export_type)
    try:
        run([*args, export_temporary])
        validate_audio_export(export_temporary, float(project['duration']))
        commit_export(project, relative, output, export_temporary)
    finally:
        export_temporary.unlink(missing_ok=True)


def export(root,p,audio_only=False,allow_incomplete=False,selectable=False,captions='none',content='transcript',replace_existing=False):
    if not audio_only and p.get('sourceType') == 'youtube':
        raise ValueError('Audio Description video export is unavailable for YouTube URL projects. Export text or narration audio instead.')
    cues = exportable_narration_cues(root, p, allow_incomplete)
    if audio_only and not cues:
        raise ValueError('Generate narration for at least one AD segment before exporting narration audio.')
    if selectable:
        if not p.get('source'):
            raise ValueError('A local source video is required for Closed Audio Description export.')
        emit('Adding selectable Audio Description to the video')
        mux_closed_audio_description(
            root, p, cues, captions=captions, content=content,
            replace_existing=replace_existing,
        )
        return
    args = [tool('ffmpeg'),'-y','-v','error']
    if p.get('source'): args += ['-i',local(root,p['source'])]
    elif audio_only: args += ['-f','lavfi','-i','anullsrc=r=48000:cl=stereo']
    else: raise ValueError('A local source video is required to render an Open Audio Description video. Narration-only export is available now.')
    narration_args, filters = audio_description_mix(root, p, cues, audio_only=audio_only)
    args += narration_args
    export_type = 'Narration Audio' if audio_only else 'Open Audio Description' + caption_export_suffix(captions, content)
    extension = 'm4a' if audio_only else 'mp4'
    relative, output, export_temporary = prepare_export_target(
        root, p, export_type, extension, replace_existing
    )
    try:
        with temporary_video_caption_file(p, 'none' if audio_only else captions, content) as caption_path:
            caption_index = 1 + len(cues)
            args += caption_input_args(captions, caption_path, p) if not audio_only else []
            args += ['-filter_complex',';'.join(filters)]
            if not audio_only:
                args += [
                    '-map','0:v:0',*caption_output_args(captions, caption_path, caption_index, content),
                ]
                if captions == 'open':
                    args += [*video_render_args(local(root, p['source'])), '-map_metadata', '0']
                else:
                    args += ['-c:v','copy']
            args += ['-map','[mix]','-c:a','aac','-movflags','+faststart','-t',str(p['duration']),export_temporary]
            emit('Adding narration and open captions to the video')
            run(args)
            if not audio_only:
                validate_captioned_video(export_temporary, float(p['duration']), captions)
                if captions == 'open':
                    validate_rendered_video(local(root, p['source']), export_temporary)
                else:
                    validate_video_stream_copy(local(root, p['source']), export_temporary)
            commit_export(
                p, relative, output, export_temporary,
                None if audio_only else ('renderedOpenCaptions' if captions == 'open' else 'copied'),
            )
    finally:
        export_temporary.unlink(missing_ok=True)


HLS_SEGMENT_DURATION = 6


def hls_web_export_type(audio, captions, content):
    audio_names = {
        'original': 'Original Audio',
        'closed-description': 'Closed Audio Description',
        'open-description': 'Open Audio Description',
    }
    if audio not in audio_names:
        raise ValueError('Web Playback audio must be original, closed-description, or open-description.')
    return 'Web Playback - ' + audio_names[audio] + caption_export_suffix(captions, content)


def fitted_video_size(width, height, maximum_width, maximum_height):
    """Fit a source inside one HLS rendition without upscaling or odd dimensions."""
    width, height = max(2, int(width)), max(2, int(height))
    scale = min(1.0, maximum_width / width, maximum_height / height)
    fitted_width = max(2, int(width * scale) // 2 * 2)
    fitted_height = max(2, int(height * scale) // 2 * 2)
    return fitted_width, fitted_height


def hls_video_renditions(project):
    width, height = int(project.get('width') or 0), int(project.get('height') or 0)
    if width < 1 or height < 1:
        raise ValueError('Video dimensions are missing. Prepare the project metadata before exporting Web Playback.')
    high_size = fitted_video_size(width, height, 1280, 720)
    low_size = fitted_video_size(width, height, 854, 480)
    if high_size == low_size:
        return [
            dict(name='high', size=high_size, bitrate='1400k', maxrate='1540k', buffer='2800k', bandwidth=1750000),
            dict(name='economy', size=low_size, bitrate='700k', maxrate='770k', buffer='1400k', bandwidth=1000000),
        ]
    return [
        dict(name='720p', size=high_size, bitrate='2800k', maxrate='3080k', buffer='5600k', bandwidth=3500000),
        dict(name='480p', size=low_size, bitrate='1000k', maxrate='1100k', buffer='2000k', bandwidth=1350000),
    ]


def hls_source_needs_tone_mapping(source):
    video = next(
        (stream for stream in probe(source).get('streams', []) if stream.get('codec_type') == 'video'),
        {},
    )
    return video.get('color_transfer') in ('smpte2084', 'arib-std-b67') or video.get('color_primaries') == 'bt2020'


def create_hls_video_rendition(source, project, destination, rendition, open_caption_path=None, tone_map_hdr=False):
    width, height = rendition['size']
    filters = []
    if tone_map_hdr:
        filters += [
            'zscale=t=linear:npl=100',
            'format=gbrpf32le',
            'tonemap=mobius:param=0.3:desat=0',
            'zscale=p=bt709:t=bt709:m=bt709:r=tv',
            'format=yuv420p',
        ]
    if open_caption_path is not None:
        filters.append(f"ass=filename='{ffmpeg_filter_path(open_caption_path)}'")
    filters.append(f'scale={width}:{height}')
    playlist = destination / f"{rendition['name']}.m3u8"
    segments = destination / f"{rendition['name']}-%05d.ts"
    run([
        tool('ffmpeg'), '-y', '-v', 'error', '-i', source,
        '-map', '0:v:0', '-an', '-sn', '-vf', ','.join(filters),
        '-c:v', 'libx264', '-preset', 'medium', '-profile:v', 'high', '-level:v', '4.0',
        '-pix_fmt', 'yuv420p', '-b:v', rendition['bitrate'], '-maxrate', rendition['maxrate'],
        '-bufsize', rendition['buffer'], '-sc_threshold', '0',
        '-force_key_frames', f'expr:gte(t,n_forced*{HLS_SEGMENT_DURATION})',
        '-f', 'hls', '-hls_time', str(HLS_SEGMENT_DURATION), '-hls_playlist_type', 'vod',
        '-hls_flags', 'independent_segments', '-hls_segment_filename', segments,
        '-t', str(project['duration']), playlist,
    ])


def create_hls_audio_rendition(root, project, destination, name, described=False, allow_incomplete=False):
    source = local(root, project['source'])
    playlist = destination / f'{name}.m3u8'
    segments = destination / f'{name}-%05d.ts'
    if described:
        cues = exportable_narration_cues(root, project, allow_incomplete)
        narration_args, filters = audio_description_mix(root, project, cues, audio_only=False)
        inputs = ['-i', source, *narration_args]
        mapping = ['-filter_complex', ';'.join(filters), '-map', '[mix]']
    elif project.get('hasAudio'):
        inputs = ['-i', source]
        mapping = ['-map', '0:a:0']
    else:
        inputs = ['-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo']
        mapping = ['-map', '0:a:0']
    run([
        tool('ffmpeg'), '-y', '-v', 'error', *inputs, *mapping, '-vn', '-sn',
        '-c:a', 'aac', '-profile:a', 'aac_low', '-b:a', '192k', '-ar', '48000', '-ac', '2',
        '-f', 'hls', '-hls_time', str(HLS_SEGMENT_DURATION), '-hls_playlist_type', 'vod',
        '-hls_segment_filename', segments, '-t', str(project['duration']), playlist,
    ])


def webvtt_timestamp(seconds):
    milliseconds = max(0, int(round(float(seconds) * 1000)))
    return f'{milliseconds // 3600000:02}:{milliseconds // 60000 % 60:02}:{milliseconds // 1000 % 60:02}.{milliseconds % 1000:03}'


def write_hls_subtitle_rendition(project, destination, name, content):
    segments = validated_caption_segments(project, content)
    vtt_name = f'{name}.vtt'
    lines = ['WEBVTT', 'X-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:0', '']
    for index, segment in enumerate(segments, 1):
        lines += [
            str(index),
            f"{webvtt_timestamp(segment['start'])} --> {webvtt_timestamp(segment['end'])}",
            segment['text'],
            '',
        ]
    (destination / vtt_name).write_text('\n'.join(lines), encoding='utf-8')
    duration = float(project['duration'])
    (destination / f'{name}.m3u8').write_text(
        '#EXTM3U\n'
        '#EXT-X-VERSION:3\n'
        f'#EXT-X-TARGETDURATION:{max(1, math.ceil(duration))}\n'
        '#EXT-X-MEDIA-SEQUENCE:0\n'
        '#EXT-X-PLAYLIST-TYPE:VOD\n'
        f'#EXTINF:{duration:.3f},\n'
        f'{vtt_name}\n'
        '#EXT-X-ENDLIST\n',
        encoding='utf-8',
    )


def hls_attribute(value):
    return str(value).replace('\\', '\\\\').replace('"', '\\"')


def write_hls_master(project, destination, renditions, audio, captions, content):
    lines = ['#EXTM3U', '#EXT-X-VERSION:3', '#EXT-X-INDEPENDENT-SEGMENTS']
    lines.append(
        '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Original Audio",LANGUAGE="en",'
        'DEFAULT=YES,AUTOSELECT=YES,URI="audio/original.m3u8"'
    )
    if audio == 'closed-description':
        lines.append(
            '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English - Audio Description",LANGUAGE="en",'
            'DEFAULT=NO,AUTOSELECT=YES,CHARACTERISTICS="public.accessibility.describes-video",'
            'URI="audio/described.m3u8"'
        )
    elif audio == 'open-description':
        lines[-1] = (
            '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English - Audio Description",LANGUAGE="en",'
            'DEFAULT=YES,AUTOSELECT=YES,CHARACTERISTICS="public.accessibility.describes-video",'
            'URI="audio/described.m3u8"'
        )

    subtitle_tracks = []
    if captions == 'dual-closed':
        subtitle_tracks = [
            ('transcript', 'English Transcript', 'transcript'),
            ('ad-transcript', 'English Descriptive Transcript', 'combined'),
        ]
    elif captions == 'closed':
        subtitle_tracks = [
            ('ad-transcript', 'English Descriptive Transcript', 'combined')
            if content == 'combined'
            else ('transcript', 'English Transcript', 'transcript')
        ]
    for name, title, _ in subtitle_tracks:
        lines.append(
            '#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subtitles",'
            f'NAME="{hls_attribute(title)}",LANGUAGE="en",DEFAULT=NO,AUTOSELECT=YES,FORCED=NO,'
            'CHARACTERISTICS="public.accessibility.transcribes-spoken-dialog,public.accessibility.describes-music-and-sound",'
            f'URI="subtitles/{name}.m3u8"'
        )

    for rendition in renditions:
        width, height = rendition['size']
        codecs = 'avc1.640028,mp4a.40.2' + (',wvtt' if subtitle_tracks else '')
        attributes = [
            f"BANDWIDTH={rendition['bandwidth']}",
            f'RESOLUTION={width}x{height}',
            f'CODECS="{codecs}"',
            'AUDIO="audio"',
        ]
        if subtitle_tracks:
            attributes.append('SUBTITLES="subtitles"')
        lines += ['#EXT-X-STREAM-INF:' + ','.join(attributes), f"video/{rendition['name']}.m3u8"]
    (destination / 'master.m3u8').write_text('\n'.join(lines) + '\n', encoding='utf-8')


def write_hls_web_files(project, destination):
    title = html.escape(str(project.get('name') or 'VidiStudio Web Playback'))
    width, height = fitted_video_size(project.get('width') or 16, project.get('height') or 9, 960, 540)
    (destination / 'index.html').write_text(f'''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title}</title>
  <link href="https://vjs.zencdn.net/8.23.4/video-js.css" rel="stylesheet">
</head>
<body>
  <main>
    <h1>{title}</h1>
    <video-js id="vidistudio-player" class="vjs-default-skin vjs-big-play-centered" controls preload="metadata" width="960" height="540">
      <source src="master.m3u8" type="application/x-mpegURL">
      <p class="vjs-no-js">Enable JavaScript to play this HLS video.</p>
    </video-js>
    <p><a href="master.m3u8">Open the HLS master playlist</a></p>
  </main>
  <script src="https://vjs.zencdn.net/8.23.4/video.min.js"></script>
  <script>videojs('vidistudio-player', {{fluid: true, aspectRatio: '{width}:{height}'}});</script>
</body>
</html>
''', encoding='utf-8')
    (destination / 'README.txt').write_text(
        'VidiStudio Web Playback (HLS)\n\n'
        'Upload this entire folder to one location on an HTTP or HTTPS web server. '\
        'Open index.html to use the included Video.js player, or load master.m3u8 from your own Video.js player.\n\n'
        'Recommended MIME types:\n'
        '  .m3u8  application/vnd.apple.mpegurl\n'
        '  .ts    video/mp2t\n'
        '  .vtt   text/vtt\n\n'
        'If the player and media use different origins, configure CORS for GET requests. '\
        'Do not rename or move individual files inside this folder because the playlists use relative URLs.\n',
        encoding='utf-8',
    )


def validate_hls_web_export(destination, project, renditions, audio, captions):
    master = (destination / 'master.m3u8').read_text(encoding='utf-8')
    if '#EXT-X-STREAM-INF:' not in master or 'AUDIO="audio"' not in master:
        raise ValueError('Web Playback export is missing its HLS video or audio declarations.')
    if audio == 'closed-description' and 'public.accessibility.describes-video' not in master:
        raise ValueError('Web Playback export is missing Audio Description accessibility metadata.')
    if captions in ('closed', 'dual-closed') and 'SUBTITLES="subtitles"' not in master:
        raise ValueError('Web Playback export is missing its switchable caption declarations.')
    expected_duration = float(project['duration'])
    for rendition in renditions:
        info = probe(destination / 'video' / f"{rendition['name']}.m3u8")
        videos = [stream for stream in info.get('streams', []) if stream.get('codec_type') == 'video']
        if len(videos) != 1 or videos[0].get('codec_name') != 'h264':
            raise ValueError('Web Playback export is missing an H.264 video rendition.')
        duration = float(info.get('format', {}).get('duration', videos[0].get('duration', 0)))
        if abs(duration - expected_duration) > .75:
            raise ValueError('Web Playback video duration does not match the project.')
    audio_names = ('original', 'described') if audio == 'closed-description' else (
        ('described',) if audio == 'open-description' else ('original',)
    )
    for name in audio_names:
        info = probe(destination / 'audio' / f'{name}.m3u8')
        streams = [stream for stream in info.get('streams', []) if stream.get('codec_type') == 'audio']
        if len(streams) != 1 or streams[0].get('codec_name') != 'aac':
            raise ValueError('Web Playback export is missing an AAC audio rendition.')
    if not (destination / 'index.html').is_file() or not (destination / 'README.txt').is_file():
        raise ValueError('Web Playback export is missing its Video.js player or hosting instructions.')


def export_hls_web(root, project, audio='closed-description', captions='none', content='transcript',
                   allow_incomplete=False, replace_existing=False):
    """Create an adaptive HLS VOD folder for Video.js and native HLS players."""
    if project.get('sourceType') == 'youtube' or not project.get('source'):
        raise ValueError('Web Playback export requires a local source video.')
    if captions not in ('none', 'closed', 'open', 'dual-closed'):
        raise ValueError('Web Playback captions must be none, closed, open, or dual-closed.')
    export_type = hls_web_export_type(audio, captions, content)
    relative = export_relative_path(root, project, export_type, 'folder').removesuffix('.folder')
    output = root / relative
    if output.exists() and not replace_existing:
        raise ValueError('An export with these options already exists. Confirm replacement to overwrite it.')
    temporary = output.with_name(f'.{output.name}.generating-{uuid.uuid4().hex}')
    try:
        (temporary / 'video').mkdir(parents=True)
        (temporary / 'audio').mkdir()
        source = local(root, project['source'])
        renditions = hls_video_renditions(project)
        tone_map_hdr = hls_source_needs_tone_mapping(source)
        with temporary_video_caption_file(project, 'open' if captions == 'open' else 'none', content) as open_caption_path:
            for rendition in renditions:
                emit(f"Creating {rendition['name']} Web Playback video")
                create_hls_video_rendition(
                    source, project, temporary / 'video', rendition,
                    open_caption_path=open_caption_path,
                    tone_map_hdr=tone_map_hdr,
                )
        if audio in ('original', 'closed-description'):
            emit('Creating original Web Playback audio')
            create_hls_audio_rendition(root, project, temporary / 'audio', 'original')
        if audio in ('closed-description', 'open-description'):
            emit('Creating described Web Playback audio')
            create_hls_audio_rendition(
                root, project, temporary / 'audio', 'described', described=True,
                allow_incomplete=allow_incomplete,
            )
        if captions in ('closed', 'dual-closed'):
            (temporary / 'subtitles').mkdir()
            tracks = [('transcript', 'transcript'), ('ad-transcript', 'combined')] if captions == 'dual-closed' else [
                ('ad-transcript', 'combined') if content == 'combined' else ('transcript', 'transcript')
            ]
            for name, track_content in tracks:
                write_hls_subtitle_rendition(project, temporary / 'subtitles', name, track_content)
        write_hls_master(project, temporary, renditions, audio, captions, content)
        write_hls_web_files(project, temporary)
        validate_hls_web_export(temporary, project, renditions, audio, captions)
        commit_directory_export(project, relative, output, temporary)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


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
    for key in ('thumbnails', 'transcript', 'cues', 'exports', 'undoStack', 'redoStack', 'transcriptUndoStack', 'transcriptRedoStack'):
        p[key] = []
    p['exportMediaInfo'] = {}
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
    if 'transcript' in selected or 'history' in selected:
        p['transcriptUndoStack'] = []
        p['transcriptRedoStack'] = []
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
        p['exportMediaInfo'] = {}
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
    parser.add_argument('command',choices=['reanalyze-transcript-segment','undo-transcript','redo-transcript','reanalyze-segment','prepare-analysis-video','check-video-availability','cleanup-project','clear-generated','delete-generated','delete-segment-audio','list-models','preview-tts','import-video','probe-video','generate-thumbnails','transcribe','generate-summary','generate-ad-cues','synthesize-tts','export-final-video','export-selectable-video','export-closed-audio-description-video','export-open-audio-description-video','export-closed-caption-video','export-dual-closed-caption-video','export-open-caption-video','export-original-audio','export-described-audio','export-hls','save-cues','save-segments','doctor',*parity.COMMANDS])
    parser.add_argument('--project',type=Path); parser.add_argument('--video',type=Path); parser.add_argument('--library',type=Path); parser.add_argument('--input',type=Path)
    parser.add_argument('--content',choices=['transcript','summary','descriptions','combined'],default='descriptions'); parser.add_argument('--url'); parser.add_argument('--name'); parser.add_argument('--timestamp',type=float,default=0); parser.add_argument('--duration',type=float); parser.add_argument('--segment'); parser.add_argument('--format',choices=['srt','vtt','txt','json','md'],default='srt'); parser.add_argument('--changed',action='store_true'); parser.add_argument('--start-stage',default='transcribe')
    parser.add_argument('--output', type=Path); parser.add_argument('--text')
    parser.add_argument('--component', action='append', choices=['transcript','summary','descriptions','narration','thumbnails','exports','history'], default=[])
    parser.add_argument('--allow-incomplete-narration',action='store_true',help='Export video or narration audio omitting missing/outdated narration after explicit confirmation.')
    parser.add_argument('--replace-existing',action='store_true',help='Replace the existing export for the same configuration after explicit confirmation.')
    parser.add_argument('--captions', choices=['none','closed','open','dual-closed'], default='none', help='Add no transcript, one switchable caption track, two switchable transcript tracks, or permanently rendered captions to an Audio Description video.')
    parser.add_argument('--web-audio', choices=['original','closed-description','open-description'], default='closed-description', help='Choose the audio presentation for a Web Playback HLS package.')
    args=parser.parse_args()
    if args.command == 'preview-tts':
        preview_tts(args.output, args.text); return
    if args.command == 'list-models':
        list_models(); return
    core=SimpleNamespace(**globals())
    if args.command in ('import-youtube','validate-config'):
        parity.execute(args,None,None,core);return
    if args.command=='doctor':
        emit('VidiStudio is ready',python=platform.python_version(),ffmpeg=tool('ffmpeg'),ffprobe=tool('ffprobe')); return
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
        p=dict(schemaVersion=2,id=str(uuid.uuid4()),name=args.video.stem,source=source,duration=duration,width=video.get('width',0),height=video.get('height',0),hasAudio=any(s['codec_type']=='audio' for s in streams),createdAt=time.time(),updatedAt=time.time(),thumbnails=[],transcript=[],summary='',cues=[],exports=[],exportMediaInfo={},status='Imported',transcriptGenerated=False,summaryGenerated=False,descriptionsGenerated=False)
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
                result=cleanup_project_storage(root,p);emit('Project cleanup complete',removedFiles=result['files'],removedBytes=result['bytes'])
            elif args.command in ('undo-transcript', 'redo-transcript'):
                restore_transcript(p, redo=args.command == 'redo-transcript')
            elif args.command=='reanalyze-transcript-segment':
                if not args.input: raise ValueError('Choose a transcript range to analyze.')
                reanalyze_transcript_segment(root,p,json.loads(args.input.read_text()))
            elif args.command=='reanalyze-segment':
                if not args.input: raise ValueError('Choose a segment to analyze.')
                reanalyze_segment(root,p,json.loads(args.input.read_text()))
            elif args.command in ('prepare-analysis-video','check-video-availability'):
                if p.get('sourceType') == 'youtube' or not p.get('source'):
                    raise ValueError('YouTube videos are accessed directly; no preparation is needed.')
                client=gemini_client()
                try:
                    if args.command=='prepare-analysis-video': reusable_video(root,p,client)
                    else: remote_video_status(root,p,client)
                finally: client.close()
            elif args.command=='clear-generated': clear_generated(root,p)
            elif args.command=='delete-generated': delete_generated_components(root,p,args.component)
            elif args.command=='delete-segment-audio': delete_segment_audio(root,p,args.segment)
            elif args.command=='probe-video': atomic_json(root/'metadata/probe.json',probe(local(root,p['source'])))
            elif args.command=='generate-thumbnails': thumbnails(root,p)
            elif args.command in ('transcribe','generate-summary','generate-ad-cues'):
                validate_analysis_prerequisites(args.command, root, p)
                ai_video(root,p,args.command)
            elif args.command=='synthesize-tts': synthesize(root,p,args.segment,args.changed)
            elif args.command in ('export-final-video','export-open-audio-description-video'):
                export(root,p,allow_incomplete=args.allow_incomplete_narration,captions=args.captions,content=args.content,replace_existing=args.replace_existing)
            elif args.command in ('export-selectable-video','export-closed-audio-description-video'):
                export(root,p,allow_incomplete=args.allow_incomplete_narration,selectable=True,captions=args.captions,content=args.content,replace_existing=args.replace_existing)
            elif args.command=='export-closed-caption-video': export_captioned_video(root,p,content=args.content,replace_existing=args.replace_existing)
            elif args.command=='export-dual-closed-caption-video': export_captioned_video(root,p,dual_closed=True,replace_existing=args.replace_existing)
            elif args.command=='export-open-caption-video': export_captioned_video(root,p,open_captions=True,content=args.content,replace_existing=args.replace_existing)
            elif args.command=='export-original-audio': export_program_audio(root,p,replace_existing=args.replace_existing)
            elif args.command=='export-described-audio': export_program_audio(root,p,described=True,allow_incomplete=args.allow_incomplete_narration,replace_existing=args.replace_existing)
            elif args.command=='export-hls':
                export_hls_web(
                    root,p,audio=args.web_audio,captions=args.captions,content=args.content,
                    allow_incomplete=args.allow_incomplete_narration,replace_existing=args.replace_existing,
                )
            elif args.command=='save-cues':
                if not args.input: raise ValueError('--input is required.')
                cues=validate_cues(json.loads(args.input.read_text()),p['duration'],p['transcript'])
                track_cue_origins(cues,p['cues']);parity.remember(p);p['cues']=cues
                p['descriptionsGenerated']=True
                p['exports']=[]
                p['exportMediaInfo']={}
            elif args.command=='save-segments':
                if not args.input: raise ValueError('--input is required.')
                payload=json.loads(args.input.read_text())
                if not isinstance(payload,dict) or not isinstance(payload.get('transcript'),list) or not isinstance(payload.get('cues'),list):
                    raise ValueError('Editable segments input must contain transcript and cues lists.')
                save_segments(p,payload['transcript'],payload['cues'])
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
