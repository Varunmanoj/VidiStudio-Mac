import AppKit
import Foundation

struct YouTubeProjectPreview {
    let videoID: String
    let canonicalURL: String
    let title: String
    let thumbnail: NSImage
}

private struct YouTubeOEmbedMetadata: Decodable {
    let title: String
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
        let canonicalURL = "https://www.youtube.com/watch?v=\(videoID)"
        let video = try await YouTubeService.shared.video(videoID)
        try video.requireAvailable()
        guard let thumbnailURL = URL(string: video.thumbnailURL) else { throw YouTubeProjectPreviewError.thumbnailUnavailable }
        let (data, _) = try await URLSession.shared.data(from: thumbnailURL)
        let thumbnail = NSImage(data: data) ?? NSImage(systemSymbolName: "film", accessibilityDescription: "Video")!
        return YouTubeProjectPreview(videoID: videoID, canonicalURL: canonicalURL, title: video.title, thumbnail: thumbnail)
    }
}
