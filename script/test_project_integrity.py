"""Compile the project integrity auditor and run its native harness."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/project-integrity-test'
BUILD.mkdir(parents=True, exist_ok=True)
env = os.environ | {'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}

subprocess.run([
    'xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(BUILD / 'modules'),
    str(ROOT / 'VidiStudio/ProjectIntegrity.swift'),
    str(ROOT / 'tests/project_integrity_harness.swift'),
    '-o', str(BUILD / 'project-integrity-harness'),
], check=True, env=env)
subprocess.run([str(BUILD / 'project-integrity-harness')], check=True, env=env)
