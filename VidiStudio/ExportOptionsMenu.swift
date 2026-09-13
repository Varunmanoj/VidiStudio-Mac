import SwiftUI

enum StudioExportAction: Hashable {
    case selectableVideo
    case mixedVideo
    case closedCaptionVideo(content: String)
    case openCaptionVideo(content: String)
    case narrationAudio
    case text(content: String, format: String)

    var command: String {
        switch self {
        case .selectableVideo: return "export-closed-audio-description-video"
        case .mixedVideo: return "export-open-audio-description-video"
        case .closedCaptionVideo: return "export-closed-caption-video"
        case .openCaptionVideo: return "export-open-caption-video"
        case .narrationAudio: return "export-audio"
        case .text: return "export-subtitles"
        }
    }

    var arguments: [String] {
        switch self {
        case .closedCaptionVideo(let content), .openCaptionVideo(let content):
            return ["--content", content]
        case .text(let content, let format):
            return ["--content", content, "--format", format]
        default:
            return []
        }
    }
}

struct ExportMenuContent: View {
    let supportsVideo: Bool
    let canPerform: (StudioExportAction) -> Bool
    let perform: (StudioExportAction) -> Void

    private let textTypes: [(title: String, content: String, formats: [String])] = [
        ("Transcript", "transcript", ["srt", "vtt", "txt", "json"]),
        ("Summary", "summary", ["md"]),
        ("Descriptions", "descriptions", ["srt", "vtt", "txt", "json"]),
        ("Combined", "combined", ["srt", "vtt", "txt", "json"]),
    ]

    var body: some View {
        if supportsVideo {
            Menu("Video", systemImage: "film") {
                Button("Closed Audio Description", systemImage: "switch.2") {
                    perform(.selectableVideo)
                }
                .disabled(!canPerform(.selectableVideo))
                Button("Open Audio Description", systemImage: "speaker.wave.3") {
                    perform(.mixedVideo)
                }
                .disabled(!canPerform(.mixedVideo))
                Divider()
                Menu("Closed Captions", systemImage: "captions.bubble") {
                    Button("Transcript", systemImage: "text.bubble") {
                        perform(.closedCaptionVideo(content: "transcript"))
                    }
                    .disabled(!canPerform(.closedCaptionVideo(content: "transcript")))
                    Button("AD Transcript", systemImage: "text.quote") {
                        perform(.closedCaptionVideo(content: "combined"))
                    }
                    .disabled(!canPerform(.closedCaptionVideo(content: "combined")))
                }
                Menu("Open Captions", systemImage: "captions.bubble.fill") {
                    Button("Transcript", systemImage: "text.bubble") {
                        perform(.openCaptionVideo(content: "transcript"))
                    }
                    .disabled(!canPerform(.openCaptionVideo(content: "transcript")))
                    Button("AD Transcript", systemImage: "text.quote") {
                        perform(.openCaptionVideo(content: "combined"))
                    }
                    .disabled(!canPerform(.openCaptionVideo(content: "combined")))
                }
            }
        }
        Menu("Audio", systemImage: "waveform") {
            Button("Narration Audio", systemImage: "square.and.arrow.up") {
                perform(.narrationAudio)
            }
            .disabled(!canPerform(.narrationAudio))
        }
        Menu("Text", systemImage: "doc.text") {
            ForEach(textTypes, id: \.content) { type in
                Menu(type.title, systemImage: "doc.text") {
                    ForEach(type.formats, id: \.self) { format in
                        let action = StudioExportAction.text(content: type.content, format: format)
                        Button(format == "md" ? "Markdown" : format.uppercased(), systemImage: "doc") {
                            perform(action)
                        }
                        .disabled(!canPerform(action))
                    }
                }
            }
        }
    }
}

struct ProjectExportMenu: View {
    let project: StudioProject
    let busy: Bool
    let perform: (StudioExportAction) -> Void

    var body: some View {
        Menu("Export", systemImage: "square.and.arrow.up") {
            ExportMenuContent(
                supportsVideo: !project.isYouTubeURLProject,
                canPerform: { action in
                    guard !busy else { return false }
                    switch action {
                    case .selectableVideo, .mixedVideo:
                        return !project.isYouTubeURLProject && !project.source.isEmpty
                    case .closedCaptionVideo(let content), .openCaptionVideo(let content):
                        return !project.isYouTubeURLProject && !project.source.isEmpty && project.canExportText(content)
                    case .narrationAudio:
                        return project.hasExportableNarration()
                    case .text(let content, _):
                        return project.canExportText(content)
                    }
                },
                perform: perform
            )
        }
        .disabled(busy)
    }
}
