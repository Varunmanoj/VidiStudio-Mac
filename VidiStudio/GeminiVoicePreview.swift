import SwiftUI
import AVFoundation
import Combine

struct GeminiNarrationVoice: Equatable, Identifiable, Decodable, Sendable {
    let id: String
    let name: String
    var language = ""
    var description = ""

    static let prebuilt: [Self] = {
        struct Defaults: Decodable { let geminiPrebuiltVoices: [String: String] }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Engine/_internal/ai-defaults.json"),
              let data = try? Data(contentsOf: url),
              let defaults = try? JSONDecoder().decode(Defaults.self, from: data) else {
            return [Self(id: "Kore", name: "Kore")]
        }
        return defaults.geminiPrebuiltVoices.map { Self(id: $0.key, name: $0.key, description: $0.value) }
    }()

    var languageLabel: String {
        if language.isEmpty { return Self.prebuilt.contains { $0.id == id } ? "Multilingual" : "Library voice" }
        return Locale.current.localizedString(forIdentifier: language) ?? language
    }
    var searchableText: String { [name, languageLabel, language, description].joined(separator: " ") }
}

extension StudioSettings {
    var geminiNarrationVoice: GeminiNarrationVoice {
        get {
            let legacy = geminiVoice.trimmingCharacters(in: .whitespacesAndNewlines)
            let developer = legacy.isEmpty ? "Kore" : legacy
            if aiProvider == "vertex" {
                let fallback = GeminiNarrationVoice.prebuilt.contains { $0.id == developer } ? developer : "Kore"
                let id = vertexGeminiVoice ?? fallback
                return GeminiNarrationVoice(id: id, name: vertexGeminiVoiceName ?? id)
            }
            return GeminiNarrationVoice(id: developer, name: geminiVoiceName ?? developer)
        }
        set {
            let name = GeminiNarrationVoice.prebuilt.contains { $0.id == newValue.id } ? nil : newValue.name
            if aiProvider == "vertex" {
                vertexGeminiVoice = newValue.id
                vertexGeminiVoiceName = name
            } else {
                if vertexGeminiVoice == nil {
                    let previous = geminiNarrationVoice.id
                    vertexGeminiVoice = GeminiNarrationVoice.prebuilt.contains { $0.id == previous } ? previous : "Kore"
                }
                geminiVoice = newValue.id
                geminiVoiceName = name
            }
        }
    }
}

