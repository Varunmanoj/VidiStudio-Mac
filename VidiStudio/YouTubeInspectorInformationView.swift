import SwiftUI
import Accessibility

struct YouTubeInspectorInformationView: View {
    @Bindable var studio: StudioModel
    let project: StudioProject
    @State private var refreshing = false
    @State private var issue: String?
    @State private var request: Task<Void, Never>?
    var body: some View {
        InspectorSection("YouTube Information") {
            VStack(alignment: .leading, spacing: 8) {
                if let video = project.youtubeMetadata {
                    row("YouTube title", video.title)
                    row("Channel", video.channelTitle)
                    row("Visibility", video.visibility.capitalized)
                    InspectorInformationRow(label: "Duration", value: video.durationLabel, spokenValue: video.spokenDuration)
                    row("Published", date(video.publishedAt))
                    row("Views", video.viewCount ?? "Unavailable")
                    row("Likes", video.likeCount ?? "Unavailable")
                    row("Comments", video.commentCount ?? "Unavailable")
                    row("Captions", video.captionsAvailable ? "Available" : "Not reported")
                    row("Language", language(video.language))
                    row("Audio language", language(video.audioLanguage))
                    row("Category", video.categoryID ?? "Unavailable")
                    row("Embedding", video.embeddable.map { $0 ? "Allowed" : "Not allowed" } ?? "Unavailable")
                    row("Processing", video.uploadStatus?.capitalized ?? "Unavailable")
                    row("Live status", video.liveStatus == "none" ? "Not live" : video.liveStatus?.capitalized ?? "Unavailable")
                    row("Channel ID", video.channelID)
                    row("Fetched", Date(timeIntervalSince1970: video.fetchedAt).formatted(date: .abbreviated, time: .shortened))
                    if !video.description.isEmpty { DisclosureGroup("Video description") { Text(video.description).textSelection(.enabled) } }
                    if !video.tags.isEmpty { DisclosureGroup("Tags") { Text(video.tags.joined(separator: ", ")).textSelection(.enabled) } }
                } else { Text("YouTube details have not been saved for this project yet.") }
                let source = ProjectVideoInformation.youtubeSource(for: project)
                YouTubeSourceInformationRows(videoID: source.videoID, sourceURL: source.url, identifierSuffix: "-youtube-information")
                YouTubePlaybackVideoControls(studio: studio, project: project)
                if !project.allowsOriginalAudioImport {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Choose Audio File…", systemImage: "waveform") {}.disabled(true)
                            .help("Remove the local playback video to import original audio.")
                        if project.originalAudio != nil {
                            Button("Remove Original Audio…", systemImage: "trash") { studio.removeYouTubeOriginalAudio(project) }
                                .disabled(!studio.canChangeYouTubePlaybackVideo(project))
                        }
                    }
                }
                YouTubeProjectLinkButtons(studio: studio, project: project)
                Button("Refresh YouTube Details", systemImage: "arrow.clockwise") { startRefresh() }.disabled(refreshing || studio.busy)
                if refreshing { HStack { ProgressView().controlSize(.small); Text("Fetching YouTube details…") } }
                if let issue { Text(issue).foregroundStyle(.red) }
            }.font(.caption)
        }
        .task(id: project.id) { if project.youtubeMetadata == nil && request == nil { await refresh() } }
        .onChange(of: studio.youtubeInspectorRefresh, initial: true) { _, projectID in
            guard projectID == project.id else { return }
            studio.youtubeInspectorRefresh = nil
            startRefresh()
        }
        .onDisappear { request?.cancel() }
    }
    private func row(_ label: String, _ value: String) -> some View {
        InspectorInformationRow(label: label, value: value.isEmpty ? "Unavailable" : value)
    }
    private func date(_ value: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = parser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        return parsed?.formatted(date: .abbreviated, time: .shortened) ?? (value.isEmpty ? "Unavailable" : value)
    }
    private func language(_ value: String?) -> String { value.flatMap { Locale.current.localizedString(forIdentifier: $0) } ?? value ?? "Unavailable" }
    private func startRefresh() {
        guard !refreshing, request == nil else { return }
        request = Task { await refresh(showPrivateSignInDialog: true); request = nil }
    }
    private func refresh(showPrivateSignInDialog: Bool = false) async {
        guard let id = project.youtubeURL.flatMap(StudioModel.youtubeVideoID), !refreshing else { return }
        refreshing = true; issue = nil; defer { refreshing = false }
        do {
            let value = try await YouTubeService.shared.refreshedProjectVideo(id, project: project, settings: studio.settings)
            try Task.checkCancellation()
            while studio.busy { try await Task.sleep(for: .milliseconds(100)); try Task.checkCancellation() }
            guard studio.selectedID == project.id else { return }
            studio.saveYouTubeMetadata(value, project: project)
        } catch YouTubeLinkIssue.privateRefreshSignIn {
            if showPrivateSignInDialog, !Task.isCancelled, studio.selectedID == project.id {
                refreshing = false
                studio.present(.privateYouTubeRefreshSignIn, context: "Refresh YouTube details")
            }
        } catch is CancellationError {} catch {
            issue = error.localizedDescription
            AccessibilityNotification.Announcement(error.localizedDescription).post()
        }
    }
}


