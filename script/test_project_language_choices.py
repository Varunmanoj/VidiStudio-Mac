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
fixture=r'''import Foundation
struct Imported { var segments: [Int]?; var path: String? }
struct Payload { var transcript: [Int]?; var summary: String?; var cues: [Int]?; var importedADTranscript: Imported?; var importedAudioDescription: Imported? }
struct SavedLanguageResult { var id: String = ""; var createdAt: Double = 0; var kind: String; var language: String; var state: String; var payload: Payload
HAS_CONTENT
}
struct OutputLanguage { static func title(_ code: String)->String { ["auto":"Auto","en":"English","hi":"Hindi","fr":"French","bn":"Bengali"][code] ?? code } }
struct StudioProject { var savedLanguageResults: [SavedLanguageResult]; var languageCode = "auto"
RESULTS
AVAILABLE
TITLE
}
let rows = [SavedLanguageResult(kind:"transcript",language:"auto",state:"saved",payload:Payload(transcript:[1])),
 SavedLanguageResult(kind:"summary",language:"en",state:"saved",payload:Payload(summary:"English summary")),
 SavedLanguageResult(kind:"descriptions",language:"hi",state:"draft",payload:Payload(cues:[1])),
 SavedLanguageResult(kind:"summary",language:"fr",state:"saved",payload:Payload(summary:"   ")),
 SavedLanguageResult(kind:"adAudio",language:"bn",state:"saved",payload:Payload(importedAudioDescription:Imported(path:"imports/audio.wav")))]
let p = StudioProject(savedLanguageResults:rows)
precondition(p.availableViewingLanguages == ["auto","bn","en","fr","hi"])
precondition(p.viewingLanguageTitle("en") == "English (Summary)")
precondition(p.viewingLanguageTitle("auto") == "Auto (Transcript)")
precondition(p.viewingLanguageTitle("hi") == "Hindi (Descriptions)")
let other = StudioProject(savedLanguageResults:[SavedLanguageResult(kind:"descriptions",language:"hi",state:"saved",payload:Payload(importedADTranscript:Imported(segments:[1])))])
precondition(other.availableViewingLanguages == ["hi"])
precondition(p.availableViewingLanguages == ["auto","bn","en","fr","hi"])
precondition(StudioProject(savedLanguageResults:[]).availableViewingLanguages.isEmpty)
let choices = StudioProject(savedLanguageResults:[
 SavedLanguageResult(id:"old",createdAt:1,kind:"summary",language:"auto",state:"saved",payload:Payload(summary:"Original")),
 SavedLanguageResult(id:"draft",createdAt:3,kind:"summary",language:"auto",state:"draft",payload:Payload(summary:"Alternative")),
 SavedLanguageResult(id:"incomplete",createdAt:2,kind:"summary",language:"auto",state:"saved",payload:Payload(summary:"")),
 SavedLanguageResult(id:"other",createdAt:4,kind:"summary",language:"hi",state:"draft",payload:Payload(summary:"Hindi draft"))])
precondition(choices.languageResults(kind:"summary",includingDrafts:true).map(\.id) == ["draft","incomplete","old"])
precondition(choices.languageResults(kind:"summary").map(\.id) == ["incomplete","old"])
precondition(choices.languageResults(kind:"summary",language:"hi",includingDrafts:true).map(\.id) == ["other"])
precondition(choices.languageResults(kind:"transcript",includingDrafts:true).isEmpty)
print("PASS: production language choices include all stored sections, separate Auto, include drafts/empty results, retain saved-only export sources, and isolate projects")
'''.replace('RESULTS',member('    func languageResults(kind:')).replace('HAS_CONTENT',member('    var hasContent: Bool')).replace('AVAILABLE',member('    var availableViewingLanguages: [String]')).replace('TITLE',member('    func viewingLanguageTitle('))
with tempfile.TemporaryDirectory(prefix='vidi-language-choices-') as temp:
    path=Path(temp);(path/'main.swift').write_text(fixture)
    subprocess.run(['xcrun','swiftc','-module-cache-path',str(path/'modules'),str(path/'main.swift'),'-o',str(path/'check')],check=True)
    subprocess.run([str(path/'check')],check=True)
