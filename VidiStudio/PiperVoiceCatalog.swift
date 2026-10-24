import SwiftUI
import AppKit
import AVFoundation
import CryptoKit

// MARK: - Catalog model

/// A voice offered by the public Piper voice collection.
struct PiperVoice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let language: String
    let languageFamily: String
    let languageName: String
    let country: String
    let quality: String
    let modelSize: Int64
    let modelPath: String
    let modelMD5: String
    let configSize: Int64
    let configPath: String
    let configMD5: String
    let speakers: Int

    var languageLabel: String {
        country.isEmpty ? languageName : "\(languageName) (\(country))"
    }
    var qualityLabel: String { Self.qualityLabel(quality) }
    var displayName: String { "\(name) (\(qualityLabel)) — \(languageLabel)" }
    var sizeLabel: String { Self.sizeLabel(modelSize) }
    var note: String {
        speakers > 1
            ? "\(qualityLabel) quality · \(sizeLabel) · \(speakers) speakers"
            : "\(qualityLabel) quality · \(sizeLabel)"
    }
    /// The short public sample published beside the model.
    var samplePath: String {
        guard let slash = modelPath.lastIndex(of: "/") else { return modelPath + "/samples/speaker_0.mp3" }
        return String(modelPath[...slash]) + "samples/speaker_0.mp3"
    }

    static func qualityLabel(_ quality: String) -> String {
        switch quality.lowercased() {
        case "x_low": return "Extra low"
        case "low": return "Low"
        case "medium": return "Medium"
        case "high": return "High"
        default: return quality.isEmpty ? "Unknown" : quality
        }
    }

    static func qualityRank(_ quality: String) -> Int {
        switch quality.lowercased() {
        case "high": return 4
        case "medium": return 3
        case "low": return 2
        case "x_low": return 1
        default: return 0
        }
    }

    static func sizeLabel(_ bytes: Int64) -> String {
        bytes >= 1_000_000
            ? String(format: "%.1f MB", Double(bytes) / 1_000_000)
            : "\(max(1, bytes / 1_000)) KB"
    }
}

enum PiperStorage {
    static let downloadBase = "https://huggingface.co/rhasspy/piper-voices/resolve/main/"
    static let catalogURL = "https://huggingface.co/rhasspy/piper-voices"

    static var rootDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VidiStudio/piper")
    }
    static var voicesDirectory: URL { rootDirectory.appendingPathComponent("voices") }
    static var samplesDirectory: URL { rootDirectory.appendingPathComponent("samples") }

    static func modelURL(_ id: String) -> URL { voicesDirectory.appendingPathComponent(id + ".onnx") }
    static func configURL(_ id: String) -> URL { voicesDirectory.appendingPathComponent(id + ".onnx.json") }
    static func sampleCacheURL(_ id: String) -> URL {
        samplesDirectory.appendingPathComponent(id.replacingOccurrences(of: "/", with: "_") + "-speaker_0.mp3")
    }

    static func downloadURL(_ path: String) -> URL? {
        guard var url = URL(string: downloadBase) else { return nil }
        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        return url
    }
}

// MARK: - Downloaded voice and catalog store

@MainActor @Observable final class PiperVoiceManager {
    static let shared = PiperVoiceManager()

    let catalog: [PiperVoice]
    private(set) var downloadedIDs: Set<String> = []
    /// Fractional download progress per voice id.
    private(set) var progress: [String: Double] = [:]
    private(set) var deletingIDs: Set<String> = []

    private init() {
        catalog = Self.loadCatalog()
        refresh()
    }

