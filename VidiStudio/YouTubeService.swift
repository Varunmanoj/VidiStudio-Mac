import AppKit
import CryptoKit
import Foundation
import Network

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
    var playlists: [YouTubePlaylist]?
    var openedFromPlaylist: YouTubePlaylist?
    var playlistChannelTitle: String?
    var playlistLookupStatus: String?
    var id: String { videoID }
    var url: String { "https://www.youtube.com/watch?v=\(videoID)" }
    var durationLabel: String { NarrationTimeFormat.timestamp(duration) }
    var publishedLabel: String {
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (parser.date(from: publishedAt) ?? ISO8601DateFormatter().date(from: publishedAt))?.formatted(date: .abbreviated, time: .omitted) ?? publishedAt
    }
    var detail: String { "\(visibility.capitalized) · \(durationLabel) · \(channelTitle)" }
    func requireAvailable() throws {
        if visibility == "private" { throw YouTubeFailure("Private Video Cannot Be Opened. Signing in to Google does not give Gemini access to this private video. Choose a public or unlisted video, or import your original local video.") }
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
struct YouTubePlaylist: Codable, Hashable, Identifiable {
    let id: String; let title: String; let description: String; let visibility: String; let count: Int?; let publishedAt: String
}
struct YouTubeCaption: Identifiable {
    let id: String; let language: String; let name: String; let kind: String; let status: String
    var label: String { "\(language) · \(name.isEmpty ? (kind == "ASR" ? "Automatic" : "Standard") : name) · \(status)" }
}
struct YouTubeConnection: Codable, Identifiable, Hashable {
    let id: String; let subject: String; let name: String; let email: String; let photo: String
    let channelID: String; let channelName: String; let channelPhoto: String; let uploads: String
    var label: String { "\(name) · \(channelName)" }
}
struct YouTubeFailure: LocalizedError {
    let message: String
    var httpStatus: Int?
    var accessExpired: Bool
    init(_ message: String, accessExpired: Bool = false, httpStatus: Int? = nil) { self.message = message; self.accessExpired = accessExpired; self.httpStatus = httpStatus }
    var errorDescription: String? { message }
}
struct YouTubeReleaseConfiguration: Decodable {
    var apiKey = ""; var clientID = ""; var clientSecret = ""
    static func load() -> Self {
        guard let url = Bundle.main.url(forResource: "youtube-config", withExtension: "json"), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return value
    }
}

/// The listener exists only during sign-in and accepts only the matching OAuth state.
@MainActor final class YouTubeOAuthCallback {
    private var listener: NWListener?
    private var pending: CheckedContinuation<String, Error>?
    private let state: String
    init(state: String) { self.state = state }
    func receive(buildURL: @escaping (String) -> URL) async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                    let listener = try NWListener(using: parameters)
                    self.listener = listener
                    listener.stateUpdateHandler = { [weak self] status in
                        Task { @MainActor in
                            guard let self, self.pending != nil else { return }
                            if case .ready = status, let port = self.listener?.port {
                                NSWorkspace.shared.open(buildURL("http://127.0.0.1:\(port.rawValue)"))
                            } else if case .failed = status { self.finish(.failure(YouTubeFailure("Sign-in could not start. Try again."))) }
                        }
                    }
                    listener.newConnectionHandler = { [weak self] connection in
                        Task { @MainActor in self?.read(connection, data: Data()) }
                    }
                    listener.start(queue: .main)
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(180))
                        self?.finish(.failure(YouTubeFailure("Sign-in timed out. Try Add Account again.")))
                    }
                } catch { finish(.failure(error)) }
            }
        } onCancel: { Task { @MainActor in self.finish(.failure(CancellationError())) } }
    }
    private func read(_ connection: NWConnection, data: Data) {
        if data.isEmpty { connection.start(queue: .main) }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] chunk, _, complete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                let buffer = data + (chunk ?? Data())
                guard buffer.count <= 16384, error == nil else { connection.cancel(); return }
                guard let request = String(data: buffer, encoding: .utf8), request.contains("\r\n\r\n") else {
                    if complete { connection.cancel() } else { self.read(connection, data: buffer) }; return
                }
                let target = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                let items = URLComponents(string: "http://127.0.0.1" + target)?.queryItems ?? []
                func item(_ key: String) -> String? { items.first { $0.name == key }?.value }
                guard item("state") == self.state else { connection.cancel(); return }
                let page = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n<!doctype html><title>VidiStudio</title><p>You may close this tab and return to VidiStudio.</p>"
                connection.send(content: Data(page.utf8), completion: .contentProcessed { _ in connection.cancel() })
                if let code = item("code") { self.finish(.success(code)) }
                else { self.finish(.failure(YouTubeFailure("Google sign-in was cancelled or permission was not granted."))) }
            }
        }
    }
    private func finish(_ result: Result<String, Error>) {
        guard let pending else { return }; self.pending = nil
        listener?.cancel(); listener = nil; pending.resume(with: result)
    }
}

