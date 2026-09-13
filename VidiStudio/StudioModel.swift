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
    var status: String
    var error: String?
    var sourceType: String?
    var youtubeURL: String?
    var transcriptGenerated: Bool?
    var summaryGenerated: Bool?
    var descriptionsGenerated: Bool?
    var undoStack: [[Segment]]?
    var redoStack: [[Segment]]?
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
            sourceDetail = project.youtubeURL.flatMap(StudioModel.youtubeVideoID(from:)) ?? "Not available"
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
    static let defaultErrorTitle = "VidiStudio needs attention"
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
    func dismissError() {
        error = nil
        errorTitle = StudioModel.defaultErrorTitle
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
            for (key, value) in saved { merged[key] = value }
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
        } catch { self.error = error.localizedDescription }
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
    func importVideo(at url: URL) -> Bool {
        guard !busy else { return false }
        guard validateLocalVideoForCreation(url) else { return false }
        let filename = url.lastPathComponent
        if let existing = projects.first(where: {
            !$0.isYouTubeURLProject
                && URL(fileURLWithPath: $0.source).lastPathComponent.caseInsensitiveCompare(filename) == .orderedSame
        }) {
            showDuplicateProjectError(existing)
            return false
        }
        execute("import-video", extra: ["--video", url.path, "--library", settings.libraryPath], project: nil)
        return true
    }
    func validateLocalVideoForCreation(_ url: URL) -> Bool {
        do {
            let size = try LocalVideoFilePolicy.size(at: url)
            guard size <= LocalVideoFilePolicy.maximumSizeBytes else {
                errorTitle = "Video File Too Large"
                error = "\(url.lastPathComponent) is \(LocalVideoFilePolicy.displaySize(size)). VidiStudio supports local video files up to 2 GB because larger files cannot be uploaded through the Gemini Files API. Choose a smaller video or create a YouTube project instead."
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
    func importYouTube(at rawURL: String, name: String? = nil) -> Bool {
        guard !busy else { return false }
        guard validateYouTubeForCreation(rawURL) else { return false }
        var arguments = ["--url", rawURL, "--library", settings.libraryPath]
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["--name", name]
        }
        execute("import-youtube", extra: arguments, project: nil)
        return true
    }
    func validateYouTubeForCreation(_ rawURL: String) -> Bool {
        let candidate = Self.youtubeVideoID(from: rawURL)
        if let existing = projects.first(where: { project in
            guard project.isYouTubeURLProject, let existingURL = project.youtubeURL else { return false }
            if let candidate, let existingID = Self.youtubeVideoID(from: existingURL) {
                return candidate == existingID
            }
            return existingURL.trimmingCharacters(in: .whitespacesAndNewlines) == rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }) {
            showDuplicateProjectError(existing)
            return false
        }
        return true
    }
    private func showDuplicateProjectError(_ project: StudioProject) {
        selectedID = project.id
        errorTitle = "Project Already Exists"
        error = "A project for this video already exists as “\(project.name)”. Please continue with the existing project or delete the existing project before continuing."
    }
    static func youtubeVideoID(from rawURL: String) -> String? {
        guard let components = URLComponents(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host?.lowercased() else { return nil }
        let pathParts = components.path.split(separator: "/").map(String.init)
        let identifier: String?
        switch host {
        case "youtu.be", "www.youtu.be":
            identifier = pathParts.first
        case "youtube.com", "www.youtube.com", "m.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com":
            if components.path == "/watch" {
                identifier = components.queryItems?.first(where: { $0.name == "v" })?.value
            } else if pathParts.count > 1, ["shorts", "embed", "live"].contains(pathParts[0]) {
                identifier = pathParts[1]
            } else {
                identifier = nil
            }
        default:
            identifier = nil
        }
        guard let identifier,
              identifier.count == 11,
              identifier.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-")).contains($0) }) else { return nil }
        return identifier
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
            let message = "Could not check the engine: \(error.localizedDescription)"
            engineCheckStatus = .failed(message)
            self.error = message
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
                error = "Choose an executable \(name) file."
                return
            }
            assign(url.standardizedFileURL.path)
        }
    }
    func trashProject(_ project: StudioProject) {
        guard !busy, let folder = project.folder else { return }
        do { try FileManager.default.trashItem(at: folder, resultingItemURL: nil); reload() }
        catch { self.error = error.localizedDescription }
    }
    func deleteGeneratedContent(_ project: StudioProject, components: Set<GeneratedContentComponent>) {
        guard !busy, !components.isEmpty else { return }
        selectedID = project.id
        let arguments = components.sorted { $0.rawValue < $1.rawValue }.flatMap { ["--component", $0.rawValue] }
        execute("delete-generated", extra: arguments, project: project)
    }
    func confirmDeleteGeneratedContent(_ project: StudioProject, component: GeneratedContentComponent) {
        guard !busy, component.hasContent(in: project) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \(component.title.lowercased()) from “\(project.name)”?"
        alert.informativeText = component.explanation + " The project and original video or YouTube link are kept. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete \(component.title)")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        if component == .narration || component == .descriptions {
            NotificationCenter.default.post(
                name: .vidiStudioNarrationAudioWillDelete,
                object: self,
                userInfo: ["projectID": project.id]
            )
        }
        deleteGeneratedContent(project, components: [component])
    }
    func confirmDeleteExport(_ project: StudioProject, path: String) {
        guard !busy, project.exports.contains(path) else { return }
        let name = URL(fileURLWithPath: path).lastPathComponent
        let alert = NSAlert()
        alert.messageText = "Delete “\(name)”?"
        alert.informativeText = "The export will be permanently removed from the project to free storage. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete Export")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        selectedID = project.id
        execute("delete-export", extra: ["--name", path], project: project)
    }
    func confirmDeleteSegmentAudio(_ project: StudioProject, cue: Segment, beforeDelete: () -> Void) {
        guard !busy, cue.audio != nil else { return }
        let alert = NSAlert()
        alert.messageText = "Delete audio for this description?"
        alert.informativeText = "Only the generated narration audio will be deleted. The description text and timing will remain unchanged."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete Segment Audio")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        beforeDelete()
        NotificationCenter.default.post(
            name: .vidiStudioNarrationAudioWillDelete,
            object: self,
            userInfo: ["projectID": project.id]
        )
        selectedID = project.id
        execute("delete-segment-audio", extra: ["--segment", cue.id], project: project)
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
            } catch { self.error = "Could not open this project: \(error.localizedDescription)" }
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
            self.error = "Could not load available Gemini models: \(error.localizedDescription)"
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
                self.error = "Could not check existing project content: \(error.localizedDescription)"
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
        case "generate-ad-cues": impact = "The Audio Description segments and their rows in AD Transcript will be regenerated. Any generated narration audio for those descriptions will be deleted immediately before description generation starts. Other project content and existing exports will be kept. New narration is not generated automatically. If description generation then fails, deleted narration audio will not be restored."
        case "transcribe": impact = "Only the transcript will be regenerated. Other content will be kept."
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
            self.error = "Could not check narration before export: \(error.localizedDescription)"
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

    func execute(_ command: String, extra: [String] = [], project: StudioProject? = nil, configurationURL: URL? = nil, cleanupURL: URL? = nil) {
        guard !busy else { return }
        errorTitle = command == "capture-frame" ? "Read Frame Text Processing" : StudioModel.defaultErrorTitle
        if command == "doctor" {
            error = nil
            engineCheckStatus = .checking
        }
        let target = project ?? (["import-video", "import-youtube", "doctor", "validate-config", "list-models"].contains(command) ? nil : selected)
        if ["export-final-video", "export-selectable-video", "export-closed-audio-description-video", "export-open-audio-description-video", "export-closed-caption-video", "export-dual-closed-caption-video", "export-open-caption-video"].contains(command), let target, target.isYouTubeURLProject {
            error = "Video export is unavailable for YouTube URL projects. You can export text and narration audio instead."
            return
        }
        if ["export-original-audio", "export-described-audio"].contains(command), let target, target.isYouTubeURLProject {
            error = "Original and final program-audio export require a local video file. You can export narration audio or text from this YouTube project."
            return
        }
        if command == "generate-ad-cues", let target, !target.canGenerateDescriptions {
            error = "Generate the transcript and summary before generating descriptions."
            return
        }
        if let target, !confirmAnalysisReplacement(command, project: target) { return }
        var exportOptions: [String] = []
        if ["export-final-video", "export-selectable-video", "export-closed-audio-description-video", "export-open-audio-description-video", "export-described-audio", "export-audio"].contains(command), let target {
            guard let options = confirmIncompleteNarrationExport(
                project: target,
                audioOnly: command == "export-audio",
                exportKindOverride: command == "export-described-audio" ? "final audio" : nil
            ) else { return }
            exportOptions = options
        }
        guard let engine = Bundle.main.resourceURL?.appendingPathComponent("Engine/vidistudio-engine"), FileManager.default.isExecutableFile(atPath: engine.path) else {
            let message = "The bundled engine is missing. Reinstall VidiStudio and try again."
            if command == "doctor" { engineCheckStatus = .failed(message) }
            error = message
            return
        }
        busy = true
        var completedExportPath: String?
        progress = 0
        message = command == "capture-frame" ? "Processing text from the selected frame…" : command.replacingOccurrences(of: "-", with: " ").capitalized
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
            let message = error.localizedDescription
            if command == "doctor" { engineCheckStatus = .failed(message) }
            busy = false; process = nil; self.error = message; return
        }
        Task {
            do {
                for try await line in output.fileHandleForReading.bytes.lines {
                    guard let data = line.data(using: .utf8), let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    if let text = event["message"] as? String { message = text; logs.append(text); if logs.count > 200 { logs.removeFirst() } }
                    if let text = event["screenText"] as? String { screenText = text; screenTimestamp = event["timestamp"] as? Double ?? 0 }
                    if let rawModels = event["models"] as? [[String: Any]] {
                        availableGeminiModels = rawModels.compactMap(GeminiModelOption.init(dictionary:))
                        geminiModelsLoaded = true
                        chooseAvailableGeminiModels()
                    }
                    if let value = event["progress"] as? Double { progress = value }
                    if let path = event["export"] as? String { completedExportPath = path }
                    if event["error"] as? Bool == true {
                        self.error = message
                        if command == "doctor" { engineCheckStatus = .failed(message) }
                    }
                    if let path = event["project"] as? String {
                        reload()
                        if let p = projects.first(where: { $0.folder?.path == path }) { selectedID = p.id }
                    }
                }
            } catch { self.error = error.localizedDescription }
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
                    self.error = "The two-track video was created, but macOS could not apply or verify its Audio Description metadata: \(error.localizedDescription)"
                }
            }
            busy = false; process = nil; reload()
            if task.terminationStatus != 0 && self.error == nil { self.error = "Processing stopped. Your previously completed results are saved." }
            if task.terminationStatus == 0 {
                self.errorTitle = StudioModel.defaultErrorTitle
            }
            if command == "doctor" {
                engineCheckStatus = task.terminationStatus == 0
                    ? .ready
                    : .failed(self.error ?? "The engine is not configured correctly.")
            }
        }
    }
    func saveCues(_ cues: [Segment]) {
        guard let p = selected, !busy else { return }
        do {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-cues-\(UUID().uuidString).json")
            try JSONEncoder().encode(cues).write(to: file)
            execute("save-cues", extra: ["--input", file.path], project: p)
        } catch { self.error = error.localizedDescription }
    }
}

func timecode(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "00:00" }
    let value = max(0, Int(seconds))
    return String(format: "%02d:%02d", value / 60, value % 60)
}
