import SwiftUI

enum VideoCaptionOption: Hashable {
    case none
    case closed(content: String)
    case open(content: String)
    case dualClosed

    var arguments: [String] {
        switch self {
        case .none:
            return []
        case .closed(let content):
            return ["--captions", "closed", "--content", content]
        case .open(let content):
            return ["--captions", "open", "--content", content]
        case .dualClosed:
            return ["--captions", "dual-closed"]
        }
    }

    var requiredContents: [String] {
        switch self {
        case .none:
            return []
        case .closed(let content), .open(let content):
            return [content]
        case .dualClosed:
            return ["transcript", "combined"]
        }
    }

    var exportTypeSuffix: String {
        switch self {
        case .none:
            return ""
        case .closed(let content):
            return " with \(content == "combined" ? "AD Transcript" : "Transcript") Closed Captions"
        case .open(let content):
            return " with \(content == "combined" ? "AD Transcript" : "Transcript") Open Captions"
        case .dualClosed:
            return " with Transcript and Descriptive Transcript Closed Captions"
        }
    }
}

enum StudioExportAction: Hashable {
    case selectableVideo(captions: VideoCaptionOption)
    case mixedVideo(captions: VideoCaptionOption)
    case closedCaptionVideo(content: String)
    case dualClosedCaptionVideo
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
        case .dualClosedCaptionVideo: return "export-dual-closed-caption-video"
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

    func arguments(replacingExisting: Bool) -> [String] {
        arguments + (replacingExisting ? ["--replace-existing"] : [])
    }

    func targetRelativePath(for project: StudioProject) -> String {
        let descriptor: (type: String, extension: String)
        switch self {
        case .selectableVideo(let captions):
            descriptor = ("Closed Audio Description" + captions.exportTypeSuffix, "mov")
        case .mixedVideo(let captions):
            descriptor = ("Open Audio Description" + captions.exportTypeSuffix, "mp4")
        case .closedCaptionVideo(let content):
            descriptor = ("\(content == "combined" ? "AD Transcript" : "Transcript") Closed Caption Video", "mp4")
        case .dualClosedCaptionVideo:
            descriptor = ("Transcript and Descriptive Transcript Closed Caption Video", "mp4")
        case .openCaptionVideo(let content):
            descriptor = ("\(content == "combined" ? "AD Transcript" : "Transcript") Open Caption Video", "mp4")
        case .originalAudio:
            descriptor = ("Original Video Audio", "mp3")
        case .describedAudio:
            descriptor = ("Final Audio with Audio Description", "mp3")
        case .narrationAudio:
            descriptor = ("Narration Audio", "m4a")
        case .text(let content, let format):
            let type = [
                "transcript": "Transcript",
                "summary": "Summary",
                "descriptions": "Descriptions",
                "combined": "Combined Text",
            ][content] ?? "Text"
            descriptor = (type, format)
        }
        return "exports/\(Self.portableProjectName(project.name)) - \(descriptor.type).\(descriptor.extension)"
    }

    private static func portableProjectName(_ rawName: String) -> String {
        let illegal = CharacterSet(charactersIn: "<>:\"/\\|?*").union(.controlCharacters)
        var name = ""
        var replacingIllegalRun = false
        for scalar in rawName.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars {
            if illegal.contains(scalar) {
                if !replacingIllegalRun { name.append("-") }
                replacingIllegalRun = true
            } else {
                name.append(String(scalar))
                replacingIllegalRun = false
            }
        }
        name = name.replacingOccurrences(of: #"\s*-\s*"#, with: " - ", options: .regularExpression)
        name = name.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let trimming = CharacterSet(charactersIn: " .-")
        name = name.trimmingCharacters(in: trimming)
        if name.isEmpty { name = "Project" }
        name = String(name.prefix(100)).trimmingCharacters(in: trimming)
        return name.isEmpty ? "Project" : name
    }
}

enum ExportCategory: String, CaseIterable, Identifiable {
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

