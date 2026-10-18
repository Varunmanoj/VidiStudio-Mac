import Foundation

@main @MainActor
struct NarrationControlsHarness {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-narration-controls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let json = """
        {"schemaVersion":2,"id":"test","name":"Test","source":"video.mp4","duration":3,"width":192,"height":108,"hasAudio":true,"createdAt":0,"updatedAt":0,"thumbnails":[],"transcript":[],"summary":"","cues":[],"exports":[],"status":"ready"}
        """
        var project = try JSONDecoder().decode(StudioProject.self, from: Data(json.utf8))
        project.folder = root
        project.cues = [Segment(id: "ad1", start: 0, end: 1, text: "First"), Segment(id: "ad2", start: 1, end: 2, text: "Second")]
        let actions = EditorShortcutActions()
        actions.available = true
        actions.handler = { _ in }
        actions.descriptionCount = project.cues.count
        func sync() {
            actions.hasNarrationAudio = project.hasNarrationAudio
            actions.hasChangedNarration = project.canGenerateMissingOrChangedAudio
            precondition(actions.synthesizeNarrationTitle == project.allADAudioTitle)
        }
        sync()
        precondition(project.allADAudioTitle == "Generate All AD Audio")
        precondition(actions.canRun("synthesize-tts"))
        precondition(!actions.canRun("synthesize-changed"))
        project.cues[0].text = "Edited before any audio"
        sync()
        precondition(!actions.canRun("synthesize-changed"))
        project.cues[0].audio = "first.mp3"
        project.cues[0].audioText = project.cues[0].text
        try Data([1]).write(to: root.appendingPathComponent("first.mp3"))
        sync()
        precondition(project.allADAudioTitle == "Regenerate All AD Audio…")
        precondition(actions.canRun("synthesize-changed"), "Partial projects must permit missing audio repair")
        project.cues[1].audio = "second.mp3"
        project.cues[1].audioText = project.cues[1].text
        try Data([1]).write(to: root.appendingPathComponent("second.mp3"))
        sync()
        precondition(!actions.canRun("synthesize-changed"), "No work remains when all audio is current")
        project.cues[0].text = "Changed after narration"
        sync()
        precondition(actions.canRun("synthesize-changed"))
        actions.ttsUsesGemini = true
        precondition(!actions.canRun("synthesize-tts") && !actions.canRun("synthesize-changed"))
        actions.hasApiKey = true
        precondition(actions.canRun("synthesize-tts") && actions.canRun("synthesize-changed"))
        actions.apiKeyVerified = false
        precondition(!actions.canRun("synthesize-tts") && !actions.canRun("synthesize-changed"))
        actions.ttsUsesGemini = false
        actions.available = false
        precondition(!actions.canRun("synthesize-tts") && !actions.canRun("synthesize-changed"))
        var playback = NarrationPlaybackSettings()
        playback.ttsMode = "gemini"
        precondition(playback.ttsMode == "gemini")
        playback.narrationPlayback = "device"
        precondition(playback.narrationPlayback == "device" && playback.ttsMode == "gemini", "Preview playback must keep the selected generation engine")
        playback.ttsMode = "system"
        precondition(playback.ttsMode == "system")
        playback.narrationPlayback = "generated"
        playback.ttsMode = "gemini"
        precondition(playback.ttsMode == "gemini", "Saved-audio playback must keep Gemini selected")
        let saved = Data("{\"ttsMode\":\"gemini\",\"narrationPlayback\":\"device\"}".utf8)
        let restored = try JSONDecoder().decode(NarrationPlaybackSettings.self, from: saved)
        precondition(restored.ttsMode == "gemini" && restored.narrationPlayback == "device", "Preview plus Gemini settings must persist for generation")
        let roundTrip = try JSONDecoder().decode(NarrationPlaybackSettings.self, from: JSONEncoder().encode(restored))
        precondition(roundTrip.ttsMode == "gemini" && roundTrip.narrationPlayback == "device")
        print("PASS: narration control states, API/busy guards, and engine selection independent of playback mode")
    }
}
