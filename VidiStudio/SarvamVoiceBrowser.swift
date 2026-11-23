import SwiftUI

struct SarvamVoiceBrowser: View {
    let model: String
    let narrationLanguage: String
    let selectedVoice: String
    @Bindable var sample: SarvamDemoPlayer
    let apiKey: String
    let select: (SarvamCatalog.Voice) -> Void
    @State private var search = ""
    @State private var style = "all"
    @State private var sort = "name"
    @FocusState private var searchFocused: Bool
    private var voices: [SarvamCatalog.Voice] { SarvamCatalog.shared.voices.filter { $0.model == model && $0.languages.contains(narrationLanguage) } }
    private var styleOptions: [(String, String)] {
        [("all", "All styles")] + Set(voices.map(\.style)).map { value in (value, voices.first { $0.style == value }?.styleLabel.isEmpty == false ? voices.first { $0.style == value }!.styleLabel : "Standard") }.sorted { $0.1 < $1.1 }
    }
    private var groups: [VoiceFamily] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = voices.filter { voice in
            (style == "all" || voice.style == style) &&
            (query.isEmpty || (voice.label + " " + voice.languages.map { SarvamCatalog.shared.languages[$0] ?? $0 }.joined(separator: " ")).localizedCaseInsensitiveContains(query))
        }
        return Dictionary(grouping: filtered, by: \.name).map { name, values in
            VoiceFamily(name: name, voices: values.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending })
        }.sorted { left, right in
            if sort == "style", left.voices.first?.styleLabel != right.voices.first?.styleLabel { return (left.voices.first?.styleLabel ?? "") < (right.voices.first?.styleLabel ?? "") }
            return left.name.localizedStandardCompare(right.name) == (sort == "descending" ? .orderedDescending : .orderedAscending)
        }
    }
    private struct VoiceFamily: Identifiable { let name: String; let voices: [SarvamCatalog.Voice]; var id: String { name } }
    private func sampleID(_ voice: SarvamCatalog.Voice) -> String { voice.model + "|" + voice.id + "|" + narrationLanguage }
    private var canPlaySample: Bool { !sample.active && !sample.preparing && !VoiceSampleSession.shared.busy && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private func toggleSample(_ voice: SarvamCatalog.Voice) {
        if sample.active && sample.activeAddress == sampleID(voice) { if sample.preparing { sample.stop() } else { sample.stop() } } else if canPlaySample { sample.play(voice, language: narrationLanguage, key: apiKey) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voices").font(.headline).accessibilityAddTraits(.isHeader).accessibilityHeading(.h3)
            SpeechChoice(title: "Style", id: "sarvam-style-filter", value: $style, options: styleOptions)
            searchBox
            SpeechChoice(title: "Sort by", id: "sarvam-voice-sort", value: $sort, options: [("name", "Voice name (A–Z)"), ("descending", "Voice name (Z–A)"), ("style", "Style (A–Z)")])
            Text("Selected: \(voices.first { $0.id == selectedVoice }?.label ?? "Selected voice unavailable")").font(.callout)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if groups.isEmpty { Text("No matching voices").foregroundStyle(.secondary) }
                    ForEach(groups) { group in
                        Text(group.name).font(.headline).accessibilityAddTraits(.isHeader).accessibilityHeading(.h3)
                        ForEach(group.voices) { voice in voiceRow(voice) }
                        Divider()
                    }
                }.padding(4)
            }.frame(minHeight: 200, idealHeight: 280, maxHeight: 320)
            .accessibilityIdentifier("sarvam-voice")
            Button("Reset Voice Filters") { resetFilters() }
                .contextMenu { Button("Reset Voice Filters") { resetFilters() }.accessibilityIdentifier("sarvam-filters-reset") }
        }
        .onChange(of: model) { _, _ in resetFilters() }
        .onChange(of: narrationLanguage) { _, _ in resetFilters() }
    }
    private func resetFilters() { search = ""; style = "all"; sort = "name" }
    private var searchBox: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search voices", text: $search, prompt: Text("Search by voice, style or language"))
                .textFieldStyle(.plain).focused($searchFocused)
                .accessibilityLabel("Search voices").accessibilityIdentifier("sarvam-voice-search")
                .onExitCommand { search = "" }
                .contextMenu {
                    Button("Search voices") { searchFocused = true }.accessibilityIdentifier("sarvam-search-focus")
                    Button("Clear voice search") { search = "" }.accessibilityIdentifier("sarvam-search-clear")
                }
            if !search.isEmpty {
                Button("Clear voice search", systemImage: "xmark.circle.fill") { search = "" }
                    .buttonStyle(.plain).labelStyle(.iconOnly).foregroundStyle(.secondary)
                    .accessibilityIdentifier("sarvam-search-clear-icon")
                    .contextMenu { Button("Clear voice search") { search = "" }.accessibilityIdentifier("sarvam-search-clear") }
            }
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.separator.opacity(0.65), lineWidth: 0.5) }
    }
    private func voiceRow(_ voice: SarvamCatalog.Voice) -> some View {
        HStack {
            Button { select(voice) } label: {
                HStack(alignment: .top) {
                    Image(systemName: selectedVoice == voice.id ? "checkmark.circle.fill" : "circle")
                    VStack(alignment: .leading) {
                        Text(voice.styleLabel.isEmpty ? "Standard" : voice.styleLabel)
                        Text(voice.languages.map { SarvamCatalog.shared.languages[$0] ?? $0 }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.buttonStyle(.plain).accessibilityLabel("Select " + voice.label + ", " + voice.languages.map { SarvamCatalog.shared.languages[$0] ?? $0 }.joined(separator: ", "))
                .accessibilityAddTraits(selectedVoice == voice.id ? .isSelected : [])
                .contextMenu {
                    Toggle(isOn: Binding(get: { selectedVoice == voice.id }, set: { if $0 { select(voice) } })) { Label("Select " + voice.label, systemImage: "person.wave.2") }
                    Button("Play Sample") { if canPlaySample { sample.play(voice, language: narrationLanguage, key: apiKey) } }.disabled(!canPlaySample)
                    Button("Stop Sample") { sample.stop() }.disabled(!sample.active)
                }
            Spacer()
            if sample.preparing && sample.activeAddress == sampleID(voice) { ProgressView().controlSize(.small).accessibilityLabel("Preparing sample of " + voice.label) }
            Button { toggleSample(voice) } label: { Image(systemName: sample.active && sample.activeAddress == sampleID(voice) ? (sample.preparing ? "stop.circle" : "stop.circle") : "play.circle") }
                .disabled(!(sample.active && sample.activeAddress == sampleID(voice)) && !canPlaySample)
                .accessibilityLabel((sample.active && sample.activeAddress == sampleID(voice) ? (sample.preparing ? "Stop sample of " : "Stop sample of ") : "Play sample of ") + voice.label)
                .contextMenu {
                    Button("Play Sample") { if canPlaySample { sample.play(voice, language: narrationLanguage, key: apiKey) } }.disabled(!canPlaySample)
                    Button("Stop Sample") { sample.stop() }.disabled(!sample.active)
                }
        }
    }
}
