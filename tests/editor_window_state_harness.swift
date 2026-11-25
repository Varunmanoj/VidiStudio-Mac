import AppKit
import ApplicationServices

private struct CheckFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure(message) }
}

private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

private func frame(_ window: AXUIElement) -> CGRect? {
    guard let position = attribute(window, "AXPosition"), let dimensions = attribute(window, "AXSize") else { return nil }
    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
          AXValueGetValue(dimensions as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: point, size: size)
}

private func place(_ window: AXUIElement, at target: CGRect) {
    // Move inward before growing and shrink before moving outward. Otherwise an
    // intermediate off-display frame can be clamped by the window manager.
    let current = frame(window) ?? target
    var point = CGPoint(x: min(current.minX, target.minX), y: min(current.minY, target.minY))
    var size = target.size
    if let value = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(window, "AXPosition" as CFString, value) }
    Thread.sleep(forTimeInterval: 0.15)
    if let value = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, "AXSize" as CFString, value) }
    Thread.sleep(forTimeInterval: 0.2)
    point = target.origin
    if let value = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(window, "AXPosition" as CFString, value) }
}

private func setMinimized(_ window: AXUIElement, _ minimized: Bool) {
    AXUIElementSetAttributeValue(window, "AXMinimized" as CFString, minimized ? kCFBooleanTrue : kCFBooleanFalse)
}

private func equals(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
    abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance &&
    abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
}

