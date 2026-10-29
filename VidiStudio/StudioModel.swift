import Foundation
import SwiftUI
import AppKit
import MediaAccessibility
import UniformTypeIdentifiers

struct Segment: Codable, Identifiable, Hashable {
    var id: String
    var start: Double
    var end: Double
    var text: String
    var speaker: String?
    var audio: String?
    var audioText: String?
    var audioDuration: Double?
    var audioSettings: String?
    var audioEngine: String?
    var audioVoice: String?
    var audioStart: Double?
    var audioEnd: Double?
    var audioError: String?
    var origin: String?
    var originSource: String?
    /// True when a person chose this provenance in Add/Edit Segment. The choice
    /// persists across saves instead of being regenerated from the current text.
    var originOverride: Bool?
    var aiOriginalText: String?
    /// Imported narration carries its own source file name so voice reports
    /// never mislabel it as a generated voice.
    var audioOrigin: String?
    var audioSourceName: String?

    var provenance: DescriptionOrigin { DescriptionOrigin(rawValue: origin ?? "") ?? .unknown }

    var narrationUpdateReasons: [String] {
        var reasons: [String] = []
        if let error = audioError, !error.isEmpty { reasons.append(error) }
        if audioText != text { reasons.append("Description text changed since the narration was generated.") }
        if audioStart.map({ abs($0 - start) > 0.001 }) == true
            || audioEnd.map({ abs($0 - end) > 0.001 }) == true {
            reasons.append("Segment timing changed since the narration was generated.")
        }
        let tolerance = audioOrigin == "imported" ? 0.05 : 0.001
        if let duration = audioDuration, duration > end - start + tolerance {
            reasons.append(String(format: "Narration is %.2fs but the segment timing only allows %.2fs.", duration, end - start))
        }
        return reasons
    }
}

enum DescriptionOrigin: String, CaseIterable {
    case ai, aiModified = "ai_modified", imported, importedModified = "imported_modified", manual, unknown

    var title: String {
        switch self {
        case .ai: return "AI-generated"
        case .aiModified: return "AI-generated · modified"
        case .imported: return "Imported"
        case .importedModified: return "Imported · modified"
        case .manual: return "Manually added"
        case .unknown: return "Origin unknown"
        }
    }
    var iconName: String {
        switch self {
        case .ai: return "sparkles"
        case .aiModified: return "pencil"
        case .imported: return "square.and.arrow.down"
        case .importedModified: return "square.and.arrow.down.on.square"
        case .manual: return "person"
        case .unknown: return "questionmark.circle"
        }
    }
    var color: Color {
        switch self {
        case .ai: return .purple
        case .aiModified: return .orange
        case .imported: return .teal
        case .importedModified: return .orange
        case .manual: return .blue
        case .unknown: return .secondary
        }
    }
    var isModified: Bool { self == .aiModified || self == .importedModified }
    var base: DescriptionOrigin {
        switch self {
        case .aiModified: return .ai
        case .importedModified: return .imported
        default: return self
        }
    }
    /// Choices exposed by the Add/Edit Segment provenance picker.
    static var editableCases: [DescriptionOrigin] { [.ai, .aiModified, .imported, .importedModified, .manual, .unknown] }
}

struct DescriptionOriginLabel: View {
    let origin: DescriptionOrigin
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: origin.iconName).accessibilityHidden(true)
            Text(origin.title).font(.caption.weight(.semibold))
        }
        .foregroundStyle(origin.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Origin: \(origin.title)")
    }
}

enum SynchronizedAudioStatus: Equatable {
    case generated, needsRegeneration, notGenerated

    static func resolve(cue: Segment, project: StudioProject) -> Self {
        guard let path = cue.audio,
              let url = project.url(path),
              FileManager.default.fileExists(atPath: url.path) else {
            return .notGenerated
        }
        // Voice settings alone do not invalidate existing audio. Text/timing
        // changes and saved generation issues do require attention.
        return cue.narrationUpdateReasons.isEmpty
            ? .generated
            : .needsRegeneration
    }

    var title: String {
        switch self {
        case .generated: return "Synchronized audio generated"
        case .needsRegeneration: return "Synchronized audio needs regeneration"
        case .notGenerated: return "Synchronized audio not generated"
        }
    }

    var iconName: String {
        switch self {
        case .generated: return "checkmark.circle"
        case .needsRegeneration: return "arrow.clockwise"
        case .notGenerated: return "waveform"
        }
    }

    var color: Color {
        switch self {
        case .generated: return .green
        case .needsRegeneration: return .orange
        case .notGenerated: return .secondary
        }
    }
}

struct SynchronizedAudioStatusLabel: View {
    let status: SynchronizedAudioStatus
    var detail: String? = nil
    var adNumber: Int? = nil
    var isNarrating: Bool = false
    var isQueued: Bool = false

    private var prefix: String {
        guard let adNumber else { return "" }
        return "AD \(adNumber) · "
    }

    private var displayTitle: String {
        if isNarrating {
            return "\(prefix)Generating narration audio…" + (detail.map { " · \($0)" } ?? "")
        }
        if isQueued {
            return "\(prefix)Queued for narration generation…"
        }
        return "\(prefix)\(status.title)" + (detail.map { " · \($0)" } ?? "")
    }

    private var statusColor: Color {
        if isNarrating { return .accentColor }
        if isQueued { return .orange }
        return status.color
    }

    private var statusIcon: String {
        if isNarrating { return "waveform.circle.fill" }
        if isQueued { return "clock.arrow.circlepath" }
        return status.iconName
    }

    var body: some View {
        HStack(spacing: 6) {
            if isNarrating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
            Image(systemName: statusIcon)
                .accessibilityHidden(true)
            Text(displayTitle)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(statusColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayTitle)
    }
}

extension Segment {
    var resolvedAudioEngine: String? {
        if let engine = audioEngine?.trimmingCharacters(in: .whitespacesAndNewlines), !engine.isEmpty {
            return engine
        }
        guard let settings = audioSettings?.trimmingCharacters(in: .whitespacesAndNewlines), !settings.isEmpty else {
            return nil
        }
        let first = settings.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return first.isEmpty ? nil : first
    }

    var resolvedAudioVoice: String? {
        if let voice = audioVoice?.trimmingCharacters(in: .whitespacesAndNewlines), !voice.isEmpty {
            return voice
        }
        guard let settings = audioSettings?.trimmingCharacters(in: .whitespacesAndNewlines), !settings.isEmpty else {
            return nil
        }
        let parts = settings.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1 else { return nil }
        let raw = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }
        return raw.lowercased().hasPrefix("default:") ? "System default" : raw
    }

    var narrationVoiceSummary: String? {
        guard audio != nil else { return nil }
        if audioOrigin == "imported" {
            return "Imported audio" + (audioSourceName.map { " · \($0)" } ?? "")
        }
        guard let engine = resolvedAudioEngine ?? (audio != nil ? "unknown" : nil),
              let voice = resolvedAudioVoice ?? (audio != nil ? "Unknown voice" : nil) else { return nil }
        return NarrationVoiceFormatting.combinedLabel(voice: voice, engine: engine)
    }
}
struct GeminiModelOption: Identifiable, Hashable {
    let name: String
    let displayName: String
    let supportedActions: [String]
    var id: String { name }

    init?(dictionary: [String: Any]) {
        guard let name = dictionary["name"] as? String, !name.isEmpty else { return nil }
        self.name = name
        displayName = dictionary["displayName"] as? String ?? name
        supportedActions = dictionary["supportedActions"] as? [String] ?? []
    }

    init(name: String) {
        self.name = name
        displayName = name
        supportedActions = []
    }
}
enum EngineCheckStatus: Equatable {
    case unchecked
    case checking
    case ready
    case failed(String)
}

struct ExportMediaInformation: Codable, Hashable {
    var duration: Double?
    var frameRate: Double?
    var width: Int
    var height: Int
    var videoCodec: String
    var videoProfile: String?
    var videoBitRate: Int64?
    var color: String
    var audio: String
    var container: String
    var fileSize: Int64
    var videoProcessing: String

    var durationDescription: String {
        guard let duration, duration.isFinite, duration > 0 else { return "Not available" }
        let seconds = Int(duration.rounded())
        let hours = seconds / 3_600
        let minutes = seconds / 60 % 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }

    var frameRateDescription: String {
        guard let frameRate, frameRate.isFinite, frameRate > 0 else { return "Not available" }
        if abs(frameRate.rounded() - frameRate) < 0.005 { return "\(Int(frameRate.rounded())) fps" }
        return String(format: "%.2f fps", frameRate)
    }

    var resolutionDescription: String {
        width > 0 && height > 0 ? "\(width) × \(height)" : "Not available"
    }

    var videoDescription: String {
        guard let videoProfile, !videoProfile.isEmpty else { return videoCodec }
        return "\(videoCodec), \(videoProfile)"
    }

    var videoBitRateDescription: String {
        guard let videoBitRate, videoBitRate > 0 else { return "Not reported" }
        if videoBitRate >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(videoBitRate) / 1_000_000)
        }
        return String(format: "%.0f kbps", Double(videoBitRate) / 1_000)
    }

    var fileSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var videoProcessingDescription: String {
        switch videoProcessing {
        case "copied": return "Original picture kept unchanged"
        case "renderedOpenCaptions": return "New video created to add open captions"
        default: return "Not available"
        }
    }
}

struct AnalysisVideoAvailability: Codable {
    var state: String
    var expiresAt: Double
    var checkedAt: Double
}

struct VideoPreparationActivity {
    let projectID: String
    let message: String
}

/// A description the engine could not narrate during a generation run.
struct NarrationFailure: Identifiable, Hashable {
    let id: Int
    let start: Double
    let end: Double
    let duration: Double
    let reason: String
}

/// The summary shown for narration status, both after a run and on demand.
/// A persistent Gemini processing failure that should pause every AI action.
/// Quota/cost exhaustion and service-wide failures are distinct from an invalid
/// key; the key may still be valid even when the account has no remaining quota.
struct AIServiceIssue: Equatable, Identifiable {
    enum Kind: String { case quota, service, access }

    let id = UUID()
    var kind: Kind
    var title: String
    var message: String
    var detail: String?

    static func detect(_ rawDetail: String) -> AIServiceIssue? {
        let detail = rawDetail.lowercased()
        if detail.contains("api key not valid") || detail.contains("api_key_invalid")
            || detail.contains("invalid api key") { return nil }
        if detail.contains("quota") || detail.contains("resource_exhausted") || detail.contains("429")
            || detail.contains("billing") || detail.contains("credit") || detail.contains("spend")
            || detail.contains("rate limit") {
            return AIServiceIssue(
                kind: .quota,
                title: "Gemini Usage Limit Reached",
                message: "Your Gemini key has no remaining quota or credits for AI processing. AI actions are paused. Add billing or credits in Google AI Studio, or wait for the limit to reset, then choose Retry AI.",
                detail: rawDetail)
        }
        if detail.contains("503") || detail.contains("service unavailable") || detail.contains("overloaded")
            || detail.contains("deadline exceeded") || detail.contains("try again later") {
            return AIServiceIssue(
                kind: .service,
                title: "Gemini AI Processing Unavailable",
                message: "Gemini could not process the request because the service is temporarily unavailable. AI actions are paused until you retry successfully or the service recovers.",
                detail: rawDetail)
        }
        if detail.contains("permission_denied") || detail.contains("permission denied") {
            return AIServiceIssue(
                kind: .access,
                title: "Gemini AI Access Needs Attention",
                message: "Gemini refused an AI processing request. Check the key's project permissions and AI Studio access, then retry. AI actions are paused until then.",
                detail: rawDetail)
        }
        return nil
    }
}

struct NarrationFailureReport: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let generated: Int
    let failures: [NarrationFailure]
    /// Non-blocking source warnings, kept separate from narration errors.
    var warnings: [String] = []
}

enum NarrationVoiceFormatting {
    static func engineDisplayName(_ engine: String?) -> String {
        switch (engine ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "gemini": return "Gemini Voices"
        case "system": return "Apple Voices"
        case "windows-core": return "Windows OneCore"
        case "sapi5": return "Windows SAPI 5"
        case "windows-natural": return "Downloaded Natural Voices"
        case "piper": return "Piper Voices"
        case "unknown", "": return "Unknown engine"
        default: return "Unknown engine"
        }
    }

    static func voiceDisplayName(_ voice: String?) -> String {
        let trimmed = (voice ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased().hasPrefix("default:") {
            return "System default"
        }
        // Windows Narrator voices are identified by their voice package name.
        if let match = trimmed.firstMatch(of: /MicrosoftWindows\.Voice\.(?<locale>[A-Za-z]{2,3}-[A-Za-z0-9]{2,8})\.(?<speaker>[A-Za-z]+)/) {
            var speaker = String(match.speaker)
            let hd = speaker.count > 2 && speaker.hasSuffix("HD")
            if hd { speaker.removeLast(2) }
            return "Microsoft \(speaker) (Natural\(hd ? " HD" : "")) - \(match.locale)"
        }
        // Piper voices are stored as ids such as en_US-amy-low.
        let piperParts = trimmed.split(separator: "-")
        if piperParts.count == 3, piperParts[0].contains("_"),
           ["x_low", "low", "medium", "high"].contains(String(piperParts[2]).lowercased()) {
            var name = piperParts[1].replacingOccurrences(of: "_", with: " ")
            if let first = name.first { name = first.uppercased() + name.dropFirst() }
            let quality = piperParts[2].replacingOccurrences(of: "_", with: " ")
            return "\(name) (\(quality)) — \(piperParts[0].replacingOccurrences(of: "_", with: "-"))"
        }
        if trimmed.contains("\\"), let last = trimmed.split(separator: "\\").last {
            return String(last)
        }
        return trimmed
    }

    static func combinedLabel(voice: String?, engine: String?) -> String {
        "\(voiceDisplayName(voice)) (\(engineDisplayName(engine)))"
    }

    static func isSystemDefaultVoice(_ voice: String) -> Bool {
        let lower = voice.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower == "system default" || lower.hasPrefix("system default (") || lower.hasPrefix("default:")
    }

    static func systemDefaultInnerVoice(_ voice: String) -> String? {
        let trimmed = voice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("system default ("), trimmed.hasSuffix(")") else { return nil }
        let start = trimmed.index(trimmed.startIndex, offsetBy: "System default (".count)
        let end = trimmed.index(before: trimmed.endIndex)
        let inner = String(trimmed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? nil : inner
    }

    static func effectiveVoiceName(_ voice: String) -> String {
        if let inner = systemDefaultInnerVoice(voice) {
            return inner
        }
        return voiceDisplayName(voice)
    }

    static func voicesMatch(engineA: String, voiceA: String, engineB: String, voiceB: String) -> Bool {
        let normEngineA = engineA.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normEngineB = engineB.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normEngineA == normEngineB else { return false }
        let trimA = voiceA.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimB = voiceB.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSystemDefaultVoice(trimA) && isSystemDefaultVoice(trimB) {
            if let innerA = systemDefaultInnerVoice(trimA), let innerB = systemDefaultInnerVoice(trimB) {
                return innerA.caseInsensitiveCompare(innerB) == .orderedSame
            }
            return true
        }
        return effectiveVoiceName(trimA).caseInsensitiveCompare(effectiveVoiceName(trimB)) == .orderedSame
    }
}

struct NarrationVoiceSummary: Identifiable, Hashable {
    let id: String
    let engine: String
    let engineDisplayName: String
    let voice: String
    let voiceDisplayName: String
    let count: Int
    let segmentNumbers: [Int]
    let isDifferentVoice: Bool

    var combinedLabel: String { "\(voiceDisplayName) (\(engineDisplayName))" }
}

struct NarrationVoiceSegmentEntry: Identifiable, Hashable {
    let id: Int
    let start: Double
    let end: Double
    let duration: Double
    let engine: String
    let engineDisplayName: String
    let voice: String
    let voiceDisplayName: String
    let audioFile: String
    let usesDifferentVoice: Bool
    let reason: String
    var isImported: Bool = false

    var combinedLabel: String { "\(voiceDisplayName) (\(engineDisplayName))" }
}

struct NarrationVoiceReport: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let primaryVoiceLabel: String?
    let hasDifferentVoices: Bool
    let voiceSummaries: [NarrationVoiceSummary]
    let differentSegments: [NarrationVoiceSegmentEntry]
    let allSegments: [NarrationVoiceSegmentEntry]
    var importedCount: Int = 0
    var hasMixedSources: Bool = false
    var importedFiles: [String] = []
}

/// Per-section processing state for the Transcript, Summary, and Audio
/// Description sections. Sections run one stage at a time, so the section that
/// owns the current engine stage shows a spinner while later stages wait their
/// turn. Navigation between sections stays available throughout.
enum SectionProcessingState: Equatable {
    case idle
    case queued
    case active

