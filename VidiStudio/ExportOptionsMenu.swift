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
    case selectableVideo(captions: VideoCaptionOption, format: String)
    case mixedVideo(captions: VideoCaptionOption, format: String)
    case closedCaptionVideo(content: String, format: String)
    case dualClosedCaptionVideo(format: String)
    case openCaptionVideo(content: String, format: String)
    case originalAudio(format: String)
    case describedAudio(format: String)
    case youtubeOriginalAudio(format: String)
    case youtubeDescribedAudio(format: String)
    case narrationAudio(format: String)
    case text(content: String, format: String)
    case webPlayback(audio: String, captions: VideoCaptionOption)

    var command: String {
        switch self {
        case .selectableVideo: return "export-closed-audio-description-video"
        case .mixedVideo: return "export-open-audio-description-video"
        case .closedCaptionVideo: return "export-closed-caption-video"
        case .dualClosedCaptionVideo: return "export-dual-closed-caption-video"
        case .openCaptionVideo: return "export-open-caption-video"
        case .originalAudio: return "export-original-audio"
        case .describedAudio: return "export-described-audio"
        case .youtubeOriginalAudio: return "export-youtube-original-audio"
        case .youtubeDescribedAudio: return "export-youtube-described-audio"
        case .narrationAudio: return "export-audio"
        case .text: return "export-subtitles"
        case .webPlayback: return "export-hls"
        }
    }

    var arguments: [String] {
        switch self {
        case .selectableVideo(let captions, let format), .mixedVideo(let captions, let format):
            return captions.arguments + ["--media-format", format]
        case .closedCaptionVideo(let content, let format), .openCaptionVideo(let content, let format):
            return ["--content", content, "--media-format", format]
        case .dualClosedCaptionVideo(let format), .originalAudio(let format), .describedAudio(let format),
             .youtubeOriginalAudio(let format), .youtubeDescribedAudio(let format), .narrationAudio(let format):
            return ["--media-format", format]
        case .text(let content, let format):
            return ["--content", content, "--format", format]
        case .webPlayback(let audio, let captions):
            return ["--web-audio", audio] + captions.arguments
        }
    }

    func arguments(replacingExisting: Bool) -> [String] {
        arguments + (replacingExisting ? ["--replace-existing"] : [])
    }

    func targetRelativePath(for project: StudioProject) -> String {
        let descriptor: (type: String, extension: String)
        switch self {
        case .selectableVideo(let captions, let format):
            descriptor = ("Closed Audio Description" + captions.exportTypeSuffix, format)
        case .mixedVideo(let captions, let format):
            descriptor = ("Open Audio Description" + captions.exportTypeSuffix, format)
        case .closedCaptionVideo(let content, let format):
            descriptor = ("\(content == "combined" ? "AD Transcript" : "Transcript") Closed Caption Video", format)
        case .dualClosedCaptionVideo(let format):
            descriptor = ("Transcript and Descriptive Transcript Closed Caption Video", format)
        case .openCaptionVideo(let content, let format):
            descriptor = ("\(content == "combined" ? "AD Transcript" : "Transcript") Open Caption Video", format)
        case .originalAudio(let format):
            descriptor = ("Original Video Audio", format)
        case .describedAudio(let format):
            descriptor = ("Final Audio with Audio Description", format)
        case .youtubeOriginalAudio(let format):
            descriptor = ("YouTube Audio Only", format)
        case .youtubeDescribedAudio(let format):
            descriptor = ("YouTube Studio Audio Description", format)
        case .narrationAudio(let format):
            descriptor = ("Narration Audio", format)
        case .text(let content, let format):
            let type = [
                "transcript": "Transcript",
                "summary": "Summary",
                "descriptions": "Descriptions",
                "combined": "AD Transcript",
            ][content] ?? "Text"
            descriptor = (type, format)
        case .webPlayback(let audio, let captions):
            let audioName = [
                "original": "Original Audio",
                "closed-description": "Closed Audio Description",
                "open-description": "Open Audio Description",
            ][audio] ?? "Audio"
            let folderName = Self.portableProjectName(project.name)
                + " - Web Playback - " + audioName + captions.exportTypeSuffix
            return "exports/\(folderName)"
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
    case webPlayback

    var id: Self { self }
    var title: String {
        switch self {
        case .webPlayback: return "Web Playback"
        default: return rawValue.capitalized
        }
    }
    var icon: String {
        switch self {
        case .video: return "film"
        case .audio: return "waveform"
        case .text: return "doc.text"
        case .webPlayback: return "globe"
        }
    }

    static func resolve(path: String) -> Self {
        let fileExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        if ["mkv", "mp4", "mov", "m4v"].contains(fileExtension) { return .video }
        if ["m4a", "aac", "mp3", "wav"].contains(fileExtension) { return .audio }
        if fileExtension.isEmpty { return .webPlayback }
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
    var webArgument: String {
        switch self {
        case .original: return "original"
        case .closedDescription: return "closed-description"
        case .openDescription: return "open-description"
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
    case youtubeOriginal
    case youtubeDescribed
    case narration

    var id: Self { self }
    var title: String {
        switch self {
        case .original: return "Original Video Audio"
        case .described: return "Final Audio with Audio Description"
        case .youtubeOriginal: return "YouTube Audio Only"
        case .youtubeDescribed: return "YouTube Audio with Narration"
        case .narration: return "Narration Audio Only"
        }
    }
    func action(format: String) -> StudioExportAction {
        switch self {
        case .original: return .originalAudio(format: format)
        case .described: return .describedAudio(format: format)
        case .youtubeOriginal: return .youtubeOriginalAudio(format: format)
        case .youtubeDescribed: return .youtubeDescribedAudio(format: format)
        case .narration: return .narrationAudio(format: format)
        }
    }
}

struct ExportDialog: View {
    @Environment(\.dismiss) private var dismiss
    let project: StudioProject
    let busy: Bool
    let perform: (StudioExportAction, Bool) -> Void
    @State private var category: ExportCategory
    @State private var videoFormat = "mkv"
    @State private var audioFormat = "wav"
    @State private var videoAudio = VideoAudioChoice.closedDescription
    @State private var videoTranscript = VideoTranscriptChoice.none
    @State private var audioChoice: AudioExportChoice
    @State private var textContent: String
    @State private var textFormat: String
    @State private var webAudio = VideoAudioChoice.closedDescription
    @State private var webTranscript = VideoTranscriptChoice.none
    @State private var replacementAction: StudioExportAction?
    @State private var openCaptionAction: StudioExportAction?

    private let textTypes: [(title: String, content: String)] = [
        ("Transcript", "transcript"),
        ("Summary", "summary"),
        ("Descriptions", "descriptions"),
        ("AD Transcript", "combined"),
    ]

    init(project: StudioProject, busy: Bool, perform: @escaping (StudioExportAction, Bool) -> Void) {
        self.project = project
        self.busy = busy
        self.perform = perform
        let firstText = ["transcript", "summary", "descriptions", "combined"]
            .first(where: project.canExportText) ?? "transcript"
        _category = State(initialValue: project.isYouTubeURLProject ? .audio : .video)
        let narrationReady = project.hasCompleteExportNarration()
        _videoAudio = State(initialValue: narrationReady ? .closedDescription : .original)
        _webAudio = State(initialValue: narrationReady ? .closedDescription : .original)
        _videoTranscript = State(initialValue: !narrationReady && project.canExportText("transcript") ? .transcriptClosed : .none)
        _audioChoice = State(initialValue: project.isYouTubeURLProject ? .youtubeOriginal : narrationReady ? .described : .original)
        _textContent = State(initialValue: firstText)
        _textFormat = State(initialValue: firstText == "summary" ? "md" : "srt")
        _replacementAction = State(initialValue: nil)
        _openCaptionAction = State(initialValue: nil)
    }

    private var availableCategories: [ExportCategory] {
        project.isYouTubeURLProject ? [.audio, .text] : ExportCategory.allCases
    }

    private var audioChoices: [AudioExportChoice] {
        project.isYouTubeURLProject ? [.youtubeOriginal, .narration, .youtubeDescribed] : [.original, .described, .narration]
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
                case .closed(let content): return .closedCaptionVideo(content: content, format: videoFormat)
                case .open(let content): return .openCaptionVideo(content: content, format: videoFormat)
                case .dualClosed: return .dualClosedCaptionVideo(format: videoFormat)
                }
            case .closedDescription:
                return .selectableVideo(captions: videoTranscript.captions, format: videoFormat)
            case .openDescription:
                return .mixedVideo(captions: videoTranscript.captions, format: videoFormat)
            }
        case .audio:
            return audioChoice.action(format: audioFormat)
        case .text:
            return .text(content: textContent, format: textFormat)
        case .webPlayback:
            return .webPlayback(audio: webAudio.webArgument, captions: webTranscript.captions)
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
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 230)
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
                        Section {
                            Picker("Format", selection: $videoFormat) {
                                ForEach(["mkv", "mp4", "mov", "m4v"], id: \.self) { format in
                                    Text(format.uppercased()).tag(format)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        Section("Audio") {
                            ExportRadioGroup(
                                title: "Audio included in the video",
                                options: VideoAudioChoice.allCases.map { option in
                                    (option, option.title, canUseVideoAudio(option))
                                },
                                selection: $videoAudio
                            )
                        }
                        Section("Transcript and Captions") {
                            ExportRadioGroup(
                                title: "Transcript included in the video",
                                options: VideoTranscriptChoice.allCases.map { option in
                                    (option, option.title, option.requiredContents.allSatisfy(project.canExportText) && (option != .none || videoAudio != .original))
                                },
                                selection: $videoTranscript
                            )
                        }
                    case .audio:
                        Section {
                            Picker("Format", selection: $audioFormat) {
                                ForEach(["wav", "mp3", "m4a"], id: \.self) { format in
                                    Text(format.uppercased()).tag(format)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        Section("Audio") {
                            ExportRadioGroup(
                                title: "Audio to save",
                                options: audioChoices.map { option in
                                    (option, option.title, canPerform(option.action(format: audioFormat)))
                                },
                                selection: $audioChoice
                            )
                        }
                    case .text:
                        Section("Text Content") {
                            ExportRadioGroup(
                                title: "Content",
                                options: textTypes.map { option in
                                    (option.content, option.title, project.canExportText(option.content))
                                },
                                selection: $textContent
                            )
                            Picker("Format", selection: $textFormat) {
                                ForEach(textFormats, id: \.self) { format in
                                    Text(format == "md" ? "Markdown" : format.uppercased()).tag(format)
                                }
                            }
                        }
                    case .webPlayback:
                        Section("Audio") {
                            ExportRadioGroup(
                                title: "Audio included in Web Playback",
                                options: VideoAudioChoice.allCases.map { option in
                                    (option, option.title, canUseVideoAudio(option))
                                },
                                selection: $webAudio
                            )
                        }
                        Section("Transcript and Captions") {
                            ExportRadioGroup(
                                title: "Transcript included in Web Playback",
                                options: VideoTranscriptChoice.allCases.map { option in
                                    (option, option.title, option.requiredContents.allSatisfy(project.canExportText))
                                },
                                selection: $webTranscript
                            )
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
        .frame(width: 800, height: 560)
        .smoothPresentation()
        .onChange(of: textContent) {
            if !textFormats.contains(textFormat) {
                textFormat = textFormats[0]
            }
        }
        .alert(
            "Open Captions May Change Video Quality",
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
            if category == .webPlayback {
                Text("Open captions become a permanent part of every adaptive Web Playback video rendition. Closed captions remain selectable and let each viewer turn them on or off. Choose Export with Open Captions only when the words must always appear in the picture.")
            } else {
                Text("Open captions become a permanent part of the picture, so VidiStudio must create a new copy of the video. It keeps the same picture size and preserves HDR where possible, but some original quality or iPhone Dolby Vision information may change. For the closest match to the original, use closed captions instead.")
            }
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
                guard !busy, canPerform(action) else { return }
                dismiss()
                perform(action, true)
            }
        } message: { action in
            Text("\(URL(fileURLWithPath: action.targetRelativePath(for: project)).lastPathComponent) already exists. Replacing it permanently deletes the current export and saves the new one in its place.")
        }
    }

    private func canUseVideoAudio(_ choice: VideoAudioChoice) -> Bool {
        guard !project.isYouTubeURLProject, project.hasFile(project.source) else { return false }
        return choice == .original || project.hasCompleteExportNarration()
    }

    private func canPerform(_ action: StudioExportAction) -> Bool {
        switch action {
        case .selectableVideo(let captions, _), .mixedVideo(let captions, _):
            guard canUseVideoAudio(.closedDescription) else { return false }
            return captions.requiredContents.allSatisfy(project.canExportText)
        case .closedCaptionVideo(let content, _), .openCaptionVideo(let content, _):
            return !project.isYouTubeURLProject && project.hasFile(project.source) && project.canExportText(content)
        case .dualClosedCaptionVideo:
            return !project.isYouTubeURLProject
                && project.hasFile(project.source)
                && project.canExportText("transcript")
                && project.canExportText("combined")
        case .originalAudio:
            return !project.isYouTubeURLProject && project.hasFile(project.source) && project.hasAudio
        case .describedAudio:
            return canUseVideoAudio(.closedDescription)
        case .youtubeOriginalAudio:
            return project.isYouTubeURLProject
        case .youtubeDescribedAudio:
            return project.isYouTubeURLProject && project.hasCompleteExportNarration()
        case .narrationAudio:
            return project.hasCompleteExportNarration()
        case .text(let content, _):
            return project.canExportText(content)
        case .webPlayback(let audio, let captions):
            let choice: VideoAudioChoice = audio == "original" ? .original : .closedDescription
            guard canUseVideoAudio(choice) else { return false }
            return captions.requiredContents.allSatisfy(project.canExportText)
        }
    }

    private func save() {
        guard canSave, let selectedAction else { return }
        let selectedTranscript = category == .webPlayback ? webTranscript : videoTranscript
        if (category == .video || category == .webPlayback) && selectedTranscript.rendersIntoVideo {
            openCaptionAction = selectedAction
            return
        }
        continueSaving(selectedAction)
    }

    private func continueSaving(_ action: StudioExportAction) {
        guard !busy, canPerform(action) else { return }
        let relative = action.targetRelativePath(for: project)
        if let target = project.url(relative), FileManager.default.fileExists(atPath: target.path) {
            replacementAction = action
            return
        }
        dismiss()
        perform(action, false)
    }

    private func preferClosedCaptions() {
        if category == .webPlayback {
            switch webTranscript {
            case .transcriptOpen: webTranscript = .transcriptClosed
            case .adTranscriptOpen: webTranscript = .adTranscriptClosed
            default: break
            }
        } else {
            switch videoTranscript {
            case .transcriptOpen: videoTranscript = .transcriptClosed
            case .adTranscriptOpen: videoTranscript = .adTranscriptClosed
            default: break
            }
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

struct ActiveExportProgressView: View {
    private var registry = ExportSessionRegistry.shared

    var body: some View {
        VStack(spacing: 0) {
            ForEach(registry.sessions) { ExportProgressBanner(activity: $0) }
        }
    }
}

struct ExportProgressBanner: View {
    let activity: ExportSession

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .accessibilityLabel("Export in progress")
                .accessibilityValue(activity.projectName)

            VStack(alignment: .leading, spacing: 2) {
                Text("Exporting \(activity.projectName)…")
                    .font(.headline)
                    .lineLimit(1)
                Text(activity.cancelling ? "Stopping the export…" : activity.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack {
                    ProgressView(value: activity.fraction)
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Export progress for \(activity.projectName)")
                    if let fraction = activity.fraction {
                        Text("\(Int(fraction * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 12)

            Button(activity.cancelling ? "Cancelling…" : "Cancel Export", action: activity.cancel)
                .disabled(activity.cancelling || !activity.canCancel)
                .fixedSize()
                .accessibilityHint("Stops the current export. Finished exports already saved remain available.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }
}
