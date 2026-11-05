"""Portable original soundtracks and independent YouTube audio preferences.

All mutations are called under the engine's project lock. Inspection is read-only.
"""
from __future__ import annotations

import contextlib
import copy
import hashlib
import math
import os
import tempfile
from pathlib import Path

import import_assets
import youtube_audio

COMMANDS = ['inspect-original-audio', 'import-original-audio', 'set-audio-sources',
            'confirm-original-audio', 'remove-original-audio']
TOLERANCE = 0.1
DEFAULTS = dict(export='youtube', playback='youtube', transcription='youtube')


class YouTubeAudioUnavailable(ValueError):
    """Only soundtrack retrieval failed; a supplied original can replace it."""


def error_metadata(error):
    return {'recovery': 'choose-original-audio'} if isinstance(error, YouTubeAudioUnavailable) else {}


def preferences(project):
    return DEFAULTS | (project.get('audioSources') or {})


def fingerprint(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def timing(audio_duration, video_duration):
    video_duration = import_assets.duration_of(dict(duration=video_duration))
    difference = abs(audio_duration - video_duration) if video_duration else None
    return dict(audioDuration=audio_duration, videoDuration=video_duration,
                difference=difference, status='unverified' if video_duration is None else
                'matched' if difference <= TOLERANCE + 1e-9 else 'mismatch')


def needs_confirmation(asset, duration):
    result = timing(asset['duration'], duration)
    if result['status'] == 'matched':
        return False
    return not (asset.get('timingAccepted') is True
                and asset.get('confirmedVideoDuration') == result['videoDuration'])


def warning(result):
    if result['videoDuration'] is None:
        message = 'Duration could not be verified against the YouTube video.'
    else:
        message = (f"Audio duration: {result['audioDuration']:.3f}s. "
                   f"Video duration: {result['videoDuration']:.3f}s. "
                   f"Difference: {result['difference']:.3f}s.")
    return message + (' Audio starts at zero. Excess audio is omitted and shorter audio ends in silence; '
                      'audio is never stretched. Review audio timing and choose Import Anyway to continue.')


def original_path(root, project, core, check_hash=True):
    asset = project.get('originalAudio')
    if not asset:
        raise ValueError('Import original audio first, or choose YouTube audio.')
    source = core.local(root, asset['path'])
    if not source.is_file():
        raise ValueError('The imported original audio is missing. Choose Audio File to repair it.')
    if check_hash and fingerprint(source) != asset.get('sha256'):
        raise ValueError('The imported original audio has changed. Import it again to check its timing.')
    if needs_confirmation(asset, project.get('duration')):
        raise ValueError('Audio timing needs confirmation. ' + warning(timing(asset['duration'], project.get('duration'))))
    return source


def provenance(project, usage):
    if preferences(project)[usage] == 'imported':
        asset = project.get('originalAudio') or {}
        return dict(origin='imported', sourceName=asset.get('sourceName', ''), sha256=asset.get('sha256'))
    return dict(origin='youtube', youtubeURL=project.get('youtubeURL', ''))


def transcript_source_summary(rows):
    actual = [row.get('transcriptionAudioSource') or dict(origin='youtube') for row in rows]
    distinct = {(value.get('origin'), value.get('sha256'), value.get('sourceName')) for value in actual}
    return actual[0] if len(distinct) == 1 else dict(origin='mixed', sourceName='Multiple audio sources')


@contextlib.contextmanager
def soundtrack(root, project, core):
    if preferences(project)['export'] == 'imported':
        yield original_path(root, project, core)
    else:
        with contextlib.ExitStack() as cleanup:
            try:
                source = cleanup.enter_context(youtube_audio.soundtrack(project.get('youtubeURL', ''), core.emit))
            except (ValueError, OSError) as error:
                # Mark only context entry failures. Mixing/encoding errors after
                # yield and cancellation must not offer a soundtrack replacement.
                raise YouTubeAudioUnavailable(
                    'YouTube audio could not be retrieved. Choose Audio File to use a matching '
                    'soundtrack and retry this export. Your existing exports are unchanged.'
                ) from None
            yield source


@contextlib.contextmanager
def normalized_audio(root, project, start, end, core):
    source = original_path(root, project, core)
    if import_assets.duration_of(project) is None:
        raise ValueError('Open the video preview to determine the YouTube duration before transcription.')
    with tempfile.TemporaryDirectory(prefix='vidistudio-original-audio-') as temporary:
        output = Path(temporary) / 'audio.wav'
        core.run([core.tool('ffmpeg'), '-y', '-v', 'error', '-i', source,
                  '-af', f'apad,atrim=start={start}:end={end},asetpts=PTS-STARTPTS',
                  '-vn', '-ac', '1', '-ar', '16000', output])
        yield output


@contextlib.contextmanager
def upload_range(root, project, client, start, end, core):
    with normalized_audio(root, project, start, end, core) as path:
        uploaded = core.gemini_adapter.ready_file(client, path, core.emit)
        try:
            yield uploaded
        finally:
            try:
                client.files.delete(name=uploaded.name)
            except Exception:
                core.emit('The temporary audio upload could not be removed.', warning=True)


def transcribe(root, project, client, model, cfg, core):
    duration = import_assets.duration_of(project)
    if duration is None:
        raise ValueError('Open the video preview to determine the YouTube duration before transcription.')
    if 'transcribe' in model:
        result = []
        for start in range(0, math.ceil(duration), 1200):
            core.emit(f'Creating the transcript from imported audio, minute {start // 60}')
            with normalized_audio(root, project, start, min(duration, start + 1200), core) as path:
                result.extend(core.gemini_adapter.transcribe_audio(client, model, path, start, core.emit))
        return result
    pair = core.parity.media_prompt_pair(cfg, 'transcript')
    with upload_range(root, project, client, 0, duration, core) as uploaded:
        raw = core.gemini_adapter.audio_interaction(client, model, uploaded.uri, uploaded.mime_type,
            core.parity.render(pair['user_prompt'], project), pair.get('system_instruction', ''))
        return core.parity.parse_json(raw)


def add_arguments(parser):
    parser.add_argument('--soundtrack-source', choices=['youtube', 'imported'])
    parser.add_argument('--playback-audio-source', choices=['youtube', 'imported'])
    parser.add_argument('--transcription-audio-source', choices=['youtube', 'imported'])
    parser.add_argument('--allow-audio-mismatch', action='store_true')
    parser.add_argument('--expected-audio-sha256')
    parser.add_argument('--expected-video-duration', type=float)
    parser.add_argument('--ad-source', choices=['generated', 'imported'], default='generated')


def inspect(args, project, core):
    duration = import_assets.duration_of(project)
    if duration is None and project.get('youtubeURL') and os.environ.get('VIDISTUDIO_YOUTUBE_AVAILABLE') != '0':
        duration = youtube_audio.video_duration(project['youtubeURL'], core.emit)
    asset = project.get('originalAudio') or {}
    source = args.input or (core.local(args.project, asset['path']) if asset.get('path') else None)
    if source is None:
        raise ValueError('Choose original audio to inspect.')
    actual = import_assets.inspect_audio(source, core)
    return timing(actual, duration) | dict(sourceName=asset.get('sourceName', source.name)
                                          if args.input is None else source.name,
                                          sha256=fingerprint(source))


def execute(args, root, project, core):
    if project.get('sourceType') != 'youtube':
        raise ValueError('Original audio selection is available for YouTube projects.')
    if args.command == 'inspect-original-audio':
        result = inspect(args, project, core)
        if args.output:
            core.atomic_json(args.output, result)
        core.emit('Original audio inspected', audioInspection=result)
        return
    working = copy.deepcopy(project)
    created = []
    try:
        if args.command in ('import-original-audio', 'confirm-original-audio'):
            if args.command == 'import-original-audio':
                if not args.input:
                    raise ValueError('Choose original audio to import.')
                import_assets.confirm_replacement(working.get('originalAudio'), args.replace_existing)
            result = inspect(args, working, core)
            expected_hash = getattr(args, 'expected_audio_sha256', None)
            expected_duration = getattr(args, 'expected_video_duration', None)
            if (expected_hash is not None and expected_hash != result['sha256']
                    or expected_duration is not None and expected_duration != (result['videoDuration'] or 0)):
                raise ValueError('The audio file or video timing changed during review. Inspect the audio again before importing.')
            if result['status'] != 'matched' and not args.allow_audio_mismatch:
                raise ValueError('Audio timing needs confirmation. ' + warning(result))
            if args.command == 'import-original-audio':
                path = import_assets.copy_asset(root, args.input, core, created, language_specific=False)
                if fingerprint(core.local(root, path)) != result['sha256']:
                    raise ValueError('The selected audio changed while importing. Choose it again.')
                working['originalAudio'] = dict(path=path, sourceName=args.input.name,
                    duration=result['audioDuration'], sha256=result['sha256'])
                working['audioSources'] = preferences(working) | dict(export='imported')
            asset = working['originalAudio']
            if asset['sha256'] != result['sha256']:
                raise ValueError('The imported original audio changed. Import it again.')
            asset.update(validationStatus=result['status'], confirmedVideoDuration=result['videoDuration'],
                         timingAccepted=bool(args.allow_audio_mismatch))
            if result['videoDuration'] is not None:
                working['duration'] = result['videoDuration']
        if args.command == 'remove-original-audio':
            working.pop('originalAudio', None)
            working['audioSources'] = dict(DEFAULTS)
        else:
            selected = preferences(working)
            for key, argument in [('export', 'soundtrack_source'), ('playback', 'playback_audio_source'),
                                  ('transcription', 'transcription_audio_source')]:
                value = getattr(args, argument, None)
                if value is not None:
                    if value == 'imported':
                        original_path(root, working, core)
                    selected[key] = value
            working['audioSources'] = selected
        # Preferences do not rewrite transcripts or discard earlier export provenance.
        core.save(root, working)
    except BaseException:
        for path in created:
            path.unlink(missing_ok=True)
        raise
    project.clear()
    project.update(working)
    core.emit('Audio sources saved', project=str(root))
