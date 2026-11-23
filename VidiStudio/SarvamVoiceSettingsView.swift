import SwiftUI
import AVFoundation
import AppKit

/// Shared picker/menu state keeps keyboard menu choices identical to the visible control.
struct SpeechChoice: View {
    let title: String
    let id: String
    @Binding var value: String
    let options: [(String, String)]
    var body: some View {
        Picker(title, selection: $value) {
            ForEach(options, id: \.0) { option in Text(option.1).tag(option.0) }
        }
        .accessibilityIdentifier(id)
        .contextMenu {
            ForEach(options, id: \.0) { option in
                Toggle(option.1, systemImage: "speaker.wave.2", isOn: Binding(get: { value == option.0 }, set: { if $0 { value = option.0 } }))
                    .accessibilityIdentifier(id + "-" + option.0)
            }
        }
    }
}

struct SpeechAdjustment: View {
    let title: String
    let id: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let initial: Double
    var step = 0.05
    var percentage = false
    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step).accessibilityLabel(title).accessibilityIdentifier(id)
                Text(percentage ? "\(Int((value * 100).rounded()))%" : value.formatted(.number.precision(.fractionLength(2)))).monospacedDigit().frame(width: 48).accessibilityIdentifier(id + "-value")
            }
        }
        .contextMenu {
            Button("Increase \(title)", systemImage: "plus") { value = min(range.upperBound, value + step) }.disabled(value >= range.upperBound).accessibilityIdentifier(id + "-increase")
            Button("Decrease \(title)", systemImage: "minus") { value = max(range.lowerBound, value - step) }.disabled(value <= range.lowerBound).accessibilityIdentifier(id + "-decrease")
            Button("Restore Default") { value = initial }.accessibilityIdentifier(id + "-reset")
        }
    }
}

@MainActor @Observable final class SarvamDemoPlayer: NSObject, AVAudioPlayerDelegate {
    var active = false
    var preparing = false
    var activeAddress: String?
    var error: String?
    private var player: AVAudioPlayer?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private let sampleOwner = UUID()

    func stop() { generation = UUID(); task?.cancel(); task = nil; player?.stop(); player = nil; active = false; activeAddress = nil; if !preparing { VoiceSampleSession.shared.end(sampleOwner) } }
    func play(_ voice: SarvamCatalog.Voice, language: String, key: String) {
        guard !active, !preparing, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard VoiceSampleSession.shared.begin(sampleOwner) else { return }
        error = nil; preparing = true; active = true; activeAddress = voice.model + "|" + voice.id + "|" + language
        let request = generation
        task = Task {
            defer { preparing = false; if !active { VoiceSampleSession.shared.end(sampleOwner) } }
            do {
                // Stop silences playback, while an already submitted audition finishes
                // caching so replay cannot accidentally submit the same charge again.
                let data = try await SarvamSettingsRequest.run("preview-sarvam-sample", key: key, timeout: 210,
                    arguments: ["--sarvam-model", voice.model, "--sarvam-voice", voice.id, "--sarvam-language", language])
                guard !Task.isCancelled, generation == request else { return }
                let events = data.split(separator: 10).compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
                guard let path = events.last?["sarvamSamplePath"] as? String else { throw CocoaError(.fileReadCorruptFile) }
                let audio = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)); audio.delegate = self
                player = audio; active = audio.play()
                if !active { error = "Sample could not be played." }
            } catch is CancellationError {
            } catch {
                guard generation == request else { return }
                active = false; self.error = error.localizedDescription
                ConnectivityService.shared.showVoiceFailure(.sarvam, fallback: "The sample could not be prepared. Check your internet connection and voice settings, then try again.")
            }
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in guard let self, self.player === player else { return }; self.stop() }
    }
}