private struct GeminiNarrationCatalog: View {
    @Bindable var studio: StudioModel
    let sampleText: String
    @FocusState private var searchFocused: Bool
    @State private var search = ""
    @State private var language = ""
    @State private var style = ""
    @State private var sort = "language"
    @State private var extraVoices: [GeminiNarrationVoice] = []
    @State private var searched = ""
    @State private var status = ""
    @State private var lookup: Task<Void, Never>?
    @State private var preview = GeminiVoicePreview()
    @State private var sampleID: String?

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSearchLibrary: Bool { !query.isEmpty && lookup == nil && studio.canUseSelectedGeminiNarration }
    private var results: [GeminiNarrationVoice] {
        let selected = studio.settings.geminiNarrationVoice
        let found = GeminiNarrationVoice.prebuilt + extraVoices
        return found.contains(where: { $0.id == selected.id }) ? found : found + [selected]
    }
    private var languageOptions: [(String, String)] {
        let languages = Dictionary(grouping: results, by: \.language)
        return [("", "All languages")] + languages.compactMap { code, voices in
            voices.first.map { (code.isEmpty ? "multilingual" : code, $0.languageLabel) }
        }.sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }
    private var styleOptions: [(String, String)] {
        [("", "All styles")] + Set(GeminiNarrationVoice.prebuilt.map(\.description).filter { !$0.isEmpty })
            .sorted().map { ($0, $0) }
    }
    private var visibleVoices: [GeminiNarrationVoice] {
        results.filter { voice in
            let eligible = language.isEmpty || language == (voice.language.isEmpty ? "multilingual" : voice.language)
            return eligible && (style.isEmpty || voice.description == style) && (query.isEmpty || voice.searchableText.localizedCaseInsensitiveContains(query)
                || (query == searched && extraVoices.contains(where: { $0.id == voice.id })))
        }.sorted { left, right in
            if sort == "language", left.languageLabel != right.languageLabel {
                return left.languageLabel.localizedStandardCompare(right.languageLabel) == .orderedAscending
            }
            return left.name.localizedStandardCompare(right.name) == (sort == "descending" ? .orderedDescending : .orderedAscending)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SpeechChoice(title: "Language and region", id: "gemini-voice-language", value: $language, options: languageOptions)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search voices", text: $search, prompt: Text("Search by voice, style or language"))
                    .focused($searchFocused).onSubmit { searchLibrary() }
                    .contextMenu {
                        Button("Search voices", systemImage: "magnifyingglass") { searchFocused = true }
                        Button("Clear voice search", systemImage: "xmark.circle") { search = "" }.disabled(search.isEmpty)
                    }
                if !search.isEmpty {
                    Button("Clear voice search", systemImage: "xmark.circle.fill") { search = "" }
                        .buttonStyle(.plain).labelStyle(.iconOnly)
                        .contextMenu { Button("Clear voice search", systemImage: "xmark.circle") { search = "" } }
                }
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            SpeechChoice(title: "Style", id: "gemini-voice-style", value: $style, options: styleOptions)
            SpeechChoice(title: "Sort by", id: "gemini-voice-sort", value: $sort, options: [
                ("name", "Voice name (A–Z)"), ("descending", "Voice name (Z–A)"), ("language", "Language (A–Z)")
            ])
            HStack {
                Button("Search Voice Library", systemImage: "magnifyingglass") { searchLibrary() }
                    .disabled(!canSearchLibrary)
                    .contextMenu {
                        Button("Search Voice Library", systemImage: "magnifyingglass") { searchLibrary() }.disabled(!canSearchLibrary)
                    }
                if lookup != nil { ProgressView().controlSize(.small).accessibilityLabel("Searching voice library") }
                if !status.isEmpty { Text(status).font(.caption) }
            }
            Text("Selected: " + studio.settings.geminiNarrationVoice.name).font(.callout)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if visibleVoices.isEmpty { Text("No matching voices").foregroundStyle(.secondary) }
                    if sort == "language" {
                        let groups = Dictionary(grouping: visibleVoices, by: \.languageLabel)
                        ForEach(groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { label in
                            Text(label).font(.headline).accessibilityAddTraits(.isHeader)
                            voiceRows(groups[label] ?? [])
                        }
                    } else {
                        voiceRows(visibleVoices)
                    }
                }.padding(4)
            }.frame(minHeight: 180, idealHeight: 280, maxHeight: 320)
            .accessibilityIdentifier("gemini-voice-results")
            if let error = preview.error { Text(error).foregroundStyle(.red) }
            Button("Reset Voice Filters", systemImage: "arrow.counterclockwise") { resetFilters() }
                .contextMenu { Button("Reset Voice Filters", systemImage: "arrow.counterclockwise") { resetFilters() } }
        }
        .onChange(of: sampleText) { _, _ in preview.stop() }
        .onReceive(Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()) { _ in preview.updatePlayback() }
        .onDisappear { lookup?.cancel(); preview.cleanUp() }
    }

    private func voiceRows(_ voices: [GeminiNarrationVoice]) -> some View {
        ForEach(voices) { voice in
            voiceRow(voice)
            Divider()
        }
    }

    private func voiceRow(_ voice: GeminiNarrationVoice) -> some View {
        let selected = voice.id == studio.settings.geminiNarrationVoice.id
        let styleLabel = GeminiNarrationVoice.prebuilt.contains { $0.id == voice.id } ? voice.description : ""
        let details = [voice.languageLabel, styleLabel].filter { !$0.isEmpty }.joined(separator: ", ")
        let active = voice.id == sampleID && (preview.loading || preview.playing)
        let canPlay = !VoiceSampleSession.shared.busy && studio.canUseSelectedGeminiNarration
            && !sampleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sampleText.count <= 500
        return HStack {
            Button {
                studio.settings.geminiNarrationVoice = voice
            } label: {
                HStack {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    VStack(alignment: .leading) {
                        Text(voice.name)
                        Text(details).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select \(voice.name), \(details)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            Spacer()
            if active && preview.loading { ProgressView().controlSize(.small).accessibilityLabel("Preparing sample of " + voice.name) }
            Button(active ? "Stop Sample" : "Play Sample", systemImage: active ? "stop.circle" : "play.circle") {
                if active { preview.stop() } else if canPlay { play(voice) }
            }
            .labelStyle(.iconOnly).disabled(!active && !canPlay)
            .accessibilityLabel((active ? "Stop sample of " : "Play sample of ") + voice.name)
        }
        .contextMenu {
            Toggle(isOn: Binding(get: { selected }, set: { if $0 { studio.settings.geminiNarrationVoice = voice } })) {
                Label("Select " + voice.name, systemImage: "person.wave.2")
            }
            Button("Play Sample", systemImage: "play.circle") { if canPlay { play(voice) } }.disabled(!canPlay)
            Button("Stop Sample", systemImage: "stop.circle") { preview.stop() }.disabled(!active)
        }
    }

    private func play(_ voice: GeminiNarrationVoice) {
        var settings = studio.settings
        settings.geminiNarrationVoice = voice
        sampleID = voice.id
        preview.play(settings: settings, text: sampleText)
    }

    private func resetFilters() {
        lookup?.cancel()
        lookup = nil
        search = ""
        language = ""
        style = ""
        sort = "language"
        extraVoices = []
        searched = ""
        status = ""
    }

    private func searchLibrary() {
        guard canSearchLibrary else { return }
        let query = query
        let settings = studio.settings
        status = ""
        lookup = Task {
            defer { if !Task.isCancelled { lookup = nil } }
            do {
                let response = try await GeminiVoiceLibrary.search(query, settings: settings)
                guard !Task.isCancelled else { return }
                extraVoices = response.voices
                searched = query
                if !languageOptions.contains(where: { $0.0 == language }) { language = "" }
                status = response.hasMore ? "More matches available. Refine your search." : "\(response.voices.count) library matches"
            } catch {
                if !Task.isCancelled { status = "Could not search the voice library." }
            }
        }
    }
}

private enum GeminiVoiceLibrary {
    struct Response: Decodable, Sendable {
        let voices: [GeminiNarrationVoice]
        let hasMore: Bool
    }

    static func search(_ query: String, settings: StudioSettings) async throws -> Response {
        guard let engine = Bundle.main.resourceURL?.appendingPathComponent("Engine/vidistudio-engine") else {
            throw CocoaError(.fileNoSuchFile)
        }
        var config = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any] ?? [:]
        config.removeValue(forKey: "apiKey")
        config.removeValue(forKey: "sarvamApiKey")
        let data = try JSONSerialization.data(withJSONObject: config)
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await Task.detached {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-voice-library-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent("config.json")
            try data.write(to: file, options: .atomic)
            let task = Process(), output = Pipe()
            task.executableURL = engine
            task.arguments = ["list-voices", "--voice-search=" + query]
            task.environment = ProcessInfo.processInfo.environment.merging([
                "VIDISTUDIO_CONFIG": file.path, "VIDISTUDIO_API_KEY": apiKey
            ]) { _, value in value }
            task.standardOutput = output
            task.standardError = FileHandle.nullDevice
            try task.run()
            let bytes = output.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            for line in bytes.split(separator: 10) {
                if let catalog = try? JSONDecoder().decode(Response.self, from: Data(line)) { return catalog }
            }
            throw CocoaError(.fileReadCorruptFile)
        }.value
    }
}

@MainActor @Observable final class GeminiVoicePreview {
    var loading = false
    var playing = false
    var error: String?
    private let sampleOwner = UUID()
    private var process: Process?
    private var audio: AVAudioPlayer?
    private var requestID = UUID()
    private var cache: [String: URL] = [:]
    private var directories: [URL] = []
    private func cacheKey(_ settings: StudioSettings, _ text: String) -> String {
        // Session-only key; never logged or persisted.
        [settings.aiProvider, settings.vertexAuth, settings.vertexProject, settings.vertexModels["tts_audio"] ?? "", settings.apiVersion, settings.models["tts_audio"] ?? "", settings.geminiNarrationVoice.id, settings.prompts["tts_audio"]?["user_prompt"] ?? "", text].joined(separator: "\u{0}")
    }
    func hasCached(settings: StudioSettings, text: String) -> Bool { cache[cacheKey(settings, text)].map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    func play(settings: StudioSettings, text: String) {
        guard !loading, !playing, !VoiceSampleSession.shared.busy else { return }
        error = nil
        let key = cacheKey(settings, text)
        if let file = cache[key] { guard VoiceSampleSession.shared.begin(sampleOwner) else { return }; playFile(file); return }
        guard ConnectivityService.shared.available(.gemini) else { error = ConnectivityService.shared.reason(.gemini); return }
        guard settings.hasApiKey else { error = "Connect an AI provider in Settings > AI to preview this voice."; return }
        if settings.aiProvider == "vertex", settings.vertexAuth == "express" { error = "Use Google sign-in in Settings → AI for Gemini narration."; return }
        guard let engine = Bundle.main.resourceURL?.appendingPathComponent("Engine/vidistudio-engine") else {
            error = "A required part of VidiStudio is unavailable. Reinstall the application, then try again."
            return
        }
        guard VoiceSampleSession.shared.begin(sampleOwner) else { return }
        loading = true
        let id = requestID
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-preview-\(UUID().uuidString)")
        let config = directory.appendingPathComponent("config.json"), file = directory.appendingPathComponent("sample.wav")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            directories.append(directory)
            var previewDict = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(settings))) as? [String: Any] ?? [:]
            let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            previewDict.removeValue(forKey: "apiKey"); previewDict.removeValue(forKey: "sarvamApiKey")
            let configData = try JSONSerialization.data(withJSONObject: previewDict)
            try configData.write(to: config, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
            let task = Process(), pipe = Pipe()
            task.executableURL = engine
            task.arguments = ["preview-tts", "--output", file.path, "--text", text]
            var environment = ProcessInfo.processInfo.environment.merging(["VIDISTUDIO_CONFIG": config.path, "VIDISTUDIO_NETWORK_EVENTS": "1"]) { _, new in new }
            if !apiKey.isEmpty { environment["VIDISTUDIO_API_KEY"] = apiKey }
            task.environment = environment
            task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
            try task.run(); process = task; loading = true
            let connectionWatch = ConnectionRecoveryWatch { if task.isRunning { task.terminate() } }
            Task {
                defer { connectionWatch.stop() }
                var failure: String?
                do {
                    for try await line in pipe.fileHandleForReading.bytes.lines {
                        if let data = line.data(using: .utf8), let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            connectionWatch.consume(event)
                            if event["error"] as? Bool == true { failure = event["message"] as? String }
                        }
                    }
                } catch { failure = "Could not read the voice preview result." }
                try? FileManager.default.removeItem(at: config)
                guard requestID == id else { try? FileManager.default.removeItem(at: directory); return }
                loading = false; process = nil
                if connectionWatch.interrupted { failure = "Connection interrupted. Connect to the internet and try again." }
                if let failure {
                    self.error = UserFacingIssue.forEngine(command: "preview-tts", technicalDetails: failure).message
                    UserFacingIssueReporter.record(failure, context: "Create Gemini voice sample")
                }
                else if FileManager.default.fileExists(atPath: file.path) { cache[key] = file; playFile(file) }
                else { self.error = "No voice sample was created. Check your Gemini and voice settings, then try again." }
                if !playing { VoiceSampleSession.shared.end(sampleOwner) }
            }
        } catch {
            loading = false; VoiceSampleSession.shared.end(sampleOwner)
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
        if !playing { VoiceSampleSession.shared.end(sampleOwner) }
    }

    func updatePlayback() { playing = audio?.isPlaying == true; if !loading && !playing { VoiceSampleSession.shared.end(sampleOwner) } }
    func stop() { requestID = UUID(); if process?.isRunning == true { process?.terminate() }; process = nil; loading = false; audio?.stop(); audio = nil; playing = false; VoiceSampleSession.shared.end(sampleOwner) }
    func cleanUp() { stop(); cache.removeAll(); for directory in directories { try? FileManager.default.removeItem(at: directory) }; directories.removeAll() }
}

