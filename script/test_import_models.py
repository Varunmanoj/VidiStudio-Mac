"""Compile production imported-asset model support into a native harness."""
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


model = (ROOT / 'VidiStudio/StudioModel.swift').read_text()
types = [declaration(model, marker) for marker in (
    'struct Segment:', 'enum DescriptionOrigin:', 'enum SynchronizedAudioStatus:',
    'struct ExportMediaInformation:', 'struct AnalysisVideoAvailability:',
    'struct ProjectPlaybackSettings:', 'struct StudioProject:',
    'enum SummaryOrigin:', 'struct NarrationSourceCounts:',
    'struct ImportedAudioDescription:', 'struct ImportedADTranscript:',
    'struct ImportConflict:', 'struct ImportFlaggedSegment:', 'struct ImportOmittedRow:',
    'struct ImportReport:', 'struct DescriptionTimingAudit:',
    'struct ImportTimingRow:', 'struct ImportTimingProposal:', 'struct AIServiceIssue:',
)]
build = ROOT / 'build/import-assets-test'
build.mkdir(parents=True, exist_ok=True)
production = build / 'ProductionImportModels.swift'
production.write_text('import Foundation\nimport SwiftUI\n' + '\n\n'.join(types))
env = os.environ | {'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(build / 'modules'),
                str(production), str(ROOT / 'tests/import_assets_harness.swift'),
                '-o', str(build / 'import-assets-harness')], check=True, env=env)
subprocess.run([str(build / 'import-assets-harness')], check=True, env=env)
