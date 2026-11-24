import AppKit
import Foundation

struct YouTubeProjectPreview {
    let video: YouTubeVideo
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
        return await selectedVideo(video)
    }

    static func selectedVideo(_ video: YouTubeVideo) async -> YouTubeProjectPreview {
        let placeholder = NSImage(systemSymbolName: "film", accessibilityDescription: "Video")!
        guard let url = URL(string: video.thumbnailURL), url.scheme == "https",
              let (data, _) = try? await URLSession.shared.data(from: url),
              let thumbnail = NSImage(data: data) else {
            return YouTubeProjectPreview(video: video, thumbnail: placeholder)
        }
        return YouTubeProjectPreview(video: video, thumbnail: thumbnail)
    }
}
