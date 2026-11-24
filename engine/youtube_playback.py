"""Portable local playback copies for YouTube projects."""

import copy
import math
import re
import time
from pathlib import Path

import import_assets
import youtube_metadata

COMMANDS = ('attach-youtube-playback', 'remove-youtube-playback', 'select-youtube-player')
VIDEO_EXPORTS = {
    'export-final-video', 'export-selectable-video', 'export-closed-audio-description-video',
    'export-open-audio-description-video', 'export-closed-caption-video', 'export-open-caption-video',
    'export-dual-closed-caption-video', 'export-hls',
}
DURATION_ERROR = 'Playback video duration does not match.'
INVALID_VIDEO = 'Choose a readable video file with a video track.'


def managed_paths(asset):
    if not isinstance(asset, dict):
        return set()
    pattern = r'playback/[a-f0-9]{32}(?:-thumbnail)?(?:\.[a-z0-9]+)?'
    return {value for value in (asset.get('path'), asset.get('thumbnail'))
            if isinstance(value, str) and re.fullmatch(pattern, value)}


def asset_path(root, value, core):
    relative = Path(value)
    return core.local(root, relative.parent) / relative.name


def remove_assets(root, asset, core):
    for value in managed_paths(asset):
        try:
            asset_path(root, value, core).unlink(missing_ok=True)
        except (OSError, ValueError):
            pass


def local_asset(root, project, core):
    if project.get('sourceType') != 'youtube':
        return None
    asset = project.get('youtubePlaybackVideo')
    if not isinstance(asset, dict) or asset.get('path') not in managed_paths(asset):
        return None
    duration, expected = asset.get('duration'), project.get('duration')
    if not all(isinstance(d, (int, float)) and math.isfinite(d) and d > 0 for d in (duration, expected)):
        return None
    return asset if abs(duration - expected) < 0.5 and core.local(root, asset['path']).is_file() else None


def analysis_settings(root, project, core):
    return dict(project, audioSources={'transcription': 'youtube'}) if local_asset(root, project, core) else project


def for_video_export(root, project, core):
    asset = local_asset(root, project, core)
    if asset is None:
        return project
    path = core.local(root, asset['path'])
    try:
        info = core.probe(path)
        streams = info.get('streams', [])
        video = next(s for s in streams if s.get('codec_type') == 'video'
                     and not s.get('disposition', {}).get('attached_pic'))
        duration = float(info['format']['duration'])
        reported = video.get('duration')
        video_duration = float(reported) if reported not in (None, 'N/A') else duration
        if not all(math.isfinite(d) and d > 0 and abs(d - project['duration']) < 0.5
                   for d in (duration, video_duration)):
            raise ValueError(DURATION_ERROR)
    except (ValueError, OSError, KeyError, TypeError, StopIteration) as exc:
        raise ValueError('Choose a matching local playback video before exporting this project.') from exc
    return dict(project, source=asset['path'], sourceType='local', hasAudio=any(s.get('codec_type') == 'audio' for s in streams),
                width=video.get('width', 0), height=video.get('height', 0), duration=duration, _exportView=True)


def execute(args, root, project, core):
    if project.get('sourceType') != 'youtube':
        raise ValueError('Local playback copies are available for YouTube projects.')
    old = project.get('youtubePlaybackVideo')
    updated = copy.deepcopy(project)
    created = []
    try:
        if args.command == 'select-youtube-player':
            if (youtube_metadata.is_private(project) or args.name not in ('youtube', 'local')
                    or local_asset(root, project, core) is None):
                raise ValueError('Switching video players requires an accessible YouTube video and its local copy.')
            updated['youtubePlaybackVideo']['useYouTubePlayer'] = args.name == 'youtube'
        elif args.command == 'remove-youtube-playback':
            updated.pop('youtubePlaybackVideo', None)
        else:
            if project.get('originalAudio') is not None:
                raise ValueError('Remove the original audio file before importing a local playback video.')
            video = args.video
            if video is None:
                raise ValueError(INVALID_VIDEO)
            import_assets.confirm_replacement(old, args.replace_existing)
            try:
                if not video.is_file():
                    raise ValueError(INVALID_VIDEO)
                info = core.probe(video)
                track = next(s for s in info.get('streams', []) if s.get('codec_type') == 'video'
                             and not s.get('disposition', {}).get('attached_pic'))
                duration = float(info['format']['duration'])
                track_duration = track.get('duration')
                video_duration = float(track_duration) if track_duration not in (None, 'N/A') else duration
            except (ValueError, OSError, KeyError, TypeError, StopIteration) as exc:
                raise ValueError(INVALID_VIDEO) from exc
            expected = project.get('duration')
            if not isinstance(expected, (float, int)) or not math.isfinite(expected) or expected <= 0:
                raise ValueError('Refresh YouTube Details before choosing a local playback video.')
            if not all(math.isfinite(value) and value > 0 for value in (duration, video_duration)):
                raise ValueError(INVALID_VIDEO)
            # YouTube normally reports whole seconds. Allow only its rounding precision.
            measured = max((duration, video_duration), key=lambda value: abs(value - expected))
            if abs(measured - expected) >= 0.5:
                raise ValueError(f'{DURATION_ERROR} YouTube is {expected:.2f} seconds and the local file is {measured:.2f} seconds.')
            last_update = 0.0

            def copy_progress(copied, total):
                nonlocal last_update
                now = time.monotonic()
                if copied not in (0, total) and now - last_update < 0.2:
                    return
                last_update = now
                fraction = min(copied / total, 1.0) if total else 0.0
                core.emit(f'Copied {copied / 1_000_000:,.1f} MB of {total / 1_000_000:,.1f} MB',
                          contentTransferProgress=fraction)

            path = import_assets.copy_asset(root, video, core, created, 'playback', language_specific=False,
                                            progress=copy_progress)
            core.emit('Creating playback thumbnail…', contentTransferProgress=1.0)
            thumbnail = Path(path).with_name(f'{Path(path).stem}-thumbnail.jpg').as_posix()
            frame = core.local(root, thumbnail)
            created.append(frame)
            try:
                core.run([core.tool('ffmpeg'), '-y', '-v', 'error', '-ss', str(min(video_duration / 4, 5)),
                          '-i', core.local(root, path), '-map', '0:V:0', '-frames:v', '1', '-vf', 'scale=480:-2', frame])
            except (ValueError, OSError) as exc:
                raise ValueError(INVALID_VIDEO) from exc
            if not frame.is_file() or frame.stat().st_size == 0:
                raise ValueError(INVALID_VIDEO)
            updated['youtubePlaybackVideo'] = dict(path=path, thumbnail=thumbnail, sourceName=video.name, duration=duration,
                                                   hasAudio=any(stream.get('codec_type') == 'audio' for stream in info['streams']))
            if isinstance(old, dict) and old.get('useYouTubePlayer') is True:
                updated['youtubePlaybackVideo']['useYouTubePlayer'] = True
        updated['updatedAt'] = time.time()
        core.atomic_json(root / 'project.json', updated)
    except BaseException:
        for asset in created:
            asset.unlink(missing_ok=True)
        raise
    if args.command != 'select-youtube-player':
        remove_assets(root, old, core)
