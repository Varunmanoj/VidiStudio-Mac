import SwiftUI
import AVFoundation
import Combine

@MainActor @Observable final class GeminiVoicePreview {
    var loading = false
    var playing = false
    var error: String?
    private var process: Process?
    private var audio: AVAudioPlayer?
    private var requestID = UUID()
    private var cache: [String: URL] = [:]
    private var directories: [URL] = []
    private func cacheKey(_ settings: StudioSettings, _ text: String) -> String {
        // Session-only key; never logged or persisted.
        [settings.apiKey, settings.apiVersion, settings.models["tts_audio"] ?? "", settings.geminiVoice, settings.prompts["tts_audio"]?["user_prompt"] ?? "", text].joined(separator: "\u{0}")
    }
    func play(settings: StudioSettings, text: String) {
        stop(); error = nil
        let key = cacheKey(settings, text)
        if let file = cache[key] { playFile(file); return }
        guard !settings.apiKey.isEmpty else { error = "Enter your Gemini API key in Settings → Gemini API to preview this voice."; return }
        guard let engine = Bundle.main.resourceURL?.appendingPathComponent("Engine/vidistudio-engine") else {
            error = "A required part of VidiStudio is unavailable. Reinstall the application, then try again."
            return
        }
        let id = requestID
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-preview-\(UUID().uuidString)")
        let config = directory.appendingPathComponent("config.json"), file = directory.appendingPathComponent("sample.wav")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            directories.append(directory)
            try JSONEncoder().encode(settings).write(to: config, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
            let task = Process(), pipe = Pipe()
            task.executableURL = engine
            task.arguments = ["preview-tts", "--output", file.path, "--text", text]
            task.environment = ProcessInfo.processInfo.environment.merging(["VIDISTUDIO_CONFIG": config.path]) { _, new in new }
            task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
            try task.run(); process = task; loading = true
            Task {
                var failure: String?
                do {
                    for try await line in pipe.fileHandleForReading.bytes.lines {
                        if let data = line.data(using: .utf8), let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any], event["error"] as? Bool == true { failure = event["message"] as? String }
                    }
                } catch { failure = "Could not read the voice preview result." }
                try? FileManager.default.removeItem(at: config)
                guard requestID == id else { try? FileManager.default.removeItem(at: directory); return }
                loading = false; process = nil
                if let failure {
                    self.error = UserFacingIssue.forEngine(command: "preview-tts", technicalDetails: failure).message
                    UserFacingIssueReporter.record(failure, context: "Create Gemini voice sample")
                }
                else if FileManager.default.fileExists(atPath: file.path) { cache[key] = file; playFile(file) }
                else { self.error = "No voice sample was created. Check your Gemini and voice settings, then try again." }
            }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            self.error = UserFacingIssueReporter.message(
                for: error,
                issue: .voicePreview,
                context: "Start Gemini voice sample"
            )
        }
    }
    private func playFile(_ file: URL) {
        do {
            audio = try AVAudioPlayer(contentsOf: file)
            playing = audio?.play() == true
            if !playing { error = "The audio sample could not be played." }
        } catch { self.error = "The audio sample could not be opened." }
    }
    func updatePlayback() { playing = audio?.isPlaying == true }
    func stop() { requestID = UUID(); if process?.isRunning == true { process?.terminate() }; process = nil; loading = false; audio?.stop(); audio = nil; playing = false }
    func cleanUp() { stop(); cache.removeAll(); for directory in directories { try? FileManager.default.removeItem(at: directory) }; directories.removeAll() }
}

struct GeminiVoiceBrowser: View {
    @Bindable var studio: StudioModel
    @State private var preview = GeminiVoicePreview()
    @State private var sample = "Hello. This is a sample of audio description narration in VidiStudio."
    private let voices = ["Aoede", "Callirrhoe", "Charon", "Fenrir", "Kore", "Leda", "Orus", "Puck", "Zephyr"]
    private var isGemini38TTS: Bool {
        guard let model = studio.settings.models["tts_audio"] else { return false }
        return ["gemini-3.8-flash-tts", "gemini-3.8-flash-lite-tts"].contains(model)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Gemini voice", selection: $studio.settings.geminiVoice) {
                ForEach(voices, id: \.self) { Text($0).tag($0) }
                if !voices.contains(studio.settings.geminiVoice) { Text(studio.settings.geminiVoice).tag(studio.settings.geminiVoice) }
            }
            TextField("Sample text", text: $sample, axis: .vertical).lineLimit(2...4)
            HStack {
                Button(preview.loading ? "Generating Sample…" : "Play Voice Sample", systemImage: "play.circle") { preview.play(settings: studio.settings, text: sample) }
                    .disabled(preview.loading || sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sample.count > 500 || !studio.hasApiKey)
                    .help(!studio.hasApiKey ? "Enter your Gemini API key in Settings → Gemini API to preview this voice" : "Play sample of Gemini voice \(studio.settings.geminiVoice)")
                    .accessibilityLabel("Play sample of Gemini voice \(studio.settings.geminiVoice)")
                Button(preview.loading ? "Cancel Generation" : "Stop Sample", systemImage: "stop.circle") { preview.stop() }.disabled(!preview.loading && !preview.playing)
                if preview.loading { ProgressView().controlSize(.small).accessibilityLabel("Generating voice sample") }
            }
            if !studio.hasApiKey {
                HStack(spacing: 8) {
                    Image(systemName: "key.slash.fill")
                        .foregroundStyle(.orange)
                    Text("Enter your Gemini API key in Settings → Gemini API to preview Gemini voices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(isGemini38TTS
                 ? "Uses the current Gemini key, TTS model, and voice to read the sample text verbatim. Samples are cached for this settings session; changing the voice or sample creates a new preview. Gemini usage charges may apply."
                 : "Uses the current Gemini key, TTS model, voice and prompt. Samples are cached for this settings session; changing the voice or sample creates a new preview. Gemini usage charges may apply.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = preview.error { Text(error).foregroundStyle(.red).accessibilityLabel("Voice preview error: \(error)") }
        }
        .onChange(of: studio.settings.geminiVoice) { _, _ in preview.stop() }
        .onChange(of: sample) { _, _ in preview.stop() }
        .onReceive(Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()) { _ in preview.updatePlayback() }
        .onDisappear { preview.cleanUp() }
    }
}
