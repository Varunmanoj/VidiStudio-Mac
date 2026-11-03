"""Network-stage events and transport classification, with no credentials or content.

The native hosts opt into events. Nested stages remain active until their last
request finishes; ending a download before yielding prevents local export work
from being cancelled when the network subsequently disappears.
"""
import contextlib
import functools
import json
import os
import socket
import threading
import urllib.error
from collections.abc import Iterator

_depth = threading.local()


def event(service, active):
    if os.environ.get('VIDISTUDIO_NETWORK_EVENTS') == '1':
        print(json.dumps(dict(message='Connecting to ' + service if active else 'Network request finished',
                              networkService=service, networkActive=active)), flush=True)


@contextlib.contextmanager
def activity(service):
    depths = getattr(_depth, 'services', None)
    if depths is None:
        depths = _depth.services = {}
    depths[service] = depths.get(service, 0) + 1
    if depths[service] == 1:
        event(service, True)
    try:
        yield
    finally:
        depths[service] -= 1
        if depths[service] == 0:
            event(service, False)


def call(service, function, *args, **kwargs):
    with activity(service):
        result = function(*args, **kwargs)
        if isinstance(result, Iterator):
            # Model catalog APIs fetch pages lazily during iteration.
            return _iterate(service, result)
        return result


def _iterate(service, iterator):
    with activity(service):
        yield from iterator


class ClientProxy:
    def __init__(self, client):
        self._client = client

    def __getattr__(self, name):
        value = getattr(self._client, name)
        if name in ('files', 'models', 'interactions', 'caches', 'voices'):
            return ClientProxy(value)
        if callable(value) and name not in ('close', '__enter__', '__exit__'):
            return functools.partial(call, 'gemini', value)
        return value


def transport_failure(error):
    seen = set()
    while error is not None and id(error) not in seen:
        seen.add(id(error))
        if isinstance(error, urllib.error.HTTPError):
            return False
        if isinstance(error, (ConnectionError, TimeoutError, socket.gaierror, urllib.error.URLError)):
            return True
        module = type(error).__module__.split('.')[0]
        if module in ('httpx', 'httpcore', 'requests') and any(word in type(error).__name__.lower()
                for word in ('connect', 'timeout', 'network', 'transport', 'readerror', 'writeerror')):
            return True
        text = str(error).lower()
        if any(marker in text for marker in ('network is unreachable', 'no route to host',
                'name or service not known', 'nodename nor servname', 'temporary failure in name resolution',
                'connection refused', 'connection reset', 'connection aborted', 'connection timed out')):
            return True
        error = error.__cause__ or error.__context__
    return False


def credential_rejected(error):
    details = getattr(error, 'details', None) or []
    if isinstance(details, list) and any(isinstance(item, dict) and item.get('reason') in
            ('API_KEY_INVALID', 'API_KEY_EXPIRED', 'API_KEY_NOT_FOUND') for item in details):
        return True
    text = str(error).lower()
    return any(marker in text for marker in ('api_key_invalid', 'api key not valid', 'invalid api key', 'api key is not valid'))


def error_metadata(error):
    return {'failureKind': 'connectivity'} if transport_failure(error) else {}
