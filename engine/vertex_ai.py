"""Vertex sessions use an explicitly selected identity and never fall back to ADC."""
import base64
import json
import mimetypes
import os
import re
import sys
from pathlib import Path
from types import SimpleNamespace


import network_activity
import youtube_metadata

MODEL_POLICY = json.loads(Path(__file__).with_name('ai-defaults.json').read_text(encoding='utf-8'))['vertexModelPolicy']
EXPRESS_MODELS = MODEL_POLICY['expressModels']
# Vertex documents this limit for a single video submitted from Cloud Storage.
MAX_CLOUD_VIDEO_SIZE_BYTES = 2 * 1024**3 - 500 * 1024
CLOUD_VIDEO_SIZE_MESSAGE = 'This video is too large for Cloud Storage analysis. Choose a smaller video.'
PROJECT_MODEL_ROWS = {row['id']: row for group in MODEL_POLICY['projectModelGroups'] for row in group['rows']}
SCOPE = 'https://www.googleapis.com/auth/cloud-platform'
YOUTUBE_SCOPE = 'https://www.googleapis.com/auth/youtube.force-ssl'
SERVICE = 'com.vidistudio.vertex-oauth'


def oauth_client():
    path = Path(__file__).with_name('vertex-desktop.json')
    if not path.is_file() and not getattr(sys, 'frozen', False):
        path = Path(__file__).resolve().parents[1] / 'Config' / 'vertex-desktop.json'
    if not path.is_file():
        raise ValueError('This installation is missing its Google sign-in configuration.')
    return json.loads(path.read_text())['installed']


def vault():
    if sys.platform == 'darwin':
        from keyring.backends.macOS import Keyring
    elif os.name == 'nt':
        from keyring.backends.Windows import WinVaultKeyring as Keyring
    else:
        raise ValueError('Google sign-in requires the desktop credential store.')
    store = Keyring()
    if os.name == 'nt':
        store.persist = 'local machine'
    return store


def sign_in():
    from google_auth_oauthlib.flow import InstalledAppFlow
    client = oauth_client()
    flow = InstalledAppFlow.from_client_config({'installed': client}, [SCOPE],
                                                autogenerate_code_verifier=True)
    creds = flow.run_local_server(host='127.0.0.1', port=0, timeout_seconds=240,
                                  authorization_prompt_message=None, prompt='consent',
                                  success_message='Google sign-in complete. Return to VidiStudio.')
    if not creds.refresh_token:
        raise ValueError('Google did not grant offline access. Reconnect in Settings.')
    save_google_sign_in(creds.refresh_token)


def save_google_sign_in(refresh_token):
    refresh_token = refresh_token.strip()
    if not refresh_token or len(refresh_token) > 8192 or not refresh_token.isascii() or any(c.isspace() for c in refresh_token):
        raise ValueError('Google sign-in could not be saved. Try again.')
    vault().set_password(SERVICE, oauth_client()['client_id'], refresh_token)


def disconnect():
    store = vault()
    account = oauth_client()['client_id']
    if store.get_password(SERVICE, account):
        store.delete_password(SERVICE, account)


def credentials(project, *, allow_missing_project=False):
    from google.oauth2.credentials import Credentials
    if not project and not allow_missing_project:
        raise ValueError('Enter your Google Cloud project ID in Settings > AI.')
    client = oauth_client()
    token = vault().get_password(SERVICE, client['client_id'])
    if not token:
        raise ValueError('Use Google sign-in in Settings > AI to connect your account.')
    return Credentials(None, refresh_token=token, token_uri='https://oauth2.googleapis.com/token',
                       client_id=client['client_id'], client_secret=client['client_secret'],
                       scopes=[SCOPE], quota_project_id=project or None)


def youtube_owner_credentials(channel_id):
    from google.oauth2.credentials import Credentials
    subject = os.environ.get('VIDISTUDIO_CLOUD_SUBJECT', '')
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,128}', subject) or not re.fullmatch(r'[A-Za-z0-9_-]{1,128}', channel_id or ''):
        raise ValueError(youtube_metadata.PRIVATE_MESSAGE)
    account = f'{subject}:{channel_id}'
    store = vault()
    if os.name == 'nt':
        refresh = store.get_password('VidiStudio/YouTube/' + account, 'YouTube refresh token')
    else:
        refresh = store.get_password('com.vidistudio.youtube', account)
    if not refresh:
        raise ValueError(youtube_metadata.PRIVATE_MESSAGE)
    client = oauth_client()
    return Credentials(None, refresh_token=refresh, token_uri='https://oauth2.googleapis.com/token',
                       client_id=client['client_id'], client_secret=client['client_secret'],
                       scopes=[YOUTUBE_SCOPE])


