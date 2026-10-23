import Foundation

/// Runs the bundled engine for Azure Voices. The Azure Speech key is passed only in
/// the process environment; the owner-only temporary config never contains it.
enum AzureEngineProcess {
    static func launch(_ arguments: [String], settings: StudioSettings) throws -> (Process, Pipe, URL) {
        guard let engine = Bundle.main.resourceURL?.appendingPathComponent("Engine/vidistudio-engine") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-azure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let config = directory.appendingPathComponent("config.json")
        try JSONEncoder().encode(settings).write(to: config, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        let task = Process(), pipe = Pipe()
        task.executableURL = engine
        task.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["VIDISTUDIO_CONFIG"] = config.path
        environment["VIDISTUDIO_AZURE_SPEECH_KEY"] = settings.azureSpeechKey.trimmingCharacters(in: .whitespacesAndNewlines)
        task.environment = environment
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try task.run()
        return (task, pipe, directory)
    }

    /// Reads newline-delimited engine events until the process closes its output.
    static func events(from pipe: Pipe) async -> (events: [[String: Any]], failure: String?) {
        var events: [[String: Any]] = []
        var failure: String?
        do {
            for try await line in pipe.fileHandleForReading.bytes.lines {
                guard let data = line.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if event["error"] as? Bool == true { failure = event["message"] as? String ?? "The online voice request failed." }
                events.append(event)
            }
        } catch { failure = "Could not read the online voice result." }
        return (events, failure)
    }
}

/// Creates Azure speech for summary read-aloud one sentence at a time. Finished and
/// in-flight requests are reused so the next sentence is prepared while one plays.
@MainActor final class AzureSpeechRenderer {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private var requests: [String: Task<URL, Error>] = [:]
    private var processes: [UUID: Process] = [:]
    private var files: [URL] = []

    func audio(for text: String, settings: StudioSettings) -> Task<URL, Error> {
        let key = String(format: "%@|%@|%.3f|%.3f|%.3f|", locale: Locale(identifier: "en_US_POSIX"),
                         settings.resolvedAzureVoice, settings.azureSpeechRegion,
                         settings.systemSpeechRate, settings.systemSpeechPitch, settings.systemSpeechVolume) + text
        if let request = requests[key] { return request }
        var speechSettings = settings
        speechSettings.ttsMode = "azure"
        let request = Task {
            do { return try await self.render(text, settings: speechSettings) }
            catch {
                // Failed requests are not reused, so a retry contacts Azure again.
                self.requests[key] = nil
                throw error
            }
        }
        requests[key] = request
        return request
    }

    private func render(_ text: String, settings: StudioSettings) async throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-summary-\(UUID().uuidString).wav")
        let (task, pipe, directory) = try AzureEngineProcess.launch(["preview-tts", "--output", file.path, "--text", text], settings: settings)
        let id = UUID()
        processes[id] = task
        files.append(file)
        let result = await withTaskCancellationHandler {
            await AzureEngineProcess.events(from: pipe)
        } onCancel: {
            task.terminate()
        }
        processes[id] = nil
        try? FileManager.default.removeItem(at: directory)
        try Task.checkCancellation()
        if let failure = result.failure { throw Failure(message: failure) }
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw Failure(message: "No online speech was created. Check your Azure key, region and voice in Settings → Narration.")
        }
        return file
    }

    /// Cancels pending requests and deletes every generated file.
    func reset() {
        for request in requests.values { request.cancel() }
        requests.removeAll()
        for process in processes.values where process.isRunning { process.terminate() }
        processes.removeAll()
        for file in files { try? FileManager.default.removeItem(at: file) }
        files.removeAll()
    }
}
