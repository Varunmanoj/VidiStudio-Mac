"""Exercise the actual management guards and focused command routing without real credentials or project edits."""
from pathlib import Path
import os
import subprocess
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT/'build/project-management-test'
BUILD.mkdir(parents=True, exist_ok=True)
model = (ROOT/'VidiStudio/StudioModel.swift').read_text()
bridge = (ROOT/'VidiStudio/ProjectGridView.swift').read_text()
def function(name):
    start = model.index('    func ' + name + '(')
    brace = model.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (model[end] == '{') - (model[end] == '}')
        end += 1
    return model[start:end]
request = model[model.index('struct ProjectManagementRequest:'):model.index('@MainActor @Observable\nfinal class StudioModel')]
focused = bridge[bridge.index('@MainActor\nstruct ProjectBrowserActions'):bridge.index('private struct ProjectBrowserKey')]
stubs = r'''import Foundation
import SwiftUI
struct StudioProject { var id: String; var name: String; var folder: URL?; var integrityPlaceholder: Bool? = false }
struct Report { var manifestUnreadable = false; var folderMissing = false }
@MainActor final class StudioModel {
    var busy = false
    var selected: StudioProject?
    var selectedID: String?
    var listedProjects: [StudioProject] = []
    var report = Report()
    var projectManagementRequest: ProjectManagementRequest?
    func integrityReport(for project: StudioProject) -> Report { report }
    func removeProjectFromList(_ project: StudioProject) { }
'''
(BUILD/'Management.swift').write_text(stubs + function('canManageProject') + '\n' + function('requestProjectManagement') + '\n}\n' + request + focused)
env = os.environ | {'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(BUILD/'modules'), str(BUILD/'Management.swift'), str(ROOT/'tests/project_management_harness.swift'), '-o', str(BUILD/'management-harness')], check=True, env=env)
subprocess.run([str(BUILD/'management-harness')], check=True, env=env)
