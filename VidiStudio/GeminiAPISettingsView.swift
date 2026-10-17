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
    @State private var keyDebounceTask: Task<Void, Never>?

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
            if !studio.hasApiKey {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .imageScale(.medium)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("API Key Required")
                            .font(.subheadline.bold())
                        Text("All AI features (transcription, summaries, audio descriptions, description rewrites, frame text OCR, and Gemini narration) are disabled across VidiStudio until an API key is entered.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            SecureField("API key", text: $studio.settings.apiKey)
                .accessibilityHint("Enter the key from your Google AI Studio account.")
                .onSubmit {
                    keyDebounceTask?.cancel()
                    if studio.hasApiKey {
                        studio.checkGeminiApiKey()
                    }
                }
                .onChange(of: studio.settings.apiKey) { _, newValue in
                    keyDebounceTask?.cancel()
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        studio.apiKeyVerified = nil
                        studio.apiKeyVerificationMessage = nil
                        return
                    }
                    keyDebounceTask = Task {
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        if !Task.isCancelled {
                            studio.checkGeminiApiKey()
                        }
                    }
                }
            Button("Open API Keys in Google AI Studio", systemImage: "arrow.up.right.square") {
                openURL(apiKeyPage)
            }
            .accessibilityHint("Opens the Google AI Studio API Keys page in your web browser.")
            Text("Your key lets VidiStudio create transcripts, summaries, descriptions, and online narration.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(studio.geminiModelsLoaded ? "Check API Key & Reload Models" : "Check API Key & Plan", systemImage: "arrow.clockwise") {
                    studio.checkGeminiApiKey()
                }
                .disabled(studio.busy || !studio.hasApiKey)
                .accessibilityHint("Checks the validity of your Gemini API key and detects available models and plan tier.")
            }

            if studio.busy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Checking API key and plan details…")
                }
                .accessibilityElement(children: .combine)
            } else if let verified = studio.apiKeyVerified {
                if verified {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .imageScale(.medium)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("API Key Verified (\(studio.settings.geminiPlan == "paid" ? "Paid Plan" : "Free Plan"))")
                                .font(.subheadline.bold())
                            if let message = studio.apiKeyVerificationMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                            .imageScale(.medium)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("API Key Check Failed")
                                .font(.subheadline.bold())
                            Text(studio.apiKeyVerificationMessage ?? "The engine could not connect to Gemini with this key. Check the key and your network connection.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            } else if studio.hasApiKey {
                Text("Click Check API Key & Plan to verify your key and load compatible models.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if studio.hasApiKey && studio.apiKeyVerified == nil && !studio.busy {
                studio.checkGeminiApiKey()
            }
        }

        if studio.hasApiKey {
            Section("Account Plan") {
                HStack {
                    Text("Plan Tier")
                        .fontWeight(.medium)
                    Spacer()
                    if studio.busy {
                        ProgressView().controlSize(.small)
                    } else {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(studio.settings.geminiPlan == "paid" ? Color.blue : Color.secondary)
                                .frame(width: 8, height: 8)
                            Text(studio.settings.geminiPlan == "paid" ? "Paid Plan" : "Free Plan")
                                .fontWeight(.semibold)
                                .foregroundStyle(studio.settings.geminiPlan == "paid" ? Color.blue : Color.primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(studio.settings.geminiPlan == "paid" ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Account Plan: \(studio.settings.geminiPlan == "paid" ? "Paid Plan" : "Free Plan")")

                Text(studio.settings.geminiPlan == "paid"
                    ? "Detected Paid Plan: Higher rate limits and enterprise data privacy."
                    : "Detected Free Plan: Standard rate limits and quotas.")
                    .font(.caption)
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
