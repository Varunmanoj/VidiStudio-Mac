import SwiftUI

private struct GeminiModelRow: Identifiable {
    let id: String
    let label: String
}

struct GeminiAPISettingsView: View {
    @Bindable var studio: StudioModel
    @Environment(\.openURL) private var openURL

    private let apiKeyPage = URL(string: "https://aistudio.google.com/api-keys")!

    private let rows = [
        GeminiModelRow(id: "transcript", label: "Speech transcription"),
        GeminiModelRow(id: "youtube_transcript", label: "YouTube transcription"),
        GeminiModelRow(id: "summary", label: "Video summaries"),
        GeminiModelRow(id: "audio_descriptions", label: "Audio descriptions"),
        GeminiModelRow(id: "screen_text", label: "On-screen text"),
        GeminiModelRow(id: "text_rewrite", label: "Description rewrites"),
        GeminiModelRow(id: "tts_audio", label: "Gemini narration"),
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
            ForEach(rows) { row in
                Picker(row.label, selection: modelBinding(row.id)) {
                    ForEach(studio.geminiModels(for: row.id)) { option in
                        Text(option.displayName).tag(option.name)
                    }
                }
                .disabled(!studio.geminiModelsLoaded)
                .accessibilityHint("Choose from models available to your Gemini account.")
            }
        } header: {
            Text("Choose models")
        } footer: {
            Text("These menus come directly from Gemini and show compatible choices available to your API key.")
        }
    }

    private func modelBinding(_ stage: String) -> Binding<String> {
        Binding(
            get: { studio.settings.models[stage] ?? "" },
            set: { studio.settings.models[stage] = $0 }
        )
    }
}