    var isProcessing: Bool { self != .idle }
}

struct StudioProject: Codable, Identifiable {
    var schemaVersion: Int
    var id: String
    var name: String
    var source: String
    var duration: Double
    var width: Int
    var height: Int
    var hasAudio: Bool
    var createdAt: Double
    var updatedAt: Double
    var thumbnails: [String]
    var transcript: [Segment]
    var summary: String
    var cues: [Segment]
    var exports: [String]
    var exportMediaInfo: [String: ExportMediaInformation]?
    var status: String
    var error: String?
    var geminiVideo: AnalysisVideoAvailability?
    var sourceType: String?
    var youtubeURL: String?
    var transcriptGenerated: Bool?
    var summaryGenerated: Bool?
    var descriptionsGenerated: Bool?
    var narrationEngine: String?
    var narrationVoice: String?
    /// Existing-asset imports. Paths are relative to the project folder and stay
    /// portable between macOS and Windows.
    var importedAudioDescription: ImportedAudioDescription?
    var importedADTranscript: ImportedADTranscript?
    var summaryOrigin: String?
    var summaryOriginSource: String?
    var lastImportReport: ImportReport?
    var importReports: [ImportReport]?
    var descriptionTimingAudit: DescriptionTimingAudit?
    /// Project-specific playback choices stored in project.json so the same
    /// choice travels with the project folder between macOS and Windows.
    var playback: ProjectPlaybackSettings?
    var undoStack: [[Segment]]?
    var redoStack: [[Segment]]?
    var transcriptUndoStack: [[Segment]]?
    var transcriptRedoStack: [[Segment]]?
    var folder: URL?
    var isYouTubeURLProject: Bool {
        sourceType == "youtube"
    }
    var hasProcessed: Bool?
    /// Set only for an in-memory placeholder representing a project folder
    /// whose project.json is missing or unreadable. Never written to disk.
    var integrityPlaceholder: Bool? = nil
    var canReprocess: Bool {
        hasProcessed == true || !transcript.isEmpty || !summary.isEmpty || !cues.isEmpty || !exports.isEmpty
    }
    var hasGeneratedContent: Bool {
        canReprocess || !thumbnails.isEmpty
            || directoryHasContent("audio-description")
            || directoryHasContent("exports")
            || !(undoStack ?? []).isEmpty
            || !(redoStack ?? []).isEmpty
            || !(transcriptUndoStack ?? []).isEmpty
            || !(transcriptRedoStack ?? []).isEmpty
    }
    func hasFile(_ relative: String) -> Bool {
        url(relative).map { FileManager.default.fileExists(atPath: $0.path) } == true
    }
    func directoryHasContent(_ relative: String) -> Bool {
        guard let directory = url(relative),
              let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return false }
        return !contents.isEmpty
    }
    var hasGeneratedTranscript: Bool {
        transcriptGenerated == true || !transcript.isEmpty
    }
    var hasNarrationAudio: Bool { cues.contains { $0.audio != nil } }
    var descriptionTimingIssueCount: Int { descriptionTimingAudit?.count ?? 0 }
    var hasDescriptionTimingIssues: Bool { descriptionTimingIssueCount > 0 }
    var summaryOriginLabel: SummaryOrigin {
        SummaryOrigin(rawValue: summaryOrigin ?? "") ?? .unknown
    }
    var importedADAudioModeLabel: String {
        importedAudioDescription?.mode == "fullMix" ? "Full AD mix" : "AD narration audio"
    }
    var canCombineImportedAudio: Bool {
        importedAudioDescription != nil && !isYouTubeURLProject && hasFile(source)
    }
    var narrationSourceCounts: NarrationSourceCounts {
        var counts = NarrationSourceCounts()
        for cue in cues where cue.audio != nil {
            switch cue.audioOrigin {
            case "generated": counts.generated += 1
            case "imported": counts.imported += 1
            default: counts.unknown += 1
            }
        }
        return counts
    }
    var importedNarrationFiles: [String] {
        Array(Set(cues.filter { $0.audio != nil && $0.audioOrigin == "imported" }.compactMap { $0.audioSourceName })).sorted()
    }
    var importedNarrationText: String {
        let counts = narrationSourceCounts
        var parts: [String] = []
        if counts.generated > 0 { parts.append("\(counts.generated) AI-generated") }
        if counts.imported > 0 { parts.append("\(counts.imported) imported") }
        if counts.unknown > 0 { parts.append("\(counts.unknown) unknown") }
        return parts.isEmpty ? "No narration audio" : parts.joined(separator: " · ")
    }
    var allADAudioTitle: String { hasNarrationAudio ? "Regenerate All AD Audio…" : "Generate All AD Audio" }
    var canGenerateMissingOrChangedAudio: Bool {
        hasNarrationAudio && cues.contains { SynchronizedAudioStatus.resolve(cue: $0, project: self) != .generated }
    }

    var canGenerateDescriptions: Bool {
        hasGeneratedTranscript && !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    func canExportText(_ content: String) -> Bool {
        switch content {
        case "transcript": return !transcript.isEmpty
        case "summary": return !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case "descriptions": return !cues.isEmpty
        case "combined": return !transcript.isEmpty && !cues.isEmpty
        default: return false
        }
    }
    func hasCompleteExportNarration() -> Bool {
        guard duration.isFinite, duration > 0, !cues.isEmpty else { return false }
        return cues.allSatisfy { cue in
            guard SynchronizedAudioStatus.resolve(cue: cue, project: self) == .generated,
                  !cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  cue.start.isFinite, cue.end.isFinite,
                  cue.start >= 0, cue.end > cue.start, cue.end <= duration,
                  let path = cue.audio, let url = url(path),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { return false }
            return true
        }
    }
    func hasExportableNarration() -> Bool {
        cues.contains {
            SynchronizedAudioStatus.resolve(cue: $0, project: self) == .generated
        }
    }
    func url(_ relative: String) -> URL? {
        guard let folder else { return nil }
        let resolved = folder.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(folder.standardizedFileURL.resolvingSymlinksInPath().path + "/") else { return nil }
        return resolved
    }
}

enum SummaryOrigin: String, CaseIterable {
    case ai, imported, manual, unknown

    var title: String {
        switch self {
        case .ai: return "AI-generated"
        case .imported: return "Imported"
        case .manual: return "Manually added"
        case .unknown: return "Origin unknown"
        }
    }
    var iconName: String {
        switch self {
        case .ai: return "sparkles"
        case .imported: return "square.and.arrow.down"
        case .manual: return "person"
        case .unknown: return "questionmark.circle"
        }
    }
    var color: Color {
        switch self {
        case .ai: return .purple
        case .imported: return .teal
        case .manual: return .blue
        case .unknown: return .secondary
        }
    }
    /// Only these three labels can be chosen explicitly for a summary.
    static var editableCases: [SummaryOrigin] { [.ai, .imported, .manual] }
}

struct NarrationSourceCounts: Hashable {
    var generated = 0
    var imported = 0
    var unknown = 0
    var total: Int { generated + imported + unknown }
    var hasMixedSources: Bool { imported > 0 && generated > 0 }
}

struct ImportedAudioDescription: Codable, Hashable {
    var path: String
    var mode: String
    var sourceName: String
    var duration: Double?
}

struct ImportedADTranscript: Codable, Hashable {
    var segments: [Segment]
    var mode: String
    var format: String?
    var sourceName: String?
    var path: String?
}

struct ImportConflict: Codable, Hashable {
    var kind: String
    var id: String?
    var row: Int?
    var start: Double?
    var end: Double?
    var text: String?
}

struct ImportFlaggedSegment: Codable, Hashable, Identifiable {
    var id: String?
    var row: Int?
    var sourceLine: Int?
    var start: Double?
    var end: Double?
    var text: String?
    var conflicts: [ImportConflict]?

    var identity: String { id ?? "\(row ?? sourceLine ?? 0)" }
}

struct ImportOmittedRow: Codable, Hashable, Identifiable {
    var sourceLine: Int?
    var text: String
    var reason: String
    var code: String

    var id: String { "\(sourceLine ?? 0)-\(code)-\(text.prefix(24))" }
}

struct ImportReport: Codable, Hashable, Identifiable {
    var id: String
    var kind: String
    var sourceName: String
    var rowsImported: Int
    var rowsFlagged: Int
    var rowsOmittedAfterVideo: Int
    var rowsOmittedInvalid: Int
    var rowsOmittedTranscriptOverlap: Int?
    var videoDuration: Double?
    var omitted: [ImportOmittedRow]?
    var flagged: [ImportFlaggedSegment]?
    var warnings: [String]?
    var guidance: String?

    var kindTitle: String {
        switch kind {
        case "transcript": return "Transcript"
        case "narration": return "Descriptions"
        case "combined": return "AD Transcript"
        case "summary": return "Summary"
        case "adAudio": return "AD audio"
        case "segmentNarration": return "Narration audio"
        default: return "Import"
        }
    }
    var hasOmissions: Bool { (omitted?.count ?? 0) > 0 }
    var hasFlags: Bool { (flagged?.count ?? 0) > 0 }
}

struct DescriptionTimingAudit: Codable, Hashable {
    var count: Int
    var segments: [ImportFlaggedSegment]
    var videoDuration: Double?
    var guidance: String?
}

enum ImportedADTranscriptMode: String, CaseIterable, Identifiable {
    case narration, combined
    var id: Self { self }
    var title: String { self == .narration ? "AD narration only" : "Dialogue + AD combined" }
    var detail: String {
        self == .narration
            ? "Creates editable description segments and validates them against the transcript."
            : "Stored as one combined caption/export track. It is not split into editable descriptions."
    }
}

enum ImportedADAudioMode: String, CaseIterable, Identifiable {
    case narration, fullMix
    var id: Self { self }
    var title: String { self == .narration ? "AD narration audio only" : "Full AD mix" }
    var detail: String {
        self == .narration
            ? "Mixed with the original audio; the original is ducked while narration speaks."
            : "Used directly as the described track. The original soundtrack stays available."
    }
}

struct ImportTimingRow: Codable, Identifiable, Hashable {
    var sourceLine: Int
    var text: String
    var start: Double?
    var end: Double?
    var aiGenerated: Bool?

    var id: Int { sourceLine }
}

struct ImportTimingProposal: Codable {
    var rows: [ImportTimingRow]
    var aiGenerated: Bool?
    var reviewed: Bool?
    var omitted: [ImportOmittedRow]?
}

struct ImportAssetSelection {
    var transcript: URL?
    var summary: URL?
    var adTranscript: URL?
    var adTranscriptMode: ImportedADTranscriptMode = .narration
    var adAudio: URL?
    var adAudioMode: ImportedADAudioMode = .narration
    /// Reviewed timing JSON created by the TXT timing editor.
    var transcriptTiming: URL?
    var adTranscriptTiming: URL?

    var hasAny: Bool {
        transcript != nil || summary != nil || adTranscript != nil || adAudio != nil
    }
    var hasTextNeedingTiming: Bool {
        [transcript, adTranscript].contains { $0?.pathExtension.lowercased() == "txt" }
    }
}

struct ProjectVideoInformation {
    let projectName: String
    let projectType: String
    let projectSize: String
    let projectFolder: String
    let sourceDetailLabel: String
    let sourceDetail: String
    let sourceURL: String?
    let duration: String
    let frameRate: String
    let resolution: String
    let videoCodec: String
    let videoBitRate: String
    let color: String
    let audio: String
    let container: String
    let sourceFileSize: String

    init(project: StudioProject) {
        let probe = Self.loadProbe(project)
        let streams = probe?["streams"] as? [[String: Any]] ?? []
        let video = streams.first { $0["codec_type"] as? String == "video" }
        let audioStream = streams.first { $0["codec_type"] as? String == "audio" }
        let format = probe?["format"] as? [String: Any]

        projectName = project.name
        projectType = project.isYouTubeURLProject ? "YouTube Video" : "Local Video"
        projectSize = Self.formattedByteCount(Self.projectFolderSize(project)) ?? "Not available"
        projectFolder = project.folder?.path ?? "Not available"
        sourceDetailLabel = project.isYouTubeURLProject ? "Video ID" : "Source File"
        if project.isYouTubeURLProject {
            sourceDetail = project.youtubeURL.flatMap { VidiStudioShareLink.youtubeVideoID(from: $0) } ?? "Not available"
            sourceURL = project.youtubeURL
        } else {
            let filename = URL(fileURLWithPath: project.source).lastPathComponent
            sourceDetail = filename.isEmpty ? "Not available" : filename
            sourceURL = nil
        }

        let probedDuration = Self.number(format?["duration"]) ?? Self.number(video?["duration"])
        duration = Self.duration(project.duration > 0 ? project.duration : probedDuration)

        let width = project.width > 0 ? project.width : Self.integer(video?["width"])
        let height = project.height > 0 ? project.height : Self.integer(video?["height"])
        resolution = width > 0 && height > 0 ? "\(width) × \(height)" : "Not available"

        let rate = Self.rate(video?["avg_frame_rate"]) ?? Self.rate(video?["r_frame_rate"])
        frameRate = rate.map(Self.frameRate) ?? "Not available"
        videoCodec = Self.codecDescription(video) ?? "Not available"
        videoBitRate = Self.bitRate(Self.integer64(video?["bit_rate"]))
        color = Self.colorDescription(video)
        audio = Self.audioDescription(audioStream, hasAudio: project.hasAudio)
        container = Self.text(format?["format_long_name"])
            ?? Self.text(format?["format_name"])?.replacingOccurrences(of: ",", with: ", ")
            ?? (project.isYouTubeURLProject ? "YouTube stream" : "Not available")

        let byteCount = Self.localFileSize(project) ?? Self.integer64(format?["size"])
        sourceFileSize = project.isYouTubeURLProject
            ? "Not stored locally"
            : Self.formattedByteCount(byteCount) ?? "Not available"
    }

