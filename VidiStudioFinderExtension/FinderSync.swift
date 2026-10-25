import AppKit
import FinderSync

/// Adds “Describe with Vidi Studio” to the Finder context menu for supported
/// video files. The containing app receives the selected file through the same
/// `vidistudio://share` handoff used by the Share extension.
final class FinderSync: FIFinderSync {
    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "wmv",
    ]

    override init() {
        super.init()
        // Finder Sync exposes contextual menus for monitored folders. Monitoring
        // the root provides the entry across the local file system; /Volumes is
        // added explicitly because some mounted volumes are not covered by root.
        var roots: Set<URL> = [URL(fileURLWithPath: "/", isDirectory: true)]
        let volumes = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        if FileManager.default.fileExists(atPath: volumes.path) {
            roots.insert(volumes)
        }
        FIFinderSyncController.default().directoryURLs = roots
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems else { return nil }
        let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard selected.count == 1,
              let url = selected.first,
              url.isFileURL,
              Self.isSupportedVideo(url) else { return nil }

        let menu = NSMenu(title: "")
        let item = NSMenuItem(
            title: "Describe with Vidi Studio",
            action: #selector(describeSelection(_:)),
            keyEquivalent: ""
        )
        item.target = self
        if let appURL = Self.containingAppURL() {
            item.image = NSWorkspace.shared.icon(forFile: appURL.path)
        }
        menu.addItem(item)
        return menu
    }

    @objc private func describeSelection(_ sender: Any?) {
        guard let selected = FIFinderSyncController.default().selectedItemURLs(),
              selected.count == 1,
              let url = selected.first,
              Self.isSupportedVideo(url),
              let deepLink = VidiStudioShareLink.makeURL(for: .videoFile(url)),
              let appURL = Self.containingAppURL() else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.open(
            [deepLink],
            withApplicationAt: appURL,
            configuration: configuration
        ) { _, error in
            if let error {
                NSLog("VidiStudio Finder extension could not open the app: %@", error.localizedDescription)
            }
        }
    }

    private static func isSupportedVideo(_ url: URL) -> Bool {
        videoExtensions.contains(url.pathExtension.lowercased())
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
}
