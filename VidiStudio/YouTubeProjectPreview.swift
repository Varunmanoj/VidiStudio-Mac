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
        var metadataComponents = URLComponents(string: "https://www.youtube.com/oembed")!
        metadataComponents.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "url", value: canonicalURL),
        ]
        guard let metadataURL = metadataComponents.url else {
            throw YouTubeProjectPreviewError.invalidURL
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let metadataRequest: URLRequest = {
            var request = URLRequest(url: metadataURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            return request
        }()
        let thumbnailRequest: URLRequest = {
            var request = URLRequest(
                url: URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")!
            )
            request.cachePolicy = .reloadIgnoringLocalCacheData
            return request
        }()

        async let metadataResponse = session.data(for: metadataRequest)
        async let thumbnailResponse = session.data(for: thumbnailRequest)
        let (metadataResult, thumbnailResult) = try await (metadataResponse, thumbnailResponse)

        guard let metadataResponse = metadataResult.1 as? HTTPURLResponse,
              (200..<300).contains(metadataResponse.statusCode),
              let metadata = try? JSONDecoder().decode(YouTubeOEmbedMetadata.self, from: metadataResult.0),
              !metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw YouTubeProjectPreviewError.detailsUnavailable
        }
        let thumbnailData = thumbnailResult.0
        guard let thumbnailResponse = thumbnailResult.1 as? HTTPURLResponse,
              (200..<300).contains(thumbnailResponse.statusCode),
              thumbnailResponse.mimeType == "image/jpeg",
              thumbnailData.count <= 5 * 1024 * 1024,
              thumbnailData.starts(with: [0xFF, 0xD8, 0xFF]),
              let thumbnail = NSImage(data: thumbnailData) else {
            throw YouTubeProjectPreviewError.thumbnailUnavailable
        }

        return YouTubeProjectPreview(
            videoID: videoID,
            canonicalURL: canonicalURL,
            title: metadata.title.trimmingCharacters(in: .whitespacesAndNewlines),
            thumbnail: thumbnail
        )
    }
}
