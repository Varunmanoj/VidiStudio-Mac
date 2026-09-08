import SwiftUI

struct SettingsView: View {
    @Bindable var studio: StudioModel
    @Environment(\.openWindow) private var openWindow
    @State private var saved = false
    @State private var section = "Appearance"
    private let sections = ["Appearance", "Narration", "Gemini API", "Developer prompts", "Storage", "Help"]
    private let stages = ["transcript", "youtube_transcript", "summary", "audio_descriptions", "screen_text", "text_rewrite", "tts_audio"]
    private func model(_ key: String) -> Binding<String> {
        Binding(get: { studio.settings.models[key] ?? "" }, set: { studio.settings.models[key] = $0 })
    }
    private func prompt(_ stage: String, _ key: String) -> Binding<String> {
        Binding(get: { studio.settings.prompts[stage]?[key] ?? "" }, set: { studio.settings.prompts[stage, default: [:]][key] = $0 })
    }
    var body: some View {
        NavigationSplitView {
            List(sections, id: \.self, selection: $section) { Text($0).tag($0) }
                .navigationTitle("Settings")
                .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
        Form {
            if section == "Help" { Section("Help and keyboard shortcuts") {
                Button("Open VidiStudio Help") { openWindow(id: "help") }
                DisclosureGroup("Keyboard shortcut reference") { ShortcutReferenceView() }
            }
            }
            if section == "Appearance" { Section("Appearance and playback") {
                Picker("Appearance", selection: $studio.settings.theme) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                Toggle("Follow transcript during playback", isOn: $studio.settings.followTranscript)
            }
            }
            if section == "Gemini API" { Section("Gemini API") {
                SecureField("API key", text: $studio.settings.apiKey)
                TextField("API version", text: $studio.settings.apiVersion)
                Picker("Video understanding", selection: $studio.settings.videoProcessing) {
                    Text("Agentic").tag("agentic"); Text("Standard").tag("standard")
                }
                ForEach(stages, id: \.self) { stage in TextField(stage.replacingOccurrences(of: "_", with: " ").capitalized, text: model(stage)) }
                Text("The speech transcription model accepts extracted audio. YouTube uses the separately configured video model. Model IDs can be updated here as Gemini versions change.").font(.caption).foregroundStyle(.secondary)
                Button("Validate API Key and Models") { studio.saveSettings(); studio.execute("validate-config") }.disabled(studio.busy)
            }
            }
            if section == "Narration" { Section("Narration") {
                Picker("Speech engine", selection: $studio.settings.ttsMode) {
                    Text("Apple on-device voices · offline").tag("system"); Text("Gemini TTS").tag("gemini")
                }
                Picker("Narration during playback", selection: $studio.settings.narrationPlayback) {
                    Text("Play generated audio").tag("generated")
                    Text("Speak on device without audio files").tag("device")
                }
                Text("Generate audio with the selected speech engine for consistent timing and exports. On-device playback speaks each active cue using the selected Apple voice; seeking or resuming restarts its text.").font(.caption).foregroundStyle(.secondary)
                if studio.settings.ttsMode == "gemini" {
                    GeminiVoiceBrowser(studio: studio)
                } else {
                    SystemVoiceBrowser(selectedVoice: $studio.settings.systemVoice)
                }
            }
            }
            if section == "Developer prompts" { Section("Developer prompts") {
                ForEach(studio.settings.prompts.keys.sorted(), id: \.self) { stage in
                    DisclosureGroup(stage.replacingOccurrences(of: "_", with: " ").capitalized) {
                        Text("System instruction").font(.caption)
                        TextEditor(text: prompt(stage, "system_instruction")).frame(minHeight: 90).accessibilityLabel("\(stage) system instruction")
                        Text("User prompt").font(.caption)
                        TextEditor(text: prompt(stage, "user_prompt")).frame(minHeight: 130).accessibilityLabel("\(stage) user prompt")
                    }
                }
            }
            }
            if section == "Storage" { Section("Local storage and tools") {
                TextField("Project library", text: $studio.settings.libraryPath)
                TextField("FFmpeg override", text: $studio.settings.ffmpegPath)
                TextField("FFprobe override", text: $studio.settings.ffprobePath)
                Button("Check Engine") { studio.execute("doctor") }.disabled(studio.busy)
            }
            }
            Text("API credentials are saved outside projects with owner-only file permissions.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).navigationTitle(section)
        }
        .background(SettingsWindowChrome().frame(width: 0, height: 0))
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save Settings") { studio.saveSettings(); saved = studio.error == nil }.keyboardShortcut("s").disabled(studio.busy)
            }
        }
        .frame(minWidth: 850, idealWidth: 940, minHeight: 650, idealHeight: 740)
        .onChange(of: section) { _, _ in saved = false }
        .preferredColorScheme(studio.settings.theme == "dark" ? .dark : studio.settings.theme == "light" ? .light : nil)
    }
}
