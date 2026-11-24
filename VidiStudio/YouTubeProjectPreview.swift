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
    case detailsUnavailable
    case thumbnailUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid YouTube video link."
        case .detailsUnavailable:
            return "VidiStudio could not fetch this video's name. Check the link and your internet connection."
        case .thumbnailUnavailable:
            return "VidiStudio found the video but could not fetch its thumbnail. Please try again."
        }
    }
}

@MainActor
enum YouTubeProjectPreviewFetcher {
    static func fetch(_ rawURL: String) async throws -> YouTubeProjectPreview {
        guard let videoID = StudioModel.youtubeVideoID(from: rawURL) else {
            throw YouTubeProjectPreviewError.invalidURL
        }
        let video = try await YouTubeService.shared.video(videoID)
        try video.requireAvailable()
        guard let thumbnailURL = URL(string: video.thumbnailURL) else { throw YouTubeProjectPreviewError.thumbnailUnavailable }
        let (data, _) = try await URLSession.shared.data(from: thumbnailURL)
        let thumbnail = NSImage(data: data) ?? NSImage(systemSymbolName: "film", accessibilityDescription: "Video")!
        return YouTubeProjectPreview(video: video, thumbnail: thumbnail)
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
