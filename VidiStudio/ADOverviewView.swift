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
    private var voiceReport: NarrationVoiceReport { studio.narrationVoiceUsageReport(for: project) }
    private var narrationVoicesStatistic: String {
        if voiceReport.allSegments.isEmpty { return "None" }
        if voiceReport.hasDifferentVoices {
            let activeCount = voiceReport.voiceSummaries.filter { $0.count > 0 }.count
            return "\(activeCount) voice\(activeCount == 1 ? "" : "s") (\(voiceReport.differentSegments.count) different)"
        }
        return voiceReport.primaryVoiceLabel ?? selectedVoice
    }
    private var narrationControlsDisabled: Bool {
        studio.busy || project.cues.isEmpty || (studio.settings.ttsMode == "gemini" && (!studio.hasApiKey || studio.isApiKeyInvalid))
    }
    private var selectedVoice: String {
        if studio.settings.ttsMode == "gemini" { return studio.settings.geminiVoice }
        if studio.settings.ttsMode == "piper" {
            return NarrationVoiceFormatting.voiceDisplayName(studio.settings.piperVoiceSignature)
        }
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
                            Divider()
                            statistic("Narration voices", value: narrationVoicesStatistic)
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
                            Text("Apple Voices").tag("system")
                            Text("Piper Voices").tag("piper")
                            Text("Gemini Voices").tag("gemini")
                        }
                        statistic("Selected voice", value: studio.settings.currentNarrationSummary)
                        if studio.isSynthesizingNarration {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                    .accessibilityHidden(true)
                                Image(systemName: "waveform.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityHidden(true)
                                Text(studio.activeNarrationStatusText)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(studio.activeNarrationStatusText)
                        }
                        if voiceReport.hasDifferentVoices {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Different narration voices are used in this project")
                                            .font(.subheadline.weight(.semibold))
                                        Text(voiceReport.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        ForEach(voiceReport.voiceSummaries) { summary in
                                            let segmentsList = summary.segmentNumbers.isEmpty
                                                ? "0 segments"
                                                : "\(summary.count) segment\(summary.count == 1 ? "" : "s") (AD \(summary.segmentNumbers.map(String.init).joined(separator: ", ")))"
                                            Text("• \(summary.combinedLabel)\(summary.isDifferentVoice ? " — Different voice" : " — Primary voice"): \(segmentsList)")
                                                .font(.caption)
                                                .foregroundStyle(summary.isDifferentVoice ? Color.orange : Color.secondary)
                                        }
                                    }
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityElement(children: .combine)
                        }
                        HStack {
                            Button(project.allADAudioTitle) { studio.execute("synthesize-tts") }
                                .help(studio.settings.ttsMode == "gemini" && !studio.hasApiKey
                                    ? "Enter your Gemini API key in Settings → Gemini API to synthesize narration with Gemini TTS"
                                    : "Create narration audio for all Audio Description segments")
                                .disabled(narrationControlsDisabled)
                            Button("Generate Missing or Changed AD Audio") { studio.execute("synthesize-tts", extra: ["--changed"]) }
                                .help(studio.settings.ttsMode == "gemini" && !studio.hasApiKey
                                    ? "Enter your Gemini API key in Settings → Gemini API to synthesize narration with Gemini TTS"
                                    : "Generate missing narration and regenerate descriptions with text, timing, or generation issues")
                                .disabled(narrationControlsDisabled || !project.canGenerateMissingOrChangedAudio)
                        }
                        HStack {
                            Button("Review Narration Issues") {
                                studio.narrationFailureReport = studio.narrationIssueReport(for: project)
                            }
                            .help("Review missing audio, generation failures, and text or timing changes without generating narration")
                            .disabled(studio.busy)
                            Button("Review Narration Voices") {
                                studio.narrationVoiceReport = voiceReport
                            }
                            .help("Review how many segments use each voice, which segments use a different voice, and segment timing details")
                            .disabled(studio.busy)
                        }
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

/// Narration issues available after generation and from AD Overview at any time.
struct NarrationFailuresView: View {
    let report: NarrationFailureReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: report.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(report.failures.isEmpty ? Color.green : Color.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.title)
                        .font(.headline)
                    Text(report.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            if !report.failures.isEmpty {
                Text("Start and end: HH:MM:SS.mmm (hours:minutes:seconds.milliseconds). Duration is in seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 12) {
                            Text("AD").frame(width: 40, alignment: .leading)
                            Text("Start").frame(width: 110, alignment: .leading)
                            Text("End").frame(width: 110, alignment: .leading)
                            Text("Duration").frame(width: 85, alignment: .leading)
                            Text("Reason").frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.vertical, 8)
                        .accessibilityHidden(true)
                        Divider()
                        ForEach(report.failures) { failure in
                            HStack(alignment: .top, spacing: 12) {
                                Text(String(failure.id)).monospacedDigit()
                                    .frame(width: 40, alignment: .leading)
                                    .accessibilityLabel("AD segment \(failure.id)")
                                Text(NarrationTimeFormat.timestamp(failure.start)).monospacedDigit()
                                    .frame(width: 110, alignment: .leading)
                                    .accessibilityLabel("Start: \(NarrationTimeFormat.spokenTime(failure.start))")
                                Text(NarrationTimeFormat.timestamp(failure.end)).monospacedDigit()
                                    .frame(width: 110, alignment: .leading)
                                    .accessibilityLabel("End: \(NarrationTimeFormat.spokenTime(failure.end))")
                                Text(NarrationTimeFormat.duration(failure.duration)).monospacedDigit()
                                    .frame(width: 85, alignment: .leading)
                                    .accessibilityLabel("Duration: \(NarrationTimeFormat.spokenDuration(failure.duration))")
                                Text(failure.reason)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .accessibilityLabel("Reason: \(failure.reason)")
                            }
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .combine)
                            Divider()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 800, minHeight: 240, idealHeight: 340, maxHeight: 420)
                .accessibilityLabel("Narration issues")
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 840)
    }
}

