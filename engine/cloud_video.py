"""Private GCS videos uploaded by or referenced from portable VidiStudio projects."""
import base64
from contextlib import contextmanager
import mimetypes
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import quote, urlencode
from uuid import UUID

import vertex_ai


def bucket_for(cfg, source_project=None):
    from google.cloud import storage
    from google.auth.transport.requests import AuthorizedSession
    quota_project = (cfg.get('vertexProject') or '').strip()
    project = source_project or quota_project
    name = (cfg.get('vertexBucket') or '').strip()
    if not name or '/' in name:
        raise ValueError('Enter the bucket name in Settings > AI.')
    creds = vertex_ai.credentials(quota_project)
    client = storage.Client(project=project, credentials=creds)
    bucket = client.get_bucket(name)
    with AuthorizedSession(creds) as session:
        response = session.get('https://cloudresourcemanager.googleapis.com/v1/projects/' + quote(project, safe=''), timeout=20)
        response.raise_for_status()
        if str(bucket.project_number) != str(response.json()['projectNumber']):
            raise ValueError('Choose a bucket in the selected Google Cloud project.')
    return bucket


def filename(name):
    if not name or name in ('.', '..') or any(c in '/\\' or ord(c)<32 for c in name):
        raise ValueError('Choose a filename without folders or control characters.')
    return name


def crc32c(path):
    import google_crc32c
    crc = google_crc32c.Checksum()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            crc.update(chunk)
    return base64.b64encode(crc.digest()).decode()


class UploadReader:
    def __init__(self, stream, total, emit):
        self.stream, self.total, self.emit = stream, total, emit

    def __getattr__(self, name):
        return getattr(self.stream, name)

    def read(self, size=-1):
        data = self.stream.read(size)
        sent = self.stream.tell()
        self.emit(f'Uploading video: {sent:,} of {self.total:,} bytes', progress=sent/max(1,self.total))
        return data


def update(args, root, project, cfg, core):
    from google.api_core.exceptions import NotFound, PreconditionFailed
    source = core.local(root, project['source'])
    record = project.get('cloudVideo')
    if record and record.get('ownership') == 'referenced':
        raise PermissionError('This project references an existing Cloud Storage video.')
    prefix = f"vidistudio/{UUID(project['id'])}/"
    if record and (record['project'] != cfg.get('vertexProject') or record['bucket'] != cfg.get('vertexBucket')
                   or not record['object'].startswith(prefix)):
        raise ValueError('Select the project and bucket shown in the Inspector.')
    bucket = bucket_for(cfg)

    def inspect(blob):
        blob.reload()
        if (blob.metadata or {}).get('vidistudio-project') != project['id']:
            raise ValueError('The cloud object belongs to a different project.')
        return blob

    def remember(blob):
        project['cloudVideo'] = dict(project=cfg['vertexProject'], bucket=bucket.name,
                                     object=blob.name, generation=str(blob.generation), crc32c=blob.crc32c,
                                     **object_details(blob))
        project['sourceType'] = 'cloud'
        core.save(root, project)

    if args.command == 'cloud-upload':
        if project.get('sourceType') == 'youtube':
            raise ValueError('Choose a local video project.')
        if record:
            return
        blob = bucket.blob(prefix + filename(source.name), chunk_size=8 * 1024 * 1024)
        blob.metadata = {'vidistudio-project': project['id']}
        preview = thumbnail(source, core.tool('ffmpeg'))
        if preview:
            blob.metadata = {**blob.metadata, 'vidistudio-thumbnail-jpeg': preview}
        size = source.stat().st_size
        try:
            with source.open('rb') as stream:
                blob.upload_from_file(UploadReader(stream,size,core.emit), size=size,
                                      content_type=mimetypes.guess_type(source.name)[0] or 'video/mp4',
                                      if_generation_match=0, checksum='crc32c')
        except PreconditionFailed:
            inspect(blob)
        inspect(blob)
        if blob.crc32c != crc32c(source):
            raise ValueError('Cloud and local video checksums differ. The local project was preserved.')
        remember(blob)
        return
    if not record:
        raise ValueError('This project has no cloud video.')
    blob = bucket.blob(record['object'])
    generation = int(record['generation'])
    if args.command == 'cloud-rename':
        dest = prefix + filename(args.name)
        if dest == blob.name:
            return
        if not object_permissions(cfg, bucket.name, blob.name, dest)['rename']:
            raise PermissionError('Your Google account does not have permission to rename this video.')
        core.emit('Renaming cloud video…')
        try:
            inspect(blob)
            moved = bucket.move_blob(blob, dest, if_source_generation_match=generation, if_generation_match=0)
        except NotFound:
            moved = inspect(bucket.blob(dest))
        if inspect(moved).crc32c != record['crc32c']:
            raise ValueError('Cloud video changed during rename. Check the object in Cloud Console.')
        remember(moved)
    elif args.command == 'cloud-remove':
        if crc32c(source) != record['crc32c']:
            raise ValueError('Restore a verified local video copy before removing the cloud video.')
        delete_project_object(cfg, project['id'], record, core.emit, bucket=bucket)
        detach_cloud_video(root, project, core.save)


