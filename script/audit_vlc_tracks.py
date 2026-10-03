"""Read and select exported tracks using the installed VLC library without a UI.

Run with DYLD_LIBRARY_PATH=/Applications/VLC.app/Contents/MacOS/lib .venv/bin/python.
"""
import ctypes as c
import json
import os
from pathlib import Path
import sys
import time

vlc_root = Path('/Applications/VLC.app/Contents/MacOS')
os.environ['VLC_PLUGIN_PATH'] = str(vlc_root/'plugins')
lib = c.CDLL(str(vlc_root/'lib/libvlc.5.dylib'))
class Description(c.Structure): pass
Description._fields_ = [('id', c.c_int), ('name', c.c_char_p), ('next', c.POINTER(Description))]

def fn(name, result, *args):
    function = getattr(lib, 'libvlc_' + name)
    function.restype = result
    function.argtypes = args
    return function

ptr = c.c_void_p
new = fn('new', ptr, c.c_int, c.POINTER(c.c_char_p))
release = fn('release', None, ptr)
media_new = fn('media_new_path', ptr, ptr, c.c_char_p)
media_release = fn('media_release', None, ptr)
player_new = fn('media_player_new_from_media', ptr, ptr)
player_release = fn('media_player_release', None, ptr)
play = fn('media_player_play', c.c_int, ptr)
pause = fn('media_player_set_pause', None, ptr, c.c_int)
stop = fn('media_player_stop', None, ptr)
state = fn('media_player_get_state', c.c_int, ptr)
free_list = fn('track_description_list_release', None, c.POINTER(Description))
version = fn('get_version', c.c_char_p)

options = (c.c_char_p*4)(b'--intf=dummy', b'--aout=dummy', b'--vout=dummy', b'--quiet')
instance = new(4, options)
assert instance, 'VLC could not initialize'
records = []
try:
    root = Path(sys.argv[1]).resolve()
    for format in ('mkv', 'mov', 'mp4', 'm4v'):
        path = root/'exports'/('Export Track Audit - Closed Audio Description with Transcript and Descriptive Transcript Closed Captions.'+format)
        media = media_new(instance, str(path).encode())
        player = player_new(media)
        try:
            assert play(player) == 0
            deadline = time.monotonic()+10
            while state(player) not in (3, 6, 7) and time.monotonic() < deadline:
                time.sleep(.05)
            assert state(player) == 3, f'VLC did not start {path}'
            pause(player, 1)
            tracks = {}
            for category, getter, setter, active in (
                ('audio', 'audio_get_track_description', 'audio_set_track', 'audio_get_track'),
                ('subtitles', 'video_get_spu_description', 'video_set_spu', 'video_get_spu'),
            ):
                head = fn(getter, c.POINTER(Description), ptr)(player)
                current = head
                rows = []
                try:
                    while current:
                        row = current.contents
                        if row.id >= 0:
                            result = fn(setter, c.c_int, ptr, c.c_int)(player, row.id)
                            deadline = time.monotonic()+2
                            while fn(active, c.c_int, ptr)(player) != row.id and time.monotonic() < deadline:
                                time.sleep(.01)
                            selected = result == 0 and fn(active, c.c_int, ptr)(player) == row.id
                            assert selected, f'VLC cannot select {category} {row.id}: {path}'
                            rows.append(dict(id=row.id, name=(row.name or b'').decode(errors='replace'), selected=selected))
                        current = row.next
                finally:
                    free_list(head)
                assert len(rows) == 2, f'VLC expected two {category} tracks: {path}: {rows}'
                assert rows[0]['name'] != rows[1]['name'], f'VLC collapsed {category} labels: {rows}'
                if category == 'subtitles':
                    assert 'Transcript' in rows[0]['name'] and 'Descriptive Transcript' in rows[1]['name'], rows
                elif format != 'mov':
                    assert 'Original Audio' in rows[0]['name'] and 'Audio Description' in rows[1]['name'], rows
                tracks[category] = rows
            records.append(dict(format=format, path=str(path), tracks=tracks))
            print(f'PASS: VLC {format.upper()} loads and selects both AAC audio tracks and both caption tracks; names: {tracks}', flush=True)
        finally:
            stop(player); player_release(player); media_release(media)
finally:
    release(instance)
report = root/'vlc-track-audit.json'
report.write_text(json.dumps(dict(version=version().decode(), records=records), indent=2))
print(f'VLC library audit: {report}')
