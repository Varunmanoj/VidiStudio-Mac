import Foundation
import Network
import AppKit
import SwiftUI

enum OnlineService: String, CaseIterable, Sendable {
    case gemini, youtube, voices
    var name: String { switch self { case .gemini: "Gemini"; case .youtube: "YouTube"; case .voices: "Voice downloads" } }
    var origin: URL {
        let address = switch self {
        case .gemini: "https://generativelanguage.googleapis.com/"
        case .youtube: "https://www.youtube.com/"
        case .voices: "https://huggingface.co/"
    }
        return URL(string: address)!
    }
}

enum ConnectionState: Equatable, Sendable { case checking, available, offline, unreachable }

/// One monitor for all project models/windows. A working network route alone is
/// insufficient: credential-free HTTPS checks detect a disconnected router too.
@MainActor @Observable
final class ConnectivityService {
    static let shared = ConnectivityService()
    private(set) var states: [OnlineService: ConnectionState] = [:]
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let probeRequest: @Sendable (OnlineService) async -> Bool
    @ObservationIgnored private var routeAvailable: Bool?
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    init(monitoring: Bool = true, probe: (@Sendable (OnlineService) async -> Bool)? = nil) {
        probeRequest = probe ?? { service in await Self.probe(service) }
        guard monitoring else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            let usable = path.status != .unsatisfied
            Task { @MainActor [weak self] in self?.routeChanged(usable) }
        }
        monitor.start(queue: DispatchQueue(label: "VidiStudio.Connectivity"))
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.check() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard NSApp.isActive, let self, self.states.values.contains(where: { $0 != .available }) else { return }
                self.check()
            }
        }
    }

    func state(_ service: OnlineService) -> ConnectionState { states[service] ?? .checking }
    func available(_ service: OnlineService) -> Bool { state(service) == .available }
    func reason(_ service: OnlineService) -> String? {
        switch state(service) {
        case .available: return nil
        case .checking: return "Checking the connection to \(service.name)…"
        case .offline: return "No internet connection. Connect to the internet to use \(service.name)."
        case .unreachable: return "Cannot reach \(service.name). Check your connection or try again later."
        }
    }
    var notice: String? {
        let missing = OnlineService.allCases.filter { !available($0) }
        guard !missing.isEmpty else { return nil }
        if missing.contains(where: { state($0) == .offline }) {
            return "You’re offline. Online processing and YouTube playback need internet. You can continue working with local files and installed voices."
        }
        return missing.compactMap(reason).joined(separator: " ")
    }
    func routeChanged(_ available: Bool) {
        routeAvailable = available
        generation += 1
        checkTask?.cancel(); checkTask = nil
        if !available { states = Dictionary(uniqueKeysWithValues: OnlineService.allCases.map { ($0, .offline) }) }
        else { check() }
    }
    func check() {
        guard routeAvailable != false, checkTask == nil else { return }
        generation += 1
        let token = generation
        let probe = probeRequest
        checkTask = Task { [weak self] in
            await withTaskGroup(of: (OnlineService, Bool).self) { group in
                for service in OnlineService.allCases { group.addTask { (service, await probe(service)) } }
                for await (service, reachable) in group {
                    guard let self, !Task.isCancelled, self.generation == token else { continue }
                    self.states[service] = reachable ? .available : .unreachable
                }
            }
            guard let self, self.generation == token else { return }
            self.checkTask = nil
        }
    }
    nonisolated private static func probe(_ service: OnlineService) async -> Bool {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5; config.timeoutIntervalForResource = 5
        config.httpCookieStorage = nil; config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: service.origin); request.httpMethod = "HEAD"
        do {
            let (_, response) = try await session.data(for: request)
            // An HTTP response, including 401/403/429, proves reachability. A
            // redirect to a captive-portal host does not.
            guard response is HTTPURLResponse, let host = response.url?.host else { return false }
            return OnlineRequirements.acceptsHost(host, service: service)
        } catch { return false }
    }
}

struct ConnectivityBanner: View {
    private var connection: ConnectivityService { .shared }
    var body: some View {
        Group {
            if let notice = connection.notice {
                HStack(alignment: .top) {
                Label(notice, systemImage: "wifi.exclamationmark").font(.callout).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Check Connection") { connection.check() }
            }
            .padding(12)
            .background(.orange.opacity(0.12))
                .accessibilityElement(children: .contain)
            }
        }
        .onChange(of: connection.notice) { old, new in
            guard old != new else { return }
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: new ?? "Connection restored. Online features are available.", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }
}

/// Used by buttons whose provider does not pass through StudioModel.execute.
struct OnlineActionModifier: ViewModifier {
    let service: OnlineService?
    func body(content: Content) -> some View {
        if let service, let reason = ConnectivityService.shared.reason(service) {
            content.disabled(true).help(reason).accessibilityHint(reason)
        } else { content }
    }
}
extension View {
    func requiresInternet(_ service: OnlineService?) -> some View { modifier(OnlineActionModifier(service: service)) }
}

/// Tracks actual network stages, never the local encode/mix after a download.
@MainActor
final class ConnectionRecoveryWatch {
    private var active: Set<OnlineService> = []
    private var offlineSince: Date?
    private var task: Task<Void, Never>?
    private(set) var interrupted = false
    init(gracePeriod: TimeInterval = 30, cancel: @escaping @MainActor () -> Void) {
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                let offline = self.active.contains { ConnectivityService.shared.state($0) == .offline }
                if !offline { self.offlineSince = nil; continue }
                if self.offlineSince == nil { self.offlineSince = Date() }
                if let since = self.offlineSince, Date().timeIntervalSince(since) >= gracePeriod {
                    self.interrupted = true; cancel(); return
                }
            }
        }
    }
    func consume(_ event: [String: Any]) {
        guard let name = event["networkService"] as? String,
              let service = OnlineService(rawValue: name), let active = event["networkActive"] as? Bool else { return }
        if active { self.active.insert(service) } else { self.active.remove(service) }
        if self.active.isEmpty { offlineSince = nil }
    }
    func stop() { task?.cancel(); task = nil }
}
