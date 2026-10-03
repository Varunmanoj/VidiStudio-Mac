import SwiftUI

enum ProjectArtifactKind: CaseIterable, Identifiable {
    case transcript
    case summary
    case descriptions
    case finalVideo
    case narrationAudio

    var id: Self { self }

    var title: String {
        switch self {
        case .transcript: return "Transcript"
        case .summary: return "Summary"
        case .descriptions: return "AD"
        case .finalVideo: return "Video Export"
        case .narrationAudio: return "Audio Export"
        }
    }

    var glyph: String {
        switch self {
        case .transcript: return "\u{e873}"
        case .summary: return "\u{f071}"
        case .descriptions: return "\u{e050}"
        case .finalVideo: return "\u{e02c}"
        case .narrationAudio: return "\u{e3a1}"
        }
    }
}

private enum ProjectArtifactAvailability {
    case generated
    case notGenerated
    case unavailable

    var badgeGlyph: String {
        switch self {
        case .generated: return "\u{e86c}"
        case .notGenerated: return "\u{e836}"
        case .unavailable: return "\u{e14b}"
        }
    }

    var color: Color {
        switch self {
        case .generated: return .green
        case .notGenerated, .unavailable: return .secondary
        }
    }
}

private struct ProjectArtifactState {
    let availability: ProjectArtifactAvailability
    let count: Int
    let accessibilityLabel: String

    init(project: StudioProject, kind: ProjectArtifactKind) {
        switch kind {
        case .transcript:
            count = project.hasGeneratedTranscript ? 1 : 0
            availability = count > 0 ? .generated : .notGenerated
            accessibilityLabel = count > 0 ? "Transcript generated" : "Transcript not generated"
        case .summary:
            let generated = !project.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || project.summaryGenerated == true
            count = generated ? 1 : 0
            availability = generated ? .generated : .notGenerated
            accessibilityLabel = generated ? "Summary generated" : "Summary not generated"
        case .descriptions:
            let generated = !project.cues.isEmpty || project.descriptionsGenerated == true
            count = project.cues.count
            availability = generated ? .generated : .notGenerated
            accessibilityLabel = generated
                ? "Audio descriptions generated, \(count) \(count == 1 ? "segment" : "segments")"
                : "Audio descriptions not generated, 0 segments"
        case .finalVideo:
            if project.isYouTubeURLProject {
                count = 0
                availability = .unavailable
                accessibilityLabel = "Video export unavailable for YouTube projects"
            } else {
                let videoExtensions = Set(["mkv", "mp4", "mov", "m4v"])
                count = project.exports.filter { videoExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }.count
                availability = count > 0 ? .generated : .notGenerated
                accessibilityLabel = count > 0
                    ? "\(count) video \(count == 1 ? "export" : "exports") generated"
                    : "Video export not generated"
            }
        case .narrationAudio:
            let audioExtensions = Set(["m4a", "aac", "mp3", "wav"])
            count = project.exports.filter { audioExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }.count
            availability = count > 0 ? .generated : .notGenerated
            accessibilityLabel = count > 0
                ? "\(count) narration audio \(count == 1 ? "export" : "exports") generated"
                : "Narration audio export not generated"
        }
    }
}

struct ProjectArtifactStatusIcon: View {
    let project: StudioProject
    let kind: ProjectArtifactKind
    var showsCount = false

    private var state: ProjectArtifactState {
        ProjectArtifactState(project: project, kind: kind)
    }

    var body: some View {
        HStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                MaterialIcon(glyph: kind.glyph, size: 19)
                    .foregroundStyle(state.availability == .generated ? .primary : .secondary)
                MaterialIcon(glyph: state.availability.badgeGlyph, size: 10)
                    .foregroundStyle(state.availability.color)
                    .padding(1)
                    .background(.background, in: Circle())
                    .offset(x: 4, y: 3)
            }
            .frame(width: 26, height: 23)
            if showsCount, state.count > 0 {
                Text(state.count, format: .number)
                    .font(.caption.monospacedDigit())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
        .help(state.accessibilityLabel)
    }
}

struct ProjectArtifactStatusRow: View {
    let project: StudioProject

    var body: some View {
        HStack(spacing: 9) {
            ForEach(ProjectArtifactKind.allCases) { kind in
                ProjectArtifactStatusIcon(project: project, kind: kind)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension StudioProject {
    var projectBrowserAccessibilityLabel: String {
        ProjectArtifactKind.allCases
            .map { ProjectArtifactState(project: self, kind: $0).accessibilityLabel }
            .joined(separator: ", ")
    }
}

/// Project source kinds matching the New Project dialog's Video File / YouTube
/// Video options, reusing the same SF Symbols so sources read identically
/// across creation, browsing, and filtering.
enum ProjectSourceFilter: String, CaseIterable, Identifiable {
    case all
    case local
    case youtube

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All"
        case .local: return "Video File"
        case .youtube: return "YouTube"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .all: return "All Projects"
        case .local: return "Local Video Projects"
        case .youtube: return "YouTube Projects"
        }
    }

    var iconName: String {
        switch self {
        case .all: return "square.stack"
        case .local: return "film"
        case .youtube: return "play.rectangle"
        }
    }

    func matches(_ project: StudioProject) -> Bool {
        switch self {
        case .all: return true
        case .local: return !project.isYouTubeURLProject
        case .youtube: return project.isYouTubeURLProject
        }
    }
}

extension StudioProject {
    /// SF Symbol shared with the New Project dialog's source picker.
    var sourceIconName: String {
        isYouTubeURLProject ? ProjectSourceFilter.youtube.iconName : ProjectSourceFilter.local.iconName
    }

    var sourceTitle: String {
        isYouTubeURLProject ? "YouTube Video" : "Video File"
    }
}
