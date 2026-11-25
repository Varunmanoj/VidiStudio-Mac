"""Validated, credential-free YouTube metadata shared by the desktop engines."""
import json
import math
import time
from pathlib import Path

PRIVATE_MESSAGE = 'Private YouTube videos are not supported.'
PRIVATE_ANALYSIS_MESSAGE = 'Private YouTube video analysis is not supported.'
ANALYSIS_COMMANDS = {'analyze', 'regenerate-all', 'analyze-video', 'transcribe', 'generate-summary',
                     'generate-ad-cues', 'reanalyze-segment', 'reanalyze-transcript-segment', 'capture-frame',
                     'prepare-analysis-video', 'check-video-availability'}
FIELDS = ('videoID', 'title', 'description', 'channelID', 'channelTitle', 'duration',
          'visibility', 'publishedAt', 'thumbnailURL', 'captionsAvailable', 'tags',
          'language', 'audioLanguage', 'categoryID', 'embeddable', 'uploadStatus',
          'liveStatus', 'viewCount', 'likeCount', 'commentCount', 'fetchedAt', 'playlists', 'openedFromPlaylist', 'playlistChannelTitle', 'playlistLookupStatus')

def validate(value, video_id=None, private_owner=None):
    if not isinstance(value, dict):
        raise ValueError('YouTube details must be an object.')
    data = {key: value[key] for key in FIELDS if key in value}
    if video_id and data.get('videoID') != video_id:
        raise ValueError('YouTube details belong to a different video.')
    if data.get('visibility') not in ('public', 'unlisted', 'private'):
        raise ValueError('This YouTube video is unavailable. Check the video and account permissions.')
    duration = data.get('duration')
    if isinstance(duration, bool) or not isinstance(duration, (float, int)) or not math.isfinite(duration) or duration <= 0:
        raise ValueError('Video duration is not available yet. Wait for YouTube processing to finish.')
    if data.get('liveStatus') in ('live', 'upcoming') or data.get('uploadStatus') in ('failed', 'rejected', 'deleted', 'uploaded'):
        raise ValueError('This video is live, scheduled, or has not finished processing on YouTube.')
    def playlist(value):
        if not isinstance(value, dict): raise ValueError('Invalid YouTube playlist details.')
        clean = {key: str(value.get(key) or '') for key in ('id', 'title', 'description', 'visibility', 'publishedAt')}
        count = value.get('count')
        clean['count'] = count if isinstance(count, int) and not isinstance(count, bool) and count >= 0 else None
        return clean
    if data.get('playlists') is not None:
        if not isinstance(data['playlists'], list): raise ValueError('Invalid YouTube playlist list.')
        data['playlists'] = [playlist(item) for item in data['playlists']]
    if data.get('openedFromPlaylist') is not None: data['openedFromPlaylist'] = playlist(data['openedFromPlaylist'])
    if data['visibility'] == 'private':
        if not private_owner or not data.get('channelID'):
            raise ValueError(PRIVATE_MESSAGE)
        private_owner(data.get('videoID'), data['channelID'])
    data['fetchedAt'] = time.time()
    return data

def read(path, video_id, private_owner=None):
    return validate(json.loads(Path(path).read_text(encoding='utf-8')), video_id, private_owner)


def private_channel(project):
    details = project.get('youtubeMetadata') or {}
    return project.get('youtubePrivateChannelID') or (details.get('channelID') if details.get('visibility') == 'private' else None)


def is_private(project):
    return bool(private_channel(project)) or (project.get('youtubeMetadata') or {}).get('visibility') == 'private'


def store(project, details):
    project['youtubeMetadata'] = details
    project['duration'] = details['duration']
    if details['visibility'] == 'private':
        project['youtubePrivateChannelID'] = details['channelID']
    else:
        project.pop('youtubePrivateChannelID', None)


def guard(project, private_owner=None):
    if project.get('sourceType') != 'youtube' or not is_private(project):
        return
    channel = private_channel(project)
    if not private_owner or not channel:
        raise ValueError(PRIVATE_MESSAGE)
    from parity import youtube_url
    private_owner(youtube_url(project['youtubeURL']).split('=')[-1], channel)


def clear(root, project):
    """Remove API metadata and downloaded caption copies after explicit user action."""
    removed = []
    project.pop('youtubeMetadata', None)
    if project.pop('youtubeCaptionSource', None):
        # Caption imports are retained in history too; remove all copies together.
        project['transcript'] = [row for row in project.get('transcript', [])
                                 if row.get('origin') not in ('imported', 'imported_modified') or
                                 not str(row.get('originSource', '')).startswith('YouTube captions')]
        for key in ('transcriptUndoStack', 'transcriptRedoStack', 'transcriptUndo', 'transcriptRedo'): project.pop(key, None)
        project.pop('transcriptAudioSource', None)
        asset = project.get('importedAssets', {}).get('transcript', {})
        if asset.get('path'):
            path = (Path(root) / asset['path']).resolve()
            if Path(root).resolve() in path.parents: removed.append(path)
            project['importedAssets'].pop('transcript', None)
        project.pop('lastImportReport', None)
        project['transcriptGenerated'] = bool(project['transcript'])
    return removed


def expire(root, project, now=None):
    """Expire API response/source caches; saved editable transcript is project content."""
    now = time.time() if now is None else now
    removed = []
    changed = False
    details = project.get('youtubeMetadata')
    if details and now - details.get('fetchedAt', 0) >= 30 * 86400:
        project.pop('youtubeMetadata', None)
        changed = True
    source = project.get('youtubeCaptionSource')
    if source and not source.get('cacheExpired') and now - source.get('fetchedAt', 0) >= 30 * 86400:
        asset = project.get('importedAssets', {}).get('transcript', {})
        if asset.get('path'):
            path = (Path(root) / asset['path']).resolve()
            if Path(root).resolve() in path.parents: removed.append(path)
            project['importedAssets'].pop('transcript', None)
            changed = True
        # Keep a local source label rather than a cached track resource.
        source.pop('trackID', None)
        source.pop('name', None)
        source['cacheExpired'] = True
        changed = True
    return changed, removed
