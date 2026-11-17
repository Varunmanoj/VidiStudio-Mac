import Foundation

enum VidiStudioSharedSource: Equatable {
    case youtube(URL)
    case videoFile(URL)
}

enum VidiStudioShareLink {
    static let scheme = "vidistudio"
    private static let host = "share"

    static func makeURL(for source: VidiStudioSharedSource) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host

        switch source {
        case .youtube(let url):
            guard youtubeVideoID(from: url.absoluteString) != nil else { return nil }
            components.queryItems = [
                URLQueryItem(name: "kind", value: "youtube"),
                URLQueryItem(name: "source", value: url.absoluteString),
            ]
        case .videoFile(let url):
            guard url.isFileURL else { return nil }
            components.queryItems = [
                URLQueryItem(name: "kind", value: "video"),
                URLQueryItem(name: "source", value: url.absoluteString),
            ]
        }
        return components.url
    }

    static func parse(_ url: URL) -> VidiStudioSharedSource? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let kind = components.queryItems?.first(where: { $0.name == "kind" })?.value,
              let sourceValue = components.queryItems?.first(where: { $0.name == "source" })?.value,
              let sourceURL = URL(string: sourceValue) else { return nil }

        switch kind {
        case "youtube":
            guard youtubeVideoID(from: sourceURL.absoluteString) != nil else { return nil }
            return .youtube(sourceURL)
        case "video":
            guard sourceURL.isFileURL else { return nil }
            return .videoFile(sourceURL)
        default:
            return nil
        }
    }

    static func youtubeVideoID(from rawURL: String) -> String? {
        guard let components = URLComponents(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.user == nil, components.password == nil,
              let host = components.host?.lowercased() else { return nil }

        var path = components.percentEncodedPath
        if path.hasSuffix("/") { path.removeLast() }
        let pathParts = path.components(separatedBy: "/").dropFirst()
        let identifier: String?
        switch host {
        case "youtu.be", "www.youtu.be":
            identifier = pathParts.count == 1 ? pathParts.first : nil
        case "youtube.com", "www.youtube.com", "m.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com":
            if components.percentEncodedPath == "/watch" {
                identifier = components.queryItems?.first(where: { $0.name == "v" })?.value
            } else if pathParts.count == 2, ["shorts", "embed", "live"].contains(pathParts.first ?? "") {
                identifier = pathParts.last
            } else {
                identifier = nil
            }
        default:
            identifier = nil
        }

        let permitted = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard let identifier,
              identifier.count == 11,
              identifier.unicodeScalars.allSatisfy({ permitted.contains($0) }) else { return nil }
        return identifier
    }
}