    private static func loadProbe(_ project: StudioProject) -> [String: Any]? {
        guard let url = project.url("metadata/probe.json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }

    private static func localFileSize(_ project: StudioProject) -> Int64? {
        guard !project.isYouTubeURLProject,
              let url = project.url(project.source),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    private static func projectFolderSize(_ project: StudioProject) -> Int64? {
        guard let folder = project.folder,
              let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: [.skipsPackageDescendants]
              ) else { return nil }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    private static func formattedByteCount(_ value: Int64?) -> String? {
        value.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }

    private static func text(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        guard let text = text(value), let number = Double(text), number.isFinite else { return nil }
        return number
    }

    private static func integer(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        return text(value).flatMap(Int.init) ?? 0
    }

    private static func integer64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        return text(value).flatMap(Int64.init)
    }

    private static func rate(_ value: Any?) -> Double? {
        guard let raw = text(value) else { return nil }
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
        let result: Double?
        if parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator != 0 {
            result = numerator / denominator
        } else {
            result = Double(raw)
        }
        guard let result, result.isFinite, result > 0 else { return nil }
        return result
    }

    private static func frameRate(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.005 { return "\(Int(value.rounded())) fps" }
        return String(format: "%.2f fps", value)
    }

    private static func duration(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "Not available" }
        let seconds = Int(value.rounded())
        let hours = seconds / 3_600
        let minutes = seconds / 60 % 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }

    private static func codecDescription(_ stream: [String: Any]?) -> String? {
        text(stream?["codec_long_name"]) ?? text(stream?["codec_name"])?.uppercased()
    }

    private static func bitRate(_ value: Int64?) -> String {
        guard let value, value > 0 else { return "Not reported" }
        if value >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(value) / 1_000_000)
        }
        return String(format: "%.0f kbps", Double(value) / 1_000)
    }

    private static func colorDescription(_ stream: [String: Any]?) -> String {
        guard let stream else { return "Not reported" }
        let transfer = text(stream["color_transfer"])
        let primaries = text(stream["color_primaries"])
        let pixelFormat = text(stream["pix_fmt"])
        let sideData = stream["side_data_list"] as? [[String: Any]] ?? []
        let hasDolbyVision = sideData.contains {
            let type = text($0["side_data_type"])?.lowercased() ?? ""
            return type.contains("dovi") || type.contains("dolby vision")
        }
        let dynamicRange: String
        if hasDolbyVision {
            dynamicRange = "Dolby Vision HDR"
        } else if transfer == "smpte2084" {
            dynamicRange = "HDR (PQ)"
        } else if transfer == "arib-std-b67" {
            dynamicRange = "HDR (HLG)"
        } else if primaries == "bt2020" {
            dynamicRange = "BT.2020 wide color"
        } else {
            dynamicRange = "SDR or not reported"
        }
        return [dynamicRange, pixelFormat, primaries].compactMap { $0 }.joined(separator: ", ")
    }

    private static func audioDescription(_ stream: [String: Any]?, hasAudio: Bool) -> String {
        guard let stream else { return hasAudio ? "Present" : "No audio track" }
        let codec = codecDescription(stream) ?? "Audio track"
        guard let channels = number(stream["channels"]).map(Int.init), channels > 0 else { return codec }
        return "\(codec), \(channels) ch"
    }
}
enum SystemCaptionPreferences {
    static var prefersSubtitlesAndSDH: Bool {
        let characteristics = MACaptionAppearanceCopyPreferredCaptioningMediaCharacteristics(.user)
            .takeRetainedValue() as? [String] ?? []
        return prefersSubtitlesAndSDH(in: characteristics)
    }

    static func prefersSubtitlesAndSDH(in characteristics: [String]) -> Bool {
        let spokenDialogue = MAMediaCharacteristicTranscribesSpokenDialogForAccessibility as String
        let musicAndSound = MAMediaCharacteristicDescribesMusicAndSoundForAccessibility as String
        return characteristics.contains(spokenDialogue) || characteristics.contains(musicAndSound)
    }
}

struct StudioSettings: Codable, Equatable {
    static let defaultLibraryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/VidiStudio Projects")
    static let legacyDefaultLibraryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Movies/VidiStudio Projects")
    /// The Gemini API key is owned by the macOS Keychain, not this struct or the config
    /// file. It is intentionally a computed property so it is excluded from `Codable`
    /// (never written to `config.json`) and survives app updates and reinstalls.
    var apiKey: String {
        get { KeychainStore.read() ?? "" }
        set { KeychainStore.write(newValue) }
    }
    var geminiPlan = "free"
    var models: [String: String] = [:]
    var prompts: [String: [String: String]] = [:]
    var apiVersion = "v1beta"
    var videoProcessing = "agentic"

    var hasApiKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var theme = "system"
    /// Reveals advanced Settings surfaces such as Developer prompts. Off by default.
    var developerMode = false
    var ttsMode = "system"
    var narrationPlayback = "generated"
    var soundWhenNarrationOff = true
    var soundWhenNarrationMissing = true
    var systemVoice = ""
    var piperVoice = ""
    var systemSpeechRate = 1.0
    var systemSpeechPitch = 1.0
    var systemSpeechVolume = 1.0
    var summarySentenceHighlight = SummaryHighlightColor.defaultSentenceHex
    var summaryWordHighlight = SummaryHighlightColor.defaultWordHex
    var captionDisplayMode = "off"
    var captionFontSize = 24.0
    var captionTextColor = "#FFFFFF"
    var captionBackgroundColor = "#000000"
    var adCaptionTextColor = "#FFD60A"
    var adCaptionBackgroundColor = "#3A2F00"
    var captionBackgroundOpacity = 0.75
    var captionPosition = "bottom"
    var geminiVoice = "Kore"
    var ffmpegPath = ""
    var ffprobePath = ""
    var libraryPath = StudioSettings.defaultLibraryURL.path
    static var url: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/VidiStudio/config.json") }

    var narrationSignature: String {
        if ttsMode == "gemini" {
            return "gemini|\(geminiVoice)|\(models["tts_audio"] ?? "")"
        }
        if ttsMode == "piper" {
            return piperSpeechSignature
        }
        return systemSpeechSignature
    }

    var piperSpeechSignature: String {
        String(
            format: "piper|%@|%.3f|%.3f|%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            piperVoiceSignature,
            systemSpeechRate,
            systemSpeechPitch,
            systemSpeechVolume
        )
    }

    /// Piper falls back to a legacy Piper id that older builds stored in `systemVoice`.
    var piperVoiceSignature: String {
        let selected = piperVoice.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty { return selected }
        let legacy = systemVoice.trimmingCharacters(in: .whitespacesAndNewlines)
        return legacy.isEmpty ? "Piper voice" : legacy
    }

    var currentNarrationEngine: String {
        if ttsMode == "gemini" { return "gemini" }
        if ttsMode == "piper" { return "piper" }
        return "system"
    }

    var currentNarrationVoice: String {
        if ttsMode == "gemini" {
            let trimmed = geminiVoice.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Kore" : trimmed
        }
        if ttsMode == "piper" { return piperVoiceSignature }
        let selected = systemVoice.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty { return selected }
        if let voice = SystemSpeechVoiceResolver.defaultVoiceDisplayName {
            return "System default (\(voice))"
        }
        return "System default"
    }

    var currentNarrationSummary: String {
        NarrationVoiceFormatting.combinedLabel(voice: currentNarrationVoice, engine: currentNarrationEngine)
    }

    var systemSpeechSignature: String {
        let selectedVoice = systemVoice.trimmingCharacters(in: .whitespacesAndNewlines)
        let voiceSignature = selectedVoice.isEmpty
            ? "default:\(SystemSpeechVoiceResolver.defaultVoiceIdentifier ?? "automatic")"
            : selectedVoice
        return String(
            format: "system|%@|%.3f|%.3f|%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            voiceSignature,
            systemSpeechRate,
            systemSpeechPitch,
            systemSpeechVolume
        )
    }

    /// Recognizes catalog ids such as `en_US-amy-low` without treating Apple voice names as Piper.
    static func looksLikePiperVoiceIdentifier(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].contains("_") else { return false }
        return ["x_low", "low", "medium", "high"].contains(parts[2].lowercased())
    }

    mutating func restoreSystemSpeechDefaults() {
        systemSpeechRate = 1.0
        systemSpeechPitch = 1.0
        systemSpeechVolume = 1.0
    }

    mutating func restoreSummaryHighlightDefaults() {
        summarySentenceHighlight = SummaryHighlightColor.defaultSentenceHex
        summaryWordHighlight = SummaryHighlightColor.defaultWordHex
    }

    mutating func restoreCaptionAppearanceDefaults() {
        captionFontSize = 24.0
        captionTextColor = "#FFFFFF"
        captionBackgroundColor = "#000000"
        adCaptionTextColor = "#FFD60A"
        adCaptionBackgroundColor = "#3A2F00"
        captionBackgroundOpacity = 0.75
        captionPosition = "bottom"
    }
}

extension Notification.Name {
    static let vidiStudioOpenSettingsSection = Notification.Name("VidiStudioOpenSettingsSection")
    static let vidiStudioSettingsDidChange = Notification.Name("VidiStudioSettingsDidChange")
    static let vidiStudioProjectNarrationDidChange = Notification.Name("VidiStudioProjectNarrationDidChange")
    static let vidiStudioProjectFollowDidChange = Notification.Name("VidiStudioProjectFollowDidChange")
    static let vidiStudioNarrationAudioWillDelete = Notification.Name("VidiStudioNarrationAudioWillDelete")
}

/// Handoff for opening Settings on a specific section. The request is stored in
/// UserDefaults as well as posted, because the Settings view may not exist yet
/// when the request is made and would otherwise miss the notification.
enum SettingsSectionRequest {
    static let defaultsKey = "VidiStudioRequestedSettingsSection"

    static func request(_ section: String) {
        UserDefaults.standard.set(section, forKey: defaultsKey)
        NotificationCenter.default.post(
            name: .vidiStudioOpenSettingsSection,
            object: nil,
            userInfo: ["section": section]
        )
    }

    /// Returns and clears a pending request, or nil when there is none.
    static func consume() -> String? {
        guard let section = UserDefaults.standard.string(forKey: defaultsKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        return section
    }
}

/// Project-specific playback choices persisted in the project's `project.json`.
/// Both desktop apps read and write the same `playback` object, so the choices
/// travel with the project folder instead of staying on one computer.
struct ProjectPlaybackSettings: Codable, Equatable {
    var narrationEnabled: Bool?
    var followTranscript: Bool?
}

enum ProjectPlaybackPreferences {
    static let narrationField = "narrationEnabled"
    static let followField = "followTranscript"

    /// Legacy user-defaults keys used before the choices moved into project.json.
    /// They are read once to migrate an existing choice and are never written.
    static func narrationKey(_ projectID: String) -> String {
        "projectNarrationEnabled.\(projectID)"
    }

    static func followKey(_ projectID: String) -> String {
        "projectFollowTranscript.\(projectID)"
    }

    static func narrationEnabled(folder: URL?, projectID: String) -> Bool {
        value(
            for: narrationField,
            folder: folder,
            projectID: projectID,
            legacyKey: narrationKey(projectID)
        ) ?? false
    }

    static func followEnabled(folder: URL?, projectID: String) -> Bool {
        value(
            for: followField,
            folder: folder,
            projectID: projectID,
            legacyKey: followKey(projectID)
        ) ?? true
    }

    static func setNarrationEnabled(_ enabled: Bool, folder: URL?, projectID: String) {
        guard value(for: narrationField, folder: folder, projectID: projectID, legacyKey: nil) != enabled else { return }
        write(narrationField, enabled, folder: folder, projectID: projectID)
        announceNarrationChange(enabled, projectID: projectID)
    }

    static func setFollowEnabled(_ enabled: Bool, folder: URL?, projectID: String) {
        guard value(for: followField, folder: folder, projectID: projectID, legacyKey: nil) != enabled else { return }
        write(followField, enabled, folder: folder, projectID: projectID)
        announceFollowChange(enabled, projectID: projectID)
    }

    static func announceNarrationChange(_ enabled: Bool, projectID: String) {
        NotificationCenter.default.post(
            name: .vidiStudioProjectNarrationDidChange,
            object: nil,
            userInfo: ["projectID": projectID, "enabled": enabled]
        )
    }

    static func announceFollowChange(_ enabled: Bool, projectID: String) {
        NotificationCenter.default.post(
            name: .vidiStudioProjectFollowDidChange,
            object: nil,
            userInfo: ["projectID": projectID, "enabled": enabled]
        )
    }

    /// Reads the saved choice from project.json. A choice made before it moved
    /// into the project is migrated once from the legacy user-defaults key.
    private static func value(
        for field: String,
        folder: URL?,
        projectID: String,
        legacyKey: String?
    ) -> Bool? {
        guard !projectID.isEmpty else { return nil }
        if let saved = manifestPlayback(folder)?[field] as? Bool { return saved }
        guard let legacyKey,
              let legacy = UserDefaults.standard.object(forKey: legacyKey) as? Bool else { return nil }
        write(field, legacy, folder: folder, projectID: projectID)
        return legacy
    }

    /// Writes one playback choice into project.json while preserving every
    /// other project field, including fields this app does not model.
    private static func write(_ field: String, _ enabled: Bool, folder: URL?, projectID: String) {
        guard !projectID.isEmpty,
              let url = manifestURL(folder),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              var root = object as? [String: Any] else { return }
        var playback = root["playback"] as? [String: Any] ?? [:]
        playback[field] = enabled
        root["playback"] = playback
        guard let updated = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) else { return }
        try? updated.write(to: url, options: .atomic)
    }

    private static func manifestPlayback(_ folder: URL?) -> [String: Any]? {
        guard let url = manifestURL(folder),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else { return nil }
        return root["playback"] as? [String: Any]
    }

    private static func manifestURL(_ folder: URL?) -> URL? {
        folder?.appendingPathComponent("project.json")
    }
}

struct OpenProjectReference: Identifiable, Equatable {
    let id: String
    var name: String
    var folder: URL?
}

@MainActor @Observable
final class OpenProjectRegistry {
    private(set) var projects: [OpenProjectReference] = []