    static func resolve(path: String) -> Self {
        let fileExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        if ["mp4", "mov", "m4v"].contains(fileExtension) { return .video }
        if ["m4a", "aac", "mp3", "wav"].contains(fileExtension) { return .audio }
        return .text
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
    case transcriptAndDescriptiveTranscriptClosed

    var id: Self { self }
    var title: String {
        switch self {
        case .none: return "No Transcript"
        case .transcriptClosed: return "Transcript — Closed Captions"
        case .transcriptOpen: return "Transcript — Open Captions"
        case .adTranscriptClosed: return "AD Transcript — Closed Captions"
        case .adTranscriptOpen: return "AD Transcript — Open Captions"
        case .transcriptAndDescriptiveTranscriptClosed:
            return "Transcript and Descriptive Transcript — Two Closed-Caption Tracks"
        }
    }
    var requiredContents: [String] {
        switch self {
        case .none: return []
        case .transcriptClosed, .transcriptOpen: return ["transcript"]
        case .adTranscriptClosed, .adTranscriptOpen: return ["combined"]
        case .transcriptAndDescriptiveTranscriptClosed: return ["transcript", "combined"]
        }
    }
    var captions: VideoCaptionOption {
        switch self {
        case .none: return .none
        case .transcriptClosed: return .closed(content: "transcript")
        case .transcriptOpen: return .open(content: "transcript")
        case .adTranscriptClosed: return .closed(content: "combined")
        case .adTranscriptOpen: return .open(content: "combined")
        case .transcriptAndDescriptiveTranscriptClosed: return .dualClosed
        }
    }
    var rendersIntoVideo: Bool {
        switch self {
        case .transcriptOpen, .adTranscriptOpen: return true
        default: return false
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
    let perform: (StudioExportAction, Bool) -> Void
    @State private var category: ExportCategory
    @State private var videoAudio = VideoAudioChoice.closedDescription
    @State private var videoTranscript = VideoTranscriptChoice.none
    @State private var audioChoice: AudioExportChoice
    @State private var textContent: String
    @State private var textFormat: String
    @State private var replacementAction: StudioExportAction?
    @State private var openCaptionAction: StudioExportAction?

    private let textTypes: [(title: String, content: String)] = [
        ("Transcript", "transcript"),
        ("Summary", "summary"),
        ("Descriptions", "descriptions"),
        ("Combined", "combined"),
    ]

    init(project: StudioProject, busy: Bool, perform: @escaping (StudioExportAction, Bool) -> Void) {
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
        _replacementAction = State(initialValue: nil)
        _openCaptionAction = State(initialValue: nil)
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
                case .dualClosed: return .dualClosedCaptionVideo
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
                                        .disabled(!option.requiredContents.allSatisfy(project.canExportText))
                                }
                            }
                            .pickerStyle(.radioGroup)
                            if videoTranscript == .transcriptAndDescriptiveTranscriptClosed {
                                Text("Adds two switchable English tracks so viewers can choose standard captions or a descriptive transcript containing dialogue and visual descriptions.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if videoTranscript.rendersIntoVideo {
                                Label("Open captions must be rendered into the picture. VidiStudio keeps the source resolution, 10-bit depth and HDR color signaling when present, using a high-quality source-aware encode. Choose closed captions to copy the original video stream without re-encoding.", systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if !(videoAudio == .original && videoTranscript == .none) {
                                Label("The original video stream is copied without re-encoding, preserving its resolution, codec, bit depth and HDR color signaling.", systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
                    Button("Export Help", systemImage: "questionmark.circle") {
                        StudioHelp.open(anchor: "exports")
                    }
                    .labelStyle(.iconOnly)
                    .help("Open Export Help")
                    .accessibilityHint("Opens the Export your work topic in VidiStudio Help")
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
        .smoothPresentation()
        .onChange(of: textContent) {
            if !textFormats.contains(textFormat) {
                textFormat = textFormats[0]
            }
        }
        .alert(
            "Open Captions Require Video Re-Encoding",
            isPresented: Binding(
                get: { openCaptionAction != nil },
                set: { if !$0 { openCaptionAction = nil } }
            ),
            presenting: openCaptionAction
        ) { action in
            Button("Cancel", role: .cancel) {
                openCaptionAction = nil
            }
            Button("Use Closed Captions") {
                openCaptionAction = nil
                preferClosedCaptions()
            }
            .keyboardShortcut(.defaultAction)
            Button("Export with Open Captions") {
                openCaptionAction = nil
                continueSaving(action)
            }
        } message: { _ in
            let source = ProjectVideoInformation(project: project)
            Text("Open captions change the picture, so FFmpeg must re-encode the video. The source is \(source.resolution), \(source.videoCodec), with \(source.color). VidiStudio will keep the source resolution, bit depth, and HDR base color signaling, but re-encoding can change compression quality and Dolby Vision dynamic metadata cannot be preserved after pixels change. Prefer closed captions to copy the original video stream without re-encoding.")
        }
        .alert(
            "Replace Existing Export?",
            isPresented: Binding(
                get: { replacementAction != nil },
                set: { if !$0 { replacementAction = nil } }
            ),
            presenting: replacementAction
        ) { action in
            Button("Cancel", role: .cancel) {
                replacementAction = nil
            }
            Button("Replace Export", role: .destructive) {
                replacementAction = nil
                dismiss()
                perform(action, true)
            }
        } message: { action in
            Text("\(URL(fileURLWithPath: action.targetRelativePath(for: project)).lastPathComponent) already exists. Replacing it permanently deletes the current file and saves the new export in its place.")
        }
    }

    private func canPerform(_ action: StudioExportAction) -> Bool {
        switch action {
        case .selectableVideo(let captions), .mixedVideo(let captions):
            guard !project.isYouTubeURLProject, !project.source.isEmpty else { return false }
            return captions.requiredContents.allSatisfy(project.canExportText)
        case .closedCaptionVideo(let content), .openCaptionVideo(let content):
            return !project.isYouTubeURLProject && !project.source.isEmpty && project.canExportText(content)
        case .dualClosedCaptionVideo:
            return !project.isYouTubeURLProject
                && !project.source.isEmpty
                && project.canExportText("transcript")
                && project.canExportText("combined")
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
        if videoTranscript.rendersIntoVideo {
            openCaptionAction = selectedAction
            return
        }
        continueSaving(selectedAction)
    }

    private func continueSaving(_ action: StudioExportAction) {
        let relative = action.targetRelativePath(for: project)
        if let target = project.url(relative), FileManager.default.fileExists(atPath: target.path) {
            replacementAction = action
            return
        }
        dismiss()
        perform(action, false)
    }

    private func preferClosedCaptions() {
        switch videoTranscript {
        case .transcriptOpen:
            videoTranscript = .transcriptClosed
        case .adTranscriptOpen:
            videoTranscript = .adTranscriptClosed
        default:
            break
        }
    }
}

struct ProjectExportButton: View {
    let project: StudioProject
    let busy: Bool
    let showDialog: () -> Void

    var body: some View {
        Button("Export…", systemImage: "square.and.arrow.up", action: showDialog)
        .disabled(busy)
        .help("Choose video, audio, or text export options for \(project.name) (Command-Shift-E in the project editor)")
        .accessibilityHint("Opens Export options. In the project editor, you can also press Command Shift E.")
    }
}
