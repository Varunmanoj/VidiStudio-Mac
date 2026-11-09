import Foundation
struct OutputLanguage {
    static func title(_ code: String) -> String { code == "hi" ? "Hindi" : code == "en" ? "English" : "Auto" }
}
struct Segment {
    var id: String; var start = 1.0; var end = 2.0; var text = "Description"
    var audio: String? = "voice.wav"; var changed = false
}
enum SynchronizedAudioStatus {
    case generated, needsRegeneration, notGenerated
    static func resolve(cue: Segment, project: StudioProject) -> Self {
        guard let path = cue.audio, FileManager.default.fileExists(atPath: project.url(path)!.path) else { return .notGenerated }
        return cue.changed ? .needsRegeneration : .generated
    }
}
struct Payload { var cues: [Segment]? }
struct Result {
    let id: String; let kind = "descriptions"; let language: String; var payload: Payload
    var hasContent: Bool { !(payload.cues ?? []).isEmpty }
}
struct StudioProject {
    let folder: URL; var duration = 10.0; var languageCode = "en"
    var cues: [Segment] = []; var savedLanguageResults: [Result] = []
    var selections: [String: String] = [:]
    func activeLanguageResultID(_ kind: String, language: String) -> String { selections[language] ?? "" }
    func url(_ path: String) -> URL? { folder.appendingPathComponent(path) }
// PRODUCTION_METHODS
}
// PRODUCTION_READINESS
@main struct Check {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: root.appendingPathComponent("voice.wav"))
        let ready = Segment(id: "ready")
        var missing = Segment(id: "missing"); missing.audio = nil
        var p = StudioProject(folder: root, cues: [ready], savedLanguageResults: [
            Result(id: "en-old", language: "en", payload: Payload(cues: [missing])),
            Result(id: "en-new", language: "en", payload: Payload(cues: [ready])),
            Result(id: "hi-new", language: "hi", payload: Payload(cues: [ready, missing]))
        ], selections: ["en": "en-new", "hi": "hi-new"])
        precondition(p.hasCompleteExportNarration())
        precondition(p.adAudioReadiness(language: "en").complete)
        let hindi = p.adAudioReadiness(language: "hi")
        precondition(!hindi.complete && hindi.ready == 1 && hindi.total == 2)
        precondition(hindi.accessibilityLabel.contains("Hindi") && hindi.accessibilityLabel.contains("1 of 2"))
        precondition(p.adAudioReadiness(language: "en").accessibilityLabel.contains("English"))
        precondition(p.adAudioReadinessByLanguage.map(\.language) == ["en", "hi"])
        p.languageCode = "hi"; p.cues = [ready, missing]
        precondition(!p.adAudioReadiness(language: "hi").complete)
        precondition(p.adAudioReadiness(language: "en").complete)
        p.selections["en"] = "en-old"
        precondition(!p.adAudioReadiness(language: "en").complete, "Must respect the selected version, not a complete alternative")
        for variant in [Segment(id: "empty-text", text: " "), Segment(id: "outdated", changed: true), Segment(id: "timing", end: 20)] {
            p.cues = [ready, variant]
            precondition(p.adAudioReadiness(language: "hi").ready == 1)
            precondition(!p.hasCompleteExportNarration())
        }
        try Data().write(to: root.appendingPathComponent("voice.wav")); p.cues = [ready]
        precondition(!p.adAudioReadiness(language: "hi").complete)
        try FileManager.default.removeItem(at: root.appendingPathComponent("voice.wav"))
        precondition(p.adAudioReadiness(language: "hi").ready == 0)
        p.cues = []
        precondition(!p.adAudioReadiness(language: "hi").complete)
        precondition(p.adAudioReadiness(language: "hi").accessibilityLabel.contains("No AD segments"))
        print("PASS: per-language versions, current projection, missing/empty/stale/invalid audio and empty text")
    }
}
