"""Run the production Summary draft/save actions without touching project files."""
from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'VidiStudio/ContentView.swift').read_text()

def declaration(marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

methods = '\n'.join(declaration(marker) for marker in (
    'private func startSummaryEditing()',
    'private func commitSummaryEdits()',
    'private func toggleSummaryEditMode()',
))
harness = (ROOT / 'tests/summary_editing_harness.swift').read_text()
build = ROOT / 'build/summary-editing-test'
build.mkdir(parents=True, exist_ok=True)
production = build / 'SummaryEditing.swift'
production.write_text(harness.replace('// PRODUCTION_ACTIONS', methods))
env = os.environ | {'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(build / 'modules'),
                str(production), '-o', str(build / 'summary-editing-harness')], check=True, env=env)
subprocess.run([str(build / 'summary-editing-harness')], check=True)