def require_private_youtube_owner(cfg, video_id, channel_id):
    from google.auth.transport.requests import AuthorizedSession
    if not cfg.get('vertexProject', '').strip() or not re.fullmatch(r'[A-Za-z0-9_-]{11}', video_id or ''):
        raise ValueError(youtube_metadata.PRIVATE_MESSAGE)
    try:
        with AuthorizedSession(youtube_owner_credentials(channel_id)) as session:
            response = session.get('https://www.googleapis.com/youtube/v3/videos',
                                   params={'part': 'snippet,status', 'id': video_id}, timeout=15)
            response.raise_for_status()
            matching = any(item.get('id') == video_id and
                           item.get('status', {}).get('privacyStatus') == 'private' and
                           item.get('snippet', {}).get('channelId') == channel_id
                           for item in response.json().get('items', []))
            if matching:
                owner = session.get('https://www.googleapis.com/youtube/v3/channels',
                                    params={'part': 'id', 'mine': 'true', 'maxResults': 50}, timeout=15)
                owner.raise_for_status()
                if any(channel.get('id') == channel_id for channel in owner.json().get('items', [])):
                    return
    except Exception as exc:
        # A failed or expired authorization cannot be used as proof of ownership.
        raise ValueError(youtube_metadata.PRIVATE_MESSAGE) from exc
    raise ValueError(youtube_metadata.PRIVATE_MESSAGE)


def express(cfg):
    return cfg.get('vertexAuth', 'signin') == 'express'


def model_for(cfg, stage):
    is_express = express(cfg)
    saved = cfg.get('vertexExpressModels' if is_express else 'vertexModels') or {}
    row = PROJECT_MODEL_ROWS.get(stage, {})
    policy_stage = row.get('stage', stage)
    catalog_rows = EXPRESS_MODELS if is_express else cfg.get('vertexCatalog', [])
    names = {row.get('name') if isinstance(row, dict) else row for row in catalog_rows}
    capability = MODEL_POLICY['stages'][policy_stage]
    patterns = [group['pattern'] for group in MODEL_POLICY['groups'] if group['capability'] == capability]
    compatible = sorted(name for name in names if isinstance(name, str) and any(re.fullmatch(p, name) for p in patterns))
    if not compatible:
        if is_express:
            raise ValueError('This task requires a model outside express mode. Use Google sign-in in Settings > AI.')
        raise ValueError('No compatible Vertex AI model is available. Use Test Connection in Settings > AI to refresh your models.')
    preferred = [saved.get(stage), saved.get(row.get('fallback', policy_stage)), *MODEL_POLICY['preferred'][capability]]
    return next((name for name in preferred if name in compatible), compatible[0])


def referenced_video(project):
    cloud = (project or {}).get('cloudVideo')
    return cloud if cloud and cloud.get('ownership') == 'referenced' else None


def client(cfg, project=None):
    from google import genai
    from google.genai import types
    options = types.HttpOptions(api_version='v1beta1', timeout=300000)
    if express(cfg):
        key = os.environ.get('VIDISTUDIO_VERTEX_KEY', '').strip()
        if not key:
            raise ValueError('Save a Vertex AI express API key in Settings > AI.')
        sdk = genai.Client(vertexai=True, api_key=key, http_options=options)
    else:
        reference = referenced_video(project)
        project_id = reference['project'] if reference else cfg.get('vertexProject', '').strip()
        sdk = genai.Client(vertexai=True, credentials=credentials(project_id), project=project_id,
                           location='global', http_options=options)
    return VertexSession(sdk)


