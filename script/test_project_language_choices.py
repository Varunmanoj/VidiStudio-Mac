"""Execute the production Swift saved-language availability rules."""
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'VidiStudio/LanguageResults.swift').read_text()
def member(marker):
    start=source.index(marker);opening=source.index('{',start);depth=1;end=opening+1
    while depth:
        depth+=(source[end]=='{')-(source[end]=='}');end+=1
    return source[start:end]
fixture='''import Foundation
struct Imported { var segments: [Int]?; var path: String? }
struct Payload { var transcript: [Int]?; var summary: String?; var cues: [Int]?; var importedADTranscript: Imported?; var importedAudioDescription: Imported? }
struct SavedLanguageResult { var kind: String; var language: String; var state: String; var payload: Payload
HAS_CONTENT
}
struct OutputLanguage { static func title(_ code: String)->String { ["auto":"Auto","en":"English","hi":"Hindi","fr":"French","bn":"Bengali"][code] ?? code } }
struct StudioProject { var savedLanguageResults: [SavedLanguageResult]
AVAILABLE
TITLE
}
let rows = [SavedLanguageResult(kind:"transcript",language:"auto",state:"saved",payload:Payload(transcript:[1])),
 SavedLanguageResult(kind:"summary",language:"en",state:"saved",payload:Payload(summary:"English summary")),
 SavedLanguageResult(kind:"descriptions",language:"hi",state:"draft",payload:Payload(cues:[1])),
 SavedLanguageResult(kind:"summary",language:"fr",state:"saved",payload:Payload(summary:"   ")),
 SavedLanguageResult(kind:"adAudio",language:"bn",state:"saved",payload:Payload(importedAudioDescription:Imported(path:"imports/audio.wav")))]
let p = StudioProject(savedLanguageResults:rows)
precondition(p.availableViewingLanguages == ["auto","bn","en"])
precondition(p.viewingLanguageTitle("en") == "English (Summary)")
precondition(p.viewingLanguageTitle("auto") == "Auto (Transcript)")
precondition(p.viewingLanguageTitle("hi") == "Hindi")
let other = StudioProject(savedLanguageResults:[SavedLanguageResult(kind:"descriptions",language:"hi",state:"saved",payload:Payload(importedADTranscript:Imported(segments:[1])))])
precondition(other.availableViewingLanguages == ["hi"])
precondition(p.availableViewingLanguages == ["auto","bn","en"])
precondition(StudioProject(savedLanguageResults:[]).availableViewingLanguages.isEmpty)
print("PASS: production language choices include populated saved sections, separate Auto, exclude drafts/empty results, and isolate projects")
'''.replace('HAS_CONTENT',member('    var hasContent: Bool')).replace('AVAILABLE',member('    var availableViewingLanguages: [String]')).replace('TITLE',member('    func viewingLanguageTitle('))
with tempfile.TemporaryDirectory(prefix='vidi-language-choices-') as temp:
    path=Path(temp);(path/'main.swift').write_text(fixture)
    subprocess.run(['xcrun','swiftc','-module-cache-path',str(path/'modules'),str(path/'main.swift'),'-o',str(path/'check')],check=True)
    subprocess.run([str(path/'check')],check=True)
