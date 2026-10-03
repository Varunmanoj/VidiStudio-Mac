"""Compile the production eligibility code and radio control into a native harness."""
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


model = (ROOT/'VidiStudio/StudioModel.swift').read_text()
exports = (ROOT/'VidiStudio/ExportOptionsMenu.swift').read_text()
types = [declaration(model, marker) for marker in (
    'struct Segment:', 'enum DescriptionOrigin:', 'enum SynchronizedAudioStatus:',
    'struct ExportMediaInformation:', 'struct AnalysisVideoAvailability:', 'struct StudioProject:',
)]
types += [declaration(exports, marker).replace('private enum', 'enum', 1) for marker in (
    'enum VideoCaptionOption:', 'enum StudioExportAction:', 'private enum VideoAudioChoice:',
)]
methods = [declaration(exports, marker).replace('private func', 'func', 1) for marker in (
    'private func canUseVideoAudio(', 'private func canPerform(',
)]
build = ROOT/'build/export-controls-test'
build.mkdir(parents=True, exist_ok=True)
production = build/'ProductionEligibility.swift'
production.write_text('import Foundation\nimport SwiftUI\n' + '\n\n'.join(types)
                      + '\nstruct ExportAvailabilityFixture { var project: StudioProject\n'
                      + '\n'.join(methods) + '\n}\n')
env = os.environ | {'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(build/'modules'),
                str(production), str(ROOT/'VidiStudio/ExportRadioGroup.swift'),
                str(ROOT/'tests/export_controls_harness.swift'), '-o', str(build/'export-controls-harness')],
               check=True, env=env)
subprocess.run([str(build/'export-controls-harness')], check=True, env=env)
