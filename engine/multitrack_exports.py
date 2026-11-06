"""Frozen, explicitly selected multilingual tracks for a single media container."""
import contextlib
import copy
import hashlib
import math
import tempfile
from pathlib import Path

import language_results as results
import import_assets
import audio_sources


def identity(plan):
    items = [plan.get('media', 'video'), plan.get('format', 'mkv'), plan.get('audioMode', 'selectable'),
             plan.get('captionMode', 'closed'), 'original' if plan.get('original', True) else 'no-original']
    items += ['a:' + row['resultID'] for row in plan.get('audio', [])]
    items += ['s:' + row['transcriptID'] + ':' + row.get('descriptionsID', '') for row in plan.get('captions', [])]
    return hashlib.sha256('\n'.join(items).encode()).hexdigest()[:12]


def languages(plan):
    return sorted(set(row['language'] for row in plan.get('audio', []) + plan.get('captions', []))) or ['auto']


def target_name(project, plan):
    labels = ' + '.join(results.track_title(code) for code in languages(plan))[:80]
    return project['name'][:40] + ' [' + labels + ']'


def export_type(plan):
    return 'Selected ' + ('Video' if plan.get('media', 'video') == 'video' else 'Audio') + ' Tracks ' + identity(plan)


def validate(root, project, plan, core):
    plan = copy.deepcopy(plan)
    if plan.get('media', 'video') not in ('video', 'audio'):
        raise ValueError('Choose video or audio.')
    video = plan.get('media', 'video') == 'video'
    formats = core.VIDEO_EXPORT_FORMATS if video else ('m4a', 'mka')
    core.media_export_format(plan.get('format'), formats, 'mkv' if video else 'm4a')
    if video and (project.get('sourceType') == 'youtube' or not project.get('source')):
        raise ValueError('Selected video tracks require a local source video.')
    duration = float(project.get('duration') or 0)
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError('Read the media duration before exporting tracks.')
    if plan.get('audioMode', 'selectable') not in ('selectable', 'mixed') or plan.get('captionMode', 'closed') not in ('closed', 'open'):
        raise ValueError('Choose selectable tracks or a single mixed/burned-in result.')
    audio, captions = plan.get('audio', []), plan.get('captions', [])
    if not video and captions:
        raise ValueError('Audio-only exports cannot contain captions.')
    if plan.get('audioMode') == 'mixed' and len(audio) > 1:
        raise ValueError('Mixed audio supports one AD result. Choose selectable tracks for multiple results.')
    if plan.get('captionMode') == 'open' and len(captions) > 1:
        raise ValueError('Burned-in captions support one result. Choose closed captions for multiple results.')
    if not video and not audio and not plan.get('original', True):
        raise ValueError('Choose at least one audio track.')
    for row in audio + captions:
        row['language'] = results.language(row['language'])
    if len({r['language'] for r in audio}) != len(audio) or len({r['language'] for r in captions}) != len(captions):
        raise ValueError('Choose only one audio result and one caption result per language.')
    seen = set()
    for row in audio:
        result = results.find(project, row['resultID'], saved_only=True)
        if result['kind'] not in ('descriptions', 'adAudio') or result['language'] != results.language(row['language']):
            raise ValueError('Choose a saved AD result in the track language.')
        if result['id'] in seen:
            raise ValueError('An audio result is selected more than once.')
        seen.add(result['id'])
        payload = copy.deepcopy(result['payload'])
        if result['kind'] == 'descriptions':
            cues = payload.get('cues', [])
            if not cues or any(not core.narration_audio_is_usable(root, cue) for cue in cues):
                raise ValueError('Generate current narration for every segment of the selected AD result.')
            core.validate_cues(cues, duration, [])
            for cue in cues:
                info = core.probe(core.local(root, cue['audio']))
                if not any(s.get('codec_type') == 'audio' for s in info.get('streams', [])) or float(info.get('format', {}).get('duration', 0)) > cue['end'] - cue['start'] + .02:
                    raise ValueError('A selected narration recording does not fit its segment.')
        else:
            import_assets.require_resolved_timing(dict(project, cues=[], transcript=[], **payload))
            asset = payload.get('importedAudioDescription') or {}
            if not asset.get('path') or not core.local(root, asset['path']).is_file():
                raise ValueError('The selected imported AD audio is missing.')
            if not any(s.get('codec_type') == 'audio' for s in core.probe(core.local(root, asset['path'])).get('streams', [])):
                raise ValueError('The selected imported AD file has no audio.')
        row['kind'] = result['kind']
        row['payload'] = payload
        row['title'] = results.track_title(result['language']) + ' - Audio Description'
    seen = set()
    for row in captions:
        transcript = results.find(project, row['transcriptID'], 'transcript', saved_only=True)
        if transcript['language'] != results.language(row['language']):
            raise ValueError('Choose a transcript in the caption language.')
        payload = copy.deepcopy(transcript['payload'])
        if not payload.get('transcript'):
            raise ValueError('The selected transcript is empty.')
        core.validate_transcript(payload['transcript'], duration)
        description_id = row.get('descriptionsID', '')
        if description_id:
            description = results.find(project, description_id, 'descriptions', saved_only=True)
            if description['language'] != transcript['language']:
                raise ValueError('AD Transcript selections must use the same language.')
            payload['cues'] = copy.deepcopy(description['payload'].get('cues', []))
            if not payload['cues']:
                raise ValueError('The selected descriptions are empty.')
            core.validate_cues(payload['cues'], duration, payload['transcript'])
        else:
            payload['cues'] = []
        key = (transcript['id'], description_id)
        if key in seen:
            raise ValueError('A caption track is selected more than once.')
        seen.add(key)
        row['payload'] = payload
        row['title'] = results.track_title(transcript['language']) + (' AD Transcript' if description_id else ' Transcript')
    plan['languages'] = languages(plan)
    plan['resultIDs'] = {row['resultID']: row['resultID'] for row in audio}
    for row in captions:
        for key in ('transcriptID', 'descriptionsID'):
            if row.get(key): plan['resultIDs'][row[key]] = row[key]
    # Validate generated AD against every independently selected spoken transcript.
    for row in audio:
        if row['kind'] == 'descriptions':
            for caption in captions:
                if caption['language'] == row['language'] and caption.get('descriptionsID') and caption['descriptionsID'] != row['resultID']:
                    raise ValueError('Choose the same description result for AD audio and AD Transcript in each language.')
                core.validate_cues(row['payload']['cues'], duration, caption['payload']['transcript'])
    if project.get('sourceType') != 'youtube':
        source = core.local(root, project.get('source', ''))
        if not source.is_file(): raise ValueError('The source media is missing.')
        if plan.get('original', True) and not project.get('hasAudio') and not audio and not video:
            raise ValueError('The source has no audio track.')
    return plan