/// Dialog detailing how many segments use each narration voice and which segments use a different voice.
struct NarrationVoicesView: View {
    let report: NarrationVoiceReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: report.hasDifferentVoices ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(report.hasDifferentVoices ? Color.orange : Color.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.title)
                        .font(.headline)
                    Text(report.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            if !report.voiceSummaries.isEmpty {
                GroupBox("Voice usage by segment count") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(report.voiceSummaries) { summary in
                            let segmentText = summary.segmentNumbers.isEmpty
                                ? "0 segments"
                                : "\(summary.count) segment\(summary.count == 1 ? "" : "s") (AD \(summary.segmentNumbers.map(String.init).joined(separator: ", ")))"
                            HStack {
                                Text("\(summary.combinedLabel)\(summary.isDifferentVoice ? " · Different voice" : " · Primary voice")")
                                    .font(.callout.weight(summary.isDifferentVoice ? .semibold : .regular))
                                    .foregroundStyle(summary.isDifferentVoice ? Color.orange : Color.primary)
                                Spacer()
                                Text(segmentText)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            if summary.id != report.voiceSummaries.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if !report.allSegments.isEmpty {
                if !report.differentSegments.isEmpty {
                    Text("Segments using a different voice: AD \(report.differentSegments.map { String($0.id) }.joined(separator: ", "))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Text("Start and end: HH:MM:SS.mmm (hours:minutes:seconds.milliseconds). Duration is in seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 12) {
                            Text("AD").frame(width: 40, alignment: .leading)
                            Text("Start").frame(width: 110, alignment: .leading)
                            Text("End").frame(width: 110, alignment: .leading)
                            Text("Duration").frame(width: 85, alignment: .leading)
                            Text("Voice & Engine").frame(width: 185, alignment: .leading)
                            Text("Details").frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.vertical, 8)
                        .accessibilityHidden(true)
                        Divider()
                        ForEach(report.allSegments) { entry in
                            HStack(alignment: .top, spacing: 12) {
                                Text(String(entry.id)).monospacedDigit()
                                    .frame(width: 40, alignment: .leading)
                                    .accessibilityLabel("AD segment \(entry.id)")
                                Text(NarrationTimeFormat.timestamp(entry.start)).monospacedDigit()
                                    .frame(width: 110, alignment: .leading)
                                    .accessibilityLabel("Start: \(NarrationTimeFormat.spokenTime(entry.start))")
                                Text(NarrationTimeFormat.timestamp(entry.end)).monospacedDigit()
                                    .frame(width: 110, alignment: .leading)
                                    .accessibilityLabel("End: \(NarrationTimeFormat.spokenTime(entry.end))")
                                Text(NarrationTimeFormat.duration(entry.duration)).monospacedDigit()
                                    .frame(width: 85, alignment: .leading)
                                    .accessibilityLabel("Duration: \(NarrationTimeFormat.spokenDuration(entry.duration))")
                                Text(entry.combinedLabel)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(width: 185, alignment: .leading)
                                    .foregroundStyle(entry.usesDifferentVoice ? Color.orange : Color.primary)
                                    .accessibilityLabel("Voice: \(entry.combinedLabel)")
                                Text(entry.reason)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundStyle(entry.usesDifferentVoice ? Color.orange : Color.secondary)
                                    .textSelection(.enabled)
                                    .accessibilityLabel("Details: \(entry.reason)")
                            }
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .combine)
                            Divider()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 800, minHeight: 220, idealHeight: 320, maxHeight: 400)
                .accessibilityLabel("Narration voice segments")
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 860)
    }
}