private func waitUntil<T>(_ value: () -> T?) -> T? {
    let deadline = Date().addingTimeInterval(8)
    repeat {
        if let result = value() { return result }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return nil
}

@MainActor
private func verify() throws {
    try require(CommandLine.arguments.count == 2, "Supply a saved local test project folder from the installed app’s library.")
    let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("project.json")))
    guard let project = manifest as? [String: Any],
          let name = project["name"] as? String, !name.isEmpty,
          (project["youtubeURL"] as? String ?? "").isEmpty,
          let source = project["source"] as? String, !source.isEmpty,
          let handoff = VidiStudioShareLink.makeURL(for: .videoFile(folder.appendingPathComponent(source))) else {
        throw CheckFailure("The test requires a saved local-video project with its source file.")
    }
    try require(FileManager.default.fileExists(atPath: folder.appendingPathComponent(source).path), "The test project’s source file is missing.")
    try require(AXIsProcessTrusted(), "macOS Accessibility access is required to inspect and move the installed windows.")
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "Varunmanojkumar.VidiStudio")
    guard apps.count == 1, let app = apps.first, app.bundleURL?.path == "/Applications/VidiStudio.app" else {
        throw CheckFailure("Open the single installed /Applications/VidiStudio.app before running the test.")
    }
    func windows() -> [AXUIElement] {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 2)
        return attribute(root, "AXWindows") as? [AXUIElement] ?? []
    }
    func title(_ window: AXUIElement) -> String { attribute(window, "AXTitle") as? String ?? "" }
    func libraryWindows() -> [AXUIElement] { windows().filter { title($0) == "All Projects" } }
    func editors() -> [AXUIElement] { windows().filter { title($0).hasPrefix(name + " — ") } }
    func close(_ editor: AXUIElement) {
        if let button = attribute(editor, "AXCloseButton") {
            AXUIElementPerformAction(button as! AXUIElement, "AXPress" as CFString)
        }
    }
    _ = app.activate(options: [])
    guard let gallery = waitUntil({ libraryWindows().first }),
          let primary = NSScreen.screens.first else { throw CheckFailure("All Projects and an active display are required.") }
    try require(editors().isEmpty, "Close only the designated test project’s editor before running the test.")
    let wasMinimized = attribute(gallery, "AXMinimized") as? Bool == true
    if wasMinimized { setMinimized(gallery, false) }
    guard let original = waitUntil({ frame(gallery) }) else { throw CheckFailure("Cannot read the All Projects window geometry.") }
    defer {
        editors().forEach(close)
        if let current = libraryWindows().first {
            setMinimized(current, false)
            place(current, at: original)
            if wasMinimized { setMinimized(current, true) }
        }
    }
    let workAreas = NSScreen.screens.map { screen -> CGRect in
        let available = screen.visibleFrame
        return CGRect(x: available.minX, y: primary.frame.maxY - available.maxY,
                      width: available.width, height: available.height)
    }
    guard let workArea = workAreas.first(where: { $0.contains(CGPoint(x: original.midX, y: original.midY)) }) else {
        throw CheckFailure("The normal library window must be on an active display.")
    }
    // Size differs horizontally, so the test also works on shorter displays where
    // the library's minimum height (including the title bar) is near the work area.
    let normal = workArea.insetBy(dx: min(80, (workArea.width - 780) / 4), dy: 0)
    try require(!equals(normal, workArea) && workArea.contains(normal), "The display is too small to distinguish normal and maximized bounds.")

    for state in ["normal", "maximized", "minimized"] {
        guard let gallery = libraryWindows().first else { throw CheckFailure("All Projects is no longer available.") }
        // Mac’s equivalent of maximizing here is filling the work area without full screen.
        let target = state == "normal" ? normal : workArea
        place(gallery, at: target)
        guard let baseline = waitUntil({ frame(gallery).flatMap { equals($0, target) ? $0 : nil } }) else {
            throw CheckFailure("Cannot set All Projects to \(target) for the \(state) test. Actual bounds \(String(describing: frame(gallery))).")
        }
        let minimized = state == "minimized"
        if minimized { setMinimized(gallery, true) }
        try require(waitUntil({ (attribute(gallery, "AXMinimized") as? Bool == true) == minimized ? true : nil }) != nil,
                    "Could not put All Projects in the \(state) state.")

        // A real handoff reaches the editor when the library is minimized and cannot receive clicks.
        // It resolves to the designated test project, so no new media or project is imported.
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", "-a", "/Applications/VidiStudio.app", handoff.absoluteString]
        try open.run()
        open.waitUntilExit()
        try require(open.terminationStatus == 0, "The project handoff did not launch.")
        guard let editor = waitUntil({ editors().first }),
              let bounds = waitUntil({ editors().first.flatMap(frame) }) else {
            throw CheckFailure("No matching editor was available through macOS Accessibility with All Projects \(state).")
        }
        try require(editors().count == 1 && title(editor) != "All Projects", "Expected one separate editor.")
        try require(workAreas.contains(where: { equals($0, bounds) }) && attribute(editor, "AXFullScreen") as? Bool == false,
                    "The editor must fill the usable display without entering full screen. Actual bounds \(bounds).")
        func verifyLibrary(_ phase: String) throws {
            // macOS can invalidate an AX proxy when another window becomes key.
            var observation = "not available"
            let preserved = waitUntil { () -> Bool? in
                let candidates = libraryWindows()
                guard candidates.count == 1, let library = candidates.first else {
                    observation = "\(candidates.count) visible to Accessibility"
                    return nil
                }
                let current = frame(library)
                let isMinimized = attribute(library, "AXMinimized") as? Bool
                observation = "minimized: \(String(describing: isMinimized)); bounds: \(String(describing: current))"
                guard isMinimized == minimized else { return nil }
                if let current, !equals(current, baseline) { return nil }
                return true
            }
            try require(preserved == true, "All Projects did not keep its \(state) state and bounds \(phase). Expected \(baseline), observed \(observation).")
        }
        try verifyLibrary("on open")
        if let currentEditor = editors().first { close(currentEditor) }
        try require(waitUntil({ editors().isEmpty ? true : nil }) != nil, "The test editor did not close.")
        try verifyLibrary("on close")
        if minimized, let library = libraryWindows().first { setMinimized(library, false) }
        print("PASS: maximized windowed editor; \(state) All Projects keeps its state and bounds on open and close.")
    }
}

@main
private enum EditorWindowStateHarness {
    static func main() {
        do { try verify() }
        catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