class VertexSession:
    def __init__(self, sdk):
        self.models = network_activity.ClientProxy(sdk.models)
        self.interactions = self
        self.close = sdk.close

    def transcribe_audio(self, model, path, offset):
        from google.genai import types
        import gemini_adapter
        response = self.models.generate_content(
            model=model, contents=[types.Part.from_bytes(data=path.read_bytes(), mime_type='audio/wav')],
            config=types.GenerateContentConfig(audio_transcription_config=types.AudioTranscriptionConfig(
                mode='VERBATIM', word_timestamp=True, diarization=True)))
        annotations = []
        for candidate in response.candidates or []:
            for part in candidate.content.parts if candidate.content else ():
                transcript = part.audio_transcription
                if transcript:
                    for word in transcript.words or []:
                        annotations.append(dict(type='word_info', text=word.word, speaker=transcript.speaker_label or '',
                                                start_offset=word.start_offset, end_offset=word.end_offset))
        return gemini_adapter.speech_segments({'steps': [{'content': [{'annotations': annotations}]}]}, offset)

    def create(self, *, model, input, system_instruction=None, response_format=None, generation_config=None):
        from google.genai import types
        parts = []
        for item in ([input] if isinstance(input, str) else input):
            if isinstance(item, str):
                parts.append(types.Part.from_text(text=item))
            elif item['type'] == 'text':
                parts.append(types.Part.from_text(text=item['text']))
            else:
                mime = item.get('mime_type') or 'video/mp4'
                uri = item.get('uri')
                if isinstance(uri, Path):
                    limit = 256_000_000 if model.startswith('gemini-3') else 15_000_000
                    if uri.stat().st_size > limit:
                        raise ValueError('This video exceeds the inline request limit. Use Google sign-in and upload it to Cloud Storage.')
                    part = types.Part.from_bytes(data=uri.read_bytes(), mime_type=mime)
                elif 'data' in item:
                    part = types.Part.from_bytes(data=base64.b64decode(item['data']), mime_type=mime)
                else:
                    part = types.Part.from_uri(file_uri=uri, mime_type=mime)
                processing = item.get('processing')
                if isinstance(processing, dict):
                    part.video_metadata = types.VideoMetadata(**{k: v for k, v in processing.items() if k in ('fps','start_offset','end_offset')})
                parts.append(part)
        config = types.GenerateContentConfig(system_instruction=system_instruction)
        if response_format:
            config.response_mime_type = response_format['mime_type']
            config.response_json_schema = response_format.get('schema')
        result = self.models.generate_content(model=model, contents=parts, config=config)
        return SimpleNamespace(output_text=result.text or '')


def media(cfg, project, source):
    cloud = project.get('cloudVideo')
    if express(cfg):
        if cloud:
            raise ValueError('Use Google sign-in to analyze this private Cloud Storage video.')
        uri = source
    else:
        if not cloud:
            raise ValueError('Upload this video to Cloud Storage before running signed-in Vertex analysis.')
        reference = referenced_video(project)
        if reference:
            # A private URI must be in the project issuing the Vertex request.
            lookup_config = dict(cfg, vertexProject=cloud['project'], vertexBucket=cloud['bucket'])
        else:
            if cloud['project'] != cfg.get('vertexProject') or cloud['bucket'] != cfg.get('vertexBucket'):
                raise ValueError('Select the Google Cloud project and bucket shown in the video Inspector.')
            lookup_config = cfg
        from cloud_video import bucket_for
        blob = bucket_for(lookup_config).blob(cloud['object'])
        blob.reload()
        if isinstance(blob.size, int) and blob.size > MAX_CLOUD_VIDEO_SIZE_BYTES:
            raise ValueError(CLOUD_VIDEO_SIZE_MESSAGE)
        if str(blob.generation) != cloud['generation']:
            raise ValueError('The cloud video has changed. Check the object in Cloud Console before analysis.')
        if not reference and (blob.metadata or {}).get('vidistudio-project') != project['id']:
            raise ValueError('The cloud video has changed. Check the object in Cloud Console before analysis.')
        uri = 'gs://' + cloud['bucket'] + '/' + cloud['object']
        content_type = (blob.content_type or '').split(';', 1)[0].strip().lower()
        if content_type.startswith('video/'):
            return SimpleNamespace(uri=uri, mime_type=content_type)
    return SimpleNamespace(uri=uri, mime_type=mimetypes.guess_type(source.name)[0] or 'video/mp4')


def catalog(cfg):
    session = client(cfg)
    try:
        if express(cfg):
            session.models.count_tokens(model=model_for(cfg, 'summary'), contents='Connection check')
            names = EXPRESS_MODELS
        else:
            names = sorted({row.name.rsplit('/', 1)[-1] for row in session.models.list(config={'query_base': True})
                            if row.name and row.name.rsplit('/', 1)[-1].startswith('gemini-')})
        if not names:
            raise ValueError('Google returned no Gemini models for this project.')
        return [dict(name=name, displayName=name, supportedActions=['generateContent']) for name in names]
    finally:
        session.close()