    var downloadedVoices: [PiperVoice] {
        catalog.filter { downloadedIDs.contains($0.id) }.sorted {
            let language = $0.languageLabel.localizedStandardCompare($1.languageLabel)
            if language != .orderedSame { return language == .orderedAscending }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func voice(id: String) -> PiperVoice? {
        catalog.first { $0.id == id }
    }

    func displayName(for id: String) -> String {
        voice(id: id)?.displayName ?? NarrationVoiceFormatting.voiceDisplayName(id)
    }

    func isDownloaded(_ id: String) -> Bool { downloadedIDs.contains(id) }

    func refresh() {
        let fileManager = FileManager.default
        downloadedIDs = Set(catalog.compactMap { voice in
            let model = PiperStorage.modelURL(voice.id)
            let config = PiperStorage.configURL(voice.id)
            guard fileManager.fileExists(atPath: model.path),
                  fileManager.fileExists(atPath: config.path),
                  fileSize(model) > 0,
                  fileSize(config) > 0
            else { return nil }
            return voice.id
        })
    }

    func download(_ voice: PiperVoice) async throws {
        guard !isDownloaded(voice.id) else { return }
        try FileManager.default.createDirectory(at: PiperStorage.voicesDirectory, withIntermediateDirectories: true)
        progress[voice.id] = 0
        defer { progress[voice.id] = nil }
        let total = max(1, voice.modelSize + voice.configSize)
        guard let modelURL = PiperStorage.downloadURL(voice.modelPath),
              let configURL = PiperStorage.downloadURL(voice.configPath) else {
            throw PiperDownloadError.message("The voice download address is invalid. Try another voice.")
        }
        try await downloadFile(
            modelURL,
            to: PiperStorage.modelURL(voice.id),
            expectedSize: voice.modelSize,
            expectedMD5: voice.modelMD5
        ) { [weak self] received in
            Task { @MainActor in
                guard let self, self.progress[voice.id] != nil else { return }
                self.progress[voice.id] = min(max(Double(received) / Double(total), 0), 0.999)
            }
        }
        try await downloadFile(
            configURL,
            to: PiperStorage.configURL(voice.id),
            expectedSize: voice.configSize,
            expectedMD5: voice.configMD5
        ) { [weak self] received in
            Task { @MainActor in
                guard let self, self.progress[voice.id] != nil else { return }
                let done = Double(voice.modelSize) + Double(received)
                self.progress[voice.id] = min(max(done / Double(total), 0), 0.999)
            }
        }
        refresh()
    }

    private func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    func delete(_ voice: PiperVoice) async throws {
        deletingIDs.insert(voice.id)
        defer { deletingIDs.remove(voice.id) }
        // Let the removal indicator render before the fast local delete finishes.
        await Task.yield()
        let fileManager = FileManager.default
        for url in [PiperStorage.modelURL(voice.id), PiperStorage.configURL(voice.id), PiperStorage.sampleCacheURL(voice.id)] {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        refresh()
    }

    func sampleURL(for voice: PiperVoice) async throws -> URL {
        let destination = PiperStorage.sampleCacheURL(voice.id)
        if FileManager.default.fileExists(atPath: destination.path), fileSize(destination) > 0 {
            return destination
        }
        try FileManager.default.createDirectory(at: PiperStorage.samplesDirectory, withIntermediateDirectories: true)
        guard let url = PiperStorage.downloadURL(voice.samplePath) else {
            throw PiperDownloadError.message("This voice has no playable sample.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let (temporary, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PiperDownloadError.message("The sample could not be downloaded. Check the internet connection and try again.")
        }
        let size = Int64((try? temporary.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        guard size > 0 else {
            throw PiperDownloadError.message("The downloaded sample was empty. Try again.")
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    private func downloadFile(
        _ url: URL,
        to destination: URL,
        expectedSize: Int64,
        expectedMD5: String,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let delegate = PiperDownloadDelegate(
            destination: destination,
            expectedSize: expectedSize,
            expectedMD5: expectedMD5,
            onProgress: onProgress
        )
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    private static func loadCatalog() -> [PiperVoice] {
        let candidates = [
            Bundle.main.url(forResource: "piper-voices", withExtension: "json"),
            Bundle.main.url(forResource: "piper-voices", withExtension: "json", subdirectory: "Assets"),
            Bundle.main.resourceURL?.appendingPathComponent("Assets/piper-voices.json"),
        ]
        guard let url = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var voices: [PiperVoice] = []
        for (id, value) in root {
            guard let item = value as? [String: Any],
                  let files = item["files"] as? [String: Any] else { continue }
            var modelPath = "", configPath = "", modelMD5 = "", configMD5 = ""
            var modelSize: Int64 = 0, configSize: Int64 = 0
            for (path, raw) in files {
                let file = raw as? [String: Any] ?? [:]
                if path.lowercased().hasSuffix(".onnx.json") {
                    configPath = path
                    configSize = number(file["size_bytes"])
                    configMD5 = text(file["md5_digest"])
                } else if path.lowercased().hasSuffix(".onnx") {
                    modelPath = path
                    modelSize = number(file["size_bytes"])
                    modelMD5 = text(file["md5_digest"])
                }
            }
            guard !modelPath.isEmpty, !configPath.isEmpty else { continue }
            let language = item["language"] as? [String: Any] ?? [:]
            let code = text(language["code"]).replacingOccurrences(of: "_", with: "-")
            var family = text(language["family"])
            if family.isEmpty { family = code.split(separator: "-").first.map(String.init) ?? code }
            var languageName = text(language["name_english"])
            if languageName.isEmpty { languageName = code }
            var name = text(item["name"])
            if name.isEmpty { name = id }
            if let first = name.first { name = first.uppercased() + name.dropFirst() }
            voices.append(PiperVoice(
                id: id,
                name: name,
                language: code,
                languageFamily: family,
                languageName: languageName,
                country: text(language["country_english"]),
                quality: text(item["quality"]),
                modelSize: modelSize,
                modelPath: modelPath,
                modelMD5: modelMD5,
                configSize: configSize,
                configPath: configPath,
                configMD5: configMD5,
                speakers: max(1, Int(number(item["num_speakers"], fallback: 1)))
            ))
        }
        return voices.sorted { left, right in
            let language = left.languageLabel.localizedStandardCompare(right.languageLabel)
            if language != .orderedSame { return language == .orderedAscending }
            let name = left.name.localizedStandardCompare(right.name)
            if name != .orderedSame { return name == .orderedAscending }
            return PiperVoice.qualityRank(left.quality) > PiperVoice.qualityRank(right.quality)
        }
    }

    private static func text(_ value: Any?) -> String { value as? String ?? "" }
    private static func number(_ value: Any?, fallback: Int64 = 0) -> Int64 {
        (value as? NSNumber)?.int64Value ?? fallback
    }
}

enum PiperDownloadError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

/// Streams a voice file and verifies its published size and checksum.
private final class PiperDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let destination: URL
    let expectedSize: Int64
    let expectedMD5: String
    let onProgress: @Sendable (Int64) -> Void
    var continuation: CheckedContinuation<Void, Error>?
    private var moveError: Error?
    private var resumed = false

    init(destination: URL, expectedSize: Int64, expectedMD5: String, onProgress: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.expectedSize = expectedSize
        self.expectedMD5 = expectedMD5
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let size = Int64((try? location.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            if expectedSize > 0, size != expectedSize {
                throw PiperDownloadError.message(
                    "The download was incomplete (\(size) of \(expectedSize) bytes). Try again."
                )
            }
            if !expectedMD5.isEmpty {
                let actual = try Self.md5(location)
                if actual.caseInsensitiveCompare(expectedMD5) != .orderedSame {
                    throw PiperDownloadError.message(
                        "The downloaded voice did not match its published checksum. Try again."
                    )
                }
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !resumed else { return }
        resumed = true
        if let error {
            continuation?.resume(throwing: error)
        } else if let moveError {
            continuation?.resume(throwing: moveError)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }

    private static func md5(_ url: URL) throws -> String {
        var hasher = Insecure.MD5()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while let data = try handle.read(upToCount: 1 << 20), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Engine speech for live preview and summary read-aloud

/// Synthesizes Piper speech with the bundled engine and caches temporary WAVs outside projects.
actor PiperSpeech {
    static let shared = PiperSpeech()

    struct Request: Sendable, Hashable {
        let text: String
        let voice: String
        let rate: Double
        let pitch: Double
        let volume: Double
    }

    static func request(text: String, settings: StudioSettings) -> Request {
        Request(
            text: text,
            voice: settings.piperVoice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? settings.systemVoice.trimmingCharacters(in: .whitespacesAndNewlines)
                : settings.piperVoice.trimmingCharacters(in: .whitespacesAndNewlines),
            rate: settings.systemSpeechRate,
            pitch: settings.systemSpeechPitch,
            volume: settings.systemSpeechVolume
        )
    }

    private var inFlight: [String: Task<URL, Error>] = [:]

    func synthesize(_ request: Request) async throws -> URL {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw PiperSpeechError.message("There is no text to speak.")
        }
        guard !request.voice.isEmpty else {
            throw PiperSpeechError.message("Choose a Piper voice in Settings, then try again.")
        }
        let key = Self.cacheKey(request)
        let cacheDirectory = Self.cacheDirectory
        let destination = cacheDirectory.appendingPathComponent(key + ".wav")
        if Self.isUsable(destination) {
            Self.touch(destination)
            return destination
        }
        if let existing = inFlight[key] {
            return try await existing.value
        }
        let task = Task {
            try await Self.render(request, destination: destination)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        do {
            let url = try await task.value
            Self.pruneCache()
            return url
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VidiStudio/PiperSpeech", isDirectory: true)
    }

    private static func cacheKey(_ request: Request) -> String {
        let material = String(
            format: "%@|%.4f|%.4f|%.4f|%@",
            locale: Locale(identifier: "en_US_POSIX"),
            request.voice, request.rate, request.pitch, request.volume, request.text
        )
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func isUsable(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 44
    }

    private static func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private static func pruneCache() {
        let fileManager = FileManager.default
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        guard let items = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for item in items {
            guard let modified = try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified < cutoff else { continue }
            try? fileManager.removeItem(at: item)
        }
    }

    private static func render(_ request: Request, destination: URL) async throws -> URL {
        guard let engine = Bundle.main.resourceURL?.appendingPathComponent("Engine/vidistudio-engine"),
              FileManager.default.isExecutableFile(atPath: engine.path) else {
            throw PiperSpeechError.message("A required part of VidiStudio is unavailable. Reinstall the application, then try again.")
        }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let identifier = UUID().uuidString
        let configURL = cacheDirectory.appendingPathComponent(identifier + ".json")
        let temporary = cacheDirectory.appendingPathComponent(identifier + ".wav")
        let config: [String: Any] = [
            "ttsMode": "piper",
            "piperVoice": request.voice,
            "systemSpeechRate": request.rate,
            "systemSpeechPitch": request.pitch,
            "systemSpeechVolume": request.volume,
        ]
        defer {
            try? FileManager.default.removeItem(at: configURL)
            try? FileManager.default.removeItem(at: temporary)
        }
        do {
            try JSONSerialization.data(withJSONObject: config).write(to: configURL, options: .atomic)
            let message = try await Task.detached(priority: .userInitiated) { () -> String? in
                let process = Process()
                process.executableURL = engine
                process.arguments = ["synthesize-speech", "--text", request.text, "--output", temporary.path]
                var environment = ProcessInfo.processInfo.environment
                environment["VIDISTUDIO_CONFIG"] = configURL.path
                environment["VIDISTUDIO_PIPER_VOICES"] = PiperStorage.voicesDirectory.path
                process.environment = environment
                let output = Pipe()
                let errors = Pipe()
                process.standardOutput = output
                process.standardError = errors
                do {
                    try process.run()
                } catch {
                    throw PiperSpeechError.message("Piper could not start. Reinstall VidiStudio, then try again.")
                }
                let outputData = output.fileHandleForReading.readDataToEndOfFile()
                _ = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    let text = String(decoding: outputData, as: UTF8.self)
                    let lines = text.split(separator: "\n")
                    for line in lines.reversed() {
                        if let data = String(line).data(using: .utf8),
                           let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let message = event["message"] as? String {
                            return message
                        }
                    }
                    return "Piper could not create audio for the selected voice. Try again or choose another voice."
                }
                return nil
            }.value
            if let message {
                throw PiperSpeechError.message(message)
            }
            guard isUsable(temporary) else {
                throw PiperSpeechError.message("Piper produced no audio. Download the voice again in Settings, then try again.")
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
            return destination
        }
    }
}

enum PiperSpeechError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

// MARK: - Settings controls

struct PiperVoiceSettingsView: View {
    @Binding var settings: StudioSettings
    @State private var manager = PiperVoiceManager.shared
    @State private var showingCatalog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Piper Voices are free neural voices that run entirely on this Mac. The Piper speech engine is included with VidiStudio; download the voices you want to use. Voices work offline and your narration text never leaves this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if manager.downloadedVoices.isEmpty {
                Text("No Piper voices are downloaded yet. Choose Download or Remove Voices to add one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Piper voice", selection: $settings.piperVoice) {
                    ForEach(manager.downloadedVoices) { voice in
                        Text(voice.displayName).tag(voice.id)
                    }
                    if !settings.piperVoice.isEmpty,
                       !manager.downloadedVoices.contains(where: { $0.id == settings.piperVoice }) {
                        Text(NarrationVoiceFormatting.voiceDisplayName(settings.piperVoice)).tag(settings.piperVoice)
                    }
                }
                .accessibilityHint("Chooses the downloaded Piper voice used for narration, live preview, and summary read-aloud")
            }
            Button("Download or Remove Voices…", systemImage: "arrow.down.circle") {
                showingCatalog = true
            }
            .accessibilityLabel("Download or remove Piper voices")
            Text("Voices are downloaded from the public Piper voice collection on Hugging Face and checked against their published size and checksum. Piper is an open-source project by Rhasspy.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $showingCatalog) {
            PiperVoiceBrowser(settings: $settings)
        }
        .task { manager.refresh() }
        .onChange(of: manager.downloadedIDs) { _, ids in
            if settings.ttsMode == "piper",
               (settings.piperVoice.isEmpty || !ids.contains(settings.piperVoice)),
               let first = manager.downloadedVoices.first {
                settings.piperVoice = first.id
            }
        }
    }
}

// MARK: - Voice catalog browser

private struct PiperFilterOption: Identifiable, Hashable {
    let id: String
    let label: String
}

struct PiperVoiceBrowser: View {
    @Binding var settings: StudioSettings
    @Environment(\.dismiss) private var dismiss
    @State private var manager = PiperVoiceManager.shared
    @State private var sample = PiperSamplePreview()
    @State private var search = ""
    @State private var language = ""
    @State private var quality = ""
    @State private var sort = "language"
    @State private var status: String?

    private var busy: Bool { !manager.progress.isEmpty || !manager.deletingIDs.isEmpty }

    private var languageOptions: [PiperFilterOption] {
        let grouped = Dictionary(grouping: manager.catalog, by: \.languageFamily)
        let options = grouped.map { family, voices in
            PiperFilterOption(id: family, label: voices.first?.languageName ?? family)
        }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        return [PiperFilterOption(id: "", label: "All languages")] + options
    }

    private var qualityOptions: [PiperFilterOption] {
        let qualities = Set(manager.catalog.map(\.quality).filter { !$0.isEmpty })
        let options = qualities.sorted {
            PiperVoice.qualityRank($0) > PiperVoice.qualityRank($1)
        }.map { PiperFilterOption(id: $0, label: PiperVoice.qualityLabel($0)) }
        return [PiperFilterOption(id: "", label: "All qualities")] + options
    }

    private let sortOptions = [
        PiperFilterOption(id: "language", label: "Language (A–Z)"),
        PiperFilterOption(id: "name", label: "Voice name (A–Z)"),
        PiperFilterOption(id: "quality", label: "Quality (high to low)"),
        PiperFilterOption(id: "size", label: "Size (smallest first)"),
    ]

    private var visibleVoices: [PiperVoice] {
        let filter = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = manager.catalog.filter { voice in
            (language.isEmpty || voice.languageFamily.caseInsensitiveCompare(language) == .orderedSame)
                && (quality.isEmpty || voice.quality.caseInsensitiveCompare(quality) == .orderedSame)
                && (filter.isEmpty || matches(voice, filter))
        }
        return query.sorted { left, right in
            switch sort {
            case "name":
                let name = left.name.localizedStandardCompare(right.name)
                if name != .orderedSame { return name == .orderedAscending }
                return left.languageLabel.localizedStandardCompare(right.languageLabel) == .orderedAscending
            case "quality":
                let rank = PiperVoice.qualityRank(left.quality) > PiperVoice.qualityRank(right.quality)
                if PiperVoice.qualityRank(left.quality) != PiperVoice.qualityRank(right.quality) { return rank }
                return left.languageLabel.localizedStandardCompare(right.languageLabel) == .orderedAscending
            case "size":
                if left.modelSize != right.modelSize { return left.modelSize < right.modelSize }
                return left.languageLabel.localizedStandardCompare(right.languageLabel) == .orderedAscending
            default:
                let lang = left.languageLabel.localizedStandardCompare(right.languageLabel)
                if lang != .orderedSame { return lang == .orderedAscending }
                let name = left.name.localizedStandardCompare(right.name)
                if name != .orderedSame { return name == .orderedAscending }
                return PiperVoice.qualityRank(left.quality) > PiperVoice.qualityRank(right.quality)
            }
        }
    }

    private func matches(_ voice: PiperVoice, _ filter: String) -> Bool {
        voice.displayName.localizedStandardContains(filter)
            || voice.language.localizedStandardContains(filter)
            || voice.country.localizedStandardContains(filter)
            || voice.quality.localizedStandardContains(filter)
            || voice.qualityLabel.localizedStandardContains(filter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Piper Voices")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Download neural voices for offline narration. Filter or sort the catalog, then play a sample before downloading.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("Search voices", text: $search, prompt: Text("Name, language, dialect, or quality"))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search voices")
                .onExitCommand { search = "" }

            HStack(spacing: 12) {
                Picker("Language", selection: $language) {
                    ForEach(languageOptions) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                Picker("Quality", selection: $quality) {
                    ForEach(qualityOptions) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                Picker("Sort by", selection: $sort) {
                    ForEach(sortOptions) { option in
                        Text(option.label).tag(option.id)
                    }
                }
            }
            .disabled(busy)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleVoices) { voice in
                        row(voice)
                        Divider()
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(minHeight: 320)
            .accessibilityLabel("Piper voice catalog")

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = sample.error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 760, idealWidth: 800, minHeight: 620)
        .task { manager.refresh() }
        .onDisappear { sample.stop() }
    }

    private var summary: String {
        let installed = manager.catalog.filter { manager.isDownloaded($0.id) }.count
        return visibleVoices.count == manager.catalog.count
            ? "\(manager.catalog.count) voices in the catalog · \(installed) downloaded."
            : "\(visibleVoices.count) of \(manager.catalog.count) voices shown · \(installed) downloaded."
    }

    @ViewBuilder
    private func row(_ voice: PiperVoice) -> some View {
        let downloaded = manager.isDownloaded(voice.id)
        let downloading = manager.progress[voice.id] != nil
        let deleting = manager.deletingIDs.contains(voice.id)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(voice.displayName)
                    .font(.body.weight(.semibold))
                Text(voice.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let progress = manager.progress[voice.id] {
                    ProgressView(value: progress)
                        .accessibilityLabel("Download progress for \(voice.displayName)")
                    Text(progressLabel(voice, progress))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if deleting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Removing \(voice.displayName)")
            }
            Button(sampleButtonTitle(voice)) {
                sample.toggle(voice, manager: manager)
            }
            .disabled(sample.loadingID != nil || busy)
            .accessibilityLabel(
                (sample.playingID == voice.id ? "Stop sample for " : "Play sample for ") + voice.displayName
            )
            .help("Plays a short sample published with this voice. The preview needs the internet; a downloaded voice itself works offline.")
            Button(deleting ? "Deleting…" : downloading ? "Downloading…" : downloaded ? "Delete" : "Download") {
                Task {
                    if downloaded {
                        await delete(voice)
                    } else {
                        await download(voice)
                    }
                }
            }
            .disabled(busy || downloading || deleting)
            .tint(downloaded || deleting ? .red : nil)
            .help(downloaded ? "Removes this voice, its settings file, and its cached sample" : "Downloads this voice and its settings file")
            .accessibilityLabel(
                deleting ? "Deleting \(voice.displayName)"
                    : downloading ? "Downloading \(voice.displayName)"
                    : (downloaded ? "Delete " : "Download ") + voice.displayName
            )
        }
        .padding(.vertical, 6)
    }

    private func sampleButtonTitle(_ voice: PiperVoice) -> String {
        if sample.loadingID == voice.id { return "Loading…" }
        return sample.playingID == voice.id ? "Stop Sample" : "Play Sample"
    }

    private func progressLabel(_ voice: PiperVoice, _ fraction: Double) -> String {
        let total = voice.modelSize + voice.configSize
        return "\(Int(fraction * 100))% · \(PiperVoice.sizeLabel(Int64(Double(total) * fraction))) of \(PiperVoice.sizeLabel(total))"
    }

    private func download(_ voice: PiperVoice) async {
        status = "Downloading \(voice.displayName)…"
        do {
            try await manager.download(voice)
            if settings.piperVoice.isEmpty || !manager.isDownloaded(settings.piperVoice) {
                settings.piperVoice = voice.id
            }
            status = "\(voice.displayName) is ready to use."
        } catch is CancellationError {
            status = "The download was canceled."
        } catch {
            status = "The voice could not be downloaded. \(error.localizedDescription)"
        }
    }

    private func delete(_ voice: PiperVoice) async {
        if sample.playingID == voice.id { sample.stop() }
        status = "Removing \(voice.displayName) and its cached sample…"
        do {
            try await manager.delete(voice)
            if settings.piperVoice == voice.id {
                settings.piperVoice = manager.downloadedVoices.first?.id ?? ""
            }
            status = "\(voice.displayName) was removed."
        } catch {
            status = "The voice could not be removed. \(error.localizedDescription)"
        }
    }
}

/// Plays hosted Piper samples without creating project files.
@MainActor @Observable final class PiperSamplePreview: NSObject, AVAudioPlayerDelegate {
    var loadingID: String?
    var playingID: String?
    var error: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var generation = 0

    func toggle(_ voice: PiperVoice, manager: PiperVoiceManager) {
        if playingID == voice.id {
            stop()
            return
        }
        stop()
        generation += 1
        let generation = generation
        loadingID = voice.id
        error = nil
        Task {
            do {
                let url = try await manager.sampleURL(for: voice)
                guard self.generation == generation else { return }
                let player = try AVAudioPlayer(contentsOf: url)
                player.delegate = self
                player.play()
                self.player = player
                self.playingID = voice.id
            } catch {
                guard self.generation == generation else { return }
                self.error = "The sample could not be played. \(error.localizedDescription)"
            }
            if self.generation == generation { self.loadingID = nil }
        }
    }

    func stop() {
        generation += 1
        player?.stop()
        player = nil
        playingID = nil
        loadingID = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.player = nil
            self.playingID = nil
        }
    }
}