@MainActor @Observable final class YouTubeService {
    static let shared = YouTubeService()
    static func expireCaches(library: String) {
        guard let executable = Bundle.main.resourceURL?.appendingPathComponent("Engine/vidistudio-engine") else { return }
        let process = Process(); process.executableURL = executable
        process.arguments = ["expire-youtube-cache", "--library", library]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    var connections: [YouTubeConnection] = []
    var selectedID: String = "" { didSet { UserDefaults.standard.set(selectedID, forKey: "YouTubeSelectedConnection") } }
    var selected: YouTubeConnection? { connections.first { $0.id == selectedID } }
    var signingIn = false
    private var access: [String: (String, Date)] = [:]
    let configuration = YouTubeReleaseConfiguration.load()
    private let session = URLSession(configuration: .ephemeral)
    init() {
        if let data = UserDefaults.standard.data(forKey: "YouTubeConnections") { connections = (try? JSONDecoder().decode([YouTubeConnection].self, from: data)) ?? [] }
        selectedID = UserDefaults.standard.string(forKey: "YouTubeSelectedConnection") ?? connections.first?.id ?? ""
    }
    private func credential(_ id: String) -> KeychainCredential { .init(service: "com.vidistudio.youtube", account: id, label: "VidiStudio YouTube connection") }
    private func save() { UserDefaults.standard.set(try? JSONEncoder().encode(connections), forKey: "YouTubeConnections") }
    static func random() -> String { (0..<2).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "") }.joined() }
    static func form(_ values: [String: String]) -> Data {
        var components = URLComponents(); components.queryItems = values.map { .init(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    }
    private func token(_ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(fields)
        let (data, response) = try await session.data(for: request)
        if (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String == "invalid_grant" {
            throw YouTubeFailure("Google access was revoked or has expired. Sign in again from YouTube Accounts.", accessExpired: true)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw YouTubeFailure("Google access has expired or was denied. Sign in again from YouTube Accounts.") }
        return value
    }
    func signIn() async throws {
        guard !signingIn else { return }
        guard !configuration.clientID.isEmpty else { throw YouTubeFailure("YouTube sign-in has not been configured for this build. Contact the VidiStudio publisher.") }
        signingIn = true; defer { signingIn = false }
        let verifier = Self.random(), state = Self.random()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        var redirect = ""
        let callback = YouTubeOAuthCallback(state: state)
        let code = try await callback.receive { uri in
            redirect = uri
            var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            url.queryItems = ["client_id": self.configuration.clientID, "redirect_uri": uri, "response_type": "code", "scope": "openid email profile https://www.googleapis.com/auth/youtube.readonly https://www.googleapis.com/auth/youtube.force-ssl", "state": state, "code_challenge": challenge, "code_challenge_method": "S256", "access_type": "offline", "prompt": "consent select_account"].map { .init(name: $0.key, value: $0.value) }
            return url.url!
        }
        let result = try await token(["client_id": configuration.clientID, "client_secret": configuration.clientSecret, "code": code, "redirect_uri": redirect, "code_verifier": verifier, "grant_type": "authorization_code"])
        guard let bearer = result["access_token"] as? String, let refresh = result["refresh_token"] as? String else { throw YouTubeFailure("Google did not grant saved access. Try signing in again and allow access.") }
        let profile = try await jsonURL("https://openidconnect.googleapis.com/v1/userinfo", bearer: bearer)
        let channels = try await api("channels", ["part": "snippet,contentDetails", "mine": "true"], bearer: bearer)
        guard let subject = profile["sub"] as? String else { throw YouTubeFailure("Google profile details were unavailable.") }
        let items = channels["items"] as? [[String: Any]] ?? []
        guard !items.isEmpty else { throw YouTubeFailure("This Google account has no YouTube channel available to the API. Sign in with the channel owner.") }
        for channel in items {
            let id = channel["id"] as? String ?? "", s = channel["snippet"] as? [String: Any] ?? [:]
            let details = channel["contentDetails"] as? [String: Any] ?? [:], lists = details["relatedPlaylists"] as? [String: Any] ?? [:]
            let connectionID = subject + ":" + id
            let connection = YouTubeConnection(id: connectionID, subject: subject, name: profile["name"] as? String ?? "Google account", email: profile["email"] as? String ?? "", photo: profile["picture"] as? String ?? "", channelID: id, channelName: s["title"] as? String ?? "YouTube channel", channelPhoto: ((s["thumbnails"] as? [String: [String: Any]])?["default"]?["url"] as? String) ?? "", uploads: lists["uploads"] as? String ?? "")
            guard credential(connectionID).write(refresh) else { throw YouTubeFailure("YouTube access could not be saved securely. Try again.") }
            connections.removeAll { $0.id == connectionID }; connections.append(connection)
            access[connectionID] = (bearer, Date().addingTimeInterval(3500)); selectedID = connectionID
        }
        save()
    }
    private func bearer(_ id: String) async throws -> String {
        if let value = access[id], value.1 > Date() { return value.0 }
        guard let refresh = credential(id).read() else { throw YouTubeFailure("Sign in to this YouTube account again.") }
        let result: [String: Any]
        do { result = try await token(["client_id": configuration.clientID, "client_secret": configuration.clientSecret, "refresh_token": refresh, "grant_type": "refresh_token"]) }
        catch let error as YouTubeFailure where error.accessExpired {
            if let subject = connections.first(where: { $0.id == id })?.subject {
                for connection in connections.filter({ $0.subject == subject }) { signOut(connection.id) }
            }
            throw error
        }
        guard let token = result["access_token"] as? String else { throw YouTubeFailure("Sign in to this YouTube account again.") }
        guard connections.contains(where: { $0.id == id }) else { throw CancellationError() }
        access[id] = (token, Date().addingTimeInterval(max(0, (result["expires_in"] as? Double ?? 3600) - 60)))
        return token
    }
    func signOut(_ id: String) { credential(id).delete(); access[id] = nil; connections.removeAll { $0.id == id }; if selectedID == id { selectedID = connections.first?.id ?? "" }; save() }
    func disconnect(_ connection: YouTubeConnection) async throws {
        guard let refresh = credential(connection.id).read() else { signOut(connection.id); return }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!); request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); request.httpBody = Self.form(["token": refresh])
        let (_, response) = try await session.data(for: request)
        guard [200, 400].contains((response as? HTTPURLResponse)?.statusCode ?? 0) else { throw YouTubeFailure("Google access could not be disconnected. Try again online.") }
        for value in connections.filter({ $0.subject == connection.subject }) { signOut(value.id) }
    }
    private func jsonURL(_ url: String, bearer: String?) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!); request.timeoutInterval = 30
        if let bearer { request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw YouTubeFailure("YouTube did not respond. Try again.") }
        guard (200..<300).contains(status) else {
            let reason = (((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? [String: Any])?["errors"] as? [[String: Any]]
            let code = reason?.first?["reason"] as? String ?? ""
            if ["quotaExceeded", "dailyLimitExceeded"].contains(code) { throw YouTubeFailure("VidiStudio’s YouTube allowance has been reached. Try again later.") }
            if status == 404 { throw YouTubeFailure("YouTube information was not found.", httpStatus: 404) }
            if status == 401 { throw YouTubeFailure("Google access has expired. Sign in again from YouTube Accounts.") }
            if status == 403 { throw YouTubeFailure("YouTube did not allow this request. Check that the selected account can access or edit this video and has granted the requested permission.") }
            throw YouTubeFailure("YouTube information is unavailable. Check your connection, video, and account permissions.")
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
    private func api(_ path: String, _ query: [String: String], bearer: String?) async throws -> [String: Any] {
        var query = query
        if bearer == nil {
            guard !configuration.apiKey.isEmpty else { throw YouTubeFailure("YouTube video details have not been configured for this build. Contact the VidiStudio publisher.") }; query["key"] = configuration.apiKey
        }
        var url = URLComponents(string: "https://www.googleapis.com/youtube/v3/" + path)!
        url.queryItems = query.map { .init(name: $0.key, value: $0.value) }
        return try await jsonURL(url.url!.absoluteString, bearer: bearer)
    }
    func video(_ id: String, connectionID: String? = nil) async throws -> YouTubeVideo {
        let connection = connectionID ?? selected?.id
        let token = try await connection.mapAsync { try await self.bearer($0) }
        let result = try await api("videos", ["part": "snippet,contentDetails,status,statistics", "id": id], bearer: token)
        guard let item = (result["items"] as? [[String: Any]])?.first else { throw YouTubeFailure("This video is unavailable. It may be private, deleted, or inaccessible to this account.") }
        return .parse(item)
    }
    func videos(playlist: String, page: String, connectionID: String) async throws -> ([YouTubeVideo], String) {
        let token = try await bearer(connectionID)
        let result = try await api("playlistItems", ["part": "contentDetails", "playlistId": playlist, "maxResults": "50", "pageToken": page], bearer: token)
        let ids = (result["items"] as? [[String: Any]] ?? []).compactMap { ($0["contentDetails"] as? [String: Any])?["videoId"] as? String }
        if ids.isEmpty { return ([], result["nextPageToken"] as? String ?? "") }
        let details = try await api("videos", ["part": "snippet,contentDetails,status,statistics", "id": ids.joined(separator: ",")], bearer: token)
        let videos = (details["items"] as? [[String: Any]] ?? []).map(YouTubeVideo.parse)
        return (ids.compactMap { id in videos.first { $0.id == id } }, result["nextPageToken"] as? String ?? "")
    }
    func playlists(page: String, connectionID: String) async throws -> ([YouTubePlaylist], String) {
        let result = try await api("playlists", ["part": "snippet,contentDetails,status", "mine": "true", "maxResults": "50", "pageToken": page], bearer: try await bearer(connectionID))
        return ((result["items"] as? [[String: Any]] ?? []).map { value in
            let s = value["snippet"] as? [String: Any] ?? [:]
            return .init(id: value["id"] as? String ?? "", title: s["title"] as? String ?? "Playlist", description: s["description"] as? String ?? "", visibility: (value["status"] as? [String: Any])?["privacyStatus"] as? String ?? "unknown", count: (value["contentDetails"] as? [String: Any])?["itemCount"] as? Int, publishedAt: s["publishedAt"] as? String ?? "")
        }, result["nextPageToken"] as? String ?? "")
    }
    func videoWithPlaylists(_ id: String) async throws -> YouTubeVideo {
        let connection = selected
        var video = try await self.video(id, connectionID: connection?.id)
        try video.requireAvailable()
        video.playlists = []
        guard let connection else { video.playlistLookupStatus = "Sign in and refresh to load playlists for your channel."; return video }
        video.playlistChannelTitle = connection.channelName
        var page = ""
        do {
            repeat {
                try Task.checkCancellation()
                guard selectedID == connection.id else { throw CancellationError() }
                let (lists, next) = try await playlists(page: page, connectionID: connection.id)
                for list in lists {
                    try Task.checkCancellation()
                    do {
                        let result = try await api("playlistItems", ["part": "id", "playlistId": list.id, "videoId": id, "maxResults": "1"], bearer: try await bearer(connection.id))
                        if !(result["items"] as? [[String: Any]] ?? []).isEmpty { video.playlists?.append(list) }
                    } catch let error as YouTubeFailure where error.httpStatus == 404 { continue }
                }
                page = next
            } while !page.isEmpty
            video.playlistLookupStatus = "Playlists returned for the connected channel."
        } catch is CancellationError { throw CancellationError() }
        catch { video.playlistLookupStatus = "Some playlist information could not be loaded. Use Refresh YouTube Details to try again." }
        guard selectedID == connection.id else { throw CancellationError() }
        return video
    }
    func captions(videoID: String, connectionID: String) async throws -> [YouTubeCaption] {
        let result = try await api("captions", ["part": "snippet", "videoId": videoID], bearer: try await bearer(connectionID))
        return (result["items"] as? [[String: Any]] ?? []).map { value in
            let s = value["snippet"] as? [String: Any] ?? [:]
            return .init(id: value["id"] as? String ?? "", language: s["language"] as? String ?? "Unknown", name: s["name"] as? String ?? "", kind: s["trackKind"] as? String ?? "standard", status: s["status"] as? String ?? "unknown")
        }
    }
    func download(_ caption: YouTubeCaption, connectionID: String) async throws -> Data {
        var url = URLComponents(string: "https://www.googleapis.com/youtube/v3/captions/" + caption.id)!
        url.queryItems = [.init(name: "tfmt", value: "srt")]
        var request = URLRequest(url: url.url!); request.setValue("Bearer " + (try await bearer(connectionID)), forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 20 * 1024 * 1024 else { throw YouTubeFailure("This caption track could not be downloaded. The selected account must have permission to edit the video.") }
        return data
    }
}
private extension Optional where Wrapped == String {
    func mapAsync<T>(_ transform: (String) async throws -> T) async rethrows -> T? { if let self { return try await transform(self) }; return nil }
}
