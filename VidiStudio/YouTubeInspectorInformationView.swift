import SwiftUI

struct YouTubeInspectorInformationView: View {
    @Bindable var studio: StudioModel
    let project: StudioProject
    @State private var fetched: YouTubeVideo?
    @State private var refreshing = false
    @State private var issue: String?
    @State private var request: Task<Void, Never>?
    private var details: YouTubeVideo? { fetched ?? project.youtubeMetadata }
    var body: some View {
        InspectorSection("YouTube Information") {
            VStack(alignment: .leading, spacing: 8) {
                if let video = details {
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
                    row("Video ID", video.videoID)
                    row("Channel ID", video.channelID)
                    row("Fetched", Date(timeIntervalSince1970: video.fetchedAt).formatted(date: .abbreviated, time: .shortened))
                    if !video.description.isEmpty { DisclosureGroup("Video description") { Text(video.description).textSelection(.enabled) } }
                    if !video.tags.isEmpty { DisclosureGroup("Tags") { Text(video.tags.joined(separator: ", ")).textSelection(.enabled) } }
                } else { Text("YouTube details have not been saved for this project yet.") }
                Button("Open in YouTube") { studio.openYouTubeInBrowser(project) }
                Button("Refresh YouTube Details") { startRefresh() }.disabled(refreshing || studio.busy)
                if refreshing { HStack { ProgressView().controlSize(.small); Text("Fetching YouTube details…") } }
                if let issue { Text(issue).foregroundStyle(.red) }
            }.font(.caption)
        }
        .task(id: project.id) { if details == nil { await refresh() } }
        .onChange(of: studio.youtubeInspectorRefresh) { _, _ in startRefresh() }
        .onChange(of: project.youtubeMetadata) { _, _ in fetched = nil }
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
    private func startRefresh() { guard !refreshing else { return }; request = Task { await refresh() } }
    private func refresh() async {
        guard let id = project.youtubeURL.flatMap(StudioModel.youtubeVideoID), !refreshing else { return }
        refreshing = true; issue = nil; defer { refreshing = false }
        do {
            let value = try await YouTubeService.shared.video(id)
            try value.requireAvailable()
            try Task.checkCancellation()
            fetched = value
            while studio.busy { try await Task.sleep(for: .milliseconds(100)); try Task.checkCancellation() }
            guard studio.selectedID == project.id else { return }
            studio.saveYouTubeMetadata(value, project: project)
        } catch is CancellationError {} catch { issue = error.localizedDescription }
    }
}
