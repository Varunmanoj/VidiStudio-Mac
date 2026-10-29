"""Compile the production Markdown transformer into a native harness."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


source = (ROOT / 'VidiStudio/MarkdownSummaryEditor.swift').read_text()
types = [declaration(source, marker) for marker in (
    'enum MarkdownCommand:', 'struct MarkdownEdit:', 'enum MarkdownTransformer '
)]
build = ROOT / 'build/markdown-test'
build.mkdir(parents=True, exist_ok=True)
production = build / 'ProductionMarkdown.swift'
production.write_text('import Foundation\n' + '\n\n'.join(types))
env = os.environ | {'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(build / 'modules'),
                str(production), str(ROOT / 'tests/markdown_transformer_harness.swift'),
                '-o', str(build / 'markdown-harness')], check=True, env=env)
subprocess.run([str(build / 'markdown-harness')], check=True, env=env)
