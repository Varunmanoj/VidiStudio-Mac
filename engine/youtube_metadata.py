"""Validated, credential-free YouTube metadata shared by the desktop engines."""
import json
import math
import time
from pathlib import Path

PRIVATE_MESSAGE = ('Private Video Cannot Be Opened. This video is private. '
                   'Signing in to Google does not give Gemini access. '
                   'Choose a public or unlisted video, or import your original local video.')
FIELDS = ('videoID', 'title', 'description', 'channelID', 'channelTitle', 'duration',
          'visibility', 'publishedAt', 'thumbnailURL', 'captionsAvailable', 'tags',
          'language', 'audioLanguage', 'categoryID', 'embeddable', 'uploadStatus',
          'liveStatus', 'viewCount', 'likeCount', 'commentCount', 'fetchedAt', 'playlists', 'openedFromPlaylist', 'playlistChannelTitle', 'playlistLookupStatus')

def validate(value, video_id=None):
    if not isinstance(value, dict):
        raise ValueError('YouTube details must be an object.')
    data = {key: value[key] for key in FIELDS if key in value}
    if video_id and data.get('videoID') != video_id:
        raise ValueError('YouTube details belong to a different video.')
    if data.get('visibility') == 'private':
        raise ValueError(PRIVATE_MESSAGE)
    if data.get('visibility') not in ('public', 'unlisted'):
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
    data['fetchedAt'] = time.time()
    return data

def read(path, video_id):
    return validate(json.loads(Path(path).read_text(encoding='utf-8')), video_id)

def guard(project):
    if project.get('sourceType') == 'youtube' and project.get('youtubeMetadata', {}).get('visibility') == 'private':
        raise ValueError(PRIVATE_MESSAGE)


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
