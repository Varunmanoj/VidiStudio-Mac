import SwiftUI

struct ADOverviewView: View {
    @Bindable var studio: StudioModel
    @Environment(\.openSettings) private var openSettings
    let project: StudioProject
    private func audioStatus(_ cue: Segment) -> SynchronizedAudioStatus {
        .resolve(cue: cue, project: project)
    }
    private var ready: Int { project.cues.filter { audioStatus($0) == .generated }.count }
    private var stale: Int { project.cues.filter { audioStatus($0) == .needsRegeneration }.count }
    private var missing: Int { project.cues.filter { audioStatus($0) == .notGenerated }.count }
    private var selectedVoice: String {
        if studio.settings.ttsMode == "gemini" { return studio.settings.geminiVoice }
        if !studio.settings.systemVoice.isEmpty { return studio.settings.systemVoice }
        if let voice = SystemSpeechVoiceResolver.defaultVoiceDisplayName {
            return "System default (\(voice))"
        }
        return "System default"
    }
    private func statistic(_ title: String, value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).monospacedDigit() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): \(value)")
            .accessibilityAddTraits(.isStaticText)
    }
    var body: some View {
        Form {
            Section("Audio description overview") {
                statistic("Description segments", value: String(project.cues.count))
                statistic("Narration audio ready", value: String(ready))
                statistic("Audio needs updating", value: String(stale))
                statistic("Audio missing or unavailable", value: String(missing))
                statistic("Description time", value: timecode(project.cues.reduce(0) { $0 + max(0, $1.end - $1.start) }))
                statistic("Spoken transcript segments", value: String(project.transcript.count))
            }
            Section("Description origins") {
                ForEach(DescriptionOrigin.allCases, id: \.rawValue) { origin in
                    HStack {
                        DescriptionOriginLabel(origin: origin)
                        Spacer()
                        Text(String(project.cues.filter { $0.provenance == origin }.count)).monospacedDigit()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(origin.title): \(project.cues.filter { $0.provenance == origin }.count) segments")
                }
                Text("AI-generated and modified AI segments are counted separately. Manual segments remain manual when edited. Older segments without recorded origin appear as unknown.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Create narration audio") {
                Picker("Speech engine", selection: $studio.settings.ttsMode) {
                    Text("Apple on-device voices · offline").tag("system")
                    Text("Gemini TTS").tag("gemini")
                }
                statistic("Voice", value: selectedVoice)
                HStack {
                    Button("Generate All AD Audio") { studio.execute("synthesize-tts") }
                    Button("Generate Missing or Changed Audio") { studio.execute("synthesize-tts", extra: ["--changed"]) }
                }.disabled(studio.busy || project.cues.isEmpty)
                Button("Voice and Narration Settings") {
                    studio.settingsSection = "Narration"
                    openSettings()
                }
                Text("Voice and speech-engine changes are saved automatically and shared with open project windows.").font(.caption).foregroundStyle(.secondary)
                Text("Both engines save narration in this project for synchronized playback and export. Existing files keep the voice they were created with even if voice settings change. Gemini TTS requires your API key. For narration without creating files, choose on-device playback in Settings → Narration and enable Narration in the editor.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