def detach_cloud_video(root, project, save):
    project.pop('cloudVideo')
    project['sourceType'] = 'local'
    save(root, project)


def delete_project_object(cfg, owner, record, emit, *, bucket=None):
    from google.api_core.exceptions import NotFound, PreconditionFailed

    name = record['object']
    generation = record['generation']
    expected_prefix = f'vidistudio/{UUID(owner)}/'
    if (not name.startswith(expected_prefix) or not name.removeprefix(expected_prefix)
            or not str(generation).isascii() or not str(generation).isdecimal() or int(generation) <= 0):
        raise ValueError('The recorded cloud video does not match this project.')
    if record['project'] != cfg.get('vertexProject') or record['bucket'] != cfg.get('vertexBucket'):
        raise ValueError('Select the project and bucket shown in the Inspector.')
    if bucket is None:
        bucket = bucket_for(cfg)
    emit('Checking the project’s cloud video…')
    blob = bucket.blob(name)
    try:
        blob.reload()
    except NotFound:
        emit('The project’s cloud video has already been deleted.')
        return
    if blob.generation != int(generation):
        raise ValueError('A newer cloud video has replaced this object. The project was preserved.')
    if (blob.metadata or {}).get('vidistudio-project') != owner:
        raise ValueError('The cloud object belongs to a different project.')
    if not object_permissions(cfg, bucket.name, name)['delete']:
        raise PermissionError('Your Google account does not have permission to delete this video.')
    emit('Deleting cloud video…')
    try:
        # Target the live object and recheck both its data and ownership metadata.
        bucket.blob(name).delete(if_generation_match=int(generation), if_metageneration_match=blob.metageneration)
    except NotFound:
        emit('The project’s cloud video has already been deleted.')
    except PreconditionFailed as exc:
        raise ValueError('The cloud video changed during deletion. The project was preserved.') from exc
    else:
        emit('Cloud video deleted')


def accessible_projects(cfg):
    from google.auth.transport.requests import AuthorizedSession

    projects = {}
    params = {'query': 'state:ACTIVE', 'pageSize': 100}
    with AuthorizedSession(vertex_ai.credentials(cfg.get('vertexProject', '').strip())) as session:
        while True:
            response = session.get('https://cloudresourcemanager.googleapis.com/v3/projects:search',
                                   params=params, timeout=20)
            response.raise_for_status()
            data = response.json()
            for item in data.get('projects', []):
                if item.get('state') == 'ACTIVE' and (project_id := item.get('projectId')):
                    projects[project_id] = item.get('displayName') or project_id
            if not (token := data.get('nextPageToken')):
                break
            params['pageToken'] = token
    return [dict(id=key, name=name) for key, name in
            sorted(projects.items(), key=lambda project: (project[1].casefold(), project[0]))]


def project_buckets(cfg, source_project=None):
    from google.cloud import storage
    project = cfg.get('vertexProject', '').strip()
    with storage.Client(project=project, credentials=vertex_ai.credentials(project)) as client:
        return sorted(bucket.name for bucket in client.list_buckets(project=source_project or project, timeout=30))


def object_details(blob):
    def date(value):
        return value.isoformat() if value else None

    fields = dict(size=blob.size, contentType=blob.content_type, storageClass=blob.storage_class,
                  created=date(blob.time_created), updated=date(blob.updated))
    return {key: str(value) for key, value in fields.items() if value is not None}


def thumbnail(source, ffmpeg):
    try:
        result = subprocess.run([ffmpeg, '-nostdin', '-v', 'error', '-i', str(source),
                                 '-map', '0:V:0', '-frames:v', '1', '-vf', 'scale=112:64:force_original_aspect_ratio=decrease',
                                 '-pix_fmt', 'yuvj420p', '-c:v', 'mjpeg', '-q:v', '9', '-f', 'image2pipe', 'pipe:1'],
                                capture_output=True, timeout=20, check=True)
        if 0 < len(result.stdout) <= 3000:
            return base64.b64encode(result.stdout).decode('ascii')
    except (OSError, subprocess.SubprocessError):
        pass
    return None


VIDEO_EXTENSIONS = {'.mp4', '.mov', '.m4v', '.mkv', '.avi', '.webm', '.wmv',
                    '.mpg', '.mpeg', '.3gp', '.3gpp', '.3g2', '.flv'}
