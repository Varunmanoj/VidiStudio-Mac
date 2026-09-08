import Foundation
import SwiftUI
import AppKit
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
    var folder: URL?
    var hasProcessed: Bool?
    var canReprocess: Bool {
        hasProcessed == true || !transcript.isEmpty || !summary.isEmpty || !cues.isEmpty || !exports.isEmpty
    }
    var hasGeneratedContent: Bool { canReprocess || !thumbnails.isEmpty }
    func url(_ relative: String) -> URL? {
        guard let folder else { return nil }
        let resolved = folder.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(folder.standardizedFileURL.resolvingSymlinksInPath().path + "/") else { return nil }
        return resolved
    }
}
struct StudioSettings: Codable {
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
    var followTranscript = true
    var ttsMode = "system"
    var narrationPlayback = "generated"
    var systemVoice = ""
    var systemSpeechRate = 1.0
    var systemSpeechPitch = 1.0
    var systemSpeechVolume = 1.0
    var geminiVoice = "Kore"
    var ffmpegPath = ""
    var ffprobePath = ""
    var libraryPath = StudioSettings.defaultLibraryURL.path
    static var url: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/VidiStudio/config.json") }

    var narrationSignature: String {
        if ttsMode == "gemini" {
            return "gemini|\(geminiVoice)|\(models["tts_audio"] ?? "")"
        }
        return String(
            format: "system|%@|%.3f|%.3f|%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            systemVoice,
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
}

@MainActor @Observable
final class StudioModel {
    static let defaultErrorTitle = "VidiStudio needs attention"
    var projects: [StudioProject] = []
    var selectedID: String? { didSet { UserDefaults.standard.set(selectedID, forKey: "lastProjectID") } }
    var settings = StudioSettings()
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
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Engine/_internal/ai-defaults.json"),
           let data = try? Data(contentsOf: url), let defaults = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["models", "prompts", "apiVersion", "videoProcessing"] { merged[key] = defaults[key] }
        }
        if let data = try? Data(contentsOf: StudioSettings.url), let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in saved { merged[key] = value }
        }
        if let data = try? JSONSerialization.data(withJSONObject: merged), let decoded = try? JSONDecoder().decode(StudioSettings.self, from: data) { settings = decoded }
        if settings.libraryPath == StudioSettings.legacyDefaultLibraryURL.path {
            settings.libraryPath = StudioSettings.defaultLibraryURL.path
        }
        reload()
        selectedID = UserDefaults.standard.string(forKey: "lastProjectID")
    }
    func saveSettings() {
        do {
            let directory = StudioSettings.url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(settings).write(to: StudioSettings.url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: StudioSettings.url.path)
            reload()
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
    func importVideo(at url: URL) {
        guard !busy else { return }
        execute("import-video", extra: ["--video", url.path, "--library", settings.libraryPath], project: nil)
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
    func attachVideo() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.movie, .video]
        panel.message = "Choose the matching local video for playback and final video export."
        if panel.runModal() == .OK, let url = panel.url { execute("attach-video", extra: ["--video", url.path]) }
    }
    func trashProject(_ project: StudioProject) {
        guard !busy, let folder = project.folder else { return }
        do { try FileManager.default.trashItem(at: folder, resultingItemURL: nil); reload() }
        catch { self.error = error.localizedDescription }
    }
    func clearGeneratedContent(_ project: StudioProject) {
        guard !busy else { return }
        let alert = NSAlert()
        alert.messageText = "Delete generated content from “\(project.name)”?"
        alert.informativeText = "This deletes transcripts, summaries, descriptions, narration, thumbnails, exports, and edit history. Your project and original video or YouTube link are kept. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete Generated Content")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        selectedID = project.id
        execute("clear-generated", project: project)
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
        case "generate-summary": impact = "Only the summary will be overwritten. Other content will be kept."
        case "generate-ad-cues": impact = "Only the AD segments will be overwritten. Other content will be kept."
        case "transcribe": impact = "Only the transcription will be overwritten. Other content will be kept."
        default: impact = "The transcript, summary, and AD segments will be regenerated. Narration files and existing exports will be kept."
        }
        let alert = NSAlert()
        alert.messageText = command == "regenerate-all" ? "Regenerate all content in “\(current.name)”?" : "Replace existing content in “\(current.name)”?"
        alert.informativeText = (existing.isEmpty ? "" : "This project already contains \(existing.joined(separator: ", ")). ") + impact + " Do you want to continue?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Continue Analysis")
        return alert.runModal() == .alertSecondButtonReturn
    }

    func execute(_ command: String, extra: [String] = [], project: StudioProject? = nil, configurationURL: URL? = nil, cleanupURL: URL? = nil) {
        guard !busy else { return }
        errorTitle = command == "capture-frame" ? "Read Frame Text Processing" : StudioModel.defaultErrorTitle
        if command == "doctor" {
            error = nil
            engineCheckStatus = .checking
        }
        let target = project ?? (["import-video", "import-youtube", "doctor", "validate-config", "list-models"].contains(command) ? nil : selected)
        if let target, !confirmAnalysisReplacement(command, project: target) { return }
        guard let engine = Bundle.main.resourceURL?.appendingPathComponent("Engine/vidistudio-engine"), FileManager.default.isExecutableFile(atPath: engine.path) else {
            let message = "The bundled engine is missing. Reinstall VidiStudio and try again."
            if command == "doctor" { engineCheckStatus = .failed(message) }
            error = message
            return
        }
        busy = true
        progress = 0
        message = command == "capture-frame" ? "Processing text from the selected frame…" : command.replacingOccurrences(of: "-", with: " ").capitalized
        let task = Process(); task.executableURL = engine
        task.arguments = [command] + (target?.folder.map { ["--project", $0.path] } ?? []) + extra
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
            busy = false; process = nil; reload()
            if task.terminationStatus != 0 && self.error == nil { self.error = "Processing stopped. Your previously completed results are saved." }
            if task.terminationStatus == 0 { self.errorTitle = StudioModel.defaultErrorTitle }
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