struct YouTubePlaybackVideo: Codable, Equatable {
    let path: String
    let thumbnail: String
    let sourceName: String
    let duration: Double
    var useYouTubePlayer: Bool?
    var hasAudio: Bool?
    var timingAcceptedFor: Double?
}

struct YouTubeProjectLinkButtons: View {
    let studio: StudioModel
    let project: StudioProject

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { links }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) { links }
        }
        .contextMenu { links }
    }

    @ViewBuilder private var links: some View {
        Button("Open in YouTube", systemImage: "arrow.up.right.square") { studio.openYouTubeInBrowser(project) }
        if project.connectedYouTubeStudioURL != nil {
            Button("Open in YouTube Studio", systemImage: "pencil") { studio.openProjectInYouTubeStudio(project) }
        }
    }
}

struct YouTubePlaybackVideoControls: View {
    let studio: StudioModel
    let project: StudioProject
    var showSource = true
    var inProjectSettings = false
    private var imported: Bool { inProjectSettings && project.localYouTubePlaybackURL != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showSource && (!inProjectSettings || project.youtubePlaybackVideo != nil || project.originalAudio != nil) {
                HStack(alignment: .center, spacing: 8) {
                    InspectorInformationRow(label: "Local playback video", value: project.localYouTubePlaybackURL == nil
                        ? (project.youtubePlaybackVideo == nil ? (project.originalAudio == nil ? "No file selected" : "Remove the original audio file to choose a video.") : "Playback file unavailable")
                        : (project.youtubePlaybackVideo?.sourceName ?? "Local video"))
                    if project.youtubePlaybackVideo != nil {
                        removeButton.labelStyle(.iconOnly).help("Remove Local Playback Video…")
                    }
                }
            }
            chooseButton
        }
        .contextMenu {
            chooseButton
            if showSource && project.youtubePlaybackVideo != nil { removeButton }
        }
    }

    private var chooseButton: some View {
        Button {
            studio.chooseYouTubePlaybackVideo(project)
        } label: {
            HStack(spacing: 6) {
                Label(inProjectSettings && project.youtubePlaybackVideo != nil ? "Replace Local Playback Video…" : "Choose Local Playback Video…", systemImage: "film")
                if imported { Image(systemName: "checkmark").foregroundStyle(.green).accessibilityHidden(true) }
            }
        }
        .accessibilityValue(imported ? "Imported" : "")
        .disabled(!studio.canChooseYouTubePlaybackVideo(project))
    }

    private var removeButton: some View {
        Button("Remove Local Playback Video…", systemImage: "trash") {
            studio.removeYouTubePlaybackVideo(project)
        }
        .disabled(!studio.canChangeYouTubePlaybackVideo(project))
    }
}
