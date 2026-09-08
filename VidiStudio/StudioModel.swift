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
    var geminiVoice = "Kore"
    var ffmpegPath = ""
    var ffprobePath = ""
    var libraryPath = StudioSettings.defaultLibraryURL.path
    static var url: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/VidiStudio/config.json") }
}

@MainActor @Observable
final class StudioModel {
    var projects: [StudioProject] = []
    var selectedID: String? { didSet { UserDefaults.standard.set(selectedID, forKey: "lastProjectID") } }
    var settings = StudioSettings()
    var busy = false
    var message = "All files stay in your local project folders."
    var progress = 0.0
    var error: String?
    var logs: [String] = []
    var screenText: String?
    var screenTimestamp = 0.0
    var process: Process?
    var isCreatingProject = false
    var selected: StudioProject? { projects.first { $0.id == selectedID } }
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
    func execute(_ command: String, extra: [String] = [], project: StudioProject? = nil) {
        guard !busy else { return }
        let target = project ?? (["import-video", "import-youtube", "doctor", "validate-config"].contains(command) ? nil : selected)
        guard let engine = Bundle.main.resourceURL?.appendingPathComponent("Engine/vidistudio-engine"), FileManager.default.isExecutableFile(atPath: engine.path) else {
            error = "The bundled engine is missing. Run script/build_and_run.sh to prepare the app."; return
        }
        busy = true; progress = 0; message = command.replacingOccurrences(of: "-", with: " ").capitalized
        let task = Process(); task.executableURL = engine
        task.arguments = [command] + (target?.folder.map { ["--project", $0.path] } ?? []) + extra
        task.environment = ProcessInfo.processInfo.environment.merging(["VIDISTUDIO_CONFIG": StudioSettings.url.path]) { _, new in new }
        let output = Pipe(); task.standardOutput = output
        let stderr = Pipe(); task.standardError = stderr
        // Drain stderr independently so verbose native libraries cannot block the engine.
        stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        process = task
        do { try task.run() } catch {
            stderr.fileHandleForReading.readabilityHandler = nil
            busy = false; process = nil; self.error = error.localizedDescription; return
        }
        Task {
            do {
                for try await line in output.fileHandleForReading.bytes.lines {
                    guard let data = line.data(using: .utf8), let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    if let text = event["message"] as? String { message = text; logs.append(text); if logs.count > 200 { logs.removeFirst() } }
                    if let text = event["screenText"] as? String { screenText = text; screenTimestamp = event["timestamp"] as? Double ?? 0 }
                    if let value = event["progress"] as? Double { progress = value }
                    if event["error"] as? Bool == true { self.error = message }
                    if let path = event["project"] as? String {
                        reload()
                        if let p = projects.first(where: { $0.folder?.path == path }) { selectedID = p.id }
                    }
                }
            } catch { self.error = error.localizedDescription }
            task.waitUntilExit()
            stderr.fileHandleForReading.readabilityHandler = nil
            busy = false; process = nil; reload()
            if task.terminationStatus != 0 && self.error == nil { self.error = "Processing stopped. Your previously completed results are saved." }
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
