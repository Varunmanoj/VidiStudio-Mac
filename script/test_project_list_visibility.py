"""Compile and run the Foundation-only project-list visibility harness."""
from pathlib import Path
import os
import subprocess
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/project-list-visibility-test'
BUILD.mkdir(parents=True, exist_ok=True)
env = os.environ | {'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(BUILD / 'modules'),
                str(ROOT / 'VidiStudio/ProjectListVisibility.swift'),
                str(ROOT / 'tests/project_list_visibility_harness.swift'),
                '-o', str(BUILD / 'project-list-visibility-harness')], check=True, env=env)
subprocess.run([str(BUILD / 'project-list-visibility-harness')], check=True, env=env)
