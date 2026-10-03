"""Validate the production progress session state without launching the user interface."""
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
build = root/'build/export-progress-test'
build.mkdir(parents=True, exist_ok=True)
env = os.environ | {'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(build/'modules'),
                str(root/'VidiStudio/ExportSession.swift'), str(root/'tests/export_progress_harness.swift'),
                '-o', str(build/'export-progress-harness')], check=True, env=env)
subprocess.run([str(build/'export-progress-harness')], check=True, env=env)
