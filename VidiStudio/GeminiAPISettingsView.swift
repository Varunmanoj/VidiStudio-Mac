import SwiftUI

private struct GeminiModelRow: Identifiable {
    let id: String
    let label: String
}

private enum GeminiModelGroup: Int, CaseIterable, Identifiable {
    case latest
    case flash
    case flashLite
    case pro
    case omni
    case speech
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .latest: "Latest"
        case .flash: "Flash"
        case .flashLite: "Flash-Lite"
        case .pro: "Pro"
        case .omni: "Omni"
        case .speech: "Speech and transcription"
        case .other: "Other models"
        }
    }
}

private struct GeminiModelMenuGroup: Identifiable {
    let group: GeminiModelGroup
    let options: [GeminiModelOption]

    var id: GeminiModelGroup { group }
}

struct GeminiAPISettingsView: View {
    @Bindable var studio: StudioModel
    @Environment(\.openURL) private var openURL

    private let apiKeyPage = URL(string: "https://aistudio.google.com/api-keys")!

    private let localVideoRows = [
        GeminiModelRow(id: "transcript", label: "Speech transcription"),
        GeminiModelRow(id: "summary", label: "Video summaries"),
        GeminiModelRow(id: "audio_descriptions", label: "Audio descriptions"),
        GeminiModelRow(id: "screen_text", label: "On-screen text"),
        GeminiModelRow(id: "text_rewrite", label: "Description rewrites"),
        GeminiModelRow(id: "tts_audio", label: "Gemini narration"),
    ]

    private let youtubeVideoRows = [
        GeminiModelRow(id: "youtube_transcript", label: "YouTube transcription"),
    ]

    var body: some View {
        Section("Connect to Gemini") {
            SecureField("API key", text: $studio.settings.apiKey)
                .accessibilityHint("Enter the key from your Google AI Studio account.")
            Button("Open API Keys in Google AI Studio", systemImage: "arrow.up.right.square") {
                openURL(apiKeyPage)
            }
            .accessibilityHint("Opens the Google AI Studio API Keys page in your web browser.")
            Text("Your key lets VidiStudio create transcripts, summaries, descriptions, and online narration.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(studio.geminiModelsLoaded ? "Reload Available Models" : "Load Available Models", systemImage: "arrow.clockwise") {
                studio.loadGeminiModels()
            }
            .disabled(studio.busy || studio.settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if studio.busy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Checking available models…")
                }
                .accessibilityElement(children: .combine)
            } else if studio.geminiModelsLoaded {
                Text("\(studio.availableGeminiModels.count) available models loaded from Gemini.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Enter your API key, then load the models available to your account.")
                    .foregroundStyle(.secondary)
            }
        }

        Section {
            ForEach(localVideoRows) { row in
                modelPicker(row)
            }
        } header: {
            Text("Local video")
        } footer: {
            Text("Summary, description, rewrite, and narration selections are also used for YouTube projects.")
        }

        Section {
            ForEach(youtubeVideoRows) { row in
                modelPicker(row)
            }
        } header: {
            Text("YouTube video")
        } footer: {
            Text("YouTube transcription has its own model because it processes the online video source differently.")
        }
    }

    private func modelBinding(_ stage: String) -> Binding<String> {
        Binding(
            get: { studio.settings.models[stage] ?? "" },
            set: { studio.settings.models[stage] = $0 }
        )
    }

    private func modelPicker(_ row: GeminiModelRow) -> some View {
        Picker(row.label, selection: modelBinding(row.id)) {
            ForEach(modelGroups(for: row.id)) { modelGroup in
                Section(modelGroup.group.title) {
                    ForEach(modelGroup.options) { option in
                        Text(modelDisplayName(option.name)).tag(option.name)
                    }
                }
            }
        }
        .disabled(!studio.geminiModelsLoaded)
        .accessibilityHint("Choose from models available to your Gemini account.")
    }

    private func modelGroups(for stage: String) -> [GeminiModelMenuGroup] {
        let grouped = Dictionary(grouping: studio.geminiModels(for: stage)) { option in
            modelGroup(for: option.name)
        }

        return GeminiModelGroup.allCases.compactMap { group in
            guard let options = grouped[group], !options.isEmpty else { return nil }
            return GeminiModelMenuGroup(
                group: group,
                options: options.sorted {
                    modelDisplayName($0.name).localizedStandardCompare(modelDisplayName($1.name)) == .orderedAscending
                }
            )
        }
    }

    private func modelGroup(for name: String) -> GeminiModelGroup {
        let normalized = name.lowercased()
        if normalized.contains("latest") { return .latest }
        if normalized.contains("tts") || normalized.contains("transcribe") { return .speech }
        if normalized.contains("flash-lite") { return .flashLite }
        if normalized.contains("pro") { return .pro }
        if normalized.contains("omni") { return .omni }
        if normalized.contains("flash") { return .flash }
        return .other
    }

    private func modelDisplayName(_ name: String) -> String {
        var tokens = name
            .replacingOccurrences(of: "models/", with: "")
            .split(separator: "-")
            .map(String.init)

        if tokens.first?.lowercased() == "gemini" {
            tokens.removeFirst()
        }

        var qualifiers: [String] = []
        if removeToken("latest", from: &tokens) { qualifiers.append("Latest") }
        if removeToken("preview", from: &tokens) { qualifiers.append("Preview") }
        if removeToken("experimental", from: &tokens) || removeToken("exp", from: &tokens) {
            qualifiers.append("Experimental")
        }
        if removeSequence(["custom", "tools"], from: &tokens) {
            qualifiers.append("Custom Tools")
        }

        var components: [String] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index].lowercased()
            if token == "flash", index + 1 < tokens.count, tokens[index + 1].lowercased() == "lite" {
                components.append("Flash-Lite")
                index += 2
                continue
            }
            components.append(formattedModelToken(tokens[index]))
            index += 1
        }

        let modelName = (["Gemini"] + components).joined(separator: " ")
        guard !qualifiers.isEmpty else { return modelName }
        return "\(modelName) — \(qualifiers.joined(separator: ", "))"
    }

    private func formattedModelToken(_ token: String) -> String {
        switch token.lowercased() {
        case "tts": "TTS"
        case "pro": "Pro"
        case "flash": "Flash"
        case "lite": "Lite"
        case "omni": "Omni"
        case "transcribe": "Transcribe"
        case "image": "Image"
        case "live": "Live"
        default: token.first?.isNumber == true ? token : token.capitalized
        }
    }

    private func removeToken(_ token: String, from tokens: inout [String]) -> Bool {
        guard let index = tokens.firstIndex(where: { $0.caseInsensitiveCompare(token) == .orderedSame }) else {
            return false
        }
        tokens.remove(at: index)
        return true
    }

    private func removeSequence(_ sequence: [String], from tokens: inout [String]) -> Bool {
        guard sequence.count <= tokens.count else { return false }
        for start in 0...(tokens.count - sequence.count) {
            let candidate = tokens[start..<(start + sequence.count)].map { $0.lowercased() }
            if candidate == sequence {
                tokens.removeSubrange(start..<(start + sequence.count))
                return true
            }
        }
        return false
    }
}
