"""Compile the actual open-project registry with an isolated native harness."""
from pathlib import Path
import os
import subprocess
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/editor-project-registry-test'
BUILD.mkdir(parents=True, exist_ok=True)
source = (ROOT/'VidiStudio/StudioModel.swift').read_text()
registry = source[source.index('struct OpenProjectReference:'):source.index('struct ProjectManagementRequest:')]
(BUILD/'Registry.swift').write_text('import Foundation\nimport Observation\n' + registry)
env = os.environ | {'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(BUILD/'modules'),
                str(BUILD/'Registry.swift'), str(ROOT/'VidiStudio/ProjectEditorWindowValue.swift'),
                str(ROOT/'tests/editor_project_registry_harness.swift'),
                '-o', str(BUILD/'editor-project-registry-harness')], check=True, env=env)
subprocess.run([str(BUILD/'editor-project-registry-harness')], check=True, env=env)
