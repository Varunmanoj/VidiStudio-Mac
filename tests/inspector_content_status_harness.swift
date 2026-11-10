import Foundation
struct OutputLanguage { static func title(_ code: String) -> String { code } }
struct Segment { let id: String; var text = "Text" }
struct Payload { var transcript: [Segment]?; var summary: String? }
struct Result { var id: String; var kind: String; var language: String; var hasContent = true; var payload: Payload }
struct AudioStatus { var complete = false; var title = "en · 1/2 AD audio"; var accessibilityLabel = "One segment missing audio" }
struct StudioProject {
    var languageCode = "en"; var transcript = [Segment(id: "a"), Segment(id: "b")]
    var summary = "Summary"; var cues = [Segment(id: "d1"), Segment(id: "d2")]
    var savedLanguageResults: [Result] = [
        Result(id: "hi-t", kind: "transcript", language: "hi", payload: Payload(transcript: [Segment(id: "h")], summary: nil)),
        Result(id: "hi-s", kind: "summary", language: "hi", payload: Payload(transcript: nil, summary: "Hindi")),
        Result(id: "hi-empty", kind: "summary", language: "hi", payload: Payload(transcript: nil, summary: " ")),
        Result(id: "fr-ad", kind: "descriptions", language: "fr", payload: Payload())]
    var selected = ["hi:transcript": "hi-t", "hi:summary": "hi-s"]
    func activeLanguageResultID(_ kind: String, language: String) -> String { selected["\(language):\(kind)"] ?? "" }
    func adAudioReadiness(language: String) -> AudioStatus { AudioStatus() }
}
// PRODUCTION_STATUS
// PRODUCTION_METHODS
@main struct Main {
    static func main() {
        var p = StudioProject()
        for section in ["transcript", "summary"] {
            precondition(p.inspectorContentStatus(section: section, language: "en")!.complete)
            precondition(!p.inspectorContentStatus(section: section, language: "en")!.title.contains("AD audio"))
            precondition(p.inspectorContentStatuses(section: section).map(\.language) == ["en", "hi"], "AD-only languages must not leak into text status")
        }
        for section in ["descriptions", "ad-overview", "ad-transcript"] {
            let status = p.inspectorContentStatus(section: section, language: "en")!
            precondition(!status.complete && status.title.contains("1/2 AD audio"))
        }
        precondition(p.inspectorContentStatus(section: "transcript", language: "en")!.title.contains("2 Transcript segments"))
        precondition(p.inspectorContentStatus(section: "summary", language: "en")!.title.contains("7 Summary characters"))
        p.summary = "A👨‍👩‍👧‍👦e\u{301}\n"
        precondition(p.inspectorContentStatus(section: "summary", language: "en")!.title.contains("4 Summary characters"), "Summary count uses displayed characters, including whitespace")
        precondition(p.inspectorContentStatus(section: "unknown", language: "en") == nil)
        precondition(p.inspectorContentStatuses(section: "unknown").isEmpty)
        p.transcript = []; p.summary = " \n"
        precondition(!p.inspectorContentStatus(section: "transcript", language: "en")!.complete)
        precondition(!p.inspectorContentStatus(section: "summary", language: "en")!.complete)
        precondition(p.inspectorContentStatus(section: "summary", language: "hi")!.complete)
        p.selected["hi:summary"] = "hi-empty"
        precondition(!p.inspectorContentStatus(section: "summary", language: "hi")!.complete, "Unselected complete versions cannot mask the selection")
        p.selected["hi:transcript"] = "missing"
        precondition(!p.inspectorContentStatus(section: "transcript", language: "hi")!.complete)
        p.transcript = [Segment(id: "a"), Segment(id: "b"), Segment(id: "c")]
        let numbers = p.segmentNumbers(isDescription: false)
        precondition(numbers == ["a": 1, "b": 2, "c": 3])
        let filteredAndSorted = p.transcript.filter { $0.id != "a" }.reversed().map { numbers[$0.id]! }
        precondition(filteredAndSorted == [3, 2], "Numbers stay tied to the complete result through filtering/sorting")
        precondition(p.segmentNumbers(isDescription: true) == ["d1": 1, "d2": 2])
        p.transcript.removeFirst()
        precondition(p.segmentNumbers(isDescription: false) == ["b": 1, "c": 2])
        p.transcript = [Segment(id: "new-result")]
        precondition(p.segmentNumbers(isDescription: false) == ["new-result": 1])
        print("PASS: tab/content/language/selected-version availability and stable per-kind result numbering")
    }
}
