import SwiftUI

enum VideoCaptionOption: Hashable {
    case none
    case closed(content: String)
    case open(content: String)

    var arguments: [String] {
        switch self {
        case .none:
            return []
        case .closed(let content):
            return ["--captions", "closed", "--content", content]
        case .open(let content):
            return ["--captions", "open", "--content", content]
        }
    }

    var requiredContent: String? {
        switch self {
        case .none:
            return nil
        case .closed(let content), .open(let content):
            return content
        }
    }
}

enum StudioExportAction: Hashable {
    case selectableVideo(captions: VideoCaptionOption)
    case mixedVideo(captions: VideoCaptionOption)
    case closedCaptionVideo(content: String)
    case openCaptionVideo(content: String)
    case originalAudio
    case describedAudio
    case narrationAudio
    case text(content: String, format: String)

    var command: String {
        switch self {
        case .selectableVideo: return "export-closed-audio-description-video"
        case .mixedVideo: return "export-open-audio-description-video"
        case .closedCaptionVideo: return "export-closed-caption-video"
        case .openCaptionVideo: return "export-open-caption-video"
        case .originalAudio: return "export-original-audio"
        case .describedAudio: return "export-described-audio"
        case .narrationAudio: return "export-audio"
        case .text: return "export-subtitles"
        }
    }

    var arguments: [String] {
        switch self {
        case .selectableVideo(let captions), .mixedVideo(let captions):
            return captions.arguments
        case .closedCaptionVideo(let content), .openCaptionVideo(let content):
            return ["--content", content]
        case .text(let content, let format):
            return ["--content", content, "--format", format]
        default:
            return []
        }
    }
}

private enum ExportCategory: String, CaseIterable, Identifiable {
    case video
    case audio
    case text

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .video: return "film"
        case .audio: return "waveform"
        case .text: return "doc.text"
        }
    }
}

private enum VideoAudioChoice: String, CaseIterable, Identifiable {
    case original
    case closedDescription
    case openDescription

    var id: Self { self }
    var title: String {
        switch self {
        case .original: return "Original Audio Only"
        case .closedDescription: return "Closed Audio Description"
        case .openDescription: return "Open Audio Description"
        }
    }
}

private enum VideoTranscriptChoice: String, CaseIterable, Identifiable {
    case none
    case transcriptClosed
    case transcriptOpen
    case adTranscriptClosed
    case adTranscriptOpen

    var id: Self { self }
    var title: String {
        switch self {
        case .none: return "No Transcript"
        case .transcriptClosed: return "Transcript — Closed Captions"
        case .transcriptOpen: return "Transcript — Open Captions"
        case .adTranscriptClosed: return "AD Transcript — Closed Captions"
        case .adTranscriptOpen: return "AD Transcript — Open Captions"
        }
    }
    var content: String? {
        switch self {
        case .none: return nil
        case .transcriptClosed, .transcriptOpen: return "transcript"
        case .adTranscriptClosed, .adTranscriptOpen: return "combined"
        }
    }
    var captions: VideoCaptionOption {
        switch self {
        case .none: return .none
        case .transcriptClosed: return .closed(content: "transcript")
        case .transcriptOpen: return .open(content: "transcript")
        case .adTranscriptClosed: return .closed(content: "combined")
        case .adTranscriptOpen: return .open(content: "combined")
        }
    }
}

private enum AudioExportChoice: String, CaseIterable, Identifiable {
    case original
    case described
    case narration

    var id: Self { self }
    var title: String {
        switch self {
        case .original: return "Original Video Audio — MP3"
        case .described: return "Final Audio with Audio Description — MP3"
        case .narration: return "Narration Audio Only — M4A"
        }
    }
    var action: StudioExportAction {
        switch self {
        case .original: return .originalAudio
        case .described: return .describedAudio
        case .narration: return .narrationAudio
        }
    }
}

struct ExportDialog: View {
    @Environment(\.dismiss) private var dismiss
    let project: StudioProject
    let busy: Bool
    let perform: (StudioExportAction) -> Void
    @State private var category: ExportCategory
    @State private var videoAudio = VideoAudioChoice.closedDescription
    @State private var videoTranscript = VideoTranscriptChoice.none
    @State private var audioChoice: AudioExportChoice
    @State private var textContent: String
    @State private var textFormat: String

    private let textTypes: [(title: String, content: String)] = [
        ("Transcript", "transcript"),
        ("Summary", "summary"),
        ("Descriptions", "descriptions"),
        ("Combined", "combined"),
    ]

    init(project: StudioProject, busy: Bool, perform: @escaping (StudioExportAction) -> Void) {
        self.project = project
        self.busy = busy
        self.perform = perform
        let firstText = ["transcript", "summary", "descriptions", "combined"]
            .first(where: project.canExportText) ?? "transcript"
        _category = State(initialValue: project.isYouTubeURLProject
            ? (project.hasExportableNarration() ? .audio : .text)
            : .video)
        _audioChoice = State(initialValue: project.isYouTubeURLProject ? .narration : .described)
        _textContent = State(initialValue: firstText)
        _textFormat = State(initialValue: firstText == "summary" ? "md" : "srt")
    }