struct GeminiVoiceBrowser: View {
    @Bindable var studio: StudioModel
    @State private var preview = GeminiVoicePreview()
    @State private var sample = "Hello. This is a sample of audio description narration in VidiStudio."
    private var sampleCached: Bool { preview.hasCached(settings: studio.settings, text: sample) }
    private var canPlaySample: Bool {
        !VoiceSampleSession.shared.busy && !sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && sample.count <= 500 && (sampleCached || studio.canUseGeminiNarration)
    }
    private func playSample() {
        guard canPlaySample, sampleCached || studio.authorizeAIConnection(for: "preview-tts", project: nil) else { return }
        preview.play(settings: studio.settings, text: sample)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voices").font(.headline).accessibilityAddTraits(.isHeader).accessibilityHeading(.h2)
            LabeledContent("AI connection", value: studio.activeAIConnection.title)
            if studio.activeAIConnection == .express {
                Text("Gemini narration requires a different AI connection.").font(.caption).foregroundStyle(.secondary)
            }
            if studio.activeAIConnection != .express {
                GeminiNarrationCatalog(studio: studio, sampleText: sample)
                    .id(studio.activeAIConnection)
            }
            TextField("Sample text", text: $sample, axis: .vertical).lineLimit(2...4)
            HStack {
                Button(preview.loading || preview.playing ? "Stop Sample" : "Play Sample", systemImage: preview.loading || preview.playing ? "stop.circle" : "play.circle") {
                    if preview.loading || preview.playing { preview.stop() } else { playSample() }
                }
                    .disabled(!preview.loading && !preview.playing && !canPlaySample)
                    .contextMenu {
                        Button("Play Sample") { playSample() }.disabled(!canPlaySample)
                        Button("Stop Sample") { preview.stop() }.disabled(!preview.loading && !preview.playing)
                    }
                    .help("Play sample of Gemini voice \(studio.settings.geminiNarrationVoice.name)")
                    .requiresInternet(preview.loading || preview.playing || preview.hasCached(settings: studio.settings, text: sample) ? nil : .gemini)
                    .accessibilityLabel((preview.loading || preview.playing ? "Stop sample of " : "Play sample of ") + "Gemini voice " + studio.settings.geminiNarrationVoice.name)
                if preview.loading { ProgressView().controlSize(.small).accessibilityLabel("Generating voice sample") }
            }
            if let error = preview.error { Text(error).foregroundStyle(.red).accessibilityLabel("Voice preview error: \(error)") }
        }
        .onChange(of: studio.settings.geminiNarrationVoice) { _, _ in preview.stop() }
        .onChange(of: studio.activeAIConnection) { _, _ in preview.stop() }
        .onChange(of: sample) { _, _ in preview.stop() }
        .onReceive(Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()) { _ in preview.updatePlayback() }
        .onChange(of: preview.error) { _, error in
            if let error { ConnectivityService.shared.showVoiceFailure(.gemini, fallback: error) }
        }
        .onDisappear { preview.cleanUp() }
    }

}
