import SwiftUI
import AppKit
import AVFoundation

struct SystemVoice: Identifiable, Sendable {
    var name: String
    var language: String
    var sample: String
    var id: String { name + language }
    var languageName: String { Locale.current.localizedString(forIdentifier: language) ?? language }
    var baseLanguageCode: String {
        Locale.Language.Components(identifier: language).languageCode?.identifier ?? language
    }
    var baseLanguageName: String {
        Locale.current.localizedString(forLanguageCode: baseLanguageCode) ?? baseLanguageCode
    }
}

private struct SystemVoiceDialectGroup: Identifiable {
    let id: String
    let name: String
    let voices: [SystemVoice]
}

private struct SystemVoiceLanguageGroup: Identifiable {
    let id: String
    let name: String
    let dialects: [SystemVoiceDialectGroup]
}

enum SystemSpeechVoiceResolver {
    static var defaultVoiceIdentifier: String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.Accessibility.plist")
        guard let data = try? Data(contentsOf: url),
              let preferences = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let selections = preferences["SpokenContentDefaultVoiceSelectionsByLanguage"] as? [Any] else { return nil }
        var choices: [String: String] = [:]
        var index = 0
        while index + 1 < selections.count {
            if let language = selections[index] as? String,
               let selection = selections[index + 1] as? [String: Any],
               let identifier = selection["voiceId"] as? String {
                choices[language] = identifier
            }
            index += 2
        }
        var languageKeys = Locale.preferredLanguages.flatMap { language -> [String] in
            let normalized = language.replacingOccurrences(of: "_", with: "-")
            return [normalized, normalized.components(separatedBy: "-").first ?? normalized]
        }
        languageKeys.append("en")
        return languageKeys.lazy.compactMap { choices[$0] }.first
    }

    static var defaultVoice: AVSpeechSynthesisVoice? {
        guard let identifier = defaultVoiceIdentifier else { return nil }
        return AVSpeechSynthesisVoice(identifier: identifier)
    }

    static func selectedVoice(named requested: String) -> AVSpeechSynthesisVoice? {
        let requested = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        if requested.isEmpty { return defaultVoice ?? AVSpeechSynthesisVoice(language: nil) }
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let normalized = requested.lowercased()
        let quality: AVSpeechSynthesisVoiceQuality? = normalized.hasSuffix(" (premium)") ? .premium
            : normalized.hasSuffix(" (enhanced)") ? .enhanced : nil
        let baseName = requested
            .replacingOccurrences(of: " (Enhanced)", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " (Premium)", with: "", options: .caseInsensitive)
        return voices.first { $0.identifier == requested }
            ?? voices.first {
                ($0.name.caseInsensitiveCompare(requested) == .orderedSame
                 || $0.name.caseInsensitiveCompare(baseName) == .orderedSame)
                && (quality == nil || $0.quality == quality)
            }
    }

    static var defaultVoiceDisplayName: String? {
        guard let voice = defaultVoice else { return nil }
        if voice.name.localizedCaseInsensitiveContains("enhanced")
            || voice.name.localizedCaseInsensitiveContains("premium") {
            return voice.name
        }
        switch voice.quality {
        case .premium: return "\(voice.name) (Premium)"
        case .enhanced: return "\(voice.name) (Enhanced)"
        default: return voice.name
        }
    }
}

@MainActor @Observable final class SystemVoiceCatalog: NSObject, @preconcurrency AVSpeechSynthesizerDelegate {
    var voices: [SystemVoice] = []
    var error: String?
    var isPlayingSample = false
    @ObservationIgnored private let sampleSynthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        sampleSynthesizer.delegate = self
    }

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
        do {
            sampleSynthesizer.speak(try SystemSpeechUtterance.make(text: voice.sample, settings: settings, voiceName: voice.name))
            error = nil
        } catch {
            self.error = UserFacingIssueReporter.message(
                for: error,
                issue: .speech,
                context: "Preview Apple voice"
            )
        }
    }
    func stop() {
        sampleSynthesizer.stopSpeaking(at: .immediate)
        isPlayingSample = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isPlayingSample = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isPlayingSample = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isPlayingSample = false
    }
}

enum SystemSpeechUtterance {
    struct UnavailableVoice: LocalizedError {
        let name: String
        var errorDescription: String? {
            "The selected Apple voice ‘\(name)’ is unavailable for live speech. Choose an installed voice in Settings → Narration, or explicitly choose System default."
        }
    }