    func open(_ id: String, name: String, folder: URL? = nil) {
        if let index = projects.firstIndex(where: { $0.id == id }) {
            if projects[index].name != name { projects[index].name = name }
            if let folder, projects[index].folder != folder { projects[index].folder = folder }
        } else {
            projects.append(OpenProjectReference(id: id, name: name, folder: folder))
        }
    }

    func close(_ id: String) {
        projects.removeAll { $0.id == id }
    }
}

@MainActor @Observable
final class StudioModel {
    static let defaultErrorTitle = "VidiStudio Couldn’t Finish"
    var projects: [StudioProject] = []
    /// Latest integrity audit for every project currently shown, including
    /// in-memory damaged placeholders whose project.json cannot be decoded.
    var projectIntegrity: [String: ProjectIntegrityReport] = [:]
    var selectedID: String? { didSet { UserDefaults.standard.set(selectedID, forKey: "lastProjectID") } }
    var settings = StudioSettings() {
        didSet {
            if settings.apiKey != oldValue.apiKey {
                aiServiceIssue = nil
                apiKeyVerified = nil
                apiKeyVerificationMessage = nil
            }
            guard settingsPersistenceEnabled, !applyingExternalSettings, settings != oldValue else { return }
            persistSettings(reloadProjects: settings.libraryPath != oldValue.libraryPath)
        }
    }
    @ObservationIgnored private var settingsPersistenceEnabled = false
    @ObservationIgnored private var applyingExternalSettings = false
    var settingsSection = "Appearance"
    var busy = false
    var processingSection: String?
    /// Ordered analysis stages for the run in progress (for example
    /// `["transcript", "summary", "descriptions"]` for Analyze Video). Empty for
    /// commands that do not process a section.
    var processingPlan: [String] = []
    var videoPreparationActivity: VideoPreparationActivity?
    var exportActivity: ExportSession? {
        didSet {
            if let oldValue, oldValue.id != exportActivity?.id {
                ExportSessionRegistry.shared.end(oldValue)
            }
        }
    }
    var cancellationRequested = false
    var message = "All files stay in your local project folders."
    var progress = 0.0
    var error: String?
    var errorTitle = StudioModel.defaultErrorTitle
    var narrationFailureReport: NarrationFailureReport?
    var narrationVoiceReport: NarrationVoiceReport?
    /// Import reports produced during the current import batch. The editor
    /// presents them together and clears them after review.
    var importReports: [ImportReport] = []
    @ObservationIgnored private var pendingVoiceMismatchReview = false
    var isSynthesizingNarration = false
    var narratingSegmentID: String?
    var narratingSegmentIndex: Int?
    var narratingTotalCount = 0
    var narratingQueueIDs: Set<String> = []
    var logs: [String] = []
    var screenText: String?
    var screenTimestamp = 0.0
    var process: Process?
    var isCreatingProject = false
    /// Opens the New Project dialog. Local and YouTube projects can be created
    /// without a Gemini key; AI actions explain their own prerequisites later.
    func beginNewProject() {
        // Creating a project never requires a Gemini key. AI actions remain
        // gated separately and explain their prerequisite when invoked.
        isCreatingProject = true
    }
    var availableGeminiModels: [GeminiModelOption] = []
    var geminiModelsLoaded = false
    var apiKeyVerified: Bool? = nil
    /// Non-nil after a quota, billing, or service-level Gemini failure. It
    /// disables every AI action until Retry AI succeeds or the key changes.
    var aiServiceIssue: AIServiceIssue?
    var isAIProcessingBlocked: Bool { aiServiceIssue != nil }
    var apiKeyVerificationMessage: String? = nil
    var hasApiKey: Bool { settings.hasApiKey }
    var hasValidApiKey: Bool { hasApiKey && apiKeyVerified != false && !isAIProcessingBlocked }
    var isApiKeyInvalid: Bool { hasApiKey && apiKeyVerified == false }
    var engineCheckStatus: EngineCheckStatus = .unchecked
    var selected: StudioProject? { projects.first { $0.id == selectedID } }

    func cancelCurrentOperation() {
        guard busy, !cancellationRequested, let process else { return }
        cancellationRequested = true
        message = exportActivity == nil ? "Stopping the current operation…" : "Stopping the export…"
        exportActivity?.cancelling = true
        exportActivity?.status = message
        process.terminate()
    }

    func isSegmentNarrating(_ segmentID: String) -> Bool {
        isSynthesizingNarration && narratingSegmentID == segmentID
    }

    func isSegmentQueuedForNarration(_ segmentID: String) -> Bool {
        isSynthesizingNarration && narratingSegmentID != segmentID && narratingQueueIDs.contains(segmentID)
    }

    var activeNarrationStatusText: String {
        if let index = narratingSegmentIndex, narratingTotalCount > 0 {
            return "Generating audio for AD segment \(index) of \(narratingTotalCount)…"
        }
        return "Generating narration audio…"
    }

    func dismissError() {
        error = nil
        errorTitle = StudioModel.defaultErrorTitle
    }

    /// Builds the narration status report from the current project so the issues
    /// can be reviewed at any time without regenerating every description.
    func narrationIssueReport(for project: StudioProject) -> NarrationFailureReport {
        var failures: [NarrationFailure] = []
        var ready = 0
        for (index, cue) in project.cues.enumerated() {
            var reasons: [String]
            if SynchronizedAudioStatus.resolve(cue: cue, project: project) == .notGenerated {
                if let error = cue.audioError, !error.isEmpty {
                    reasons = [error]
                } else {
                    reasons = [cue.audio == nil ? "Narration audio has not been generated." : "The generated narration audio file is missing or unavailable."]
                }
            } else {
                reasons = cue.narrationUpdateReasons
            }
            if !reasons.isEmpty {
                failures.append(NarrationFailure(id: index + 1, start: cue.start, end: cue.end,
                                                 duration: cue.end - cue.start, reason: reasons.joined(separator: "\n")))
            } else {
                ready += 1
            }
        }
        let total = project.cues.count
        let detail = total == 0 ? "There are no audio description segments in this project yet." : failures.isEmpty
            ? "All \(total) audio description segments have current narration audio."
            : "\(failures.count) of \(total) description\(total == 1 ? "" : "s") need attention."
        let counts = project.narrationSourceCounts
        var warnings: [String] = []
        if counts.hasMixedSources {
            warnings.append("This project mixes AI-generated narration (\(counts.generated) segments) and imported narration (\(counts.imported) segments).")
        }
        if project.importedNarrationFiles.count > 1 {
            warnings.append("Imported narration comes from \(project.importedNarrationFiles.count) different audio files: \(project.importedNarrationFiles.joined(separator: ", ")).")
        }
        if counts.imported > 0 && counts.generated == 0 && counts.unknown == 0 {
            warnings.append("All narration audio in this project is imported. Generated voice settings do not apply to these segments.")
        }
        if counts.generated > 0 && counts.imported == 0 && counts.unknown == 0 {
            warnings.append("This project uses only AI-generated narration.")
        }
        if counts.unknown > 0 {
            warnings.append("\(counts.unknown) narration segment(s) have no recorded source and are labelled Unknown voice.")
        }
        return NarrationFailureReport(title: "Narration status", detail: detail, generated: ready, failures: failures, warnings: warnings)
    }

    /// Builds a detailed report of narration voice and engine usage across segments.
    func narrationVoiceUsageReport(for project: StudioProject) -> NarrationVoiceReport {
        var narratedEntries: [(index: Int, cue: Segment, engine: String, voice: String, path: String)] = []
        var importedEntries: [NarrationVoiceSegmentEntry] = []
        var generatedCount = 0
        for (index, cue) in project.cues.enumerated() {
            guard let path = cue.audio,
                  let url = project.url(path),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            if cue.audioOrigin == "imported" {
                let source = cue.audioSourceName ?? "Unknown source file"
                importedEntries.append(NarrationVoiceSegmentEntry(
                    id: index + 1, start: cue.start, end: cue.end,
                    duration: max(0, cue.end - cue.start),
                    engine: "imported", engineDisplayName: "Imported audio",
                    voice: source, voiceDisplayName: source, audioFile: path,
                    usesDifferentVoice: false,
                    reason: "Imported audio from \(source). It is not generated narration and does not use a selected voice.",
                    isImported: true))
                continue
            }
            generatedCount += 1
            let engine = cue.resolvedAudioEngine ?? "unknown"
            let voice = cue.resolvedAudioVoice ?? "Unknown voice"
            narratedEntries.append((index: index + 1, cue: cue, engine: engine, voice: voice, path: path))
        }
        if narratedEntries.isEmpty && importedEntries.isEmpty {
            return NarrationVoiceReport(
                title: "Narration voice details",
                detail: "No narration audio has been generated for this project yet.",
                primaryVoiceLabel: nil,
                hasDifferentVoices: false,
                voiceSummaries: [],
                differentSegments: [],
                allSegments: []
            )
        }
        if narratedEntries.isEmpty {
            let files = Set(importedEntries.map(\.voiceDisplayName)).sorted()
            return NarrationVoiceReport(
                title: "Imported narration audio",
                detail: "All narration audio in this project is imported. Generated voice settings do not apply to these segments.",
                primaryVoiceLabel: nil,
                hasDifferentVoices: false,
                voiceSummaries: [],
                differentSegments: [],
                allSegments: importedEntries,
                importedCount: importedEntries.count,
                hasMixedSources: importedEntries.count > 0,
                importedFiles: files
            )
        }
        let primaryEngine: String
        let primaryVoice: String
        if let savedEngine = project.narrationEngine?.trimmingCharacters(in: .whitespacesAndNewlines),
           let savedVoice = project.narrationVoice?.trimmingCharacters(in: .whitespacesAndNewlines),
           !savedEngine.isEmpty, !savedVoice.isEmpty {
            primaryEngine = savedEngine
            primaryVoice = savedVoice
        } else {
            primaryEngine = narratedEntries[0].engine
            primaryVoice = narratedEntries[0].voice
        }
        let primaryLabel = NarrationVoiceFormatting.combinedLabel(voice: primaryVoice, engine: primaryEngine)
        var allSegments: [NarrationVoiceSegmentEntry] = []
        var differentSegments: [NarrationVoiceSegmentEntry] = []
        var grouped: [(engine: String, voice: String, isDifferent: Bool, numbers: [Int])] = []

        for item in narratedEntries {
            let matchesPrimary = NarrationVoiceFormatting.voicesMatch(
                engineA: item.engine, voiceA: item.voice,
                engineB: primaryEngine, voiceB: primaryVoice
            )
            let engineDisplay = NarrationVoiceFormatting.engineDisplayName(item.engine)
            let voiceDisplay = NarrationVoiceFormatting.voiceDisplayName(item.voice)
            let reason = matchesPrimary
                ? "Uses primary voice \(voiceDisplay) (\(engineDisplay))"
                : "Different voice: uses \(voiceDisplay) (\(engineDisplay)) instead of \(primaryLabel)"
            let entry = NarrationVoiceSegmentEntry(
                id: item.index,
                start: item.cue.start,
                end: item.cue.end,
                duration: max(0, item.cue.end - item.cue.start),
                engine: item.engine,
                engineDisplayName: engineDisplay,
                voice: item.voice,
                voiceDisplayName: voiceDisplay,
                audioFile: item.path,
                usesDifferentVoice: !matchesPrimary,
                reason: reason
            )
            allSegments.append(entry)
            if !matchesPrimary {
                differentSegments.append(entry)
            }
            if let existingIndex = grouped.firstIndex(where: {
                NarrationVoiceFormatting.voicesMatch(engineA: $0.engine, voiceA: $0.voice, engineB: item.engine, voiceB: item.voice)
            }) {
                grouped[existingIndex].numbers.append(item.index)
            } else {
                grouped.append((engine: item.engine, voice: item.voice, isDifferent: !matchesPrimary, numbers: [item.index]))
            }
        }
        if !grouped.contains(where: {
            NarrationVoiceFormatting.voicesMatch(engineA: $0.engine, voiceA: $0.voice, engineB: primaryEngine, voiceB: primaryVoice)
        }) {
            grouped.insert((engine: primaryEngine, voice: primaryVoice, isDifferent: false, numbers: []), at: 0)
        }
        let summaries = grouped.map { group in
            NarrationVoiceSummary(
                id: "\(group.engine)|\(group.voice)",
                engine: group.engine,
                engineDisplayName: NarrationVoiceFormatting.engineDisplayName(group.engine),
                voice: group.voice,
                voiceDisplayName: NarrationVoiceFormatting.voiceDisplayName(group.voice),
                count: group.numbers.count,
                segmentNumbers: group.numbers,
                isDifferentVoice: group.isDifferent
            )
        }
        allSegments.append(contentsOf: importedEntries)
        let hasDifferent = !differentSegments.isEmpty || summaries.filter { $0.count > 0 }.count > 1
        let activeVoiceCount = summaries.filter { $0.count > 0 }.count
        let hasMixedSources = !importedEntries.isEmpty && generatedCount > 0
        var detail: String
        if hasDifferent {
            let breakdown = summaries.map { "\($0.combinedLabel): \($0.count) segment\($0.count == 1 ? "" : "s")" }.joined(separator: "; ")
            detail = "\(differentSegments.count) of \(generatedCount) generated segment\(generatedCount == 1 ? "" : "s") use a different voice from \(primaryLabel). (\(breakdown))"
        } else {
            detail = "All \(generatedCount) generated audio description segment\(generatedCount == 1 ? "" : "s") use \(primaryLabel)."
        }
        if !importedEntries.isEmpty {
            detail += " \(importedEntries.count) segment\(importedEntries.count == 1 ? "" : "s") use imported audio from \(Set(importedEntries.map(\.voiceDisplayName)).sorted().joined(separator: ", "))."
        }
        return NarrationVoiceReport(
            title: hasDifferent || hasMixedSources ? "Narration sources need review" : "Narration voice details",
            detail: detail,
            primaryVoiceLabel: primaryLabel,
            hasDifferentVoices: hasDifferent || activeVoiceCount > 1,
            voiceSummaries: summaries,
            differentSegments: differentSegments,
            allSegments: allSegments,
            importedCount: importedEntries.count,
            hasMixedSources: hasMixedSources,
            importedFiles: Set(importedEntries.map(\.voiceDisplayName)).sorted()
        )
    }

    func present(_ issue: UserFacingIssue, technicalDetails: String? = nil, context: String = "VidiStudio") {
        errorTitle = issue.title
        error = issue.message
        guard let technicalDetails, !technicalDetails.isEmpty else { return }
        UserFacingIssueReporter.record(technicalDetails, context: context)
        logs.append("\(context): \(technicalDetails)")
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
    }

