import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Bindable var studio: StudioModel
    @Environment(\.openWindow) private var openWindow
    @State private var saved = false
    private let stages = ["transcript", "youtube_transcript", "summary", "audio_descriptions", "screen_text", "text_rewrite", "tts_audio"]
    private func model(_ key: String) -> Binding<String> {
        Binding(get: { studio.settings.models[key] ?? "" }, set: { studio.settings.models[key] = $0 })
    }
    private func prompt(_ stage: String, _ key: String) -> Binding<String> {
        Binding(get: { studio.settings.prompts[stage]?[key] ?? "" }, set: { studio.settings.prompts[stage, default: [:]][key] = $0 })
    }
    var body: some View {
        Form {
            Section("Help and keyboard shortcuts") {
                Button("Open VidiStudio Help") { openWindow(id: "help") }
                DisclosureGroup("Keyboard shortcut reference") { ShortcutReferenceView() }
            }
            Section("Appearance and playback") {
                Picker("Appearance", selection: $studio.settings.theme) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                Toggle("Follow transcript during playback", isOn: $studio.settings.followTranscript)
            }
            Section("Gemini API") {
                SecureField("API key", text: $studio.settings.apiKey)
                TextField("API version", text: $studio.settings.apiVersion)
                Picker("Video understanding", selection: $studio.settings.videoProcessing) {
                    Text("Agentic").tag("agentic"); Text("Standard").tag("standard")
                }
                ForEach(stages, id: \.self) { stage in TextField(stage.replacingOccurrences(of: "_", with: " ").capitalized, text: model(stage)) }
                Text("The speech transcription model accepts extracted audio. YouTube uses the separately configured video model. Model IDs can be updated here as Gemini versions change.").font(.caption).foregroundStyle(.secondary)
                Button("Validate API Key and Models") { studio.saveSettings(); studio.execute("validate-config") }.disabled(studio.busy)
            }
            Section("Narration") {
                Picker("Speech engine", selection: $studio.settings.ttsMode) {
                    Text("System voices · offline").tag("system"); Text("Gemini TTS").tag("gemini")
                }
                Picker("System voice", selection: $studio.settings.systemVoice) {
                    Text("System default").tag("")
                    ForEach(Array(Set(AVSpeechSynthesisVoice.speechVoices().map(\.name))).sorted(), id: \.self) { name in Text(name).tag(name) }
                }
                TextField("Gemini voice", text: $studio.settings.geminiVoice)
            }
            Section("Developer prompts") {
                ForEach(studio.settings.prompts.keys.sorted(), id: \.self) { stage in
                    DisclosureGroup(stage.replacingOccurrences(of: "_", with: " ").capitalized) {
                        Text("System instruction").font(.caption)
                        TextEditor(text: prompt(stage, "system_instruction")).frame(minHeight: 90).accessibilityLabel("\(stage) system instruction")
                        Text("User prompt").font(.caption)
                        TextEditor(text: prompt(stage, "user_prompt")).frame(minHeight: 130).accessibilityLabel("\(stage) user prompt")
                    }
                }
            }
            Section("Local storage and tools") {
                TextField("Project library", text: $studio.settings.libraryPath)
                TextField("FFmpeg override", text: $studio.settings.ffmpegPath)
                TextField("FFprobe override", text: $studio.settings.ffprobePath)
            }
            HStack {
                Button("Save Settings") { studio.saveSettings(); saved = studio.error == nil }.keyboardShortcut("s")
                Button("Check Engine") { studio.execute("doctor") }
                if saved { Label("Saved", systemImage: "checkmark.circle.fill") }
            }.disabled(studio.busy)
            Text("API credentials are saved outside projects with owner-only file permissions.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).padding().frame(width: 700, height: 720)
    }
}
