"""Create retained export fixtures and audit codecs, metadata, caption content and timing.

Run with .venv/bin/python. --engine selects the packaged executable. The native
inspector must be compiled from the production metadata writer plus the Swift
harness in tests/export_track_inspector.swift before running this audit.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'engine'))
import vidistudio_engine as engine


def require(condition, detail):
    if not condition:
        raise AssertionError(detail)


def title(stream):
    tags = stream.get('tags', {})
    return tags.get('title') or tags.get('name') or tags.get('handler_name')


def cues_from_text(text):
    rows = []
    for block in re.split(r'\n\s*\n', text.replace('\r', '').strip()):
        lines = block.splitlines()
        timing = next((index for index, line in enumerate(lines) if ' --> ' in line), None)
        if timing is None: continue
        def seconds(value):
            hour, minute, second = value.strip().split()[0].replace(',', '.').split(':')
            return int(hour)*3600 + int(minute)*60 + float(second)
        start, end = lines[timing].split(' --> ')
        rows.append((seconds(start), seconds(end), '\n'.join(lines[timing+1:])))
    return rows


def check_cues(actual, expected):
    require(len(actual) == len(expected), f'Caption count differs: {actual} / {expected}')
    for row, cue in zip(actual, expected):
        require(row[2] == cue['text'] and abs(row[0]-cue['start']) <= .0011
                and abs(row[1]-cue['end']) <= .0011, f'Caption content/timing differs: {row} / {cue}')


def audit(args):
    folder = args.output.resolve()
    (folder/'source').mkdir(parents=True, exist_ok=True)
    (folder/'audio-description').mkdir(exist_ok=True)
    ffmpeg = engine.tool('ffmpeg')
    engine.run([ffmpeg, '-y', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=24',
                '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000', '-t', '6',
                '-c:v', 'libx264', '-c:a', 'pcm_s16le', folder/'source/video.mov'])
    speech = folder/'audio-description/narration.aiff'
    engine.run(['/usr/bin/say', '-o', speech, 'A moving test pattern.'])
    engine.run([ffmpeg, '-y', '-v', 'error', '-i', speech, folder/'audio-description/narration.wav'])
    duration = float(engine.probe(folder/'audio-description/narration.wav')['format']['duration'])
    require(duration < 3.5, 'System narration is too long for the fixture')
    project = dict(schemaVersion=2, id='export-track-audit', name='Export Track Audit', sourceType='upload',
                   source='source/video.mov', duration=6, width=320, height=180, hasAudio=True,
                   transcript=[dict(id='t', start=.25, end=1.25, text='Original audio test tone.')],
                   cues=[dict(id='ad', start=2, end=2+duration+.05, text='A moving test pattern.',
                              audioText='A moving test pattern.', audioDuration=duration,
                              audio='audio-description/narration.wav')], summary='', exports=[])
    (folder/'project.json').write_text(json.dumps(project))
    config = folder/'settings.json'
    config.write_text('{}')
    prefix = [str(args.engine.resolve())] if args.engine else [sys.executable, str(ROOT/'engine/vidistudio_engine.py')]

    def cli(command, *options):
        result = subprocess.run([*prefix, command, '--project', str(folder), '--replace-existing', *options],
                                capture_output=True, text=True, env=os.environ | {'VIDISTUDIO_CONFIG': str(config)}, timeout=90)
        require(result.returncode == 0, result.stdout+result.stderr)
        return folder/json.loads((folder/'project.json').read_text())['exports'][-1]

    records = []
    caption_choices = [('none', 'transcript'), ('closed', 'transcript'), ('closed', 'combined'),
                       ('dual-closed', 'transcript'), ('open', 'transcript'), ('open', 'combined')]
    for format in engine.VIDEO_EXPORT_FORMATS:
        for audio in ('original', 'closed-description', 'open-description'):
            for captions, content in caption_choices:
                if audio == 'original' and captions == 'none': continue
                command = ('export-dual-closed-caption-video' if captions == 'dual-closed' else
                           'export-open-caption-video' if captions == 'open' else 'export-closed-caption-video') if audio == 'original' else (
                           'export-closed-audio-description-video' if audio == 'closed-description' else 'export-open-audio-description-video')
                path = cli(command, '--media-format', format, '--captions', captions, '--content', content)
                native = None
                if format != 'mkv':
                    options = ['--finalize'] if format == 'mov' else []
                    if audio != 'original': options += ['--described']
                    result = subprocess.run([str(args.inspector.resolve()), str(path), *options], capture_output=True, text=True, timeout=30)
                    require(result.returncode == 0, result.stdout+result.stderr)
                    native = json.loads(result.stdout.splitlines()[-1])
                    require(native['playable'], f'AVFoundation cannot play {path}')
                    require(all(row['selected'] for rows in native['groups'].values() for row in rows), f'Unselectable native track: {path}')
                info = engine.probe(path)
                audio_tracks = [item for item in info['streams'] if item['codec_type'] == 'audio']
                subtitle_tracks = [item for item in info['streams'] if item['codec_type'] == 'subtitle']
                expected_names = ['Original Audio', 'English - Audio Description'] if audio == 'closed-description' else [
                    'Original Audio' if audio == 'original' else 'English - Audio Description']
                require([title(track) for track in audio_tracks] == expected_names, f'Audio names differ: {path}')
                require(all(track['codec_name'] == 'aac' and track['tags']['language'] == 'eng' for track in audio_tracks), f'Audio codec/language differs: {path}')
                require(audio_tracks[0]['disposition']['default'] == 1, f'Incorrect default audio: {path}')
                if format != 'mov' and audio != 'original':
                    require(audio_tracks[-1]['disposition']['visual_impaired'] == 1, f'Missing described audio flag: {path}')
                if format == 'mov':
                    native_audio = native['tracks']['audio']
                    require(len(native_audio) == len(audio_tracks), f'Native audio options differ: {path}')
                    require(native_audio[-1]['describesVideo'] == (audio != 'original'), f'Apple audio characteristic differs: {path}')
                engine.validate_video_caption_streams(info, captions)
                if captions in ('closed', 'dual-closed'):
                    contents = ('transcript', 'combined') if captions == 'dual-closed' else (content,)
                    for index, track_content in enumerate(contents):
                        extracted = engine.run([ffmpeg, '-v', 'error', '-i', path, '-map', f'0:s:{index}', '-f', 'srt', '-'])
                        check_cues(cues_from_text(extracted), engine.validated_caption_segments(project, track_content))
                        if format != 'mov' and track_content == 'combined':
                            require(subtitle_tracks[index]['disposition']['descriptions'] == 1, f'Missing descriptive-text flag: {path}')
                    if format == 'mov':
                        native_subtitles = [row for row in native['groups']['subtitles'] if not row['forced']]
                        require(len(native_subtitles) == len(contents), f'Native subtitle options differ: {path}')
                        for row, track_content in zip(native_subtitles, contents):
                            require(row['spokenDialog'] and not row['musicAndSound'], f'Incorrect Apple transcript semantics: {path}')
                            require(row['describesVideo'] == (track_content == 'combined'), f'Incorrect Apple descriptive text semantics: {path}')
                if captions != 'open': engine.validate_video_stream_copy(folder/project['source'], path)
                # Decode all media, not just container headers.
                engine.run([ffmpeg, '-v', 'error', '-i', path, '-map', '0:v:0', '-map', '0:a', '-f', 'null', '-'])
                records.append(dict(kind='video', format=format, audio=audio, captions=captions, content=content,
                                    path=str(path), streams=info['streams'], native=native))
        print(f'PASS: {format.upper()} audio/caption combinations', flush=True)
    for format in ('srt', 'vtt'):
        for content in ('transcript', 'combined'):
            path = cli('export-subtitles', '--format', format, '--content', content)
            check_cues(cues_from_text(path.read_text()), project['transcript'] if content == 'transcript' else sorted(project['transcript'] + project['cues'], key=lambda cue: cue['start']))
            records.append(dict(kind='text', format=format, content=content, path=str(path)))
    for audio in ('original', 'closed-description', 'open-description'):
        for captions, content in caption_choices:
            path = cli('export-hls', '--web-audio', audio, '--captions', captions, '--content', content)
            master = (path/'master.m3u8').read_text()
            require('describes-music-and-sound' not in master, 'HLS falsely tagged as SDH')
            if audio != 'original': require('public.accessibility.describes-video' in master, 'HLS missing AD characteristic')
            if captions in ('closed', 'dual-closed'):
                contents = ('transcript', 'combined') if captions == 'dual-closed' else (content,)
                for track_content in contents:
                    name = 'ad-transcript' if track_content == 'combined' else 'transcript'
                    check_cues(cues_from_text((path/'subtitles'/f'{name}.vtt').read_text()), engine.validated_caption_segments(project, track_content))
            records.append(dict(kind='web', audio=audio, captions=captions, content=content, path=str(path), master=master))
        print(f'PASS: Web Playback {audio} caption combinations', flush=True)
    report = folder/'track-audit.json'
    report.write_text(json.dumps(dict(engine=str(args.engine or ENGINE_PATH), sourceAudio='pcm_s16le',
                                      language='English fixture; exporter currently uses en/eng', records=records), indent=2))
    print(f'PASS: {len(records)} retained exports; report: {report}')


ENGINE_PATH = ROOT/'engine/vidistudio_engine.py'
if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--engine', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT/'build/export-track-audit')
    parser.add_argument('--inspector', type=Path, default=ROOT/'build/export-track-inspector')
    audit(parser.parse_args())
