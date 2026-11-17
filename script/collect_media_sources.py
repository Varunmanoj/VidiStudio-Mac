#!/usr/bin/env python3
"""Collect source evidence for an existing Mac media bundle; fail closed on gaps.

This does not certify a public release or substitute a newer source version.
Only checksum-pinned archives or exact git commits are accepted. Installed
Homebrew recipes retain embedded patches and build/resource instructions.
"""
import argparse
import concurrent.futures
import hashlib
import json
import re
import shutil
import subprocess
import urllib.parse
from pathlib import Path


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def source_inputs(recipe):
    lines = recipe.splitlines()
    found = []
    for index, line in enumerate(lines):
        match = re.match(r'^(\s*)url "([^"]+)"', line)
        if not match or '#{' in match[2]:
            continue
        indent, url = len(match[1]), match[2]
        following = []
        for next_line in lines[index + 1:]:
            if next_line.strip() and len(next_line) - len(next_line.lstrip()) <= indent and not re.match(r'\s*(?:sha256|version|mirror)\b', next_line):
                break
            following.append(next_line)
        text = '\n'.join(following)
        revision = re.search(r'revision:\s*"([a-f0-9]{40})"', text)
        checksum = re.search(r'^\s*sha256 "([a-f0-9]{64})"', text, re.M)
        if url.endswith('.git') and revision:
            found.append(dict(url=url, revision=revision[1]))
        elif checksum:
            found.append(dict(url=url, sha256=checksum[1]))
    return list({json.dumps(item, sort_keys=True): item for item in found}.values())


def collect(item, output):
    result = dict(item)
    try:
        folder = output / item['component'] / 'sources'
        folder.mkdir(parents=True, exist_ok=True)
        if 'revision' in item:
            revision = item['revision']
            cache = folder / (revision + '.git')
            if not cache.exists():
                subprocess.run(['git', 'init', '--bare', str(cache)], check=True, capture_output=True)
            subprocess.run(['git', '-C', str(cache), 'fetch', '--depth=1', item['url'], revision], check=True, capture_output=True, timeout=150)
            actual = subprocess.check_output(['git', '-C', str(cache), 'rev-parse', 'FETCH_HEAD'], text=True).strip()
            if actual != revision:
                raise ValueError('Fetched git commit does not match recipe')
            archive = folder / (revision + '.tar.gz')
            subprocess.run(['git', '-C', str(cache), 'archive', '--format=tar.gz', '--prefix=source/', '-o', str(archive.resolve()), revision], check=True, capture_output=True)
            paths = subprocess.check_output(['git', '-C', str(cache), 'ls-tree', '-r', revision], text=True)
            if any(line.startswith('160000 ') for line in paths.splitlines()):
                result['gap'] = 'Git submodule sources require separate collection'
            shutil.rmtree(cache)
            result['verification'] = 'exact-git-commit'
        else:
            name = Path(urllib.parse.unquote(urllib.parse.urlsplit(item['url']).path)).name or 'source.tar'
            archive = folder / (item['sha256'][:16] + '-' + name)
            if not archive.exists() or digest(archive) != item['sha256']:
                temporary = archive.with_name(archive.name + '.partial')
                # Use the host curl TLS trust store; never disable verification.
                subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error',
                                '--connect-timeout', '15', '--max-time', '180',
                                '--output', str(temporary), item['url']],
                               check=True, capture_output=True, timeout=190)
                if digest(temporary) != item['sha256']:
                    temporary.unlink()
                    raise ValueError('Source SHA-256 differs from installed Homebrew recipe')
                temporary.replace(archive)
            result['verification'] = 'recipe-sha256'
        result.update(path=str(archive.relative_to(output)), actual_sha256=digest(archive), bytes=archive.stat().st_size, status='collected')
    except Exception as error:
        detail = str(error)
        if isinstance(error, subprocess.CalledProcessError):
            detail += ': ' + error.stderr.decode(errors='replace')[-600:]
        result.update(status='missing', error=detail)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('provenance', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--cellar', type=Path, default=Path('/opt/homebrew/Cellar'))
    parser.add_argument('--workers', type=int, default=6)
    parser.add_argument('--extra-inputs', type=Path, action='append', default=[],
                        help='Additional checksum/commit-pinned inputs, e.g. Cargo.lock crate sources')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    provenance = json.loads(args.provenance.read_text())
    (args.output / 'media-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    items, gaps = [], []
    for name, version in sorted(set((p['formula'], p['version']) for p in provenance)):
        component = name + '-' + version
        prefix = args.cellar / name / version
        recipes = list((prefix / '.brew').glob('*.rb'))
        folder = args.output / component
        folder.mkdir(exist_ok=True)
        if len(recipes) != 1:
            gaps.append(dict(component=component, reason='Exact installed recipe not found'))
            continue
        recipe = recipes[0].read_text()
        shutil.copy2(recipes[0], folder / recipes[0].name)
        receipt = prefix / 'INSTALL_RECEIPT.json'
        if receipt.exists():
            data = json.loads(receipt.read_text())
            data.get('source', {}).pop('path', None)
            (folder / receipt.name).write_text(json.dumps(data, indent=2) + '\n')
        inputs = source_inputs(recipe)
        if not inputs:
            gaps.append(dict(component=component, reason='No checksum/commit-pinned source input parsed'))
        items.extend(dict(component=component, **source) for source in inputs)
        # Build recipes may fetch generated/vendor dependencies not expressible
        # as literal Homebrew resources. Preserve and flag these for review.
        if any(token in recipe for token in ['std_cargo_args', 'cargo "', 'git submodule', 'fetch --', 'curl ', 'wget ']):
            gaps.append(dict(component=component, reason='Recipe includes additional vendor/build-time source fetching; audit required'))
    for extra in args.extra_inputs:
        items.extend(json.loads(extra.read_text()))
    items = list({json.dumps(item, sort_keys=True): item for item in items}.values())
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(collect, item, args.output) for item in items]
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            results.append(result)
            print(result['status'], result['component'], result.get('error', result.get('path')), flush=True)
            (args.output / 'source-manifest.json').write_text(json.dumps(dict(complete=False, inputs=results, review_gaps=gaps), indent=2) + '\n')
    missing = [r for r in results if r['status'] != 'collected' or r.get('gap')]
    report = dict(complete=False, collected=sum(r['status'] == 'collected' for r in results), missing_inputs=len(missing), inputs=results, review_gaps=gaps,
                  note='Source collection evidence only. Exact binary provenance, all recipe resources/vendor dependencies, notices and build instructions require final review.')
    (args.output / 'source-manifest.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['complete', 'collected', 'missing_inputs', 'review_gaps']}), flush=True)
    return 1 if missing or gaps else 0


if __name__ == '__main__':
    raise SystemExit(main())