struct SarvamVoiceSettingsView: View {
    @Bindable var studio: StudioModel
    @State private var sample = SarvamDemoPlayer()
    @State private var key = ""
    @State private var storageError: String?
    @State private var deletingKey = false
    @State private var keyCheckTask: Task<Void, Never>?
    @FocusState private var keyFocused: Bool
    @Environment(\.openURL) private var openURL
    private var model: String { studio.settings.sarvamSpeech.model }
    private var selected: SarvamVoicePreferences { studio.settings.sarvamSpeech.selected }
    private var voices: [SarvamCatalog.Voice] {
        SarvamCatalog.shared.voices.filter { $0.model == model && $0.languages.contains(selected.language) }
    }
    private var knownModel: Bool { SarvamCatalog.models.contains(model) }
    private var languageOptions: [(String, String)] {
        if !knownModel { return SarvamCatalog.shared.languages.map { ($0.key,$0.value) }.sorted { $0.1 < $1.1 } }
        let codes = Set(SarvamCatalog.shared.voices.filter { $0.model == model }.flatMap(\.languages))
        return codes.map { ($0, SarvamCatalog.shared.languages[$0] ?? $0) }.sorted { $0.1 < $1.1 }
    }
    private var sampleVoice: SarvamCatalog.Voice? { voices.first { $0.id == selected.voice } }
    private func preference<T>(_ path: WritableKeyPath<SarvamVoicePreferences, T>) -> Binding<T> {
        Binding(get: { selected[keyPath: path] }, set: { value in
            sample.stop()
            var profile = selected; profile[keyPath: path] = value
            studio.settings.sarvamSpeech.profiles[model] = profile
        })
    }
    private var modelOptions: [(String, String)] {
        var values = studio.sarvamModels.map { ($0.id,$0.label) }
        if !values.contains(where: { $0.0 == model }) { values.append((model,SarvamCatalog.modelLabel(model))) }
        return values
    }
    private func scheduleKeyCheck() {
        keyCheckTask?.cancel()
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        keyCheckTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(700))
                while studio.busy { try await Task.sleep(for: .milliseconds(200)) }
                guard !Task.isCancelled else { return }
                studio.checkSarvamApiKey()
            } catch { }
        }
    }
    private var keyStatusLabel: String {
        if key.isEmpty { return "No API key" }
        if studio.sarvamKeyChecking { return "Checking API key…" }
        if !studio.sarvamKeyMessage.isEmpty { return studio.sarvamKeyMessage }
        switch studio.settings.sarvamKeyStatus {
        case "verified": return "API key verified"
        case "invalid": return "API key rejected"
        case "unavailable": return "Key check unavailable. Try again."
        default: return "API key saved — not yet checked"
        }
    }
    private func playSample() { guard !sample.active, !sample.preparing, !VoiceSampleSession.shared.busy, studio.settings.hasSarvamApiKey, let voice = sampleVoice else { return }; sample.play(voice, language: selected.language, key: studio.settings.sarvamApiKey) }
    private func openKeys() { openURL(URL(string: "https://indus.sarvam.ai/key-management")!) }
    var body: some View {
        Section {
            HStack(spacing: 8) {
            SecureField("Sarvam API key", text: $key).focused($keyFocused)
                .accessibilityIdentifier("sarvam-api-key")
                .onChange(of: key) { _, value in
                    guard value != studio.settings.sarvamApiKey else { return }
                    if KeychainStore.sarvam.write(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        sample.stop(); studio.settings.sarvamKeyStatus = "unverified"; studio.settings.sarvamCredentialRevision += 1; studio.sarvamKeyMessage = ""; storageError = nil; scheduleKeyCheck()
                    } else { storageError = "Could not save the Sarvam API key to Keychain." }
                }
                .contextMenu {
                    Button("Edit Sarvam API Key") { keyFocused = true }.accessibilityIdentifier("sarvam-key-edit")
                    Button("Delete Sarvam API Key…", role: .destructive) { deletingKey = true }.disabled(key.isEmpty).accessibilityIdentifier("sarvam-key-delete")
                    Button("Open Sarvam API Keys") { openKeys() }.accessibilityIdentifier("sarvam-key-dashboard")
                }
                Image(systemName: studio.sarvamKeyChecking ? "clock" : studio.settings.sarvamKeyStatus == "verified" ? "checkmark.circle.fill" : studio.settings.sarvamKeyStatus == "invalid" ? "xmark.circle.fill" : studio.settings.sarvamKeyStatus == "unavailable" ? "exclamationmark.triangle.fill" : "key")
                    .foregroundStyle(studio.settings.sarvamKeyStatus == "verified" && !studio.sarvamKeyChecking ? Color.green : studio.settings.sarvamKeyStatus == "invalid" ? Color.red : Color.secondary)
                    .help(keyStatusLabel).accessibilityLabel(keyStatusLabel)
                    .accessibilityIdentifier("sarvam-key-status")
                Button(role: .destructive) { deletingKey = true } label: { Image(systemName: "trash").foregroundStyle(.red) }
                    .buttonStyle(.borderless).disabled(key.isEmpty || studio.sarvamKeyChecking)
                    .help("Delete Sarvam API key").accessibilityLabel("Delete Sarvam API key")
                    .accessibilityIdentifier("sarvam-key-delete-icon")
                    .contextMenu { Button("Delete Sarvam API Key…", role: .destructive) { deletingKey = true }.disabled(key.isEmpty || studio.sarvamKeyChecking).accessibilityIdentifier("sarvam-key-delete") }
            }
            HStack {
                Button(studio.sarvamKeyChecking ? "Checking API Key…" : "Check API Key", systemImage: "checkmark.shield") { keyCheckTask?.cancel(); studio.checkSarvamApiKey() }
                    .disabled(key.isEmpty || studio.busy || studio.sarvamKeyChecking)
                    .contextMenu { Button("Check API Key") { keyCheckTask?.cancel(); studio.checkSarvamApiKey() }.disabled(key.isEmpty || studio.busy || studio.sarvamKeyChecking).accessibilityIdentifier("sarvam-key-check") }
                Button("Open Sarvam API Keys", systemImage: "arrow.up.right.square") { openKeys() }
                    .contextMenu { Button("Open Sarvam API Keys") { openKeys() }.accessibilityIdentifier("sarvam-key-dashboard") }
            }
            if let storageError { Text(storageError).foregroundStyle(.red) }
            SpeechChoice(title: "Model", id: "sarvam-model", value: $studio.settings.sarvamSpeech.model,
                         options: modelOptions)
            Button(studio.sarvamModelsRefreshing ? "Refreshing Models…" : "Refresh Models", systemImage: "arrow.clockwise") { studio.refreshSarvamModels() }
                .disabled(studio.busy || studio.sarvamModelsRefreshing)
                .contextMenu { Button("Refresh Models") { studio.refreshSarvamModels() }.disabled(studio.busy || studio.sarvamModelsRefreshing).accessibilityIdentifier("sarvam-models-refresh") }
            if !studio.sarvamModelStatus.isEmpty { Text(studio.sarvamModelStatus).foregroundStyle(.secondary) }
            SpeechChoice(title: "Narration language", id: "sarvam-language", value: preference(\.language), options: languageOptions)
            if knownModel {
                SarvamVoiceBrowser(model: model, narrationLanguage: selected.language, selectedVoice: selected.voice, sample: sample, apiKey: studio.settings.sarvamApiKey) { voice in
                    var profile = selected; profile.voice = voice.id
                    if !voice.languages.contains(profile.language), let language = voice.languages.first { profile.language = language }
                    sample.stop(); studio.settings.sarvamSpeech.profiles[model] = profile
                }
            } else { Text("Default voice") }
            if knownModel {
            SpeechAdjustment(title: "Speaking speed", id: "sarvam-pace", value: preference(\.pace), range: model == "bulbul:v2" ? 0.3...3 : 0.5...2, initial: 1)
            if model == "bulbul:v2" {
                SpeechAdjustment(title: "Pitch", id: "sarvam-pitch", value: preference(\.pitch), range: -0.75...0.75, initial: 0)
                SpeechAdjustment(title: "Loudness", id: "sarvam-loudness", value: preference(\.loudness), range: 0.3...3, initial: 1)
                Toggle("Normalize text", isOn: preference(\.preprocessing))
                    .contextMenu { Toggle("Normalize text", isOn: preference(\.preprocessing)).accessibilityIdentifier("sarvam-preprocessing") }
            } else {
                SpeechAdjustment(title: "Expressiveness", id: "sarvam-temperature", value: preference(\.temperature), range: 0.01...1, initial: 0.6, step: 0.01)
            }
            SpeechChoice(title: "Sample rate", id: "sarvam-sample-rate", value: Binding(get: { String(selected.sampleRate) }, set: { preference(\.sampleRate).wrappedValue = Int($0) ?? 22050 }),
                         options: (model == "bulbul:v2" ? [8000,16000,22050,24000] : [8000,16000,22050,24000,32000,44100,48000]).map { (String($0), "\($0) Hz") })
            SpeechChoice(title: "Audio format", id: "sarvam-codec", value: preference(\.codec), options: ["wav","mp3","aac","flac"].map { ($0, $0.uppercased()) })
            }
            HStack {
                Button(sample.active ? "Stop Sample" : "Play Sample", systemImage: sample.active ? "stop.circle" : "play.circle") { if sample.active { sample.stop() } else { playSample() } }
                    .disabled(!sample.active && (sampleVoice == nil || !studio.settings.hasSarvamApiKey || sample.preparing || VoiceSampleSession.shared.busy)).accessibilityIdentifier("sarvam-sample")
                    .contextMenu {
                        Button("Play Sample") { playSample() }.disabled(sampleVoice == nil || sample.active || sample.preparing || VoiceSampleSession.shared.busy || !studio.settings.hasSarvamApiKey).accessibilityIdentifier("sarvam-sample-play")
                        Button("Stop Sample") { sample.stop() }.disabled(!sample.active).accessibilityIdentifier("sarvam-sample-stop")
                    }
                if sample.preparing { ProgressView().controlSize(.small).accessibilityLabel("Preparing Sarvam sample") }
            }
            if let error = sample.error { Text(error).foregroundStyle(.red) }
        } header: { Text("Sarvam Voices").accessibilityHeading(.h2) }
        .onAppear { key = studio.settings.sarvamApiKey; studio.refreshSarvamModels(); if studio.settings.sarvamKeyStatus != "verified" { scheduleKeyCheck() } }
        .onDisappear { keyCheckTask?.cancel(); sample.stop() }
        .onChange(of: model) { _, _ in sample.stop() }
        .onChange(of: studio.settings.sarvamKeyStatus) { _, _ in
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: keyStatusLabel, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        .onChange(of: selected.language) { _, _ in
            if !voices.contains(where: { $0.id == selected.voice }), let first = voices.first { preference(\.voice).wrappedValue = first.id }
        }
        .alert("Delete Sarvam API Key?", isPresented: $deletingKey) {
            Button("Delete API Key", role: .destructive) {
                if KeychainStore.sarvam.write("") { sample.stop(); keyCheckTask?.cancel(); studio.sarvamKeyMessage = ""; key = ""; sample.stop(); studio.settings.sarvamKeyStatus = "unverified"; studio.settings.sarvamCredentialRevision += 1; storageError = nil }
                else { storageError = "Could not delete the Sarvam API key from Keychain." }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct SummaryVoiceSettingsView: View {
    @Binding var settings: StudioSettings
    @State private var showingPiperCatalog = false
    private var local: LocalSummarySpeech { settings.summarySpeech ?? settings.initialSummarySpeech }
    private func field<T>(_ path: WritableKeyPath<LocalSummarySpeech, T>) -> Binding<T> {
        Binding(get: { local[keyPath: path] }, set: { value in var profile = local; profile[keyPath: path] = value; settings.summarySpeech = profile })
    }
    private func restoreSummaryControls() {
        var profile = local; profile.rate = 1; profile.pitch = 1; profile.volume = 1; settings.summarySpeech = profile
    }
    private var voiceSettings: Binding<StudioSettings> {
        Binding(get: { settings.resolvedSummarySettings }, set: { value in
            var profile = local; profile.systemVoice = value.systemVoice; profile.piperVoice = value.piperVoice
            settings.summarySpeech = profile
        })
    }
    private var voiceOptions: [(String, String)] {
        if local.engine == "piper" { return PiperVoiceManager.shared.downloadedVoices.map { ($0.id, $0.displayName) } }
        return [("", "System default")] + AVSpeechSynthesisVoice.speechVoices().map { ($0.identifier, "\($0.name) — \($0.language)") }
    }
    var body: some View {
        Section {
            SpeechChoice(title: "Summary engine", id: "summary-engine", value: field(\.engine), options: [("system", "Apple Voices"), ("piper", "Piper Voices")])
            SpeechAdjustment(title: "Speech rate", id: "summary-rate", value: field(\.rate), range: 0.5...2, initial: 1, percentage: true)
            SpeechAdjustment(title: "Pitch", id: "summary-pitch", value: field(\.pitch), range: 0.5...2, initial: 1, percentage: true)
            SpeechAdjustment(title: "Speech volume", id: "summary-volume", value: field(\.volume), range: 0...1, initial: 1, percentage: true)
            Button("Restore Defaults", systemImage: "arrow.counterclockwise") { restoreSummaryControls() }
                .contextMenu { Button("Restore Defaults") { restoreSummaryControls() }.accessibilityIdentifier("summary-controls-reset") }
            Group {
                if local.engine == "piper" { PiperVoiceSettingsView(settings: voiceSettings) }
                else { SystemVoiceBrowser(settings: voiceSettings, menuPrefix: "summary") }
            }
            .contextMenu {
                Menu("Summary voice") {
                    ForEach(voiceOptions, id: \.0) { option in
                        Toggle(option.1, systemImage: "speaker.wave.2", isOn: Binding(get: { (local.engine == "piper" ? local.piperVoice : local.systemVoice) == option.0 }, set: { if $0 { field(local.engine == "piper" ? \.piperVoice : \.systemVoice).wrappedValue = option.0 } }))
                    }
                }
                .accessibilityIdentifier("summary-voice")
                if local.engine == "piper" { Button("Download or Remove Voices…") { showingPiperCatalog = true }.accessibilityIdentifier("summary-manage-voices") }
            }
        } header: { Text("Summary voice").accessibilityHeading(.h2) }
        .sheet(isPresented: $showingPiperCatalog) { PiperVoiceBrowser(settings: voiceSettings) }
        .onAppear { if settings.summarySpeech == nil { settings.summarySpeech = settings.initialSummarySpeech } }
    }
}
