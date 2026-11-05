"""Execute the Mac production viewing projection without an app window."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root/'VidiStudio/StudioModel.swift').read_text()
start = source.index('    private static func decodeViewingProject(')
opening = source.index('{', start)
depth, end = 1, opening + 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
method = source[start:end].replace('private static', 'static', 1)
fixture = r'''
import Foundation
struct StudioProject: Codable {
    var summary: String
    var summaryOrigin: String?
    var transcript: [[String: String]]?
    var cues: [[String: String]]?
    var sectionLanguages: [String: String]?
}
struct Loader {
METHOD
}
let old = #"{"selectedLanguage":"auto","sectionLanguages":{"summary":"hi"},"summary":"Stale Hindi projection","languageResults":[{"id":"a","kind":"summary","language":"auto","state":"saved","createdAt":1,"payload":{"summary":"Auto saved","summaryOrigin":"manual"}},{"id":"h","kind":"summary","language":"hi","state":"saved","createdAt":2,"payload":{"summary":"Hindi saved","summaryOrigin":"imported"}}]}"#
let automatic = try Loader.decodeViewingProject(Data(old.utf8))
precondition(automatic.summary == "Auto saved" && automatic.summaryOrigin == "manual")
precondition(automatic.sectionLanguages?["summary"] == "hi")
let hindiJSON = old.replacingOccurrences(of: #""selectedLanguage":"auto""#, with: #""selectedLanguage":"hi""#)
precondition(try Loader.decodeViewingProject(Data(hindiJSON.utf8)).summary == "Hindi saved")
let emptyJSON = old.replacingOccurrences(of: #""selectedLanguage":"auto""#, with: #""selectedLanguage":"ta""#)
precondition(try Loader.decodeViewingProject(Data(emptyJSON.utf8)).summary.isEmpty)
precondition(try Loader.decodeViewingProject(Data(#"{"summary":"Legacy saved"}"#.utf8)).summary == "Legacy saved")
print("PASS: production Mac loader restores viewing language, provenance, empty states, legacy content, and independent generation targets")
'''.replace('METHOD', method)
# Throwing work is evaluated before the nonthrowing assertion autoclosures.
fixture = fixture.replace('precondition(try Loader.decodeViewingProject(Data(hindiJSON.utf8)).summary == "Hindi saved")', 'let hindi = try Loader.decodeViewingProject(Data(hindiJSON.utf8)); precondition(hindi.summary == "Hindi saved")')
fixture = fixture.replace('precondition(try Loader.decodeViewingProject(Data(emptyJSON.utf8)).summary.isEmpty)', 'let empty = try Loader.decodeViewingProject(Data(emptyJSON.utf8)); precondition(empty.summary.isEmpty)')
fixture = fixture.replace('precondition(try Loader.decodeViewingProject(Data(#"{"summary":"Legacy saved"}"#.utf8)).summary == "Legacy saved")', 'let legacy = try Loader.decodeViewingProject(Data(#"{"summary":"Legacy saved"}"#.utf8)); precondition(legacy.summary == "Legacy saved")')
with tempfile.TemporaryDirectory(prefix='vidi-view-loader-') as temporary:
    folder = Path(temporary)
    (folder/'main.swift').write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(folder/'modules'), str(folder/'main.swift'), '-o', str(folder/'check')], check=True)
    subprocess.run([str(folder/'check')], check=True)
