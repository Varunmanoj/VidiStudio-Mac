import SwiftUI
import AppKit

struct YouTubeAudioExportRecovery {
    let project: StudioProject
    let command: String
    let arguments: [String]
}

extension StudioModel {
    func chooseAudioForFailedExport(_ recovery: YouTubeAudioExportRecovery) {
        guard !busy else { return }
        dismissError()
        guard let file = ImportFileKind.originalAudio.choose() else { return }
        let current = projects.first(where: { $0.id == recovery.project.id }) ?? recovery.project
        importOriginalAudio(file, into: current) { imported in
            guard let imported else { return }
            var arguments = recovery.arguments
            while let index = arguments.firstIndex(of: "--soundtrack-source") {
                arguments.remove(at: index)
                if arguments.indices.contains(index) { arguments.remove(at: index) }
            }
            arguments += ["--soundtrack-source", "imported"]
            self.execute(recovery.command, extra: arguments, project: imported)
        }
    }

    func importOriginalAudio(_ file: URL?, into project: StudioProject, playback: Bool? = nil,
                             transcription: Bool? = nil, replaceExisting: Bool = false,
                             completion: ((StudioProject?) -> Void)? = nil) {
        guard !busy else { return }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("audio-inspection-\(UUID()).json")
        var arguments = ["--output", output.path]
        if let file { arguments += ["--input", file.path] }
        execute("inspect-original-audio", extra: arguments, project: project) { result in
            defer { try? FileManager.default.removeItem(at: output) }
            guard result != nil, let data = try? Data(contentsOf: output),
                  let inspection = try? JSONDecoder().decode(OriginalAudioInspection.self, from: data) else {
                completion?(nil); return
            }
            var accepted = false
            if inspection.status != "matched" {
                let alert = NSAlert()
                alert.messageText = inspection.status == "unverified" ? "Duration could not be verified" : "Audio duration does not match"
                alert.informativeText = inspection.sourceName + "\n\n" + inspection.warning
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Choose Another File")
                alert.addButton(withTitle: "Import Anyway")
                switch alert.runModal() {
                case .alertThirdButtonReturn: accepted = true
                case .alertSecondButtonReturn:
                    if let chosen = ImportFileKind.originalAudio.choose() {
                        self.importOriginalAudio(chosen, into: project, playback: playback, transcription: transcription,
                                                 replaceExisting: replaceExisting, completion: completion)
                    } else { completion?(nil) }
                    return
                default: completion?(nil); return
                }
            }
            if file != nil, project.originalAudio != nil, !replaceExisting {
                let alert = NSAlert()
                alert.messageText = "Replace imported original audio?"
                alert.informativeText = "Replace \(project.originalAudio?.sourceName ?? "the existing file") with \(inspection.sourceName)?"
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Replace")
                guard alert.runModal() == .alertSecondButtonReturn else { completion?(nil); return }
            }
            var extra: [String] = []
            extra += ["--expected-audio-sha256", inspection.sha256, "--expected-video-duration", String(inspection.videoDuration ?? 0)]
            if let file { extra += ["--input", file.path, "--replace-existing"] }
            if accepted { extra.append("--allow-audio-mismatch") }
            if let playback { extra += ["--playback-audio-source", playback ? "imported" : "youtube"] }
            if let transcription { extra += ["--transcription-audio-source", transcription ? "imported" : "youtube"] }
            self.execute(file == nil ? "confirm-original-audio" : "import-original-audio", extra: extra, project: project, completion: completion)
        }
    }
}

struct YouTubeAudioSourceControls: View {
    @Bindable var studio: StudioModel
    let project: StudioProject
    var compact = false
    var showsSection = true

    private var current: StudioProject { studio.projects.first(where: { $0.id == project.id }) ?? project }
    private var sources: AudioSourceSettings { current.audioSources ?? AudioSourceSettings() }

