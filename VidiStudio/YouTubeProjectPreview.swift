import AppKit
import Foundation

struct YouTubeProjectPreview {
    let video: YouTubeVideo
    var account: YouTubeConnection?
    let thumbnail: NSImage
    var videoID: String { video.id }
    var canonicalURL: String { video.url }
    var title: String { video.title }
}

enum YouTubeProjectPreviewError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid YouTube video link."
        }
    }
}

@MainActor
enum YouTubeProjectPreviewFetcher {
    static func fetch(_ rawURL: String, settings: StudioSettings) async throws -> YouTubeProjectPreview {
        guard let videoID = StudioModel.youtubeVideoID(from: rawURL) else {
            throw YouTubeProjectPreviewError.invalidURL
        }
        let video = try await YouTubeService.shared.videoForNewProject(videoID, settings: settings)
        let service = YouTubeService.shared
        let account = video.visibility == "private"
            ? service.privateConnection(video.channelID, settings: settings)
            : service.connections.first { $0.channelID == video.channelID }
        return await selectedVideo(video, account: account)
    }

    static func selectedVideo(_ video: YouTubeVideo, account: YouTubeConnection? = nil) async -> YouTubeProjectPreview {
        let placeholder = NSImage(systemSymbolName: "film", accessibilityDescription: "Video")!
        guard let url = video.safeThumbnailURL,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let thumbnail = NSImage(data: data) else {
            return YouTubeProjectPreview(video: video, account: account, thumbnail: placeholder)
        }
        return YouTubeProjectPreview(video: video, account: account, thumbnail: thumbnail)
    }
}
