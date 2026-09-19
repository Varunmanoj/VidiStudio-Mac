import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: NSViewController {
    private let statusLabel = NSTextField(labelWithString: "Sending to VidiStudio…")
    private let progressIndicator = NSProgressIndicator()
    private var hasStarted = false

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 150))
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .regular
        progressIndicator.startAnimation(nil)

        statusLabel.alignment = .center
        statusLabel.maximumNumberOfLines = 3
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.setAccessibilityLabel("Sending shared video to VidiStudio")

        let stack = NSStackView(views: [progressIndicator, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
        ])
        view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !hasStarted else { return }
        hasStarted = true
        Task { await sendSharedItem() }
    }

    private func sendSharedItem() async {
        do {
            let source = try await SharedItemResolver.resolve(extensionContext?.inputItems ?? [])
            guard let deepLink = VidiStudioShareLink.makeURL(for: source) else {
                throw ShareExtensionError.unsupportedItem
            }
            guard let extensionContext else { throw ShareExtensionError.unavailableContext }

            try openInContainingApp(deepLink, extensionContext: extensionContext)
        } catch {
            showError(error)
        }
    }

    private func openInContainingApp(_ deepLink: URL, extensionContext: NSExtensionContext) throws {
        guard let containingAppURL = Self.containingAppURL() else {
            throw ShareExtensionError.couldNotLocateVidiStudio
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        let completion = WorkspaceOpenCompletion(
            viewController: self,
            extensionContext: extensionContext
        )

        // A macOS Share extension is not permitted to open its containing app through
        // NSExtensionContext. Target the containing bundle explicitly through Launch
        // Services so the URL is delivered to VidiStudio's onOpenURL handler.
        NSWorkspace.shared.open(
            [deepLink],
            withApplicationAt: containingAppURL,
            configuration: configuration
        ) { runningApplication, error in
            completion.finish(
                opened: runningApplication != nil && error == nil,
                errorDescription: error?.localizedDescription
            )
        }
    }

    @MainActor
    private final class WorkspaceOpenCompletion: @unchecked Sendable {
        private weak var viewController: ShareViewController?
        private let extensionContext: NSExtensionContext

        init(viewController: ShareViewController, extensionContext: NSExtensionContext) {
            self.viewController = viewController
            self.extensionContext = extensionContext
        }

        nonisolated func finish(opened: Bool, errorDescription: String?) {
            Task { @MainActor in
                guard let viewController else { return }
                if opened {
                    extensionContext.completeRequest(returningItems: nil)
                } else {
                    viewController.showError(
                        ShareExtensionError.couldNotOpenVidiStudio(errorDescription)
                    )
                }
            }
        }
    }

    private static func containingAppURL() -> URL? {
        let extensionBundleURL = Bundle.main.bundleURL.standardizedFileURL
        guard extensionBundleURL.pathExtension == "appex" else { return nil }

        let candidate = extensionBundleURL
            .deletingLastPathComponent() // PlugIns
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // VidiStudio.app
        guard candidate.pathExtension == "app",
              FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }

    private func showError(_ error: Error) {
        let message: String
        if let shareError = error as? ShareExtensionError {
            message = shareError.errorDescription ?? "VidiStudio could not receive this item. Open VidiStudio and try sharing again."
        } else {
            NSLog("VidiStudio Share internal error: %@", error.localizedDescription)
            message = "VidiStudio could not receive this item. Open VidiStudio and try sharing again."
        }
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        statusLabel.stringValue = message
        statusLabel.setAccessibilityLabel(message)

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeExtension))
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\r"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            closeButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
        ])
        NSAccessibility.post(element: statusLabel, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    @objc private func closeExtension() {
        extensionContext?.cancelRequest(withError: ShareExtensionError.cancelled)
    }
}

private enum ShareExtensionError: LocalizedError {
    case unavailableContext
    case unsupportedItem
    case notYouTube
    case couldNotLocateVidiStudio
    case couldNotOpenVidiStudio(String?)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailableContext:
            return "VidiStudio could not receive the shared item. Close the Share window and try again."
        case .unsupportedItem:
            return "Share one local video file or a YouTube video page with VidiStudio."
        case .notYouTube:
            return "This web page is not a supported YouTube video link."
        case .couldNotLocateVidiStudio:
            return "The VidiStudio app could not be located. Reinstall VidiStudio, then try sharing again."
        case .couldNotOpenVidiStudio(let detail):
            if let detail, !detail.isEmpty {
                NSLog("VidiStudio Share could not open the app: %@", detail)
            }
            return "VidiStudio could not open. Open the app from Applications, then try sharing again."
        case .cancelled:
            return "Sharing to VidiStudio was cancelled."
        }
    }
}

private enum SharedItemResolver {
    static func resolve(_ inputItems: [Any]) async throws -> VidiStudioSharedSource {
        let providers = inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }

        for provider in providers {
            if let fileURL = await loadURL(from: provider, typeIdentifiers: [
                UTType.movie.identifier,
                UTType.video.identifier,
                UTType.fileURL.identifier,
            ]), fileURL.isFileURL, isMovie(fileURL) {
                return .videoFile(fileURL)
            }
        }

        for provider in providers {
            if let webURL = await loadURL(from: provider, typeIdentifiers: [UTType.url.identifier]),
               ["http", "https"].contains(webURL.scheme?.lowercased() ?? "") {
                guard VidiStudioShareLink.youtubeVideoID(from: webURL.absoluteString) != nil else {
                    throw ShareExtensionError.notYouTube
                }
                return .youtube(webURL)
            }
        }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = await loadText(from: provider),
               let webURL = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
               VidiStudioShareLink.youtubeVideoID(from: webURL.absoluteString) != nil {
                return .youtube(webURL)
            }
        }

        throw ShareExtensionError.unsupportedItem
    }

    private static func loadURL(from provider: NSItemProvider, typeIdentifiers: [String]) async -> URL? {
        for typeIdentifier in typeIdentifiers where provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
            if let result = await loadItem(from: provider, typeIdentifier: typeIdentifier) {
                if let url = result as? URL { return url }
                if let url = result as? NSURL { return url as URL }
                if let data = result as? Data,
                   let string = String(data: data, encoding: .utf8),
                   let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return url
                }
                if let string = result as? String, let url = URL(string: string) { return url }
            }
        }
        return nil
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        guard let result = await loadItem(from: provider, typeIdentifier: UTType.plainText.identifier) else { return nil }
        if let string = result as? String { return string }
        if let attributed = result as? NSAttributedString { return attributed.string }
        if let data = result as? Data { return String(data: data, encoding: .utf8) }
        return nil
    }

    private static func loadItem(from provider: NSItemProvider, typeIdentifier: String) async -> NSSecureCoding? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    private static func isMovie(_ url: URL) -> Bool {
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           contentType.conforms(to: .movie) || contentType.conforms(to: .video) {
            return true
        }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .video)
    }
}
