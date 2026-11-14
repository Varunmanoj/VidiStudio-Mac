import Foundation
import Observation

struct ProjectSearchQuery: Equatable {
    let section: String?
    let term: String

    init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(tr|sum|des|adt)\s*:\s*"#
        if let range = trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            let prefix = trimmed[range].split(separator: ":", maxSplits: 1)[0].trimmingCharacters(in: .whitespaces).lowercased()
            section = ["tr": "transcript", "sum": "summary", "des": "descriptions", "adt": "ad-transcript"][prefix]
            term = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            section = nil
            term = trimmed
        }
    }

    func applies(to tab: String) -> Bool {
        !term.isEmpty && tab != "ad-overview" && (section == nil || section == tab)
    }

    func matches(_ text: String) -> Bool {
        text.precomposedStringWithCanonicalMapping.range(of: term.precomposedStringWithCanonicalMapping, options: .caseInsensitive) != nil
    }

    func matchingRanges(in text: String) -> [Range<String.Index>] {
        guard !term.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex,
              let range = text.range(of: term, options: .caseInsensitive, range: start..<text.endIndex) {
            guard !range.isEmpty else { break }
            ranges.append(range)
            start = range.upperBound
        }
        return ranges
    }
}

struct ProjectSearchHit: Identifiable {
    let id: String
    let resultID: String
    let kind: String
    let section: String
    let text: String
    let segmentID: String?
    let isDescription: Bool
    let start: Double?
    let end: Double?
    let importedCombined: Bool
}

struct ProjectSearchGroup: Identifiable {
    let result: SavedLanguageResult
    let section: String
    let selected: Bool
    var hits: [ProjectSearchHit]
    var id: String { section + ":" + result.id }
    var title: String {
        let kind = result.kind == "descriptions" ? "Descriptions" : result.kind.capitalized
        return "\(kind) · \(result.title) · \(result.state == "draft" ? "Draft" : "Saved")\(selected ? " · Selected" : "")"
    }
}

/// Owns the window's transient query and a revision-cached text projection.
/// Playback invalidations never reparse saved versions or Markdown.
@Observable
final class ProjectSearchState {
    var text = "" { didSet { if text != oldValue { refresh() } } }
    var focusRequest = 0
    var selectedHitID: String?
    private(set) var groups: [String: [ProjectSearchGroup]] = [:]
    @ObservationIgnored private var documents: [ProjectSearchGroup] = []
    @ObservationIgnored private var revision = ""
    var query: ProjectSearchQuery { ProjectSearchQuery(text) }
    var selectedHit: ProjectSearchHit? { groups.values.flatMap { $0 }.flatMap(\.hits).first { $0.id == selectedHitID } }

    func update(_ project: StudioProject) {
        let key = "\(project.id):\(project.languageCode):\(project.updatedAt)"
        guard revision != key else { return }
        if !revision.isEmpty && !revision.hasPrefix(project.id + ":") { text = "" }
        revision = key
        documents = Self.index(project)
        refresh()
    }

    private func refresh() {
        let parsed = query
        var next: [String: [ProjectSearchGroup]] = [:]
        if !parsed.term.isEmpty {
            for var group in documents where parsed.applies(to: group.section) {
                group.hits = group.hits.filter { parsed.matches($0.text) }
                if !group.hits.isEmpty { next[group.section, default: []].append(group) }
            }
        }
        groups = next
        if selectedHit == nil { selectedHitID = nil }
    }

    static func index(_ project: StudioProject) -> [ProjectSearchGroup] {
        var groups: [ProjectSearchGroup] = []
        for result in project.savedLanguageResults.filter({ $0.language == project.languageCode && ["saved", "draft"].contains($0.state) }) {
            let payload = result.payload
            func append(_ section: String, segments: [Segment], description: Bool, combined: Bool = false) {
                let hits = segments.enumerated().filter { !$0.element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { index, segment in
                    ProjectSearchHit(id: "\(section):\(result.id):\(combined ? "combined" : "segment"):\(segment.id):\(index)", resultID: result.id, kind: result.kind, section: section,
                        text: segment.text, segmentID: segment.id, isDescription: description, start: segment.start, end: segment.end, importedCombined: combined)
                }
                guard !hits.isEmpty else { return }
                groups.append(ProjectSearchGroup(result: result, section: section, selected: result.id == project.activeLanguageResultID(result.kind), hits: hits))
            }
            switch result.kind {
            case "transcript":
                append("transcript", segments: payload.transcript ?? [], description: false)
                append("ad-transcript", segments: payload.transcript ?? [], description: false)
            case "descriptions":
                let imported = payload.importedADTranscript
                let cues = payload.cues ?? []
                let descriptions = cues.isEmpty && imported?.mode != "combined" ? imported?.segments ?? [] : cues
                append("descriptions", segments: descriptions, description: true)
                let combined = imported?.mode == "combined"
                append("ad-transcript", segments: combined ? imported?.segments ?? [] : descriptions, description: true, combined: combined)
            case "summary":
                let hits = SummarySpeechParser.sentences(from: payload.summary ?? "").map { sentence in
                    ProjectSearchHit(id: "summary:\(result.id):\(sentence.id)", resultID: result.id, kind: result.kind, section: "summary", text: sentence.text,
                        segmentID: nil, isDescription: false, start: nil, end: nil, importedCombined: false)
                }
                if !hits.isEmpty { groups.append(ProjectSearchGroup(result: result, section: "summary", selected: result.id == project.activeLanguageResultID("summary"), hits: hits)) }
            default: break
            }
        }
        return groups.sorted {
            if $0.selected != $1.selected { return $0.selected }
            if $0.result.updatedAt != $1.result.updatedAt { return $0.result.updatedAt > $1.result.updatedAt }
            return $0.id < $1.id
        }
    }
}
