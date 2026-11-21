import Foundation

struct YouTubeVideo: Codable, Identifiable, Hashable {
    var videoID: String
    var title: String
    var description: String
    var channelID: String
    var channelTitle: String
    var duration: Double
    var visibility: String
    var publishedAt: String
    var thumbnailURL: String
    var captionsAvailable: Bool
    var tags: [String]
    var language: String?
    var audioLanguage: String?
    var categoryID: String?
    var embeddable: Bool?
    var uploadStatus: String?
    var liveStatus: String?
    var viewCount: String?
    var likeCount: String?
    var commentCount: String?
    var fetchedAt: Double
    var id: String { videoID }
    var url: String { "https://www.youtube.com/watch?v=\(videoID)" }
    var spokenDuration: String { NarrationTimeFormat.spokenProjectDuration(duration) }
    var spokenDetail: String { "\(visibility.capitalized), duration \(spokenDuration), \(channelTitle)" }
    var durationLabel: String { NarrationTimeFormat.projectDuration(duration) }
    var publishedLabel: String {
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (parser.date(from: publishedAt) ?? ISO8601DateFormatter().date(from: publishedAt))?.formatted(date: .abbreviated, time: .omitted) ?? publishedAt
    }
    var detail: String { "\(visibility.capitalized) · \(durationLabel) · \(channelTitle)" }
    func requireAvailable() throws {
        if visibility == "private" { throw YouTubeFailure("Private Video Cannot Be Opened. Choose a public or unlisted video, or import your original local video.") }
        if ["live", "upcoming"].contains(liveStatus ?? "") || duration <= 0 || ["failed", "rejected", "deleted", "uploaded"].contains(uploadStatus ?? "") {
            throw YouTubeFailure("This video is live, scheduled, or has not finished processing on YouTube. Try again when a completed video is available.")
        }
    }
    static func parse(_ value: [String: Any]) -> YouTubeVideo {
        let s = value["snippet"] as? [String: Any] ?? [:], c = value["contentDetails"] as? [String: Any] ?? [:]
        let status = value["status"] as? [String: Any] ?? [:], stats = value["statistics"] as? [String: Any] ?? [:]
        let thumbnails = s["thumbnails"] as? [String: [String: Any]] ?? [:]
        let raw = c["duration"] as? String ?? ""
        let regex = try! NSRegularExpression(pattern: "([0-9]+(?:\\.[0-9]+)?)([DHMS])")
        let duration = regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)).reduce(0.0) { sum, m in
            let number = Double((raw as NSString).substring(with: m.range(at: 1))) ?? 0
            let unit = (raw as NSString).substring(with: m.range(at: 2))
            return sum + number * (["D": 86400.0, "H": 3600, "M": 60, "S": 1][unit] ?? 0)
        }
        return .init(videoID: value["id"] as? String ?? "", title: s["title"] as? String ?? "Unavailable video", description: s["description"] as? String ?? "", channelID: s["channelId"] as? String ?? "", channelTitle: s["channelTitle"] as? String ?? "", duration: duration, visibility: status["privacyStatus"] as? String ?? "unknown", publishedAt: s["publishedAt"] as? String ?? "", thumbnailURL: (thumbnails["medium"] ?? thumbnails["default"])?["url"] as? String ?? "", captionsAvailable: c["caption"] as? String == "true", tags: s["tags"] as? [String] ?? [], language: s["defaultLanguage"] as? String, audioLanguage: s["defaultAudioLanguage"] as? String, categoryID: s["categoryId"] as? String, embeddable: status["embeddable"] as? Bool, uploadStatus: status["uploadStatus"] as? String, liveStatus: s["liveBroadcastContent"] as? String, viewCount: stats["viewCount"] as? String, likeCount: stats["likeCount"] as? String, commentCount: stats["commentCount"] as? String, fetchedAt: Date().timeIntervalSince1970)
    }
}
struct YouTubeFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
struct YouTubeReleaseConfiguration: Decodable {
    var apiKey = ""
    static func load() -> Self {
        guard let url = Bundle.main.url(forResource: "youtube-config", withExtension: "json"), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return value
    }
}

@MainActor final class YouTubeService {
    static let shared = YouTubeService()
    static func expireCaches(library: String) {
        guard let executable = Bundle.main.resourceURL?.appendingPathComponent("Engine/vidistudio-engine") else { return }
        let process = Process(); process.executableURL = executable
        process.arguments = ["expire-youtube-cache", "--library", library]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private let configuration = YouTubeReleaseConfiguration.load()
    private let session = URLSession(configuration: .ephemeral)

    private func jsonURL(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url); request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw YouTubeFailure("YouTube did not respond. Try again.") }
        guard (200..<300).contains(status) else {
            let reason = (((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? [String: Any])?["errors"] as? [[String: Any]]
            let code = reason?.first?["reason"] as? String ?? ""
            if ["quotaExceeded", "dailyLimitExceeded"].contains(code) { throw YouTubeFailure("VidiStudio’s YouTube allowance has been reached. Try again later.") }
            if status == 404 { throw YouTubeFailure("YouTube information was not found.") }
            if status == 403 { throw YouTubeFailure("YouTube did not allow this request. Try again with an available public or unlisted video.") }
            throw YouTubeFailure("YouTube information is unavailable. Check your connection and video.")
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
    func video(_ id: String) async throws -> YouTubeVideo {
        guard !configuration.apiKey.isEmpty else {
            throw YouTubeFailure("YouTube video details have not been configured for this build. Contact the VidiStudio publisher.")
        }
        var url = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        url.queryItems = [
            .init(name: "part", value: "snippet,contentDetails,status,statistics"),
            .init(name: "id", value: id),
            .init(name: "key", value: configuration.apiKey)
        ]
        let result = try await jsonURL(url.url!)
        guard let item = (result["items"] as? [[String: Any]])?.first else {
            throw YouTubeFailure("This video is unavailable. Use an available public or unlisted video.")
        }
        return .parse(item)
    }
}