    private var availableCategories: [ExportCategory] {
        project.isYouTubeURLProject ? [.audio, .text] : ExportCategory.allCases
    }

    private var textFormats: [String] {
        textContent == "summary" ? ["md"] : ["srt", "vtt", "txt", "json"]
    }

    private var selectedAction: StudioExportAction? {
        switch category {
        case .video:
            switch videoAudio {
            case .original:
                switch videoTranscript.captions {
                case .none: return nil
                case .closed(let content): return .closedCaptionVideo(content: content)
                case .open(let content): return .openCaptionVideo(content: content)
                }
            case .closedDescription:
                return .selectableVideo(captions: videoTranscript.captions)
            case .openDescription:
                return .mixedVideo(captions: videoTranscript.captions)
            }
        case .audio:
            return audioChoice.action
        case .text:
            return .text(content: textContent, format: textFormat)
        }
    }

    private var canSave: Bool {
        guard !busy, let selectedAction else { return false }
        return canPerform(selectedAction)
    }

    var body: some View {
        NavigationSplitView {
            List(availableCategories, selection: $category) { option in
                Label(option.title, systemImage: option.icon)
                    .tag(option)
            }
            .listStyle(.sidebar)
            .navigationTitle("Export")
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 210)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.title)
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(project.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)
                Form {
                    switch category {
                    case .video:
                        Section("Audio") {
                            Picker("Audio included in the video", selection: $videoAudio) {
                                ForEach(VideoAudioChoice.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                            .pickerStyle(.radioGroup)
                        }
                        Section("Transcript and Captions") {
                            Picker("Transcript included in the video", selection: $videoTranscript) {
                                ForEach(VideoTranscriptChoice.allCases) { option in
                                    Text(option.title)
                                        .tag(option)
                                        .disabled(option.content.map(project.canExportText) == false)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            if videoAudio == .original && videoTranscript == .none {
                                Label("Choose Audio Description or a transcript to create an accessible video export.", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    case .audio:
                        Section("Audio") {
                            Picker("Audio to save", selection: $audioChoice) {
                                ForEach(AudioExportChoice.allCases) { option in
                                    Text(option.title)
                                        .tag(option)
                                        .disabled(!canPerform(option.action))
                                }
                            }
                            .pickerStyle(.radioGroup)
                            Text(audioChoice == .original
                                ? "Exports the video's original soundtrack without Audio Description."
                                : audioChoice == .described
                                    ? "Exports the final program soundtrack with synchronized Audio Description mixed in."
                                    : "Exports only synchronized Audio Description narration, with silence between segments.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    case .text:
                        Section("Text Content") {
                            Picker("Content", selection: $textContent) {
                                ForEach(textTypes, id: \.content) { option in
                                    Text(option.title)
                                        .tag(option.content)
                                        .disabled(!project.canExportText(option.content))
                                }
                            }
                            Picker("Format", selection: $textFormat) {
                                ForEach(textFormats, id: \.self) { format in
                                    Text(format == "md" ? "Markdown" : format.uppercased()).tag(format)
                                }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                Divider()
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Save", systemImage: "square.and.arrow.down") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                }
                .padding(20)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 760, height: 560)
        .onChange(of: textContent) {
            if !textFormats.contains(textFormat) {
                textFormat = textFormats[0]
            }
        }
    }

    private func canPerform(_ action: StudioExportAction) -> Bool {
        switch action {
        case .selectableVideo(let captions), .mixedVideo(let captions):
            guard !project.isYouTubeURLProject, !project.source.isEmpty else { return false }
            return captions.requiredContent.map(project.canExportText) ?? true
        case .closedCaptionVideo(let content), .openCaptionVideo(let content):
            return !project.isYouTubeURLProject && !project.source.isEmpty && project.canExportText(content)
        case .originalAudio:
            return !project.isYouTubeURLProject && !project.source.isEmpty && project.hasAudio
        case .describedAudio:
            return !project.isYouTubeURLProject && !project.source.isEmpty
        case .narrationAudio:
            return project.hasExportableNarration()
        case .text(let content, _):
            return project.canExportText(content)
        }
    }

    private func save() {
        guard canSave, let selectedAction else { return }
        dismiss()
        perform(selectedAction)
    }
}

struct ProjectExportButton: View {
    let project: StudioProject
    let busy: Bool
    let showDialog: () -> Void

    var body: some View {
        Button("Export…", systemImage: "square.and.arrow.up", action: showDialog)
        .disabled(busy)
        .help("Choose video, audio, or text export options for \(project.name)")
    }
}
