import SwiftUI
import AppKit
import AVFoundation

struct SystemVoice: Identifiable, Sendable {
    var name: String
    var language: String
    var sample: String
    var id: String { name + language }
    var languageName: String { Locale.current.localizedString(forIdentifier: language) ?? language }
}
@MainActor @Observable final class SystemVoiceCatalog {
    var voices: [SystemVoice] = []
    var error: String?
    @ObservationIgnored private let sampleSynthesizer = AVSpeechSynthesizer()
    func refresh() async {
        let result = await Task.detached { () -> [SystemVoice] in
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            process.arguments = ["-v", "?"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let pattern = #"^(.+?)\s+([a-z]{2,3}_[A-Za-z_]+)\s+#\s*(.*)$"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            var seen = Set<String>()
            return String(decoding: data, as: UTF8.self).components(separatedBy: .newlines).compactMap { line in
                let ns = line as NSString
                guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
                let voice = SystemVoice(name: ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces), language: ns.substring(with: match.range(at: 2)), sample: ns.substring(with: match.range(at: 3)))
                return seen.insert(voice.id).inserted ? voice : nil
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }.value
        voices = result
        error = result.isEmpty ? "No system voices were available. Install a voice in macOS Accessibility settings, then refresh." : nil
    }
    func preview(_ voice: SystemVoice, settings: StudioSettings) {
        stop()
        sampleSynthesizer.speak(SystemSpeechUtterance.make(text: voice.sample, settings: settings, voiceName: voice.name))
    }
    func stop() { sampleSynthesizer.stopSpeaking(at: .immediate) }
}

enum SystemSpeechUtterance {
    static func make(text: String, settings: StudioSettings, voiceName: String? = nil) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        let scaledRate = AVSpeechUtteranceDefaultSpeechRate * Float(settings.systemSpeechRate)
        utterance.rate = min(max(scaledRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        utterance.pitchMultiplier = Float(min(max(settings.systemSpeechPitch, 0.5), 2.0))
        utterance.volume = Float(min(max(settings.systemSpeechVolume, 0), 1.0))
        let requested = (voiceName ?? settings.systemVoice).trimmingCharacters(in: .whitespacesAndNewlines)
        if !requested.isEmpty {
            let baseName = requested.replacingOccurrences(of: " (Enhanced)", with: "")
            utterance.voice = AVSpeechSynthesisVoice.speechVoices().first {
                $0.identifier == requested || $0.name == requested || $0.name == baseName
            }
        }
        return utterance
    }
}

struct SystemVoiceBrowser: View {
    @Binding var settings: StudioSettings
    @State private var catalog = SystemVoiceCatalog()
    @State private var language = "all"
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Language and region", selection: $language) {
                Text("All languages").tag("all")
                ForEach(Array(Set(catalog.voices.map(\.language))).sorted(), id: \.self) { code in
                    Text(Locale.current.localizedString(forIdentifier: code) ?? code).tag(code)
                }
            }
            voiceSearchField
            HStack {
                Button("Use system default voice") { settings.systemVoice = "" }
                Button("Play Selected Voice", systemImage: "play.circle") {
                    catalog.preview(catalog.voices.first { $0.name == settings.systemVoice } ?? SystemVoice(name: settings.systemVoice, language: "", sample: "This is a sample of audio description narration in VidiStudio."), settings: settings)
                }
            }
            Text("Selected: \(settings.systemVoice.isEmpty ? "System default" : settings.systemVoice)").font(.callout)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(catalog.voices.filter { (language == "all" || $0.language == language) && (search.isEmpty || $0.name.localizedStandardContains(search) || $0.languageName.localizedStandardContains(search)) }) { voice in
                        HStack {
                            Button { settings.systemVoice = voice.name } label: {
                                HStack { Image(systemName: settings.systemVoice == voice.name ? "checkmark.circle.fill" : "circle"); VStack(alignment: .leading) { Text(voice.name); Text(voice.languageName).font(.caption).foregroundStyle(.secondary) } }
                            }.buttonStyle(.plain).accessibilityLabel("Select \(voice.name), \(voice.languageName)").accessibilityAddTraits(settings.systemVoice == voice.name ? .isSelected : [])
                            Spacer()
                            Button("Speak Sample", systemImage: "play.circle") { catalog.preview(voice, settings: settings) }.labelStyle(.iconOnly).accessibilityLabel("Speak sample of \(voice.name), \(voice.languageName)")
                        }
                        Divider()
                    }
                }.padding(4)
            }.frame(minHeight: 200, idealHeight: 280, maxHeight: 320)
            HStack {
                Button("Refresh Voices") { Task { await catalog.refresh() } }
                Button("Stop Sample") { catalog.stop() }
                Button("Open macOS Voice Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess")!)
                }
            }
            Text("Lists voices available to macOS speech on this Mac. Download additional languages and enhanced voices in System Settings → Accessibility → Read & Speak, then refresh.").font(.caption).foregroundStyle(.secondary)
            if let error = catalog.error { Text(error).foregroundStyle(.red) }
        }.task { await catalog.refresh() }.onDisappear { catalog.stop() }
    }

    private var voiceSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search voices", text: $search, prompt: Text("Search by voice or language"))
                .textFieldStyle(.plain)
                .accessibilityLabel("Search voices")
                .accessibilityHint("Filters the available voices by voice name or language")
                .onExitCommand { search = "" }
            if !search.isEmpty {
                Button("Clear voice search", systemImage: "xmark.circle.fill") { search = "" }
                    .buttonStyle(.plain)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Shows all available voices")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.65), lineWidth: 0.5)
        }
    }
}