    static func make(text: String, settings: StudioSettings, voiceName: String? = nil) throws -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        let scaledRate = AVSpeechUtteranceDefaultSpeechRate * Float(settings.systemSpeechRate)
        utterance.rate = min(max(scaledRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        utterance.pitchMultiplier = Float(min(max(settings.systemSpeechPitch, 0.5), 2.0))
        utterance.volume = Float(min(max(settings.systemSpeechVolume, 0), 1.0))
        let requested = (voiceName ?? settings.systemVoice).trimmingCharacters(in: .whitespacesAndNewlines)
        if requested.isEmpty {
            utterance.voice = SystemSpeechVoiceResolver.defaultVoice
        } else {
            let voices = AVSpeechSynthesisVoice.speechVoices()
            let normalized = requested.lowercased()
            let quality: AVSpeechSynthesisVoiceQuality? = normalized.hasSuffix(" (premium)") ? .premium
                : normalized.hasSuffix(" (enhanced)") ? .enhanced : nil
            let baseName = requested
                .replacingOccurrences(of: " (Enhanced)", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: " (Premium)", with: "", options: .caseInsensitive)
            let match = voices.first { $0.identifier == requested }
                ?? voices.first {
                    ($0.name.caseInsensitiveCompare(requested) == .orderedSame
                     || $0.name.caseInsensitiveCompare(baseName) == .orderedSame)
                    && (quality == nil || $0.quality == quality)
                }
            guard let match else {
                throw UnavailableVoice(name: requested)
            }
            utterance.voice = match
        }
        return utterance
    }
}

struct SystemVoiceBrowser: View {
    @Binding var settings: StudioSettings
    var menuPrefix = "local"
    @FocusState private var voiceSearchFocused: Bool
    @State private var catalog = SystemVoiceCatalog()
    @State private var language = "all"
    @State private var search = ""
    @State private var sort = "language"
    var body: some View {
        let selectedName = selectedVoiceLabel
        VStack(alignment: .leading, spacing: 12) {
            Text("Voices").font(.headline).accessibilityAddTraits(.isHeader).accessibilityHeading(.h2)
            Picker("Language and region", selection: $language) {
                Text("All languages").tag("all")
                ForEach(languageGroups) { group in
                    Section(group.name) {
                        ForEach(group.dialects) { dialect in
                            Text(dialect.name).tag(dialect.id)
                        }
                    }
                }
            }
            .accessibilityIdentifier(menuPrefix + "-language-filter")
            voiceSearchField
            SpeechChoice(title: "Sort by", id: menuPrefix + "-voice-sort", value: $sort, options: [("language", "Language (A–Z)"), ("name", "Voice name (A–Z)")])
            Text("Selected: \(selectedVoiceLabel)").font(.callout)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleLanguageGroups) { group in
                        Text(group.name)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.dialects) { dialect in
                            Text(dialect.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(dialect.voices) { voice in
                                HStack {
                                    Button { settings.systemVoice = voice.name } label: {
                                        HStack {
                                            Image(systemName: selectedName == voice.name ? "checkmark.circle.fill" : "circle")
                                            Text(voice.name)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Select \(voice.name), \(dialect.name)")
                                    .accessibilityAddTraits(selectedName == voice.name ? .isSelected : [])
                                    .contextMenu {
                                        Button("Select " + voice.name) { settings.systemVoice = voice.name }
                                        Button("Play Sample") { catalog.preview(voice, settings: settings) }
                                    }
                                    Spacer()
                                    Button("Speak Sample", systemImage: "play.circle") {
                                        catalog.preview(voice, settings: settings)
                                    }
                                    .labelStyle(.iconOnly)
                                    .accessibilityLabel("Speak sample of \(voice.name), \(dialect.name)")
                                }
                                Divider()
                            }
                        }
                    }
                }.padding(4)
            }.frame(minHeight: 200, idealHeight: 280, maxHeight: 320)
            HStack {
                Button("Use system default voice") { settings.systemVoice = "" }.accessibilityIdentifier(menuPrefix + "-voice-default")
                Button(
                    catalog.isPlayingSample ? "Stop Sample" : "Play Sample",
                    systemImage: catalog.isPlayingSample ? "stop.circle" : "play.circle"
                ) {
                    if catalog.isPlayingSample {
                        catalog.stop()
                    } else {
                        catalog.preview(
                            catalog.voices.first { $0.name == settings.systemVoice }
                                ?? SystemVoice(name: settings.systemVoice, language: "", sample: "This is a sample of audio description narration in VidiStudio."),
                            settings: settings
                        )
                    }
                }
                Button("Refresh Voices") { Task { await catalog.refresh() } }.accessibilityIdentifier(menuPrefix + "-voices-refresh")
                Button("Open macOS Voice Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess")!)
                }
            }
            Text("Voices available on this Mac. Download more in Accessibility → Read & Speak, then refresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = catalog.error { Text(error).foregroundStyle(.red) }
        }
        .contextMenu {
            Button("Search voices") { voiceSearchFocused = true }.accessibilityIdentifier(menuPrefix + "-search-focus")
            Button("Use system default voice") { settings.systemVoice = "" }.accessibilityIdentifier(menuPrefix + "-voice-default")
            Button("Play Sample") { catalog.preview(catalog.voices.first { $0.name == settings.systemVoice } ?? SystemVoice(name: settings.systemVoice, language: "", sample: "This is a sample of the selected voice."), settings: settings) }
            Button("Stop Sample") { catalog.stop() }.disabled(!catalog.isPlayingSample).accessibilityIdentifier(menuPrefix + "-sample-stop")
            Button("Refresh Voices") { Task { await catalog.refresh() } }.accessibilityIdentifier(menuPrefix + "-voices-refresh")
            Button("Open macOS Voice Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess")!) }
            Button("Clear voice search") { search = "" }.accessibilityIdentifier(menuPrefix + "-search-clear")
        }
        .task { await catalog.refresh() }.onDisappear { catalog.stop() }
    }

    private var selectedVoiceLabel: String {
        if !settings.systemVoice.isEmpty {
            if let voice = SystemSpeechVoiceResolver.selectedVoice(named: settings.systemVoice) {
                let suffix = voice.quality == .premium ? " (Premium)" : voice.quality == .enhanced ? " (Enhanced)" : ""
                return voice.name.hasSuffix(suffix) ? voice.name : voice.name + suffix
            }
            return settings.systemVoice.hasPrefix("com.apple.") ? "Selected voice unavailable" : settings.systemVoice
        }
        if let voice = SystemSpeechVoiceResolver.defaultVoiceDisplayName {
            return "System default (\(voice))"
        }
        return "System default"
    }

    private var languageGroups: [SystemVoiceLanguageGroup] {
        let groupedByLanguage = Dictionary(grouping: catalog.voices, by: \.baseLanguageCode)
        return groupedByLanguage.map { code, voices in
            let dialects = Dictionary(grouping: voices, by: \.language).map { locale, dialectVoices in
                SystemVoiceDialectGroup(
                    id: locale,
                    name: Locale.current.localizedString(forIdentifier: locale) ?? locale,
                    voices: dialectVoices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                )
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return SystemVoiceLanguageGroup(
                id: code,
                name: voices.first?.baseLanguageName ?? code,
                dialects: dialects
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var visibleLanguageGroups: [SystemVoiceLanguageGroup] {
        let filtered: [SystemVoiceLanguageGroup] = languageGroups.compactMap { group -> SystemVoiceLanguageGroup? in
            let dialects = group.dialects.compactMap { dialect -> SystemVoiceDialectGroup? in
                guard language == "all" || dialect.id == language else { return nil }
                let voices = dialect.voices.filter {
                    search.isEmpty
                        || $0.name.localizedStandardContains(search)
                        || $0.languageName.localizedStandardContains(search)
                        || $0.baseLanguageName.localizedStandardContains(search)
                }
                guard !voices.isEmpty else { return nil }
                return SystemVoiceDialectGroup(id: dialect.id, name: dialect.name, voices: voices)
            }
            guard !dialects.isEmpty else { return nil }
            return SystemVoiceLanguageGroup(id: group.id, name: group.name, dialects: dialects)
        }
        if sort == "name" {
            let voices = filtered.flatMap(\.dialects).flatMap(\.voices).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return voices.isEmpty ? [] : [SystemVoiceLanguageGroup(id: "names", name: "Voices by name", dialects: [SystemVoiceDialectGroup(id: "names", name: "Matching voices", voices: voices)])]
        }
        return filtered
    }

    private var voiceSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search voices", text: $search, prompt: Text("Search by voice or language"))
                .textFieldStyle(.plain)
                .accessibilityLabel("Search voices")
                .focused($voiceSearchFocused)
                .accessibilityIdentifier(menuPrefix + "-voice-search")
                .accessibilityHint("Filters the available voices by voice name or language")
                .onExitCommand { search = "" }
            if !search.isEmpty {
                Button("Clear voice search", systemImage: "xmark.circle.fill") { search = "" }
                    .buttonStyle(.plain)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Shows all available voices")
                    .contextMenu { Button("Clear voice search") { search = "" }.accessibilityIdentifier(menuPrefix + "-search-clear") }
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
