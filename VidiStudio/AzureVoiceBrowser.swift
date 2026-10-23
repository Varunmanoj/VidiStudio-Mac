import SwiftUI
import AVFoundation
import Combine

struct AzureVoiceOption: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String
    let languageName: String
    let gender: String

    func label(showingLanguage: Bool) -> String {
        var details: [String] = []
        if showingLanguage, !languageName.isEmpty { details.append(languageName) }
        if !gender.isEmpty { details.append(gender) }
        let title = "Microsoft \(name)"
        return details.isEmpty ? title : "\(title) — \(details.joined(separator: ", "))"
    }
}

/// Loads Azure Online Voices and plays samples through the engine. The Azure Speech key is
/// passed only in the process environment; the temporary config never contains it.
@MainActor @Observable final class AzureVoiceEngine {
    var voices: [AzureVoiceOption] = []
    var loadingVoices = false
    var loadingSample = false
    var playing = false
    var error: String?
    private var voiceProcess: Process?
    private var sampleProcess: Process?
    private var audio: AVAudioPlayer?
    private var voiceRequestID = UUID()
    private var sampleRequestID = UUID()
    private var directories: [URL] = []

    private func launch(_ arguments: [String], settings: StudioSettings) throws -> (Process, Pipe, URL) {
        guard let engine = Bundle.main.resourceURL?.appendingPathComponent("Engine/vidistudio-engine") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-azure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        directories.append(directory)
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

    private static func events(from pipe: Pipe) async -> (events: [[String: Any]], failure: String?) {
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

    func loadVoices(settings: StudioSettings) {
        voiceProcess?.terminate(); voiceProcess = nil
        let id = UUID(); voiceRequestID = id
        guard settings.hasAzureSpeechKey else { voices = []; loadingVoices = false; return }
        do {
            let (task, pipe, directory) = try launch(["list-azure-voices"], settings: settings)
            voiceProcess = task; loadingVoices = true; error = nil
            Task {
                let result = await Self.events(from: pipe)
                try? FileManager.default.removeItem(at: directory)
                guard voiceRequestID == id else { return }
                loadingVoices = false; voiceProcess = nil
                if let failure = result.failure {
                    error = failure
                    UserFacingIssueReporter.record(failure, context: "Load Azure Online Voices")
                    return
                }
                let items = result.events.compactMap { $0["voices"] as? [[String: Any]] }.last ?? []
                voices = items.compactMap { item in
                    guard let id = item["id"] as? String, !id.isEmpty else { return nil }
                    return AzureVoiceOption(id: id, name: item["name"] as? String ?? id, language: item["language"] as? String ?? "",
                                            languageName: item["languageName"] as? String ?? "", gender: item["gender"] as? String ?? "")
                }
            }
        } catch {
            loadingVoices = false
            self.error = "A required part of VidiStudio is unavailable. Reinstall the application, then try again."
        }
    }

    func play(settings: StudioSettings, text: String) {
        stop(); error = nil
        var sampleSettings = settings
        sampleSettings.ttsMode = "azure"
        let id = UUID(); sampleRequestID = id
        do {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-azure-sample-\(UUID().uuidString).wav")
            let (task, pipe, directory) = try launch(["preview-tts", "--output", file.path, "--text", text], settings: sampleSettings)
            sampleProcess = task; loadingSample = true
            Task {
                let result = await Self.events(from: pipe)
                try? FileManager.default.removeItem(at: directory.appendingPathComponent("config.json"))
                guard sampleRequestID == id else { try? FileManager.default.removeItem(at: file); return }
                loadingSample = false; sampleProcess = nil
                if let failure = result.failure {
                    error = failure
                    UserFacingIssueReporter.record(failure, context: "Create Azure voice sample")
                } else if FileManager.default.fileExists(atPath: file.path) {
                    do {
                        audio = try AVAudioPlayer(contentsOf: file)
                        playing = audio?.play() == true
                        if !playing { error = "The audio sample could not be played." }
                    } catch { self.error = "The audio sample could not be opened." }
                    try? FileManager.default.removeItem(at: file)
                } else {
                    error = "No voice sample was created. Check your Azure key, region and voice, then try again."
                }
            }
        } catch {
            self.error = "A required part of VidiStudio is unavailable. Reinstall the application, then try again."
        }
    }

    func updatePlayback() { playing = audio?.isPlaying == true }

    func stop() {
        sampleRequestID = UUID()
        if sampleProcess?.isRunning == true { sampleProcess?.terminate() }
        sampleProcess = nil; loadingSample = false
        audio?.stop(); audio = nil; playing = false
    }

    func cleanUp() {
        stop()
        voiceRequestID = UUID()
        if voiceProcess?.isRunning == true { voiceProcess?.terminate() }
        voiceProcess = nil; loadingVoices = false
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        directories.removeAll()
    }
}

/// Lets people add the optional Azure Speech key. Azure Online Voices appears in the speech
/// engine menu only once a key is saved.
struct AzureSpeechKeySettings: View {
    @Bindable var studio: StudioModel
    private let keyPage = URL(string: "https://portal.azure.com/#create/Microsoft.CognitiveServicesSpeechServices")!

    var body: some View {
        GroupBox("Azure online voices") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Add an Azure Speech key to use Microsoft's natural online voices, such as Ava, Andrew, Jenny and Ryan, in every language. Once a key is added, Azure Online Voices appears in the Speech engine menu.")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("Azure Speech key", text: $studio.settings.azureSpeechKey)
                    .textContentType(.password)
                    .accessibilityHint("Stored securely in your Keychain")
                TextField("Azure region", text: $studio.settings.azureSpeechRegion, prompt: Text("eastus"))
                    .accessibilityHint("The region of your Azure Speech resource, for example eastus or westeurope")
                HStack {
                    Link("Get an Azure Speech key", destination: keyPage)
                    if studio.settings.hasAzureSpeechKey {
                        Button("Remove Key", systemImage: "trash", role: .destructive) {
                            studio.settings.azureSpeechKey = ""
                        }
                        .accessibilityHint("Removes the Azure Speech key from your Keychain")
                    }
                }
                Text("Online voices need the internet. Narration text is sent to Microsoft Azure, and Azure may charge for use.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .onChange(of: studio.settings.hasAzureSpeechKey) { _, hasKey in
            if !hasKey && studio.settings.ttsMode == "azure" { studio.settings.ttsMode = "system" }
        }
    }
}

struct AzureVoiceBrowser: View {
    @Bindable var studio: StudioModel
    @State private var engine = AzureVoiceEngine()
    @State private var language = ""
    @State private var search = ""
    @State private var sample = "Hello. This is a sample of audio description narration in VidiStudio."

    private var languages: [String] {
        Array(Set(engine.voices.map(\.languageName).filter { !$0.isEmpty })).sorted()
    }

    private var filtered: [AzureVoiceOption] {
        engine.voices.filter { voice in
            (language.isEmpty || voice.languageName == language)
                && (search.isEmpty || voice.label(showingLanguage: true).localizedCaseInsensitiveContains(search) || voice.id.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Language", selection: $language) {
                    Text("All Languages").tag("")
                    ForEach(languages, id: \.self) { Text($0).tag($0) }
                }
                Button("Refresh Voices", systemImage: "arrow.clockwise") { engine.loadVoices(settings: studio.settings) }
                    .disabled(engine.loadingVoices)
                    .accessibilityHint("Reloads the online voices available with your Azure key")
            }
            TextField("Search voices", text: $search)
            Picker("Online voice", selection: $studio.settings.azureVoice) {
                ForEach(filtered) { Text($0.label(showingLanguage: language.isEmpty)).tag($0.id) }
                if !filtered.contains(where: { $0.id == studio.settings.azureVoice }) {
                    Text(NarrationVoiceFormatting.voiceDisplayName(studio.settings.resolvedAzureVoice)).tag(studio.settings.azureVoice)
                }
            }
            if engine.loadingVoices {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                    Text("Loading online voices…").font(.caption).foregroundStyle(.secondary)
                }
            }
            TextField("Sample text", text: $sample, axis: .vertical).lineLimit(2...4)
            HStack {
                Button(engine.loadingSample ? "Generating Sample…" : "Play Voice Sample", systemImage: "play.circle") {
                    engine.play(settings: studio.settings, text: sample)
                }
                .disabled(engine.loadingSample || sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sample.count > 500)
                .accessibilityLabel("Play sample of online voice \(NarrationVoiceFormatting.voiceDisplayName(studio.settings.resolvedAzureVoice))")
                Button(engine.loadingSample ? "Cancel Generation" : "Stop Sample", systemImage: "stop.circle") { engine.stop() }
                    .disabled(!engine.loadingSample && !engine.playing)
                if engine.loadingSample { ProgressView().controlSize(.small).accessibilityLabel("Generating voice sample") }
            }
            if let error = engine.error {
                Text(error).foregroundStyle(.red).accessibilityLabel("Online voice error: \(error)")
            }
        }
        .onAppear { engine.loadVoices(settings: studio.settings) }
        .onChange(of: studio.settings.azureVoice) { _, _ in engine.stop() }
        .onChange(of: sample) { _, _ in engine.stop() }
        .onReceive(Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()) { _ in engine.updatePlayback() }
        .onDisappear { engine.cleanUp() }
    }
}
