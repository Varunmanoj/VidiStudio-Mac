import AppKit
import Foundation

@main
@MainActor
struct ExportControlsHarness {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-export-controls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let json = """
        {"schemaVersion":2,"id":"test","name":"Test","source":"video.mp4","duration":3,"width":192,"height":108,"hasAudio":true,"createdAt":0,"updatedAt":0,"thumbnails":[],"transcript":[],"summary":"","cues":[],"exports":[],"status":"ready"}
        """
        var project = try JSONDecoder().decode(StudioProject.self, from: Data(json.utf8))
        project.folder = root
        try Data([1]).write(to: root.appendingPathComponent("video.mp4"))
        var availability = ExportAvailabilityFixture(project: project)
        precondition(!availability.canPerform(.selectableVideo(captions: .none, format: "mkv")))
        precondition(!availability.canPerform(.mixedVideo(captions: .none, format: "mkv")))
        precondition(!availability.canPerform(.describedAudio(format: "wav")))
        precondition(!availability.canPerform(.narrationAudio(format: "wav")))
        precondition(!availability.canPerform(.text(content: "transcript", format: "srt")))
        precondition(!availability.canPerform(.closedCaptionVideo(content: "transcript", format: "mkv")))
        precondition(!availability.canPerform(.webPlayback(audio: "closed-description", captions: .none)))
        precondition(availability.canPerform(.originalAudio(format: "wav")))
        precondition(availability.canPerform(.webPlayback(audio: "original", captions: .none)))
        project.transcriptGenerated = true
        precondition(!project.canExportText("transcript"), "An empty generated transcript has no exportable text")
        project.transcript = [Segment(id: "t", start: 0, end: 0.5, text: "Hello")]
        availability.project = project
        precondition(availability.canPerform(.closedCaptionVideo(content: "transcript", format: "mkv")))
        precondition(!availability.canPerform(.dualClosedCaptionVideo(format: "mkv")))
        project.cues = [Segment(id: "ad", start: 1, end: 2, text: "A shape moves", audio: "narration.wav", audioText: "A shape moves")]
        availability.project = project
        precondition(project.canExportText("combined"), "Text export does not require speech")
        precondition(!availability.canPerform(.describedAudio(format: "wav")), "A missing narration file must block export")
        try Data().write(to: root.appendingPathComponent("narration.wav"))
        precondition(!project.hasCompleteExportNarration(), "Empty narration must block export")
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("narration.wav"))
        availability.project = project
        precondition(availability.canPerform(.selectableVideo(captions: .dualClosed, format: "mkv")))
        precondition(availability.canPerform(.describedAudio(format: "wav")))
        precondition(availability.canPerform(.narrationAudio(format: "m4a")))
        precondition(availability.canPerform(.webPlayback(audio: "closed-description", captions: .closed(content: "transcript"))))
        project.cues.append(Segment(id: "ad2", start: 2, end: 3, text: "Another shape"))
        availability.project = project
        precondition(!availability.canPerform(.narrationAudio(format: "wav")), "Partial narration must block export")
        project.cues.removeLast()
        project.cues[0].audioText = "Old description"
        precondition(!project.hasCompleteExportNarration(), "Stale narration must block export")
        project.sourceType = "youtube"
        availability.project = project
        precondition(availability.canPerform(.youtubeOriginalAudio(format: "wav")))
        precondition(!availability.canPerform(.youtubeDescribedAudio(format: "wav")))
        project.cues[0].audioText = project.cues[0].text
        availability.project = project
        precondition(availability.canPerform(.youtubeDescribedAudio(format: "wav")))
        project.transcript = []
        availability.project = project
        precondition(!availability.canPerform(.text(content: "combined", format: "srt")))
        precondition(!availability.canPerform(.text(content: "transcript", format: "srt")))
        precondition(availability.canPerform(.text(content: "descriptions", format: "txt")))
        project.cues = []
        availability.project = project
        precondition(!availability.canPerform(.youtubeDescribedAudio(format: "wav")))
        precondition(availability.canPerform(.youtubeOriginalAudio(format: "wav")))

        _ = NSApplication.shared
        let radios = ExportRadioGroupView()
        var selected = 1
        var changes = 0
        let configure = { (enabled: [Bool]) in
            radios.configure(title: "Audio to save", titles: ["Original", "Narration", "Combined"], enabled: enabled, selectedIndex: selected) { index in
                selected = index
                changes += 1
            }
        }
        configure([true, false, false])
        precondition(!radios.radioButtons[1].isEnabled && radios.radioButtons[1].state == .on)
        radios.radioButtons[2].performClick(nil)
        precondition(selected == 1 && changes == 0, "An unavailable radio must not change selection")
        // Even an explicitly delivered target action cannot bypass availability.
        NSApp.sendAction(radios.radioButtons[2].action!, to: radios.radioButtons[2].target, from: radios.radioButtons[2])
        precondition(selected == 1 && changes == 0)
        radios.radioButtons[0].performClick(nil)
        precondition(selected == 0 && changes == 1)
        configure([true, true, true])
        radios.radioButtons[2].performClick(nil)
        precondition(selected == 2 && changes == 2)
        configure([true, false, false])
        precondition(radios.radioButtons[2].state == .on && !radios.radioButtons[2].isEnabled)
        precondition(radios.accessibilityLabel() == "Audio to save")
        print("Export prerequisites and native radio enable/disable transitions passed")
    }
}