def metadata(kind, index, row, default=False):
    tag = results.track_language(row['language'])
    flags = ('default+' if default else '') + 'visual_impaired' if kind == 'a' and row.get('described') else ('default' if default else '0')
    if kind == 's' and row.get('descriptionsID'): flags = 'descriptions'
    args = []
    for key, value in [('language', tag), ('title', row['title']), ('handler_name', row['title'])]:
        args += [f'-metadata:s:{kind}:{index}', f'{key}={value}']
    return args + [f'-disposition:{kind}:{index}', flags]


def execute(root, project, plan, core, replace=False):
    video = plan.get('media', 'video') == 'video'
    format = plan.get('format', 'mkv' if video else 'm4a')
    view = copy.deepcopy(project)
    view['name'] = target_name(project, plan)
    view['_exportLanguages'] = plan['languages']
    relative, output, temporary = core.prepare_export_target(root, view, export_type(plan), format, replace)
    duration = float(project['duration'])
    previous = results._export_language
    try:
        with contextlib.ExitStack() as stack:
            stack.callback(temporary.unlink, missing_ok=True)
            directory = Path(stack.enter_context(tempfile.TemporaryDirectory(prefix='vidistudio-tracks-')))
            needs_program = plan.get('original', True) or any(row['kind'] == 'descriptions' or row['payload'].get('importedAudioDescription', {}).get('mode') != 'fullMix' for row in plan.get('audio', []))
            if project.get('sourceType') == 'youtube':
                source = (stack.enter_context(audio_sources.soundtrack(root, project, core)) if needs_program else core.local(root, plan['audio'][0]['payload']['importedAudioDescription']['path']))
            else:
                source = core.local(root, project['source'])
            has_original = bool(project.get('hasAudio') or project.get('sourceType') == 'youtube')
            args = [core.tool('ffmpeg'), '-y', '-v', 'error', '-i', source]
            audio_rows = []
            if plan.get('original', True) and has_original and (plan.get('audioMode') != 'mixed' or not plan.get('audio')):
                audio_rows.append((0, dict(language=core.original_audio_language(source), title='Original Audio')))
            for number, row in enumerate(plan.get('audio', [])):
                track = directory / f'audio-{number}.m4a'
                selected = dict(project, **row['payload'])
                selected['hasAudio'] = has_original
                if row['kind'] == 'adAudio':
                    inputs, filters = import_assets.imported_mix(root, selected, core)
                else:
                    inputs, filters = core.audio_description_mix(root, selected, selected['cues'])
                core.run_export([core.tool('ffmpeg'), '-y', '-v', 'error', '-i', source, *inputs,
                                 '-filter_complex', ';'.join(filters), '-map', '[mix]', '-c:a', 'aac', '-b:a', '256k', '-t', str(duration), track], duration, message='Creating ' + row['title'])
                args += ['-i', track]
                audio_rows.append((number + 1, dict(row, described=True)))
            caption_rows = []
            for number, row in enumerate(plan.get('captions', [])):
                results._export_language = row['language']
                selected = dict(project, **row['payload'])
                mode = plan.get('captionMode', 'closed')
                path = stack.enter_context(core.temporary_video_caption_file(selected, mode, 'combined' if row.get('descriptionsID') else 'transcript'))
                if mode == 'closed':
                    input_index = 1 + len(plan.get('audio', [])) + number
                    args += core.caption_input_args('closed', path, selected)
                    caption_rows.append((input_index, row))
                else:
                    args += ['-vf', f"ass=filename='{core.ffmpeg_filter_path(path)}'"]
            if video: args += ['-map', '0:v:0']
            for index, (input_index, row) in enumerate(audio_rows):
                args += ['-map', f'{input_index}:a:0', *metadata('a', index, row, default=index == 0)]
            for index, (input_index, row) in enumerate(caption_rows):
                args += ['-map', f'{input_index}:s:0', *metadata('s', index, row)]
                if format != 'mkv': args += [f'-tag:s:{index}', 'tx3g']
            args += ['-map_metadata', '-1', '-map_chapters', '-1', '-c:a', 'aac', '-b:a', '256k']
            if video:
                args += core.video_render_args(source) if plan.get('captionMode') == 'open' and plan.get('captions') else ['-c:v', 'copy']
                args += ['-c:s', 'subrip' if format == 'mkv' else 'mov_text', *core.video_container_args(format)]
            else:
                args += ['-f', 'matroska'] if format == 'mka' else ['-f', 'ipod', '-movflags', '+faststart']
            core.run_export([*args, '-t', str(duration), temporary], duration, message='Creating selected media tracks')
            info = core.probe(temporary)
            for kind, rows in [('audio', audio_rows), ('subtitle', caption_rows)]:
                streams = [s for s in info['streams'] if s.get('codec_type') == kind]
                if len(streams) != len(rows): raise ValueError('The exported track count does not match the selection.')
                for stream, (_, row) in zip(streams, rows):
                    tags = stream.get('tags', {})
                    title = tags.get('title') or tags.get('handler_name')
                    if title != row['title'] or tags.get('language', 'und') != results.track_language(row['language']):
                        raise ValueError('The exported track labels do not match the selection.')
            if abs(float(info['format']['duration']) - duration) > .25: raise ValueError('Exported tracks do not match the media duration.')
            if video:
                if len([s for s in info['streams'] if s.get('codec_type') == 'video']) != 1: raise ValueError('The export must contain one video track.')
                if plan.get('captionMode') == 'open' and plan.get('captions'): core.validate_rendered_video(source, temporary)
                else: core.validate_video_stream_copy(source, temporary)
            processing = ('renderedOpenCaptions' if plan.get('captionMode') == 'open' and plan.get('captions') else 'copied') if video else None
            core.commit_export(project, relative, output, temporary, processing)
    finally:
        results._export_language = previous
