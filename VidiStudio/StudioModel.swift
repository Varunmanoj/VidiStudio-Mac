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
    var origin: String?
    var aiOriginalText: String?

    var provenance: DescriptionOrigin { DescriptionOrigin(rawValue: origin ?? "") ?? .unknown }
}

enum DescriptionOrigin: String, CaseIterable {
    case ai, aiModified = "ai_modified", manual, unknown

    var title: String {
        switch self {
        case .ai: return "AI-generated"
        case .aiModified: return "AI-generated · modified"
        case .manual: return "Manually added"
        case .unknown: return "Origin unknown"
        }
    }
    var glyph: String {
        switch self {
        case .ai: return "\u{e65f}"
        case .aiModified: return "\u{e3c9}"
        case .manual: return "\u{e7fe}"
        case .unknown: return "\u{e887}"
        }
    }
    var color: Color {
        switch self {
        case .ai: return .purple
        case .aiModified: return .orange
        case .manual: return .blue
        case .unknown: return .secondary
        }
    }
}

struct DescriptionOriginLabel: View {
    let origin: DescriptionOrigin
    var body: some View {
        HStack(spacing: 5) {
            MaterialIcon(glyph: origin.glyph)
            Text(origin.title).font(.caption.weight(.semibold))
        }
        .foregroundStyle(origin.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Description origin: \(origin.title)")
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
        // The settings signature records which voice created this file. A later
        // voice change must not invalidate or replace otherwise synchronized
        // project audio; only a text change requires regeneration.
        return cue.audioText == cue.text
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

    var glyph: String {
        switch self {
        case .generated: return "\u{e86c}"
        case .needsRegeneration: return "\u{e629}"
        case .notGenerated: return "\u{e1b8}"
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

    var body: some View {
        HStack(spacing: 5) {
            MaterialIcon(glyph: status.glyph)
            Text(status.title).font(.caption.weight(.semibold))
        }
        .foregroundStyle(status.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.title)
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

struct ExportActivity: Equatable {
    let projectID: String
    let projectName: String
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
    var undoStack: [[Segment]]?
    var redoStack: [[Segment]]?
    var transcriptUndoStack: [[Segment]]?
    var transcriptRedoStack: [[Segment]]?
    var folder: URL?
    var isYouTubeURLProject: Bool {
        sourceType == "youtube"
    }
    var hasProcessed: Bool?
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
    var apiKey = ""
    var models: [String: String] = [:]
    var prompts: [String: [String: String]] = [:]
    var apiVersion = "v1beta"
    var videoProcessing = "agentic"
    var theme = "system"
    var ttsMode = "system"
    var narrationPlayback = "generated"
    var soundWhenNarrationOff = true
    var soundWhenNarrationMissing = true
    var systemVoice = ""
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
        return systemSpeechSignature
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

enum ProjectPlaybackPreferences {
    static func narrationKey(_ projectID: String) -> String {
        "projectNarrationEnabled.\(projectID)"
    }

    static func narrationEnabled(_ projectID: String) -> Bool {
        UserDefaults.standard.object(forKey: narrationKey(projectID)) as? Bool ?? false
    }

    static func followKey(_ projectID: String) -> String {
        "projectFollowTranscript.\(projectID)"
    }

    static func followEnabled(_ projectID: String) -> Bool {
        UserDefaults.standard.object(forKey: followKey(projectID)) as? Bool ?? true
    }

    static func setNarrationEnabled(_ enabled: Bool, projectID: String) {
        let key = narrationKey(projectID)
        let previous = UserDefaults.standard.object(forKey: key) as? Bool
        UserDefaults.standard.set(enabled, forKey: key)
        guard previous != enabled else { return }
        announceNarrationChange(enabled, projectID: projectID)
    }

    static func announceNarrationChange(_ enabled: Bool, projectID: String) {
        NotificationCenter.default.post(
            name: .vidiStudioProjectNarrationDidChange,
            object: nil,
            userInfo: ["projectID": projectID, "enabled": enabled]
        )
    }

    static func setFollowEnabled(_ enabled: Bool, projectID: String) {
        let key = followKey(projectID)
        let previous = UserDefaults.standard.object(forKey: key) as? Bool
        UserDefaults.standard.set(enabled, forKey: key)
        guard previous != enabled else { return }
        announceFollowChange(enabled, projectID: projectID)
    }

    static func announceFollowChange(_ enabled: Bool, projectID: String) {
        NotificationCenter.default.post(
            name: .vidiStudioProjectFollowDidChange,
            object: nil,
            userInfo: ["projectID": projectID, "enabled": enabled]
        )
    }
}

struct OpenProjectReference: Identifiable, Equatable {
    let id: String
    var name: String
}

@MainActor @Observable
final class OpenProjectRegistry {
    private(set) var projects: [OpenProjectReference] = []

    func open(_ id: String, name: String) {
        if let index = projects.firstIndex(where: { $0.id == id }) {
            if projects[index].name != name { projects[index].name = name }
        } else {
            projects.append(OpenProjectReference(id: id, name: name))
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
    var selectedID: String? { didSet { UserDefaults.standard.set(selectedID, forKey: "lastProjectID") } }
    var settings = StudioSettings() {
        didSet {
            guard settingsPersistenceEnabled, !applyingExternalSettings, settings != oldValue else { return }
            persistSettings(reloadProjects: settings.libraryPath != oldValue.libraryPath)
        }
    }
    @ObservationIgnored private var settingsPersistenceEnabled = false
    @ObservationIgnored private var applyingExternalSettings = false
    var settingsSection = "Appearance"
    var busy = false
    var processingSection: String?
    var videoPreparationActivity: VideoPreparationActivity?
    var exportActivity: ExportActivity?
    var cancellationRequested = false
    var message = "All files stay in your local project folders."
    var progress = 0.0
    var error: String?
    var errorTitle = StudioModel.defaultErrorTitle
    var logs: [String] = []
    var screenText: String?
    var screenTimestamp = 0.0
    var process: Process?
    var isCreatingProject = false
    var availableGeminiModels: [GeminiModelOption] = []
    var geminiModelsLoaded = false
    var engineCheckStatus: EngineCheckStatus = .unchecked
    var selected: StudioProject? { projects.first { $0.id == selectedID } }

    func cancelCurrentOperation() {
        guard busy, !cancellationRequested, let process else { return }
        cancellationRequested = true
        message = exportActivity == nil ? "Stopping the current operation…" : "Stopping the export…"
        process.terminate()
    }

    func dismissError() {
        error = nil
        errorTitle = StudioModel.defaultErrorTitle
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
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Engine/_internal/ai-defaults.json"),
           let data = try? Data(contentsOf: url), let defaults = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["models", "prompts", "apiVersion", "videoProcessing"] { merged[key] = defaults[key] }
        }
        if let data = try? Data(contentsOf: StudioSettings.url), let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            hasSavedCaptionDisplayMode = saved["captionDisplayMode"] is String
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
        if let data = try? JSONSerialization.data(withJSONObject: merged), let decoded = try? JSONDecoder().decode(StudioSettings.self, from: data) { settings = decoded }
        var migratedLibrary = false
        var seededCaptionDisplayMode = false
        if settings.libraryPath == StudioSettings.legacyDefaultLibraryURL.path {
            settings.libraryPath = StudioSettings.defaultLibraryURL.path
            migratedLibrary = true
        }
        if !hasSavedCaptionDisplayMode, SystemCaptionPreferences.prefersSubtitlesAndSDH {
            settings.captionDisplayMode = "transcript"
            seededCaptionDisplayMode = true
        }
        settingsPersistenceEnabled = true
        if migratedLibrary || seededCaptionDisplayMode { persistSettings(reloadProjects: false) }
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
        let root = URL(fileURLWithPath: settings.libraryPath)
        let previous = selected?.folder
        var folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for path in UserDefaults.standard.stringArray(forKey: "recentProjectFolders") ?? [] {
            let folder = URL(fileURLWithPath: path)
            if !folders.contains(folder) { folders.append(folder) }
        }
        if let previous, !folders.contains(previous) { folders.append(previous) }
        projects = folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("project.json")), var p = try? JSONDecoder().decode(StudioProject.self, from: data) else { return nil }
            p.folder = folder
            return p
        }.sorted { $0.updatedAt > $1.updatedAt }
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
        do { try FileManager.default.trashItem(at: folder, resultingItemURL: nil); reload() }
        catch {
            present(.projectDelete, technicalDetails: error.localizedDescription, context: "Move project to Bin")
        }
    }
    func confirmTrashProject(_ project: StudioProject) {
        guard !busy, project.folder != nil else { return }
        guard confirmDeletion(
            title: "Move “\(project.name)” to the Bin?",
            message: "The complete project folder, including its source video or YouTube link, generated content, narration, and exports, will be moved to the Bin. You can restore it until the Bin is emptied.",
            actionTitle: "Move to Bin"
        ) else { return }
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
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "Enter your Gemini API key first."
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-models-\(UUID().uuidString)")
        let configuration = directory.appendingPathComponent("config.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(settings).write(to: configuration, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configuration.path)
            availableGeminiModels = []
            geminiModelsLoaded = false
            execute("list-models", configurationURL: configuration, cleanupURL: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            let issue = UserFacingIssue.forEngine(command: "list-models", technicalDetails: error.localizedDescription)
            present(issue, technicalDetails: error.localizedDescription, context: "Load Gemini models")
        }
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
            "tts_audio": ["gemini-3.1-flash-tts-preview", "gemini-2.5-flash-preview-tts"],
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

    private func confirmIncompleteNarrationExport(project: StudioProject, audioOnly: Bool, exportKindOverride: String? = nil) -> [String]? {
        var current = project
        do {
            guard let folder = project.folder else { return nil }
            current = try JSONDecoder().decode(StudioProject.self, from: Data(contentsOf: folder.appendingPathComponent("project.json")))
            current.folder = folder
        } catch {
            present(.exportPreparation, technicalDetails: error.localizedDescription, context: "Prepare export")
            return nil
        }
        let missing = current.cues.filter {
            SynchronizedAudioStatus.resolve(cue: $0, project: current) != .generated
        }
        if audioOnly && !current.hasExportableNarration() {
            self.error = "Generate narration for at least one AD segment before exporting narration audio."
            return nil
        }
        guard !missing.isEmpty || current.cues.isEmpty else { return [] }
        let alert = NSAlert()
        let exportKind = exportKindOverride ?? (audioOnly ? "narration audio" : "video")
        alert.messageText = "Export \(exportKind) with incomplete audio descriptions?"
        alert.informativeText = current.cues.isEmpty
            ? "This project has no AD segments. Continuing exports \(exportKind) without audio descriptions."
            : "\(missing.count) of \(current.cues.count) AD segments have missing narration or narration for earlier text. Continuing exports \(exportKind) with available, synchronized narration only. Those \(missing.count) descriptions will be omitted from the audio. This does not generate missing narration. Cancel and choose Synthesize Narration to include all descriptions."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Export Anyway")
        guard alert.runModal() == .alertSecondButtonReturn else { return nil }
        return ["--allow-incomplete-narration"]
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
        errorTitle = StudioModel.defaultErrorTitle
        if command == "doctor" {
            error = nil
            engineCheckStatus = .checking
        }
        let target = project ?? (["import-video", "import-youtube", "doctor", "validate-config", "list-models"].contains(command) ? nil : selected)
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
        var exportOptions: [String] = []
        let webPlaybackNeedsNarration = command == "export-hls"
            && (extra.contains("closed-description") || extra.contains("open-description"))
        if (["export-final-video", "export-selectable-video", "export-closed-audio-description-video", "export-open-audio-description-video", "export-described-audio", "export-audio"].contains(command) || webPlaybackNeedsNarration), let target {
            guard let options = confirmIncompleteNarrationExport(
                project: target,
                audioOnly: command == "export-audio",
                exportKindOverride: command == "export-described-audio"
                    ? "final audio"
                    : command == "export-hls" ? "Web Playback folder" : nil
            ) else { return }
            exportOptions = options
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
            exportActivity = ExportActivity(projectID: target.id, projectName: target.name)
        } else {
            exportActivity = nil
        }
        if let target, ["prepare-analysis-video", "check-video-availability"].contains(command) {
            videoPreparationActivity = VideoPreparationActivity(
                projectID: target.id, message: "Checking video availability")
        }
        processingSection = Self.initialProcessingSection(for: command)
        var completedExportPath: String?
        var completedProjectPath: String?
        progress = 0
        message = UserFacingProgress.message(for: command)
        let task = Process(); task.executableURL = engine
        task.arguments = [command] + (target?.folder.map { ["--project", $0.path] } ?? []) + extra + exportOptions
        task.environment = ProcessInfo.processInfo.environment.merging(["VIDISTUDIO_CONFIG": (configurationURL ?? StudioSettings.url).path]) { _, new in new }
        let output = Pipe(); task.standardOutput = output
        let stderr = Pipe(); task.standardError = stderr
        // Drain stderr independently so verbose native libraries cannot block the engine.
        stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        process = task
        do { try task.run() } catch {
            stderr.fileHandleForReading.readabilityHandler = nil
            if let cleanupURL { try? FileManager.default.removeItem(at: cleanupURL) }
            let detail = error.localizedDescription
            let issue = UserFacingIssue.forEngine(command: command, technicalDetails: detail)
            if command == "doctor" { engineCheckStatus = .failed(issue.message) }
            busy = false
            exportActivity = nil
            cancellationRequested = false
            videoPreparationActivity = nil
            processingSection = nil
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
                        logs.append(text)
                        if logs.count > 200 { logs.removeFirst() }
                        if !eventIsError && !eventIsWarning { message = text }
                    }
                    if let text = event["screenText"] as? String { screenText = text; screenTimestamp = event["timestamp"] as? Double ?? 0 }
                    if let rawModels = event["models"] as? [[String: Any]] {
                        availableGeminiModels = rawModels.compactMap(GeminiModelOption.init(dictionary:))
                        geminiModelsLoaded = true
                        chooseAvailableGeminiModels()
                    }
                    if let value = event["progress"] as? Double { progress = value }
                    if let section = event["processingSection"] as? String {
                        processingSection = section
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
                    if let path = event["export"] as? String { completedExportPath = path }
                    if eventIsError {
                        let detail = eventMessage ?? "The operation stopped without further details."
                        let issue = UserFacingIssue.forEngine(command: command, technicalDetails: detail)
                        present(issue, technicalDetails: detail, context: "Run \(command)")
                        if command == "doctor" { engineCheckStatus = .failed(issue.message) }
                    }
                    if let path = event["project"] as? String {
                        completedProjectPath = path
                        reload()
                        if let p = projects.first(where: { $0.folder?.path == path }) { selectedID = p.id }
                    }
                }
            } catch {
                let detail = error.localizedDescription
                present(
                    UserFacingIssue.forEngine(command: command, technicalDetails: detail),
                    technicalDetails: detail,
                    context: "Read \(command) result"
                )
            }
            task.waitUntilExit()
            stderr.fileHandleForReading.readabilityHandler = nil
            if let cleanupURL { try? FileManager.default.removeItem(at: cleanupURL) }
            reload()
            if task.terminationStatus == 0, ["export-selectable-video", "export-closed-audio-description-video"].contains(command), let folder = target?.folder {
                do {
                    guard let path = completedExportPath,
                          URL(fileURLWithPath: path).pathExtension.lowercased() == "mov" else {
                        throw AccessibilityMetadataWriterError.exportNotFound
                    }
                    try await AppleAccessibilityMetadataWriter().finalizeClosedDescriptionTrack(at: folder.appendingPathComponent(path))
                    message = "Closed Audio Description export complete"
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
            process = nil
            reload()
            videoPreparationActivity = nil
            if operationWasCancelled {
                message = exportWasCancelled ? "Export cancelled." : "Operation cancelled."
            } else if task.terminationStatus != 0 && self.error == nil {
                present(UserFacingIssue.forEngine(command: command, technicalDetails: nil), context: "\(command) stopped")
            }
            if task.terminationStatus == 0 {
                self.errorTitle = StudioModel.defaultErrorTitle
            }
            if command == "doctor" {
                engineCheckStatus = task.terminationStatus == 0
                    ? .ready
                    : .failed(self.error ?? UserFacingIssue.engineCheck.message)
            }
            let completedProject = completedProjectPath.flatMap { path in
                projects.first(where: { $0.folder?.path == path })
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

    private static func isExportCommand(_ command: String) -> Bool {
        command.hasPrefix("export-")
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
}

func timecode(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "00:00" }
    let value = max(0, Int(seconds))
    return String(format: "%02d:%02d", value / 60, value % 60)
}