VIDEO_CONTENT_TYPES = {
    'video/mp4', 'video/quicktime', 'video/x-m4v', 'video/x-matroska',
    'video/avi', 'video/msvideo', 'video/x-msvideo', 'video/vnd.avi',
    'video/webm', 'video/x-ms-wmv', 'video/mpeg', 'video/3gpp', 'video/3gpp2',
    'video/x-flv', 'video/flv',
}
GENERIC_CONTENT_TYPES = {'', 'application/octet-stream', 'binary/octet-stream'}


def is_video(blob):
    if blob.name.endswith('/'):
        return False
    content_type = (blob.content_type or '').split(';', 1)[0].strip().lower()
    if Path(blob.name).suffix.lower() in VIDEO_EXTENSIONS:
        return content_type in VIDEO_CONTENT_TYPES or content_type in GENERIC_CONTENT_TYPES
    # Use declared video metadata for objects with no filename extension.
    return not Path(blob.name).suffix and content_type in VIDEO_CONTENT_TYPES


def project_owned(blob):
    if (blob.metadata or {}).get('vidistudio-project'):
        return True
    components = blob.name.split('/')
    if len(components) > 2 and components[0] == 'vidistudio':
        try:
            UUID(components[1])
            return True
        except ValueError:
            pass
    return False


def bucket_files(cfg, name, source_project=None):
    source = dict(cfg, vertexBucket=name)
    bucket = bucket_for(source, source_project) if source_project else bucket_for(source)
    return [dict(name=blob.name, generation=str(blob.generation),
                 video=True, projectOwned=project_owned(blob),
                 thumbnail=(blob.metadata or {}).get('vidistudio-thumbnail-jpeg', '')[:4000],
                 **object_details(blob))
            for blob in bucket.list_blobs(fields='items(name,generation,contentType,size,storageClass,timeCreated,updated,metadata),nextPageToken')
            if is_video(blob)]


def preview(cfg, bucket, name, generation, limit, core, source_project=None):
    with tempfile.TemporaryDirectory(prefix='vidistudio-cloud-preview-') as tmp:
        source, _ = download(dict(cfg, vertexBucket=bucket), name, Path(tmp), limit, core.emit, generation, source_project)
        return thumbnail(source, core.tool('ffmpeg'))


def video_names(cfg):
    bucket = bucket_for(cfg)
    return [blob.name for blob in bucket.list_blobs() if is_video(blob)]


DOWNLOAD_PERMISSION_ERROR = 'Google Cloud denied permission to download this video. Check Google sign-in and your access to the object.'
DOWNLOAD_CHECK_ERROR = 'VidiStudio could not verify download permission. Check your connection and Google Cloud access, then retry.'
DOWNLOAD_CHANGED_ERROR = 'The selected file has changed. Refresh the file list and choose it again.'
DOWNLOAD_MISSING_ERROR = 'The selected video is no longer available in Cloud Storage. Refresh the file list.'
DOWNLOAD_CHECKSUM_ERROR = 'Downloaded video checksum did not match Cloud Storage. Retry the import.'


def download(cfg, name, directory, limit, emit, generation=None, source_project=None):
    import grpc
    from google.api_core.exceptions import Forbidden, NotFound, PreconditionFailed, Unauthorized
    from google.auth.exceptions import RefreshError
    from requests.exceptions import HTTPError

    emit('Checking Cloud Storage access…')
    try:
        bucket = bucket_for(cfg, source_project) if source_project else bucket_for(cfg)
        blob = bucket.blob(name)
        blob.reload()
        if generation is not None and str(blob.generation) != generation:
            raise ValueError(DOWNLOAD_CHANGED_ERROR)
        if not is_video(blob):
            raise ValueError('Choose a supported Cloud Storage video.')
        if blob.size > limit:
            raise ValueError('The selected video exceeds the supported import size.')
        try:
            with iam_permission_test(cfg, bucket.name) as (resource, allowed):
                if 'storage.objects.get' not in allowed(f'{resource}/objects/{name}', 'storage.objects.get'):
                    raise PermissionError(DOWNLOAD_PERMISSION_ERROR)
        except grpc.RpcError as exc:
            denied = getattr(exc, 'code', lambda: None)() in (grpc.StatusCode.PERMISSION_DENIED, grpc.StatusCode.UNAUTHENTICATED)
            if denied:
                raise PermissionError(DOWNLOAD_PERMISSION_ERROR) from exc
            raise ValueError(DOWNLOAD_CHECK_ERROR) from exc
        path = directory / filename(name.rsplit('/', 1)[-1])
        written = 0
        emit(f'Downloading video: 0 of {blob.size:,} bytes', progress=0)
        with blob.open('rb', chunk_size=8 * 1024 * 1024, if_generation_match=int(blob.generation)) as stream, path.open('xb') as output:
            while chunk := stream.read(8 * 1024 * 1024):
                output.write(chunk)
                written += len(chunk)
                emit(f'Downloading video: {written:,} of {blob.size:,} bytes', progress=written/max(1, blob.size))
    except (Forbidden, Unauthorized, RefreshError) as exc:
        raise PermissionError(DOWNLOAD_PERMISSION_ERROR) from exc
    except HTTPError as exc:
        if exc.response is not None and exc.response.status_code in (401, 403):
            raise PermissionError(DOWNLOAD_PERMISSION_ERROR) from exc
        raise ValueError(DOWNLOAD_CHECK_ERROR) from exc
    except NotFound as exc:
        raise ValueError(DOWNLOAD_MISSING_ERROR) from exc
    except PreconditionFailed as exc:
        raise ValueError(DOWNLOAD_CHANGED_ERROR) from exc
    emit('Verifying the downloaded video…')
    if written != blob.size or crc32c(path) != blob.crc32c:
        raise ValueError(DOWNLOAD_CHECKSUM_ERROR)
    return path, dict(project=source_project or cfg['vertexProject'].strip(), bucket=bucket.name,
                      object=name, generation=str(blob.generation), crc32c=blob.crc32c,
                      ownership='referenced', **object_details(blob))


