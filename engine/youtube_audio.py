"""Temporary public YouTube soundtrack retrieval for described-audio exports."""
import contextlib
import os
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import parity

DOWNLOAD_TIMEOUT = 900
DOWNLOAD_ATTEMPTS = 3
RETRY_DELAYS = (2, 4)
MAX_AUDIO_BYTES = 2 * 1024 * 1024 * 1024
DOWNLOAD_ERROR = ('YouTube audio could not be downloaded. Check your connection and that the video '
                  'is public, then try again. If YouTube blocks the download, import your original '
                  'video as a local project and export its described audio instead.')


def javascript_runtime():
    suffix = '.exe' if os.name == 'nt' else ''
    bundled = Path(sys.executable).parent / 'media' / ('deno' + suffix)
    if bundled.is_file():
        return bundled
    # Source builds use the same locked runtime that gets copied into the app.
    from deno._find_deno import find_deno_bin
    return Path(find_deno_bin())


def original_audio_format(context):
    formats = [item for item in context['formats']
               if item.get('vcodec') == 'none' and item.get('acodec') not in (None, 'none')]
    original = [item for item in formats if 'original' in str(item.get('format_note', '')).lower()
                or str(item.get('language', '')).endswith('-orig')]
    if not formats:
        raise ValueError('This YouTube video has no downloadable audio-only track.')
    yield (original or formats)[-1]


def download(url, directory, emit, ffmpeg_path=None):
    """Worker: no browser cookies, login, external config, or saved stream URLs."""
    import yt_dlp
    url = parity.youtube_url(url)

    class QuietLogger:
        def debug(self, message): pass
        def warning(self, message): pass
        def error(self, message): pass

    last_update = 0

    def progress(status):
        nonlocal last_update
        downloaded = status.get('downloaded_bytes', 0)
        if downloaded > MAX_AUDIO_BYTES:
            raise ValueError('The YouTube audio is too large to download. Import your original video instead.')
        now = time.monotonic()
        if status['status'] == 'downloading' and now - last_update >= 1:
            total = status.get('total_bytes') or status.get('total_bytes_estimate')
            percentage = min(100, round(downloaded * 100 / total)) if total else None
            emit('Downloading original YouTube audio' + (f' — {percentage}%' if percentage is not None else ''),
                 exportProgress=min(0.25, downloaded / total * 0.25) if total else None)
            last_update = now

    options = {
        'format': original_audio_format, 'noplaylist': True, 'quiet': True,
        'logger': QuietLogger(), 'progress_hooks': [progress],
        'outtmpl': str(Path(directory) / 'soundtrack.%(ext)s'),
        'cachedir': False, 'socket_timeout': 20, 'retries': 2, 'fragment_retries': 2,
        'extractor_retries': 2, 'max_filesize': MAX_AUDIO_BYTES,
        'js_runtimes': {'deno': {'path': str(javascript_runtime())}},
        'remote_components': set(),
    }
    if ffmpeg_path:
        options['ffmpeg_location'] = str(Path(ffmpeg_path).parent)
    for attempt in range(DOWNLOAD_ATTEMPTS):
        last_update = 0
        try:
            # Re-extract stream details and discard failed/partial files before
            # trying again. A stale output must never be used as the soundtrack.
            with tempfile.TemporaryDirectory(prefix='attempt-', dir=directory) as temporary:
                attempt_options = dict(options, outtmpl=str(Path(temporary) / 'soundtrack.%(ext)s'))
                with yt_dlp.YoutubeDL(attempt_options) as downloader:
                    info = downloader.extract_info(url, download=False)
                    if not info or info.get('_type', 'video') != 'video':
                        raise ValueError('Choose one public YouTube video.')
                    if info.get('is_live') or info.get('live_status') in ('is_live', 'is_upcoming', 'post_live'):
                        raise ValueError('Wait until the YouTube live video has finished processing before exporting.')
                    if info.get('availability') not in (None, 'public'):
                        raise ValueError('The YouTube video must be public before its audio can be exported.')
                    downloader.process_info(info)
                files = [item for item in Path(temporary).glob('soundtrack.*')
                         if item.is_file() and item.suffix not in ('.part', '.ytdl')]
                if len(files) != 1 or not files[0].stat().st_size:
                    raise yt_dlp.utils.DownloadError(DOWNLOAD_ERROR)
                if files[0].stat().st_size > MAX_AUDIO_BYTES:
                    raise ValueError('The YouTube audio is too large to download. Import your original video instead.')
                files[0].replace(Path(directory) / files[0].name)
            return
        except (yt_dlp.utils.DownloadError, OSError):
            if attempt + 1 == DOWNLOAD_ATTEMPTS:
                raise ValueError(DOWNLOAD_ERROR) from None
        except Exception:
            # Downloader errors may contain temporary signed stream URLs. Keep
            # them out of stdout, application logs, and saved project errors.
            # Validation failures and cancellation do not start another attempt.
            raise ValueError(DOWNLOAD_ERROR) from None
        emit(f'YouTube audio download failed. Retrying — attempt {attempt + 2} of {DOWNLOAD_ATTEMPTS}',
             exportProgress=None)
        time.sleep(RETRY_DELAYS[attempt])


def stop_worker(process):
    if process.poll() is None:
        try:
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
                if process.poll() is None:
                    process.kill()
            else:
                os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()


@contextlib.contextmanager
def soundtrack(url, emit):
    """Bound the entire download and kill its runtime on timeout/cancellation."""
    url = parity.youtube_url(url)
    with tempfile.TemporaryDirectory(prefix='vidistudio-youtube-audio-') as temporary:
        command = [sys.executable]
        if not getattr(sys, 'frozen', False):
            command.append(str(Path(__file__).with_name('vidistudio_engine.py')))
        command += ['download-youtube-audio', '--url', url, '--output', temporary]
        emit('Downloading original YouTube audio', exportProgress=None)
        process = subprocess.Popen(command, stderr=subprocess.DEVNULL, start_new_session=os.name != 'nt')
        try:
            deadline = time.monotonic() + DOWNLOAD_TIMEOUT
            while process.poll() is None:
                if time.monotonic() >= deadline:
                    raise ValueError('YouTube audio download timed out. Try again, or import your original video.')
                try:
                    process.wait(timeout=.25)
                except subprocess.TimeoutExpired:
                    pass
            if process.returncode:
                raise ValueError(DOWNLOAD_ERROR)
            files = [item for item in Path(temporary).glob('soundtrack.*')
                     if item.is_file() and item.suffix not in ('.part', '.ytdl')]
            if len(files) != 1 or not files[0].stat().st_size or files[0].stat().st_size > MAX_AUDIO_BYTES:
                raise ValueError(DOWNLOAD_ERROR)
            yield files[0]
        finally:
            stop_worker(process)
