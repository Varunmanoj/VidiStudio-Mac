from pathlib import Path
import subprocess
import tempfile
import unittest
from tests.test_ad_audio_readiness import declaration

ROOT = Path(__file__).resolve().parents[1]


class TextExportContentTests(unittest.TestCase):
    def test_native_export_predicates_reject_empty_and_whitespace_rows(self):
        project = (ROOT/'VidiStudio/StudioModel.swift').read_text()
        language = (ROOT/'VidiStudio/LanguageResults.swift').read_text()
        fixture = '''import Foundation
struct Segment { var text: String }
struct Imported { var segments: [Segment] = [] }
struct Payload { var transcript: [Segment]?; var summary: String?; var cues: [Segment]?; var importedADTranscript: Imported? }
struct StudioProject {
    var transcript: [Segment] = []; var summary = ""; var cues: [Segment] = []
PROJECT_METHOD
}
struct SavedLanguageResult {
    var kind: String; var payload: Payload
RESULT_PROPERTY
}
@main struct Main {
    static func main() {
        var p = StudioProject()
        for rows in [[], [Segment(text: " \\n\\t")]] {
            p.transcript = rows; p.cues = rows; p.summary = " \\n"
            for kind in ["transcript", "summary", "descriptions", "combined"] { precondition(!p.canExportText(kind)) }
            for kind in ["transcript", "summary", "descriptions"] {
                let result = SavedLanguageResult(kind: kind, payload: Payload(transcript: rows, summary: " ", cues: rows))
                precondition(!result.hasExportableText)
            }
        }
        p.transcript = [Segment(text: "Dialogue")]
        precondition(p.canExportText("transcript") && !p.canExportText("combined"))
        p.cues = [Segment(text: "Description")]; p.summary = "Summary"
        for kind in ["transcript", "summary", "descriptions", "combined"] { precondition(p.canExportText(kind)) }
        precondition(SavedLanguageResult(kind: "transcript", payload: Payload(transcript: p.transcript)).hasExportableText)
        precondition(SavedLanguageResult(kind: "descriptions", payload: Payload(importedADTranscript: Imported(segments: p.cues))).hasExportableText)
    }
}
'''.replace('PROJECT_METHOD', declaration(project,'    func canExportText(')).replace('RESULT_PROPERTY',declaration(language,'    var hasExportableText:'))
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder); (path/'Check.swift').write_text(fixture)
            result=subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(path/'modules'),str(path/'Check.swift'),'-o',str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result=subprocess.run([str(path/'check')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_export_choices_and_status_use_real_text(self):
        view=(ROOT/'VidiStudio/MediaTrackSelection.swift').read_text()
        self.assertIn('filter(\\.hasExportableText)', view)
        self.assertIn('result.hasExportableText', (ROOT/'VidiStudio/SavedResultStatus.swift').read_text())
        self.assertIn('.contextMenu { Picker(title, selection: $selection, content: content) }', view)
        win=ROOT.parent/'Vidi-Studio-Windows/Vidi Studio Windows'
        self.assertIn('r.Kind == "transcript" && r.HasExportableText', (win/'Views/ExportDialog.Tracks.cs').read_text())
        self.assertIn('kind == "adAudio" ? r.HasContent : r.HasExportableText', (win/'Views/ExportDialog.cs').read_text())
        self.assertIn('picker.IsEnabled && (value is not ComboBoxItem option || option.IsEnabled)', (win/'Views/ExportDialog.Tracks.cs').read_text())