@contextmanager
def iam_permission_test(cfg, bucket):
    from google.auth.transport.grpc import secure_authorized_channel
    from google.auth.transport.requests import Request
    from google.iam.v1.iam_policy_pb2 import TestIamPermissionsRequest, TestIamPermissionsResponse

    bucket_resource = f'projects/_/buckets/{bucket}'
    routing = (('x-goog-request-params', urlencode({'bucket': bucket_resource})),)
    with secure_authorized_channel(vertex_ai.credentials(cfg.get('vertexProject', '').strip()),
                                   Request(), 'storage.googleapis.com:443') as channel:
        test = channel.unary_unary('/google.storage.v2.Storage/TestIamPermissions',
                                  request_serializer=TestIamPermissionsRequest.SerializeToString,
                                  response_deserializer=TestIamPermissionsResponse.FromString)

        def allowed(resource, *permissions):
            return set(test(TestIamPermissionsRequest(resource=resource, permissions=permissions),
                            timeout=10, metadata=routing).permissions)

        yield bucket_resource, allowed


def object_permissions(cfg, bucket, object_name, destination=None):
    with iam_permission_test(cfg, bucket) as (bucket_resource, allowed):
        held = allowed(f'{bucket_resource}/objects/{object_name}', 'storage.objects.get', 'storage.objects.delete')
        delete = 'storage.objects.delete' in held
        # The candidate destination is checked against any object-specific IAM rules before copying.
        rename = delete and 'storage.objects.get' in held and 'storage.objects.create' in allowed(
            f'{bucket_resource}/objects/{destination}' if destination else bucket_resource, 'storage.objects.create')
        return dict(delete=delete, rename=rename)


def manage_bucket_video(cfg, args, emit):
    if not all((args.source_project, args.source_bucket, args.name, args.source_generation)):
        raise ValueError('Choose a bucket video first.')
    bucket = bucket_for(dict(cfg, vertexBucket=args.source_bucket), args.source_project)
    blob = bucket.blob(args.name)
    blob.reload()
    if str(blob.generation) != args.source_generation:
        raise ValueError('The selected file has changed. Refresh the file list and choose it again.')
    if not is_video(blob):
        raise ValueError('Choose a video to manage.')
    if project_owned(blob):
        raise ValueError('Manage this project-owned video from its project.')
    generation = int(blob.generation)
    if args.command == 'cloud-object-rename':
        prefix, separator, _ = blob.name.rpartition('/')
        destination = prefix + separator + filename(args.new_name)
        if destination == blob.name:
            return
        if not object_permissions(cfg, bucket.name, blob.name, destination)['rename']:
            raise PermissionError('Your Google account does not have permission to rename this video.')
        emit('Copying video to its new name…')
        bucket.copy_blob(blob, bucket, destination, if_source_generation_match=generation, if_generation_match=0)
        emit('Removing the old object…')
        try:
            blob.delete(if_generation_match=generation)
        except Exception as exc:
            raise ValueError('The new copy may exist. Refresh the bucket and check both names before retrying.') from exc
        emit('Cloud video renamed')
    else:
        if not object_permissions(cfg, bucket.name, blob.name)['delete']:
            raise PermissionError('Your Google account does not have permission to delete this video.')
        emit('Deleting cloud video…')
        blob.delete(if_generation_match=generation)
        emit('Cloud video deleted')
