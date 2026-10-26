"""Compile production narration control state into a native transition harness."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def declaration(source, marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def declaration_line(source, marker):
    for line in source.splitlines():
        if marker in line:
            return line.strip()
    raise AssertionError(f'{marker} not found')


model = (ROOT/'VidiStudio/StudioModel.swift').read_text()
shortcuts = (ROOT/'VidiStudio/KeyboardShortcuts.swift').read_text()
types = [declaration(model, marker) for marker in (
    'struct Segment:', 'enum DescriptionOrigin:', 'enum SynchronizedAudioStatus:',
    'struct ExportMediaInformation:', 'struct AnalysisVideoAvailability:',
    'struct ProjectPlaybackSettings:', 'struct StudioProject:',
)]
types.append('@MainActor\n' + declaration(shortcuts, 'final class EditorShortcutActions'))
types.append(declaration(model, 'enum ProjectPlaybackPreferences {'))
types.append(
    'extension Notification.Name {\n'
    '    static let vidiStudioProjectNarrationDidChange = Notification.Name("harness-project-narration")\n'
    '    static let vidiStudioProjectFollowDidChange = Notification.Name("harness-project-follow")\n'
    '}'
)
playback = [declaration_line(model, marker) for marker in (
    'var ttsMode = "system"', 'var narrationPlayback = "generated"',
)]
types.append('struct NarrationPlaybackSettings: Codable {\n' + '\n'.join(playback) + '\n}')
build = ROOT/'build/narration-controls-test'
build.mkdir(parents=True, exist_ok=True)
production = build/'ProductionNarrationControls.swift'
production.write_text('import Foundation\nimport SwiftUI\n' + '\n\n'.join(types))
env = os.environ | {'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(build/'modules'),
                str(production), str(ROOT/'tests/narration_controls_harness.swift'),
                '-o', str(build/'narration-controls-harness')], check=True, env=env)
subprocess.run([str(build/'narration-controls-harness')], check=True, env=env)
