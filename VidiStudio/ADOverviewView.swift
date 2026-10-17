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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 340), spacing: 16)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    GroupBox("Audio description overview") {
                        VStack(alignment: .leading, spacing: 10) {
                            statistic("Description segments", value: String(project.cues.count))
                            Divider()
                            statistic("Narration audio ready", value: String(ready))
                            Divider()
                            statistic("Audio needs updating", value: String(stale))
                            Divider()
                            statistic("Audio missing or unavailable", value: String(missing))
                            Divider()
                            statistic("Description time", value: timecode(project.cues.reduce(0) { $0 + max(0, $1.end - $1.start) }))
                            Divider()
                            statistic("Spoken transcript segments", value: String(project.transcript.count))
                        }
                        .padding(.vertical, 4)
                    }
                    GroupBox("Description origins") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(DescriptionOrigin.allCases, id: \.rawValue) { origin in
                                HStack {
                                    DescriptionOriginLabel(origin: origin)
                                    Spacer()
                                    Text(String(project.cues.filter { $0.provenance == origin }.count)).monospacedDigit()
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(origin.title): \(project.cues.filter { $0.provenance == origin }.count) segments")
                                if origin != DescriptionOrigin.allCases.last {
                                    Divider()
                                }
                            }
                            Text("AI-generated and modified AI segments are counted separately. Manual segments remain manual when edited. Older segments without recorded origin appear as unknown.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                GroupBox("Create narration audio") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Speech engine", selection: $studio.settings.ttsMode) {
                            Text("Apple on-device voices · offline").tag("system")
                            Text("Gemini TTS").tag("gemini")
                        }
                        HStack {
                            Button("Generate All AD Audio") { studio.execute("synthesize-tts") }
                                .help(studio.settings.ttsMode == "gemini" && !studio.hasApiKey
                                    ? "Enter your Gemini API key in Settings → Gemini API to synthesize narration with Gemini TTS"
                                    : "Create narration audio for all Audio Description segments")
                            Button("Generate Missing or Changed Audio") { studio.execute("synthesize-tts", extra: ["--changed"]) }
                                .help(studio.settings.ttsMode == "gemini" && !studio.hasApiKey
                                    ? "Enter your Gemini API key in Settings → Gemini API to synthesize narration with Gemini TTS"
                                    : "Recreate narration only for descriptions whose text or voice settings changed")
                        }
                        .disabled(studio.busy || project.cues.isEmpty || (studio.settings.ttsMode == "gemini" && !studio.hasApiKey))
                        if studio.settings.ttsMode == "gemini" && !studio.hasApiKey {
                            HStack(spacing: 8) {
                                Image(systemName: "key.slash.fill")
                                    .foregroundStyle(.orange)
                                Text("Enter your Gemini API key in Settings → Gemini API to use Gemini TTS.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("Voice and Narration Settings") {
                            studio.settingsSection = "Narration"
                            SettingsSectionRequest.request("Narration")
                            openSettings()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}