    var body: some View {
        if current.isYouTubeURLProject {
            ProjectAudioSourcesSection(showsSection: showsSection) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(current.originalAudio.map { "Imported audio: \($0.sourceName)" } ?? "No original audio file imported")
                        .font(.caption).textSelection(.enabled)
                    sourcePicker("Export source", key: "--soundtrack-source", value: sources.export, youtube: "Extract from YouTube when exporting")
                    sourcePicker("Playback audio", key: "--playback-audio-source", value: sources.playback, youtube: "YouTube audio")
                    sourcePicker("Transcription source", key: "--transcription-audio-source", value: sources.transcription, youtube: "YouTube video")
                    Text("Playing: \(sources.playback == "imported" ? "Imported audio: \(current.originalAudio?.sourceName ?? "Missing file")" : "YouTube audio")")
                        .font(.caption)
                    Text("AD audio available: \(current.importedAudioDescription.map { "Imported AD audio: \($0.sourceName)" } ?? "Generated narration")")
                        .font(.caption)
                    if !current.transcript.isEmpty, let source = current.transcriptAudioSource {
                        Text("Existing transcript audio: \(source.origin == "youtube" ? "YouTube video" : source.label)").font(.caption)
                    }
                    if let asset = current.originalAudio {
                        if !current.hasFile(asset.path) {
                            Label("Imported original audio is missing. Choose Audio File to repair it.", systemImage: "exclamationmark.triangle").font(.caption)
                        } else if asset.needsConfirmation(videoDuration: current.duration) {
                            Label("Audio timing needs confirmation", systemImage: "exclamationmark.triangle").font(.caption)
                            Button("Review Audio Timing…") { studio.importOriginalAudio(nil, into: current) }
                        } else if current.duration <= 0 {
                            Text("Duration could not be verified; imported with your confirmation.").font(.caption)
                        } else if abs(asset.duration - current.duration) > 0.100000001 {
                            Text("Different audio duration accepted for this video.").font(.caption)
                        } else {
                            Text("Audio duration matches the video.").font(.caption)
                        }
                    }
                    HStack {
                        Button("Choose Audio File…") {
                            if let file = ImportFileKind.originalAudio.choose() {
                                let alert = NSAlert()
                                alert.messageText = "Use imported original audio"
                                alert.informativeText = "Choose how to use \(file.lastPathComponent). Transcription can be selected separately below."
                                alert.addButton(withTitle: "Use for exports only")
                                alert.addButton(withTitle: "Use for playback and exports")
                                alert.addButton(withTitle: "Cancel")
                                let answer = alert.runModal()
                                guard answer != .alertThirdButtonReturn else { return }
                                studio.importOriginalAudio(file, into: current, playback: answer == .alertSecondButtonReturn)
                            }
                        }
                        if current.originalAudio != nil {
                            Button("Remove Selection") { studio.execute("remove-original-audio", project: current) }
                        }
                    }
                }
                .disabled(studio.busy)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func sourcePicker(_ title: String, key: String, value: String, youtube: String) -> some View {
        Picker(title, selection: Binding(get: { value }, set: { selected in
            studio.execute("set-audio-sources", extra: [key, selected], project: current)
        })) {
            Text(youtube).tag("youtube")
            if let asset = current.originalAudio {
                Text("Imported audio: \(asset.sourceName)").tag("imported")
            }
        }
        .accessibilityLabel(title)
    }
}

struct OriginalAudioImportFields: View {
    @Binding var selection: ImportAssetSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selection.originalAudio?.lastPathComponent ?? "Extract from YouTube when exporting")
                    .lineLimit(2).textSelection(.enabled)
                Spacer()
                Button("Choose Audio File…") {
                    if let file = ImportFileKind.originalAudio.choose() { selection.originalAudio = file }
                }
                if selection.originalAudio != nil {
                    Button("Remove Selection") { selection.originalAudio = nil }
                }
            }
            if selection.originalAudio != nil {
                Picker("Use original audio", selection: $selection.originalAudioPlayback) {
                    Text("Use for exports only").tag(false)
                    Text("Use for playback and exports").tag(true)
                }.pickerStyle(.radioGroup)
                Picker("Transcription source", selection: $selection.originalAudioTranscription) {
                    Text("YouTube video").tag(false)
                    Text("Chosen original audio file").tag(true)
                }.pickerStyle(.radioGroup)
                Text("Timing is checked before importing. A difference over 0.1 seconds, or an unknown video duration, requires your confirmation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProjectAudioSourcesSection<Content: View>: View {
    let showsSection: Bool
    @ViewBuilder var content: () -> Content
    var body: some View {
        if showsSection { InspectorSection("Audio sources") { content() } }
        else { content() }
    }
}