    init() {
        var merged = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(settings))) as? [String: Any] ?? [:]
        var hasSavedCaptionDisplayMode = false
        var legacyApiKey: String?
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Engine/_internal/ai-defaults.json"),
           let data = try? Data(contentsOf: url), let defaults = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["models", "prompts", "apiVersion", "videoProcessing"] { merged[key] = defaults[key] }
        }
        if let data = try? Data(contentsOf: StudioSettings.url), let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            hasSavedCaptionDisplayMode = saved["captionDisplayMode"] is String
            legacyApiKey = saved["apiKey"] as? String
            if let savedModels = saved["models"] as? [String: Any] {
                var models = merged["models"] as? [String: Any] ?? [:]
                for (key, value) in savedModels { models[key] = value }
                merged["models"] = models
            }
            if let savedPrompts = saved["prompts"] as? [String: Any] {
                var prompts = merged["prompts"] as? [String: Any] ?? [:]
                for (stage, value) in savedPrompts {
                    guard let overrides = value as? [String: Any] else { continue }
                    var pair = prompts[stage] as? [String: Any] ?? [:]
                    for (key, prompt) in overrides { pair[key] = prompt }
                    prompts[stage] = pair
                }
                merged["prompts"] = prompts
            }
            for (key, value) in saved where key != "models" && key != "prompts" { merged[key] = value }
        }
        var seededCaptionDisplayMode = false
        if let data = try? JSONSerialization.data(withJSONObject: merged), let decoded = try? JSONDecoder().decode(StudioSettings.self, from: data) {
            settings = decoded
        }
        var migratedLibrary = false
        if settings.libraryPath == StudioSettings.legacyDefaultLibraryURL.path {
            settings.libraryPath = StudioSettings.defaultLibraryURL.path
            migratedLibrary = true
        }
        if !hasSavedCaptionDisplayMode, SystemCaptionPreferences.prefersSubtitlesAndSDH {
            settings.captionDisplayMode = "transcript"
            seededCaptionDisplayMode = true
        }
        // Azure Voices was removed; its legacy choice falls back to Apple Voices.
        // Older Mac builds also stored Piper voice ids in `systemVoice`, so move
        // those into the Piper selection now that Piper speech is available again.
        var migratedSpeechEngine = false
        if settings.ttsMode == "azure" {
            settings.ttsMode = "system"
            migratedSpeechEngine = true
        }
        if settings.piperVoice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let legacyVoice = settings.systemVoice.trimmingCharacters(in: .whitespacesAndNewlines)
            if StudioSettings.looksLikePiperVoiceIdentifier(legacyVoice) {
                settings.piperVoice = legacyVoice
                settings.systemVoice = ""
                migratedSpeechEngine = true
            }
        }
        settingsPersistenceEnabled = true
        // One-time migration: move any plaintext key left in config.json into the Keychain,
        // then re-save so the on-disk file no longer contains it.
        var migratedApiKey = false
        if let legacyApiKey, !legacyApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if KeychainStore.containsValue() || KeychainStore.write(legacyApiKey) { migratedApiKey = true }
        }
        if migratedLibrary || seededCaptionDisplayMode || migratedSpeechEngine || migratedApiKey { persistSettings(reloadProjects: false) }
        reload()
        selectedID = UserDefaults.standard.string(forKey: "lastProjectID")
    }

    func applyExternalSettings(_ updated: StudioSettings) {
        let libraryChanged = settings.libraryPath != updated.libraryPath
        applyingExternalSettings = true
        settings = updated
        applyingExternalSettings = false
        if libraryChanged { reload() }
    }

    private func persistSettings(reloadProjects: Bool) {
        do {
            let directory = StudioSettings.url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(settings).write(to: StudioSettings.url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: StudioSettings.url.path)
            if reloadProjects { reload() }
            NotificationCenter.default.post(
                name: .vidiStudioSettingsDidChange,
                object: self,
                userInfo: ["settings": settings]
            )
        } catch {
            present(.settingsSave, technicalDetails: error.localizedDescription, context: "Save settings")
        }
    }
    func reload() {
        let root = URL(fileURLWithPath: settings.libraryPath).standardizedFileURL
        let previous = selected?.folder?.standardizedFileURL
        var candidates: [URL: Bool] = [:]
        let libraryFolders = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for folder in libraryFolders {
            candidates[folder.standardizedFileURL] = false
        }
        for path in UserDefaults.standard.stringArray(forKey: "recentProjectFolders") ?? [] {
            candidates[URL(fileURLWithPath: path).standardizedFileURL] = true
        }
        if let previous {
            candidates[previous] = true
        }

        var loaded: [StudioProject] = []
        var integrity: [String: ProjectIntegrityReport] = [:]
        for (folder, referenced) in candidates {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
            if exists && !isDirectory.boolValue { continue }
            let isOpenProject = folder == previous

            if let project = Self.loadProject(at: folder) {
                loaded.append(project)
                integrity[project.id] = StudioProjectIntegrity.inspect(project)
                continue
            }

            // Keep a damaged entry visible when its manifest is gone and the
            // folder still exists. A missing folder is only kept for the
            // project currently open in an editor, so old recent paths do not
            // turn into permanent ghost entries.
            guard exists || isOpenProject else { continue }
            guard !busy || referenced || isOpenProject else { continue }
            guard (exists ? ProjectIntegrityAuditor.folderLooksLikeProject(folder) : true) else { continue }

            let placeholder = StudioProjectIntegrity.damagedPlaceholder(folder: folder)
            loaded.append(placeholder)
            integrity[placeholder.id] = StudioProjectIntegrity.inspect(placeholder)
        }

        projects = loaded.sorted { $0.updatedAt > $1.updatedAt }
        projectIntegrity = integrity
        // If the selected project turned into a damaged placeholder with a
        // different synthesized ID, keep the editor pointed at the same folder.
        if let previous,
           let selectedID,
           !projects.contains(where: { $0.id == selectedID }),
           let replacement = projects.first(where: { $0.folder?.standardizedFileURL == previous }) {
            self.selectedID = replacement.id
        }
    }

    private static func loadProject(at folder: URL) -> StudioProject? {
        let manifest = folder.appendingPathComponent("project.json")
        guard let data = try? Data(contentsOf: manifest), !data.isEmpty,
              var project = try? JSONDecoder().decode(StudioProject.self, from: data) else {
            return nil
        }
        project.folder = folder
        project.integrityPlaceholder = nil
        return project
    }

    func integrityReport(for project: StudioProject) -> ProjectIntegrityReport {
        projectIntegrity[project.id] ?? StudioProjectIntegrity.inspect(project)
    }

    /// Re-audits all projects, upgrading placeholders when their manifest is
    /// restored. Called on app activation and by the project browser's timer.
    func refreshProjectIntegrity() {
        var reports: [String: ProjectIntegrityReport] = [:]
        var shouldReload = false
        for project in projects {
            let report = StudioProjectIntegrity.inspect(project)
            if project.integrityPlaceholder == true,
               !report.manifestUnreadable,
               !report.folderMissing {
                shouldReload = true
            }
            reports[project.id] = report
        }
        projectIntegrity = reports
        if shouldReload { reload() }
    }

    /// Re-audits the project shown in one editor window without touching the
    /// rest of the library.
    func refreshProjectIntegrity(for projectID: String) {
        guard let project = projects.first(where: { $0.id == projectID }) else { return }
        let report = StudioProjectIntegrity.inspect(project)
        if project.integrityPlaceholder == true,
           !report.manifestUnreadable,
           !report.folderMissing {
            let folder = project.folder
            reload()
            if let folder,
               let restored = projects.first(where: { $0.folder?.standardizedFileURL == folder.standardizedFileURL }) {
                selectedID = restored.id
            }
            return
        }
        if projectIntegrity[project.id] != report {
            var reports = projectIntegrity
            reports[project.id] = report
            projectIntegrity = reports
        }
    }
    func importVideo() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.prompt = "Import Video"
        panel.message = "A copy will be saved in your local project library."
        if panel.runModal() == .OK, let url = panel.url {
            importVideo(at: url)
        }
    }
    @discardableResult
    func importVideo(at url: URL, completion: ((StudioProject?) -> Void)? = nil) -> Bool {
        guard !busy else { return false }
        guard validateLocalVideoForCreation(url) else { return false }
        if let existing = existingProject(forVideoAt: url) {
            showDuplicateProjectError(existing)
            return false
        }
        execute(
            "import-video",
            extra: ["--video", url.path, "--library", settings.libraryPath],
            project: nil,
            completion: completion
        )
        return true
    }
    func validateLocalVideoForCreation(_ url: URL) -> Bool {
        guard LocalVideoFilePolicy.isSupportedVideo(url) else {
            errorTitle = "Unsupported Video File"
            error = "Choose a video that plays on this Mac, such as an MP4 or MOV file."
            return false
        }
        do {
            let size = try LocalVideoFilePolicy.size(at: url)
            guard size <= LocalVideoFilePolicy.maximumSizeBytes else {
                errorTitle = "Video File Too Large"
                error = "\(url.lastPathComponent) is \(LocalVideoFilePolicy.displaySize(size)). VidiStudio currently accepts video files up to 2 GB. Choose a smaller copy, or use a YouTube link when the video is available online."
                return false
            }
            return true
        } catch {
            errorTitle = "Video File Unavailable"
            self.error = "VidiStudio could not read the size of \(url.lastPathComponent). Choose an available local video file and try again."
            return false
        }
    }
    @discardableResult
    func importYouTube(at rawURL: String, name: String? = nil, completion: ((StudioProject?) -> Void)? = nil) -> Bool {
        guard !busy else { return false }
        guard validateYouTubeForCreation(rawURL) else { return false }
        var arguments = ["--url", rawURL, "--library", settings.libraryPath]
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["--name", name]
        }
        execute("import-youtube", extra: arguments, project: nil, completion: completion)
        return true
    }
    func validateYouTubeForCreation(_ rawURL: String) -> Bool {
        if let existing = existingProject(forYouTubeURL: rawURL) {
            showDuplicateProjectError(existing)
            return false
        }
        return true
    }
    func existingProject(forVideoAt url: URL) -> StudioProject? {
        let filename = url.lastPathComponent
        return projects.first {
            !$0.isYouTubeURLProject
                && URL(fileURLWithPath: $0.source).lastPathComponent.caseInsensitiveCompare(filename) == .orderedSame
        }
    }
    func existingProject(forYouTubeURL rawURL: String) -> StudioProject? {
        let candidate = Self.youtubeVideoID(from: rawURL)
        return projects.first { project in
            guard project.isYouTubeURLProject, let existingURL = project.youtubeURL else { return false }
            if let candidate, let existingID = Self.youtubeVideoID(from: existingURL) {
                return candidate == existingID
            }
            return existingURL.trimmingCharacters(in: .whitespacesAndNewlines)
                == rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    private func showDuplicateProjectError(_ project: StudioProject) {
        selectedID = project.id
        errorTitle = "Project Already Exists"
        error = "A project for this video already exists as “\(project.name)”. Please continue with the existing project or delete the existing project before continuing."
    }
    static func youtubeVideoID(from rawURL: String) -> String? {
        VidiStudioShareLink.youtubeVideoID(from: rawURL)
    }
    func chooseProjectLibrary() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Project Folder"
        panel.message = "Choose the folder where new VidiStudio projects will be created."
        let current = URL(fileURLWithPath: settings.libraryPath)
        panel.directoryURL = FileManager.default.fileExists(atPath: current.path)
            ? current
            : current.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            settings.libraryPath = url.standardizedFileURL.path
        }
    }
    func chooseFFmpeg() {
        chooseMediaTool(named: "FFmpeg", currentPath: settings.ffmpegPath) {
            settings.ffmpegPath = $0
        }
    }
    func chooseFFprobe() {
        chooseMediaTool(named: "FFprobe", currentPath: settings.ffprobePath) {
            settings.ffprobePath = $0
        }
    }
    func checkEngine() {
        guard !busy else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-engine-check-\(UUID().uuidString)")
        let configuration = directory.appendingPathComponent("config.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(settings).write(to: configuration, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configuration.path)
            execute("doctor", configurationURL: configuration, cleanupURL: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            present(.engineCheck, technicalDetails: error.localizedDescription, context: "Check media tools")
            engineCheckStatus = .failed(UserFacingIssue.engineCheck.message)
        }
    }
    private func chooseMediaTool(named name: String, currentPath: String, assign: (String) -> Void) {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose \(name)"
        panel.message = "Choose the \(name) executable. Leave this setting empty to use the copy bundled with VidiStudio."
        if !currentPath.isEmpty {
            let current = URL(fileURLWithPath: currentPath)
            panel.directoryURL = current.deletingLastPathComponent()
        } else if FileManager.default.fileExists(atPath: "/opt/homebrew/bin") {
            panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true)
        }
        if panel.runModal() == .OK, let url = panel.url {
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                errorTitle = "Choose a Different File"
                error = "The selected item cannot be used. Choose the \(name) application or leave this setting empty to use VidiStudio’s included copy."
                return
            }
            assign(url.standardizedFileURL.path)
        }
    }
    func trashProject(_ project: StudioProject) {
        guard !busy, let folder = project.folder else { return }
        guard FileManager.default.fileExists(atPath: folder.path) else {
            forgetProject(project)
            return
        }
        do {
            try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
            if selectedID == project.id { selectedID = nil }
            reload()
        } catch {
            present(.projectDelete, technicalDetails: error.localizedDescription, context: "Move project to Bin")
        }
    }

    /// Removes a project entry whose folder no longer exists. There is nothing
    /// to move to the Bin, so this only clears the app's recent/library record.
    func forgetProject(_ project: StudioProject) {
        projects.removeAll { $0.id == project.id }
        var reports = projectIntegrity
        reports[project.id] = nil
        projectIntegrity = reports
        if selectedID == project.id { selectedID = nil }
        if let path = project.folder?.path {
            var recent = UserDefaults.standard.stringArray(forKey: "recentProjectFolders") ?? []
            let previousCount = recent.count
            recent.removeAll { $0 == path }
            if recent.count != previousCount {
                UserDefaults.standard.set(recent, forKey: "recentProjectFolders")
            }
        }
    }

    func confirmTrashProject(_ project: StudioProject) {
        guard !busy, project.folder != nil else { return }
        let folderExists = project.folder.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        let damaged = project.integrityPlaceholder == true || integrityReport(for: project).isDamaged
        let title: String
        let message: String
        let actionTitle: String
        if !folderExists {
            title = "Remove “\(project.name)” from VidiStudio?"
            message = "The project folder no longer exists, so there are no files to move to the Bin. This removes the missing project entry from VidiStudio."
            actionTitle = "Remove Project"
        } else if damaged {
            title = "Delete damaged project “\(project.name)”?"
            message = "This project is marked as damaged. The complete project folder, including any remaining transcript, description, narration, and export files, will be moved to the Bin. You can restore it until the Bin is emptied."
            actionTitle = "Move to Bin"
        } else {
            title = "Move “\(project.name)” to the Bin?"
            message = "The complete project folder, including its source video or YouTube link, generated content, narration, and exports, will be moved to the Bin. You can restore it until the Bin is emptied."
            actionTitle = "Move to Bin"
        }
        guard confirmDeletion(title: title, message: message, actionTitle: actionTitle) else { return }
        trashProject(project)
    }
    func deleteGeneratedContent(_ project: StudioProject, components: Set<GeneratedContentComponent>) {
        guard !busy, !components.isEmpty else { return }
        selectedID = project.id
        let arguments = components.sorted { $0.rawValue < $1.rawValue }.flatMap { ["--component", $0.rawValue] }
        execute("delete-generated", extra: arguments, project: project)
    }
    func confirmDeleteGeneratedContent(_ project: StudioProject, component: GeneratedContentComponent) {
        _ = confirmDeleteGeneratedContent(project, components: [component])
    }
    @discardableResult
    func confirmDeleteGeneratedContent(_ project: StudioProject, components: Set<GeneratedContentComponent>) -> Bool {
        let available = components.filter { $0.hasContent(in: project) }
        guard !busy, !available.isEmpty else { return false }
        let sorted = available.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let title: String
        let message: String
        let actionTitle: String
        if let component = sorted.first, sorted.count == 1 {
            title = "Delete \(component.title.lowercased()) from “\(project.name)”?"
            message = component.explanation + " The project and original video or YouTube link are kept. This cannot be undone."
            actionTitle = "Delete \(component.title)"
        } else {
            title = "Delete selected components from “\(project.name)”?"
            message = "This permanently deletes: \(sorted.map(\.title).joined(separator: ", ")). The project and original video or YouTube link are kept. This cannot be undone."
            actionTitle = "Delete Selected"
        }
        guard confirmDeletion(title: title, message: message, actionTitle: actionTitle) else { return false }
        if available.contains(.narration) || available.contains(.descriptions) {
            NotificationCenter.default.post(
                name: .vidiStudioNarrationAudioWillDelete,
                object: self,
                userInfo: ["projectID": project.id]
            )
        }
        deleteGeneratedContent(project, components: Set(available))
        return true
    }
    func confirmDeleteExport(_ project: StudioProject, path: String) {
        guard !busy, project.exports.contains(path) else { return }
        let name = URL(fileURLWithPath: path).lastPathComponent
        guard confirmDeletion(
            title: "Delete “\(name)”?",
            message: "The export will be permanently removed from the project to free storage. This cannot be undone.",
            actionTitle: "Delete Export"
        ) else { return }
        deleteExport(project, path: path)
    }
    func deleteExport(_ project: StudioProject, path: String) {
        guard !busy, project.exports.contains(path) else { return }
        selectedID = project.id
        execute("delete-export", extra: ["--name", path], project: project)
    }
    func confirmDeleteSegmentAudio(_ project: StudioProject, cue: Segment, beforeDelete: () -> Void) {
        guard !busy, cue.audio != nil else { return }
        guard confirmDeletion(
            title: "Delete audio for this description?",
            message: "Only the generated narration audio will be deleted. The description text and timing will remain unchanged. This cannot be undone.",
            actionTitle: "Delete Segment Audio"
        ) else { return }
        beforeDelete()
        NotificationCenter.default.post(
            name: .vidiStudioNarrationAudioWillDelete,
            object: self,
            userInfo: ["projectID": project.id]
        )
        selectedID = project.id
        execute("delete-segment-audio", extra: ["--segment", cue.id], project: project)
    }
    func confirmDeleteSegment(_ project: StudioProject, cue: Segment, beforeDelete: () -> Void) {
        _ = confirmDeleteSegments(
            project,
            transcriptIDs: [],
            descriptionIDs: [cue.id],
            beforeDelete: beforeDelete
        )
    }
    @discardableResult
    func confirmDeleteSegments(
        _ project: StudioProject,
        transcriptIDs: Set<String>,
        descriptionIDs: Set<String>,
        beforeDelete: () -> Void
    ) -> Bool {
        let transcriptToDelete = project.transcript.filter { transcriptIDs.contains($0.id) }
        let descriptionsToDelete = project.cues.filter { descriptionIDs.contains($0.id) }
        let count = transcriptToDelete.count + descriptionsToDelete.count
        guard !busy, count > 0 else { return false }
        let title: String
        let message: String
        let actionTitle: String
        if count == 1, transcriptToDelete.count == 1 {
            title = "Delete this transcript segment?"
            message = "The transcript text and timing will be permanently removed. This cannot be undone."
            actionTitle = "Delete Segment"
        } else if count == 1 {
            title = "Delete this Audio Description segment?"
            message = "The description text, timing, and its generated narration audio will be permanently removed. This cannot be undone."
            actionTitle = "Delete Segment"
        } else {
            title = "Delete \(count) selected segments?"
            let transcriptSummary = transcriptToDelete.isEmpty ? nil : "\(transcriptToDelete.count) transcript"
            let descriptionSummary = descriptionsToDelete.isEmpty ? nil : "\(descriptionsToDelete.count) Audio Description"
            let summary = [transcriptSummary, descriptionSummary].compactMap { $0 }.joined(separator: " and ")
            message = "This permanently removes \(summary) segments, including generated narration audio belonging to the selected descriptions. This cannot be undone."
            actionTitle = "Delete Selected"
        }
        guard confirmDeletion(
            title: title,
            message: message,
            actionTitle: actionTitle
        ) else { return false }
        beforeDelete()
        if descriptionsToDelete.contains(where: { $0.audio != nil }) {
            NotificationCenter.default.post(
                name: .vidiStudioNarrationAudioWillDelete,
                object: self,
                userInfo: ["projectID": project.id]
            )
        }
        selectedID = project.id
        saveSegments(
            project.transcript.filter { !transcriptIDs.contains($0.id) },
            cues: project.cues.filter { !descriptionIDs.contains($0.id) }
        )
        return true
    }
    private func confirmDeletion(title: String, message: String, actionTitle: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        let destructiveButton = alert.addButton(withTitle: actionTitle)
        destructiveButton.hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn
    }
    func openProject() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Choose a VidiStudio folder containing project.json."
        if panel.runModal() == .OK, let folder = panel.url {
            do {
                var p = try JSONDecoder().decode(StudioProject.self, from: Data(contentsOf: folder.appendingPathComponent("project.json")))
                p.folder = folder
                var recent = UserDefaults.standard.stringArray(forKey: "recentProjectFolders") ?? []
                recent.removeAll { $0 == folder.path }; recent.insert(folder.path, at: 0)
                UserDefaults.standard.set(Array(recent.prefix(50)), forKey: "recentProjectFolders")
                projects.removeAll { $0.id == p.id }; projects.insert(p, at: 0); selectedID = p.id
            } catch {
                present(.projectOpen, technicalDetails: error.localizedDescription, context: "Open project")
            }
        }
    }
    func loadGeminiModels() {
        guard !busy else { return }
        guard settings.hasApiKey else {
            apiKeyVerified = false
            apiKeyVerificationMessage = "Enter your Gemini API key in Settings → Gemini API to enable features."
            error = "Enter your Gemini API key first."
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-models-\(UUID().uuidString)")
        let configuration = directory.appendingPathComponent("config.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var executionDict = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(settings))) as? [String: Any] ?? [:]
            let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !apiKey.isEmpty { executionDict["apiKey"] = apiKey }
            let configData = try JSONSerialization.data(withJSONObject: executionDict)
            try configData.write(to: configuration, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configuration.path)
            availableGeminiModels = []
            geminiModelsLoaded = false
            apiKeyVerified = nil
            apiKeyVerificationMessage = nil
            execute("check-api-key", configurationURL: configuration, cleanupURL: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            apiKeyVerified = false
            apiKeyVerificationMessage = error.localizedDescription
            let issue = UserFacingIssue.forEngine(command: "check-api-key", technicalDetails: error.localizedDescription)
            present(issue, technicalDetails: error.localizedDescription, context: "Load Gemini models")
        }
    }
    func checkGeminiApiKey() {
        loadGeminiModels()
    }
    func deleteGeminiApiKey() {
        settings.apiKey = ""
        KeychainStore.delete()
        aiServiceIssue = nil
        apiKeyVerified = nil
        apiKeyVerificationMessage = nil
        availableGeminiModels = []
        geminiModelsLoaded = false
        settings.geminiPlan = "free"
        chooseAvailableGeminiModels()
        persistSettings(reloadProjects: false)
    }
    func geminiModels(for stage: String) -> [GeminiModelOption] {
        guard geminiModelsLoaded else {
            return settings.models[stage].map { [GeminiModelOption(name: $0)] } ?? []
        }
        let specializedTerms = ["tts", "transcribe", "image", "embedding", "live", "computer-use", "robotics", "research"]
        let general = availableGeminiModels.filter { option in
            !specializedTerms.contains { option.name.localizedCaseInsensitiveContains($0) }
        }
        if stage == "tts_audio" {
            return availableGeminiModels.filter { $0.name.localizedCaseInsensitiveContains("tts") }
        }
        if stage == "transcript" {
            let transcription = availableGeminiModels.filter { $0.name.localizedCaseInsensitiveContains("transcribe") }
            return transcription.isEmpty ? general : transcription
        }
        return general
    }
    private func chooseAvailableGeminiModels() {
        let priorities: [String: [String]] = [
            "transcript": ["gemini-3.5-transcribe"],
            "tts_audio": ["gemini-3.8-flash-lite-tts", "gemini-3.8-flash-tts", "gemini-3.1-flash-tts-preview", "gemini-2.5-flash-preview-tts"],
        ]
        for stage in ["transcript", "youtube_transcript", "summary", "audio_descriptions", "screen_text", "text_rewrite", "tts_audio"] {
            let options = geminiModels(for: stage)
            guard !options.isEmpty else { continue }
            let current = settings.models[stage] ?? ""
            guard !options.contains(where: { $0.name == current }) else { continue }
            let preferred = priorities[stage]?.compactMap { name in options.first { $0.name == name } }.first
                ?? options.first(where: { $0.name == "gemini-3.8-flash" })
                ?? options.first(where: { $0.name == "gemini-3.5-flash" })
                ?? options.first(where: { $0.name == "gemini-2.5-flash" })
                ?? options.first
            settings.models[stage] = preferred?.name
        }
    }
    private func confirmAnalysisReplacement(_ command: String, project: StudioProject) -> Bool {
        guard ["analyze", "regenerate-all", "transcribe", "generate-summary", "generate-ad-cues"].contains(command) else { return true }
        // Read the saved project too, so results written since the last UI refresh are protected.
        var current = project
        if let folder = project.folder {
            do {
                current = try JSONDecoder().decode(StudioProject.self, from: Data(contentsOf: folder.appendingPathComponent("project.json")))
                current.folder = folder
            } catch {
                present(.projectRead, technicalDetails: error.localizedDescription, context: "Check existing project content")
                return false
            }
        }
        var existing: [String] = []
        let all = command == "analyze" || command == "regenerate-all"
        if (all || command == "transcribe"), !current.transcript.isEmpty { existing.append("transcription") }
        if (all || command == "generate-summary"), !current.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { existing.append("summary") }
        if (all || command == "generate-ad-cues"), !current.cues.isEmpty { existing.append("audio description segments") }
        if (all || command == "generate-ad-cues"), current.cues.contains(where: { $0.audio != nil }) { existing.append("narration audio") }
        let subtitleExtensions: Set<String> = ["srt", "vtt"]
        let savedSubtitles = current.exports.contains { subtitleExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
        let exportFiles = current.url("exports").flatMap { try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) } ?? []
        if all && (savedSubtitles || exportFiles.contains(where: { subtitleExtensions.contains($0.pathExtension.lowercased()) })) {
            existing.append("subtitles")
        }
        guard !existing.isEmpty || command == "regenerate-all" else { return true }
        let impact: String
        switch command {
        case "regenerate-all": impact = "All generated content, including transcripts, summaries, AD segments, narration, subtitles, exports, thumbnails, and edit history, will be deleted. The transcript, summary, and AD segments will then be recreated. Your original video and project are kept. Generate narration and exports separately afterward. If analysis fails, deleted content will not be restored."
        case "generate-summary": impact = "Only the summary will be regenerated. Other content will be kept."
        case "generate-ad-cues": impact = "The Audio Description segments and their rows in AD Transcript will be regenerated. Any generated narration audio for those descriptions will be deleted immediately before description generation starts. Other project content and existing exports will be kept. New narration is not generated automatically. If description generation then fails, deleted narration audio will not be restored. If you only want to add or improve descriptions for particular sections, choose Cancel, open Add Segment in Descriptions, set the section's time range, and use Re-Analyze This Segment instead of regenerating every Audio Description."
        case "transcribe": impact = "The entire transcript and its dialogue rows in AD Transcript will be regenerated, replacing manual transcript edits and clearing transcript edit history. The multilingual settings apply to every spoken language. Existing summaries, Audio Description segments, narration audio, and exports will be kept; review description timing against the new dialogue afterward. If you only want to add or improve dialogue for particular sections, choose Cancel, open Add Segment in Transcript edit mode, set the section's time range, and use Re-Analyze This Segment instead of regenerating the entire transcript."
        default: impact = "The transcript, summary, Audio Description segments, and AD Transcript rows will be regenerated. Any generated narration audio for the current descriptions will be deleted immediately before the description stage starts. Existing exports will be kept, and new narration is not generated automatically. If description generation then fails, deleted narration audio will not be restored."
        }
        let alert = NSAlert()
        switch command {
        case "transcribe": alert.messageText = "Regenerate transcript in “\(current.name)”?"
        case "generate-summary": alert.messageText = "Regenerate summary in “\(current.name)”?"
        case "generate-ad-cues": alert.messageText = "Regenerate Audio Descriptions in “\(current.name)”?"
        default: alert.messageText = "Reanalyze “\(current.name)”?"
        }
        alert.informativeText = (existing.isEmpty ? "" : "This project already contains \(existing.joined(separator: ", ")). ") + impact + " Do you want to continue?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: command == "analyze" ? "Reanalyze" : "Regenerate")
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func confirmNarrationVoiceChange(_ command: String, extra: [String], project: StudioProject) -> Bool {
        guard command == "synthesize-tts" else { return true }
        var current = project
        if let folder = project.folder {
            do {
                current = try JSONDecoder().decode(StudioProject.self, from: Data(contentsOf: folder.appendingPathComponent("project.json")))
                current.folder = folder
            } catch {
                present(.projectRead, technicalDetails: error.localizedDescription, context: "Check existing project narration")
                return false
            }
        }
        if extra.contains("--regenerate-all") {
            pendingVoiceMismatchReview = false
            guard current.hasNarrationAudio else { return true }
            let alert = NSAlert()
            alert.messageText = "Regenerate all AD audio in “\(current.name)”?"
            alert.informativeText = "All generated narration audio will be replaced by newly generated audio for every Audio Description segment using the currently selected voice: \(settings.currentNarrationSummary). This becomes the project's primary narration voice as soon as generation starts. Description text and timing will be kept. Existing audio is replaced only after each segment is generated successfully; if generation fails or is canceled, some old audio may remain. Do you want to continue?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Regenerate All AD Audio")
            return alert.runModal() == .alertSecondButtonReturn
        }
        let narratedCues = current.cues.filter { cue in
            if let path = cue.audio, let url = current.url(path), FileManager.default.fileExists(atPath: url.path) {
                return true
            }
            return cue.audio != nil || cue.resolvedAudioVoice != nil
        }
        guard !narratedCues.isEmpty else {
            pendingVoiceMismatchReview = false
            return true
        }
        let targetSegmentID: String? = {
            guard let idx = extra.firstIndex(of: "--segment"), extra.indices.contains(idx + 1) else { return nil }
            return extra[idx + 1]
        }()
        let targetSegment = targetSegmentID.flatMap { id in current.cues.first(where: { $0.id == id }) }
        let selectedEngine = settings.currentNarrationEngine
        let selectedVoice = settings.currentNarrationVoice
        var existingLabels: [String] = []
        var hasDifferentVoice = false
        for cue in narratedCues {
            let cueEngine = cue.resolvedAudioEngine ?? current.narrationEngine ?? "system"
            let cueVoice = cue.resolvedAudioVoice ?? current.narrationVoice ?? "System default"
            let label = NarrationVoiceFormatting.combinedLabel(voice: cueVoice, engine: cueEngine)
            if !existingLabels.contains(label) {
                existingLabels.append(label)
            }
            if !NarrationVoiceFormatting.voicesMatch(engineA: cueEngine, voiceA: cueVoice, engineB: selectedEngine, voiceB: selectedVoice) {
                hasDifferentVoice = true
            }
        }
        if let pEngine = current.narrationEngine, let pVoice = current.narrationVoice,
           !pEngine.isEmpty, !pVoice.isEmpty,
           !NarrationVoiceFormatting.voicesMatch(engineA: pEngine, voiceA: pVoice, engineB: selectedEngine, voiceB: selectedVoice) {
            hasDifferentVoice = true
            let label = NarrationVoiceFormatting.combinedLabel(voice: pVoice, engine: pEngine)
            if !existingLabels.contains(label) {
                existingLabels.insert(label, at: 0)
            }
        }
        guard hasDifferentVoice else {
            pendingVoiceMismatchReview = false
            return true
        }
        let alert = NSAlert()
        if let targetSegment {
            alert.messageText = targetSegment.audio == nil
                ? "Generate segment narration with a different voice in “\(current.name)”?"
                : "Regenerate segment narration with a different voice in “\(current.name)”?"
            alert.informativeText = "This project already contains narration generated using \(existingLabels.joined(separator: ", ")). You have selected \(settings.currentNarrationSummary). Proceeding will generate narration for this AD segment with the new voice, so the voices in the project will differ and be detailed in AD Overview. Do you want to proceed?"
        } else {
            alert.messageText = "Generate narration with a different voice in “\(current.name)”?"
            alert.informativeText = "This project already contains narration generated using \(existingLabels.joined(separator: ", ")). You have selected \(settings.currentNarrationSummary). Proceeding will result in different narration voices across the project, which will be detailed in AD Overview. Do you want to proceed with generating narration?"
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Proceed")
        let confirmed = alert.runModal() == .alertSecondButtonReturn
        pendingVoiceMismatchReview = confirmed
        return confirmed
    }

    private func requireCompleteNarrationForExport(project: StudioProject) -> Bool {
        var current = project
        do {
            guard let folder = project.folder else { return false }
            current = try JSONDecoder().decode(StudioProject.self, from: Data(contentsOf: folder.appendingPathComponent("project.json")))
            current.folder = folder
        } catch {
            present(.exportPreparation, technicalDetails: error.localizedDescription, context: "Prepare export")
            return false
        }
        guard current.hasCompleteExportNarration() else {
            errorTitle = "Narration Isn’t Ready to Export"
            error = "Generate current narration for every AD segment before exporting. Check that each segment fits within the video."
            return false
        }
        return true
    }

    func execute(
        _ command: String,
        extra: [String] = [],
        project: StudioProject? = nil,
        configurationURL: URL? = nil,
        cleanupURL: URL? = nil,
        completion: ((StudioProject?) -> Void)? = nil
    ) {
        guard !busy else { return }
        let extra = command == "synthesize-tts" && !extra.contains("--segment") && !extra.contains("--changed") && !extra.contains("--regenerate-all")
            ? extra + ["--regenerate-all"] : extra
        errorTitle = StudioModel.defaultErrorTitle
        if command == "doctor" {
            error = nil
            engineCheckStatus = .checking
        }
        let target = project ?? (["import-video", "import-youtube", "doctor", "validate-config", "list-models", "check-api-key"].contains(command) ? nil : selected)
        if ["export-final-video", "export-selectable-video", "export-closed-audio-description-video", "export-open-audio-description-video", "export-closed-caption-video", "export-dual-closed-caption-video", "export-open-caption-video", "export-hls"].contains(command), let target, target.isYouTubeURLProject {
            errorTitle = "Video Export Isn’t Available"
            error = "This project uses a YouTube link, so VidiStudio does not have a local video to export. You can still export text and available narration audio."
            return
        }
        if ["export-original-audio", "export-described-audio"].contains(command), let target, target.isYouTubeURLProject {
            errorTitle = "Audio Export Isn’t Available"
            error = "This project uses a YouTube link, so its original soundtrack is not stored on this Mac. You can still export narration-only audio or text."
            return
        }
        if command == "generate-ad-cues", let target, !target.canGenerateDescriptions {
            errorTitle = "More Project Content Is Needed"
            error = "Generate the transcript and summary before generating descriptions."
            return
        }
        if let target, !confirmAnalysisReplacement(command, project: target) { return }
        if let target, !confirmNarrationVoiceChange(command, extra: extra, project: target) { return }
        let webPlaybackNeedsNarration = command == "export-hls"
            && (extra.contains("closed-description") || extra.contains("open-description"))
        if (["export-final-video", "export-selectable-video", "export-closed-audio-description-video", "export-open-audio-description-video", "export-described-audio", "export-youtube-described-audio", "export-audio"].contains(command) || webPlaybackNeedsNarration), let target {
            guard requireCompleteNarrationForExport(project: target) else { return }
        }
        guard let engine = Bundle.main.resourceURL?.appendingPathComponent("Engine/vidistudio-engine"), FileManager.default.isExecutableFile(atPath: engine.path) else {
            let issue = UserFacingIssue(
                title: "VidiStudio Needs to Be Reinstalled",
                message: "A required part of VidiStudio is unavailable. Reinstall the application, then try again."
            )
            if command == "doctor" { engineCheckStatus = .failed(issue.message) }
            present(issue, context: "Missing bundled processing component")
            completion?(nil)
            return
        }
        busy = true
        cancellationRequested = false
        if Self.isExportCommand(command), let target {
            exportActivity = ExportSessionRegistry.shared.begin(
                projectID: target.id, projectName: target.name,
                status: UserFacingProgress.message(for: command), cancel: { [weak self] in
                    self?.cancelCurrentOperation()
                })
        } else {
            exportActivity = nil
        }
        if let target, ["prepare-analysis-video", "check-video-availability"].contains(command) {
            videoPreparationActivity = VideoPreparationActivity(
                projectID: target.id, message: "Checking video availability")
        }
        processingSection = Self.initialProcessingSection(for: command)
        processingPlan = Self.analysisSections(for: command, extra: extra)
        if command == "synthesize-tts", let target {
            isSynthesizingNarration = true
            narratingTotalCount = target.cues.count
            if let flagIdx = extra.firstIndex(of: "--segment"), extra.indices.contains(flagIdx + 1) {
                let segID = extra[flagIdx + 1]
                narratingQueueIDs = [segID]
                narratingSegmentID = segID
                narratingSegmentIndex = target.cues.firstIndex(where: { $0.id == segID }).map { $0 + 1 }
            } else {
                let changedOnly = extra.contains("--changed")
                let preserveUsable = changedOnly
                let queued = target.cues.enumerated().filter { _, cue in
                    !preserveUsable || SynchronizedAudioStatus.resolve(cue: cue, project: target) != .generated
                }
                narratingQueueIDs = Set(queued.map { $0.element.id })
                narratingSegmentID = queued.first?.element.id
                narratingSegmentIndex = queued.first.map { $0.offset + 1 }
            }
        } else {
            isSynthesizingNarration = false
            narratingSegmentID = nil
            narratingSegmentIndex = nil
            narratingTotalCount = 0
            narratingQueueIDs = []
        }
        var completedExportPath: String?
        var completedProjectPath: String?
        progress = 0
        message = UserFacingProgress.message(for: command)
        var temporaryExecutionDirectory: URL?
        var effectiveConfigurationURL = configurationURL
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if effectiveConfigurationURL == nil && !apiKey.isEmpty {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-run-\(UUID().uuidString)")
            let tempConfig = tempDir.appendingPathComponent("config.json")
            do {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                var executionDict = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(settings))) as? [String: Any] ?? [:]
                executionDict["apiKey"] = apiKey
                let data = try JSONSerialization.data(withJSONObject: executionDict)
                try data.write(to: tempConfig, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempConfig.path)
                effectiveConfigurationURL = tempConfig
                temporaryExecutionDirectory = tempDir
            } catch {
                effectiveConfigurationURL = StudioSettings.url
            }
        }
        let task = Process(); task.executableURL = engine
        task.arguments = [command] + (target?.folder.map { ["--project", $0.path] } ?? []) + extra
        var environment = ProcessInfo.processInfo.environment.merging([
            "VIDISTUDIO_CONFIG": (effectiveConfigurationURL ?? StudioSettings.url).path,
            "VIDISTUDIO_PIPER_VOICES": PiperStorage.voicesDirectory.path,
        ]) { _, new in new }
        if !apiKey.isEmpty { environment["VIDISTUDIO_API_KEY"] = apiKey }
        task.environment = environment
        let output = Pipe(); task.standardOutput = output
        let stderr = Pipe(); task.standardError = stderr
        // Drain stderr independently so verbose native libraries cannot block the engine.
        stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        process = task
        do { try task.run() } catch {
            stderr.fileHandleForReading.readabilityHandler = nil
            if let cleanupURL { try? FileManager.default.removeItem(at: cleanupURL) }
            if let temporaryExecutionDirectory { try? FileManager.default.removeItem(at: temporaryExecutionDirectory) }
            let detail = error.localizedDescription
            let issue = UserFacingIssue.forEngine(command: command, technicalDetails: detail)
            if command == "doctor" { engineCheckStatus = .failed(issue.message) }
            busy = false
            exportActivity = nil
            cancellationRequested = false
            videoPreparationActivity = nil
            processingSection = nil
            processingPlan = []
            isSynthesizingNarration = false
            narratingSegmentID = nil
            narratingSegmentIndex = nil
            narratingTotalCount = 0
            narratingQueueIDs = []
            process = nil
            present(issue, technicalDetails: detail, context: "Start \(command)")
            completion?(nil)
            return
        }
        Task {
            do {
                for try await line in output.fileHandleForReading.bytes.lines {
                    guard let data = line.data(using: .utf8), let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    let eventMessage = event["message"] as? String
                    let eventIsError = event["error"] as? Bool == true
                    let eventIsWarning = event["warning"] as? Bool == true
                    if let text = eventMessage {
                        if event["exportProgress"] == nil {
                            logs.append(text)
                            if logs.count > 200 { logs.removeFirst() }
                        }
                        if !eventIsError && !eventIsWarning {
                            message = text
                            if exportActivity?.cancelling != true { exportActivity?.status = text }
                        }
                    }
                    if let text = event["screenText"] as? String { screenText = text; screenTimestamp = event["timestamp"] as? Double ?? 0 }
                    if let rawModels = event["models"] as? [[String: Any]] {
                        availableGeminiModels = rawModels.compactMap(GeminiModelOption.init(dictionary:))
                        geminiModelsLoaded = true
                        chooseAvailableGeminiModels()
                        apiKeyVerified = true
                        aiServiceIssue = nil
                        if let plan = event["plan"] as? String {
                            settings.geminiPlan = plan
                        }
                        let planName = (event["plan"] as? String ?? settings.geminiPlan) == "paid" ? "Paid Plan" : "Free Plan"
                        apiKeyVerificationMessage = "API key verified and active (\(planName)). \(availableGeminiModels.count) models available."
                    }
                    if let value = event["progress"] as? Double {
                        progress = value
                        exportActivity?.update(fraction: value)
                    }
                    if event.keys.contains("exportProgress") {
                        exportActivity?.update(fraction: event["exportProgress"] as? Double)
                    }
                    if let section = event["processingSection"] as? String {
                        processingSection = section
                    }
                    if let total = event["narratingTotal"] as? Int {
                        narratingTotalCount = total
                    }
                    if let queue = event["narratingQueue"] as? [String] {
                        narratingQueueIDs = Set(queue)
                    }
                    if let narratingID = event["narratingSegment"] as? String {
                        narratingSegmentID = narratingID
                        if let idx = event["narratingIndex"] as? Int {
                            narratingSegmentIndex = idx
                        }
                    } else if event["narratedSegment"] is String {
                        if let nextID = (event["narratingQueue"] as? [String])?.first {
                            narratingSegmentID = nextID
                            if let p = selected, let nextIdx = p.cues.firstIndex(where: { $0.id == nextID }) {
                                narratingSegmentIndex = nextIdx + 1
                            }
                        } else {
                            narratingSegmentID = nil
                        }
                    }
                    if let state = event["videoPreparation"] as? String, let target {
                        switch state {
                        case "uploading":
                            videoPreparationActivity = VideoPreparationActivity(
                                projectID: target.id, message: "Uploading video")
                        case "processing":
                            videoPreparationActivity = VideoPreparationActivity(
                                projectID: target.id, message: "Preparing video")
                        case "ready":
                            reload()
                            videoPreparationActivity = nil
                        default: break
                        }
                    }
                    if let rawFailures = event["narrationFailures"] as? [[String: Any]] {
                        let failures = rawFailures.compactMap { item -> NarrationFailure? in
                            guard let index = item["index"] as? Int else { return nil }
                            return NarrationFailure(
                                id: index,
                                start: item["start"] as? Double ?? 0,
                                end: item["end"] as? Double ?? 0,
                                duration: item["duration"] as? Double ?? 0,
                                reason: item["reason"] as? String ?? "Unknown error")
                        }
                        if !failures.isEmpty {
                            let generated = event["narrationGenerated"] as? Int ?? 0
                            narrationFailureReport = NarrationFailureReport(
                                title: "Some descriptions need attention",
                                detail: "Narration finished for \(generated) description\(generated == 1 ? "" : "s"). \(failures.count) could not be created.",
                                generated: generated,
                                failures: failures)
                        }
                    }
                    if let path = event["export"] as? String { completedExportPath = path }
                    if let raw = event["importReport"] as? [String: Any],
                       let data = try? JSONSerialization.data(withJSONObject: raw),
                       let report = try? JSONDecoder().decode(ImportReport.self, from: data),
                       report.kind != "segmentNarration",
                       importReports.last?.id != report.id {
                        importReports.append(report)
                    }
                    if eventIsError {
                        let detail = eventMessage ?? "The operation stopped without further details."
                        if Self.isAICommand(command), let aiIssue = AIServiceIssue.detect(detail) {
                            aiServiceIssue = aiIssue
                        }
                        let issue = UserFacingIssue.forEngine(command: command, technicalDetails: detail)
                        present(issue, technicalDetails: detail, context: "Run \(command)")
                        if command == "doctor" { engineCheckStatus = .failed(issue.message) }
                        if (command == "list-models" || command == "check-api-key" || detail.localizedCaseInsensitiveContains("api key not valid") || detail.localizedCaseInsensitiveContains("api_key_invalid"))
                            && aiServiceIssue == nil {
                            apiKeyVerified = false
                            apiKeyVerificationMessage = detail
                            availableGeminiModels = []
                            geminiModelsLoaded = false
                        }
                    }
                    if let path = event["project"] as? String {
                        completedProjectPath = path
                        reload()
                        if let p = projects.first(where: { $0.folder?.path == path }) { selectedID = p.id }
                    }
                }
            } catch {
                let detail = error.localizedDescription
                if Self.isAICommand(command), let aiIssue = AIServiceIssue.detect(detail) {
                    aiServiceIssue = aiIssue
                }
                if (command == "list-models" || command == "check-api-key" || detail.localizedCaseInsensitiveContains("api key not valid") || detail.localizedCaseInsensitiveContains("api_key_invalid"))
                    && aiServiceIssue == nil {
                    apiKeyVerified = false
                    apiKeyVerificationMessage = detail
                    availableGeminiModels = []
                    geminiModelsLoaded = false
                }
                present(
                    UserFacingIssue.forEngine(command: command, technicalDetails: detail),
                    technicalDetails: detail,
                    context: "Read \(command) result"
                )
            }
            exportActivity?.canCancel = false
            task.waitUntilExit()
            stderr.fileHandleForReading.readabilityHandler = nil
            if let cleanupURL { try? FileManager.default.removeItem(at: cleanupURL) }
            if let temporaryExecutionDirectory { try? FileManager.default.removeItem(at: temporaryExecutionDirectory) }
            reload()
            if task.terminationStatus == 0, Self.isExportCommand(command), let folder = target?.folder,
               let path = completedExportPath, URL(fileURLWithPath: path).pathExtension.lowercased() == "mov" {
                do {
                    let described = ["export-selectable-video", "export-closed-audio-description-video",
                                     "export-final-video", "export-open-audio-description-video",
                                     "combine-imported-audio"].contains(command)
                    exportActivity?.status = "Finishing accessibility information"
                    exportActivity?.update(fraction: 0.99)
                    try await AppleAccessibilityMetadataWriter().finalizeVideoTracks(at: folder.appendingPathComponent(path), described: described)
                    message = "Video export complete"
                } catch {
                    present(.exportMetadata, technicalDetails: error.localizedDescription, context: "Finish export accessibility information")
                }
            }
            let operationWasCancelled = cancellationRequested
            let exportWasCancelled = operationWasCancelled && exportActivity != nil
            busy = false
            exportActivity = nil
            cancellationRequested = false
            processingSection = nil
            processingPlan = []
            isSynthesizingNarration = false
            narratingSegmentID = nil
            narratingSegmentIndex = nil
            narratingTotalCount = 0
            narratingQueueIDs = []
            process = nil
            reload()
            videoPreparationActivity = nil
            if operationWasCancelled {
                message = exportWasCancelled ? "Export cancelled." : "Operation cancelled."
            } else if task.terminationStatus != 0 && self.error == nil {
                present(UserFacingIssue.forEngine(command: command, technicalDetails: nil), context: "\(command) stopped")
            }
            if task.terminationStatus == 0 {
                if Self.isAICommand(command) { aiServiceIssue = nil }
                self.errorTitle = StudioModel.defaultErrorTitle
            } else if (command == "list-models" || command == "check-api-key") && aiServiceIssue == nil {
                apiKeyVerified = false
                availableGeminiModels = []
                geminiModelsLoaded = false
                if apiKeyVerificationMessage == nil {
                    apiKeyVerificationMessage = self.error ?? "The Gemini API key could not be verified. Please check the key in Settings → Gemini API."
                }
            }
            if command == "doctor" {
                engineCheckStatus = task.terminationStatus == 0
                    ? .ready
                    : .failed(self.error ?? UserFacingIssue.engineCheck.message)
            }
            let completedProject = completedProjectPath.flatMap { path in
                projects.first(where: { $0.folder?.path == path })
            } ?? (target.flatMap { t in projects.first(where: { $0.id == t.id }) })
            if command == "synthesize-tts" {
                let shouldShowVoiceReport = pendingVoiceMismatchReview
                pendingVoiceMismatchReview = false
                if shouldShowVoiceReport, task.terminationStatus == 0, !operationWasCancelled,
                   narrationFailureReport == nil, let completedProject {
                    let report = narrationVoiceUsageReport(for: completedProject)
                    if report.hasDifferentVoices {
                        narrationVoiceReport = report
                    }
                }
            }
            completion?(task.terminationStatus == 0 ? completedProject : nil)
        }
    }

    private static func initialProcessingSection(for command: String) -> String? {
        switch command {
        case "transcribe", "reanalyze-transcript-segment", "undo-transcript", "redo-transcript", "analyze", "regenerate-all": return "transcript"
        case "generate-summary": return "summary"
        case "generate-ad-cues", "reanalyze-segment", "prepare-analysis-video": return "descriptions"
        default: return nil
        }
    }

    /// The ordered analysis stages a command processes. Only commands that emit
    /// a `processingSection` event are listed so the per-section spinner never
    /// waits on a stage that will not report progress.
    private static func analysisSections(for command: String, extra: [String]) -> [String] {
        let stages: [String]
        switch command {
        case "analyze", "regenerate-all": stages = ["transcript", "summary", "descriptions"]
        case "transcribe", "reanalyze-transcript-segment": stages = ["transcript"]
        case "generate-summary": stages = ["summary"]
        case "generate-ad-cues", "reanalyze-segment", "prepare-analysis-video": stages = ["descriptions"]
        default: return []
        }
        guard let flagIndex = extra.firstIndex(of: "--start-stage"), extra.indices.contains(flagIndex + 1) else { return stages }
        let startStage = extra[flagIndex + 1]
        guard let index = stages.firstIndex(of: startStage) else { return stages }
        return Array(stages[index...])
    }

    /// Combined processing state for a group of section keys (a tab can show
    /// more than one stage, such as the AD Transcript list).
    func sectionProcessingState(for sections: [String]) -> SectionProcessingState {
        guard busy, exportActivity == nil, !processingPlan.isEmpty, !sections.isEmpty else { return .idle }
        let current = processingSection ?? processingPlan.first ?? ""
        guard let currentIndex = processingPlan.firstIndex(of: current) else { return .idle }
        if sections.contains(current) { return .active }
        let queued = sections.contains { section in
            guard let index = processingPlan.firstIndex(of: section) else { return false }
            return index > currentIndex
        }
        return queued ? .queued : .idle
    }

    /// Short, user-facing stage label shown in the project status bar while a
    /// section is processed. Video preparation takes precedence so the Files API
    /// upload step is called out before the stage name.
    var processingStageTitle: String {
        if let activity = videoPreparationActivity { return activity.message }
        switch processingSection {
        case "transcript": return "Generating transcript"
        case "summary": return "Generating summary"
        case "descriptions": return "Generating audio descriptions"
        default: return processingPlan.isEmpty ? "Processing project" : "Processing"
        }
    }

    static func isAICommand(_ command: String) -> Bool {
        ["transcribe", "generate-summary", "generate-ad-cues", "analyze", "regenerate-all",
         "reanalyze-segment", "reanalyze-transcript-segment", "rewrite-cue", "capture-frame",
         "check-api-key", "list-models", "validate-config", "import-youtube", "align-imported-text",
         "synthesize-tts", "prepare-analysis-video"].contains(command)
    }

    private static func isExportCommand(_ command: String) -> Bool {
        command.hasPrefix("export-") || command == "combine-imported-audio"
    }
    func reanalyzeSegment(_ segment: Segment, hint: String, isDescription: Bool = true) {
        guard let project = selected, !busy else { return }
        struct ReanalysisRequest: Encodable {
            let id: String
            let start: Double
            let end: Double
            let text: String
            let origin: String?
            let aiOriginalText: String?
            let hint: String
        }
        let request = ReanalysisRequest(
            id: segment.id,
            start: segment.start,
            end: segment.end,
            text: segment.text,
            origin: segment.origin,
            aiOriginalText: segment.aiOriginalText,
            hint: hint
        )
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-refine-\(UUID().uuidString).json")
        do {
            try JSONEncoder().encode(request).write(to: file, options: .atomic)
            execute(isDescription ? "reanalyze-segment" : "reanalyze-transcript-segment", extra: ["--input", file.path], project: project, cleanupURL: file)
        } catch {
            try? FileManager.default.removeItem(at: file)
            present(.projectSave, technicalDetails: error.localizedDescription, context: "Prepare segment analysis")
        }
    }

    func saveCues(_ cues: [Segment]) {
        guard let p = selected, !busy else { return }
        do {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-cues-\(UUID().uuidString).json")
            try JSONEncoder().encode(cues).write(to: file)
            execute("save-cues", extra: ["--input", file.path], project: p)
        } catch {
            present(.projectSave, technicalDetails: error.localizedDescription, context: "Save Audio Description segments")
        }
    }
    func saveSegments(_ transcript: [Segment], cues: [Segment]) {
        guard let project = selected, !busy else { return }
        struct EditableSegments: Encodable {
            let transcript: [Segment]
            let cues: [Segment]
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-segments-\(UUID().uuidString)")
        let input = directory.appendingPathComponent("segments.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(EditableSegments(transcript: transcript, cues: cues)).write(to: input, options: .atomic)
            execute("save-segments", extra: ["--input", input.path], project: project, cleanupURL: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            present(.projectSave, technicalDetails: error.localizedDescription, context: "Save transcript and Audio Description segments")
        }
    }

    func saveSummary(_ text: String, origin: SummaryOrigin? = nil) {
        guard let project = selected, !busy else { return }
        struct EditableSummary: Encodable {
            let summary: String
            let summaryOrigin: String?
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-summary-\(UUID().uuidString)")
        let input = directory.appendingPathComponent("summary.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(EditableSummary(summary: text, summaryOrigin: origin?.rawValue)).write(to: input, options: .atomic)
            execute("save-summary", extra: ["--input", input.path], project: project, cleanupURL: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            present(.projectSave, technicalDetails: error.localizedDescription, context: "Save project summary")
        }
    }

    /// Runs the selected existing-asset imports in a stable order and then the
    /// optional combine. Each command is atomic in the engine; the chain stops
    /// on the first failure so later assets are not touched.
    func importAssets(
        _ selection: ImportAssetSelection,
        into project: StudioProject,
        combine: Bool,
        replaceExisting: Bool = false,
        completion: ((StudioProject?) -> Void)? = nil
    ) {
        guard !busy else { return }
        var steps: [(command: String, arguments: [String])] = []
        if let transcript = selection.transcript {
            var arguments = ["--input", transcript.path]
            if let timing = selection.transcriptTiming { arguments += ["--timing-input", timing.path] }
            steps.append(("import-transcript", arguments))
        }
        if let adTranscript = selection.adTranscript {
            var arguments = ["--input", adTranscript.path, "--ad-transcript-mode", selection.adTranscriptMode.rawValue]
            if let timing = selection.adTranscriptTiming { arguments += ["--timing-input", timing.path] }
            steps.append(("import-ad-transcript", arguments))
        }
        if let summary = selection.summary {
            steps.append(("import-summary", ["--input", summary.path]))
        }
        if let audio = selection.adAudio {
            steps.append(("import-ad-audio", ["--input", audio.path, "--audio-mode", selection.adAudioMode.rawValue]))
        }
        if replaceExisting {
            steps = steps.map { (command: $0.command, arguments: $0.arguments + ["--replace-existing"]) }
        }
        importReports.removeAll()
        var current = project
        var remaining = steps

        func finish(_ result: StudioProject?) {
            guard var result, combine, selection.adAudio != nil else {
                completion?(result)
                return
            }
            execute(
                "combine-imported-audio",
                extra: ["--audio-presentation", "selectable", "--captions", "none", "--media-format", "mov"]
                    + (replaceExisting ? ["--replace-existing"] : []),
                project: result
            ) { combined in completion?(combined ?? result) }
        }

        func runNext() {
            guard let step = remaining.first else {
                finish(current)
                return
            }
            remaining.removeFirst()
            execute(step.command, extra: step.arguments, project: current) { updated in
                guard let updated else {
                    completion?(nil)
                    return
                }
                current = updated
                runNext()
            }
        }
        runNext()
    }

    /// Combines the imported AD asset again without re-importing text.
    func combineImportedAudio(for project: StudioProject, replacingExisting: Bool = false, completion: ((StudioProject?) -> Void)? = nil) {
        guard !busy else { return }
        execute(
            "combine-imported-audio",
            extra: ["--audio-presentation", "selectable", "--captions", "none", "--media-format", "mov"]
                + (replacingExisting ? ["--replace-existing"] : []),
            project: project,
            completion: completion
        )
    }

    func importSegmentNarration(_ audio: URL, into cue: Segment, project: StudioProject, replacingExisting: Bool, completion: ((StudioProject?) -> Void)? = nil) {
        guard !busy else { return }
        execute(
            "import-segment-narration",
            extra: ["--input", audio.path, "--segment", cue.id] + (replacingExisting ? ["--replace-existing"] : []),
            project: project,
            completion: completion
        )
    }

    func clearImportReports() {
        importReports.removeAll()
    }

    /// Requests proposed TXT timings. The proposal is never saved by this call;
    /// the timing editor must review it before import.
    func alignImportedText(
        file: URL,
        mode: ImportedADTranscriptMode,
        project: StudioProject,
        completion: @escaping (Result<ImportTimingProposal, Error>) -> Void
    ) {
        guard !busy else { return }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("vidistudio-alignment-\(UUID().uuidString).json")
        execute(
            "align-imported-text",
            extra: ["--input", file.path, "--output", output.path, "--ad-transcript-mode", mode.rawValue],
            project: project
        ) { _ in
            defer { try? FileManager.default.removeItem(at: output) }
            do {
                let proposal = try JSONDecoder().decode(ImportTimingProposal.self, from: Data(contentsOf: output))
                completion(.success(proposal))
            } catch {
                completion(.failure(error))
            }
        }
    }
}

func timecode(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "00:00" }
    let value = max(0, Int(seconds))
    return String(format: "%02d:%02d", value / 60, value % 60)
}
