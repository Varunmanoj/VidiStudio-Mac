import AppKit
import SwiftUI

@MainActor struct YouTubeDetailsView: View {
    @Bindable var studio: StudioModel
    let project: StudioProject
    @State private var video: YouTubeVideo?
    @State private var error: String?
    @State private var loading = false
    @State private var deletingData = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YouTube Details").font(.title2).accessibilityAddTraits(.isHeader).accessibilityHeading(.h1)
            if let v = video {
                Text(v.title).font(.headline); Text(v.detail).accessibilityLabel(v.spokenDetail); Text(v.description)
                Text("Published: \(v.publishedAt)\nViews: \(v.viewCount ?? "Unavailable") · Likes: \(v.likeCount ?? "Unavailable") · Comments: \(v.commentCount ?? "Unavailable")\nLanguage: \(v.language ?? "Unavailable") · Audio language: \(v.audioLanguage ?? "Unavailable")\nCategory: \(v.categoryID ?? "Unavailable") · Embedding: \(v.embeddable.map { $0 ? "Allowed" : "Not allowed" } ?? "Unavailable")\nProcessing: \(v.uploadStatus ?? "Unavailable") · Live status: \(v.liveStatus ?? "Unavailable")\nTags: \(v.tags.joined(separator: ", "))").textSelection(.enabled)
            }
            Button("Refresh Details") { Task { await refresh() } }.disabled(loading)
            if loading { ProgressView("Loading YouTube information") }
            if let error { Text(error).foregroundStyle(.red) }
            Button("Delete Stored YouTube Data…", role: .destructive) { deletingData = true }.disabled(studio.busy)
        }.padding().frame(minWidth: 650)
        .confirmationDialog("Delete stored YouTube data for this project?", isPresented: $deletingData, titleVisibility: .visible) {
            Button("Delete Stored YouTube Data", role: .destructive) { studio.execute("clear-youtube-data", project: project); video = nil }
        } message: { Text("Removes fetched details, downloaded caption copies, imported YouTube caption rows (including edits to those rows), and transcript history. Other manually created transcript rows remain. Nothing is deleted on YouTube.") }
        .task { await refresh() }
    }
    private func refresh() async {
        guard let url = project.youtubeURL, let id = StudioModel.youtubeVideoID(from: url) else { return }
        loading = true; error = nil; defer { loading = false }
        do { let value = try await YouTubeService.shared.video(id); video = value; try value.requireAvailable(); studio.saveYouTubeMetadata(value, project: project) }
        catch { self.error = error.localizedDescription }
    }
}

extension StudioProject {
    var youtubeWatchURL: URL? {
        guard let id = youtubeURL.flatMap(StudioModel.youtubeVideoID) else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(id)")
    }
}
extension StudioModel {
    func openYouTubeInBrowser(_ project: StudioProject) {
        guard let url = project.youtubeWatchURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openYouTubeVideo(_ video: YouTubeVideo, completion: @escaping (StudioProject?) -> Void) {
        do {
            try video.requireAvailable()
            if let existing = existingProject(forYouTubeURL: video.url) { selectedID = existing.id; completion(existing); return }
            let metadata = try temporaryYouTubeFile(try JSONEncoder().encode(video), extension: "json")
            execute("import-youtube", extra: ["--url", video.url, "--library", settings.libraryPath, "--youtube-metadata", metadata.path], cleanupURL: metadata, completion: completion)
        } catch { self.error = error.localizedDescription; completion(nil) }
    }
    func temporaryYouTubeFile(_ data: Data, extension suffix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-youtube-\(UUID().uuidString).\(suffix)")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }
    func saveYouTubeMetadata(_ video: YouTubeVideo, project: StudioProject) {
        guard !busy else { return }
        do {
            let file = try temporaryYouTubeFile(try JSONEncoder().encode(video), extension: "json")
            execute("update-youtube-metadata", extra: ["--youtube-metadata", file.path], project: project, cleanupURL: file)
        } catch { self.error = error.localizedDescription }
    }
}
