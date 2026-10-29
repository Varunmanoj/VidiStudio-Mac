import Foundation

@main
struct ImportAssetsHarness {
    static func main() throws {
        let json = """
        {
          "schemaVersion": 2, "id": "p", "name": "Imported", "source": "source/video.mp4",
          "duration": 12.5, "width": 640, "height": 360, "hasAudio": true,
          "createdAt": 0, "updatedAt": 0, "thumbnails": [], "status": "Ready",
          "transcript": [{"id":"t","start":0,"end":1,"text":"Hi","origin":"imported","originSource":"talk.srt"}],
          "summary": "# Imported summary", "summaryOrigin": "imported", "summaryOriginSource": "notes.md",
          "cues": [
            {"id":"a","start":2,"end":4,"text":"One","audio":"audio-description/a.mp3","audioOrigin":"generated","audioEngine":"system","audioVoice":"Voice A","origin":"ai"},
            {"id":"b","start":4,"end":6,"text":"Two","audio":"audio-description/b.wav","audioOrigin":"imported","audioSourceName":"ad.wav","origin":"imported"},
            {"id":"c","start":6,"end":8,"text":"Three","audio":"audio-description/c.wav","audioOrigin":"imported","audioSourceName":"other.wav","origin":"imported_modified"}
          ],
          "exports": [],
          "importedAudioDescription": {"path":"imports/ad.wav","mode":"fullMix","duration":12.5,"sourceName":"ad.wav"},
          "importedADTranscript": {"segments":[],"mode":"combined","sourceName":"combined.vtt"},
          "descriptionTimingAudit": {"count":1,"segments":[{"id":"b","row":2,"start":4,"end":6,"text":"Two","conflicts":[{"kind":"transcript","row":2,"start":5,"end":6,"text":"Hi there"}]}],"videoDuration":12.5},
          "lastImportReport": {"id":"r","kind":"narration","sourceName":"ad.srt","rowsImported":3,"rowsFlagged":1,"rowsOmittedAfterVideo":2,"rowsOmittedInvalid":1,"videoDuration":12.5,"omitted":[{"sourceLine":4,"text":"Too late","reason":"Ends after video","code":"afterVideo"}],"warnings":["Check timing."],"guidance":"Fix it."}
        }
        """
        var project = try JSONDecoder().decode(StudioProject.self, from: Data(json.utf8))
        project.folder = FileManager.default.temporaryDirectory
        precondition(project.summaryOriginLabel == .imported)
        precondition(project.importedAudioDescription?.mode == "fullMix")
        precondition(project.importedADTranscript?.mode == "combined")
        precondition(project.descriptionTimingIssueCount == 1 && project.hasDescriptionTimingIssues)
        precondition(project.descriptionTimingAudit?.segments[0].conflicts?.first?.kind == "transcript")
        precondition(project.narrationSourceCounts.generated == 1)
        precondition(project.narrationSourceCounts.imported == 2)
        precondition(project.narrationSourceCounts.total == 3)
        precondition(project.importedNarrationText == "1 AI-generated · 2 imported", project.importedNarrationText)
        precondition(project.importedNarrationFiles == ["ad.wav", "other.wav"])
        precondition(project.cues[1].provenance == .imported)
        precondition(project.cues[2].provenance == .importedModified)
        precondition(project.lastImportReport?.rowsImported == 3)
        precondition(project.lastImportReport?.omitted?.first?.code == "afterVideo")
        precondition(project.lastImportReport?.kindTitle == "Descriptions")
        precondition(DescriptionOrigin.allCases.map(\.rawValue) == ["ai","ai_modified","imported","imported_modified","manual","unknown"])
        precondition(DescriptionOrigin.imported.title == "Imported")
        precondition(DescriptionOrigin.importedModified.title == "Imported · modified")
        precondition(SummaryOrigin.editableCases == [.ai, .imported, .manual])
        precondition(!project.canCombineImportedAudio, "A missing source file cannot be combined")
        let quota = AIServiceIssue.detect("429 RESOURCE_EXHAUSTED: quota exceeded")
        precondition(quota?.kind == .quota)
        let service = AIServiceIssue.detect("503 service unavailable; try again later")
        precondition(service?.kind == .service)
        precondition(AIServiceIssue.detect("API key not valid") == nil)
        precondition(AIServiceIssue.detect("ordinary validation failure") == nil)
        print("PASS: imported project fields, provenance, timing audit, narration sources, and import report decoding")
    }
}
