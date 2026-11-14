// Used by test_installed_menu_icons.py against the running, foreground app.
import AppKit
import ApplicationServices
import Vision

func attribute(_ element: AXUIElement, _ key: String) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func title(_ element: AXUIElement) -> String {
    attribute(element, kAXTitleAttribute) as? String ?? ""
}

func frame(_ element: AXUIElement) -> CGRect {
    guard let position = attribute(element, kAXPositionAttribute),
          let size = attribute(element, kAXSizeAttribute) else { return .zero }
    var point = CGPoint.zero, dimensions = CGSize.zero
    AXValueGetValue(position as! AXValue, .cgPoint, &point)
    AXValueGetValue(size as! AXValue, .cgSize, &dimensions)
    return CGRect(origin: point, size: dimensions)
}

func pause(_ interval: TimeInterval) {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: interval))
}

func fail(_ reason: String) -> Never {
    FileHandle.standardError.write(Data((reason + "\n").utf8))
    exit(1)
}

// Opt-in cold launch check. Ask the running app to quit normally so unsaved
// work can veto termination. Read the bar as soon as Accessibility exposes it.
func sampleLaunch() throws {
    let bundle = URL(fileURLWithPath: "/Applications/VidiStudio.app")
    let id = "Varunmanojkumar.VidiStudio"
    if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
        guard running.terminate() else { fail("The app declined to quit") }
        for _ in 0..<500 where !running.isTerminated { pause(0.01) }
        guard running.isTerminated else { fail("The app is waiting to close") }
    }
    NSWorkspace.shared.openApplication(at: bundle, configuration: NSWorkspace.OpenConfiguration()) { _, error in
        if let error { fail(error.localizedDescription) }
    }
    let end = ProcessInfo.processInfo.systemUptime + 10
    var process: AXUIElement?
    var states: [[String]] = []
    var samples = 0
    while ProcessInfo.processInfo.systemUptime < end {
        if process == nil, let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            process = AXUIElementCreateApplication(app.processIdentifier)
        }
        if let process, let bar = attribute(process, kAXMenuBarAttribute) {
            let titles = children(bar as! AXUIElement).map(title)
            if !titles.isEmpty {
                if states.last != titles { states.append(titles) }
                samples += 1
            }
        }
        pause(0.003)
    }
    let result = try JSONSerialization.data(withJSONObject: ["samples": samples, "states": states])
    FileHandle.standardOutput.write(result)
}

if CommandLine.arguments.dropFirst().elementsEqual(["--sample-launch"]) {
    guard AXIsProcessTrusted() else { fail("Accessibility permission required") }
    try sampleLaunch()
    exit(0)
}

guard CommandLine.arguments.count >= 3, AXIsProcessTrusted(),
      let app = NSRunningApplication.runningApplications(withBundleIdentifier: "Varunmanojkumar.VidiStudio").first else {
    fail("Start VidiStudio and grant the test runner Accessibility access.")
}
app.activate(options: [])
pause(0.8)
let process = AXUIElementCreateApplication(app.processIdentifier)
guard let bar = attribute(process, kAXMenuBarAttribute) else { fail("Could not read menu bar") }
let roots = children(bar as! AXUIElement)
var items = roots
var openMenus: [AXUIElement] = []
defer {
    for menu in openMenus.reversed() { AXUIElementPerformAction(menu, kAXCancelAction as CFString) }
}
if ["--section", "--gallery"].contains(CommandLine.arguments[1]) {
    let allowed = ["Show Transcript", "Show Summary", "Show Descriptions", "Show AD Overview", "Show AD Transcript"]
    let section = CommandLine.arguments[2]
    let gallery = CommandLine.arguments[1] == "--gallery"
    guard gallery || allowed.contains(section) else { fail("Unknown editor section") }
    for name in gallery ? ["Window", "VidiStudio"] : ["Project", "Editor Sections", section] {
        guard let item = items.first(where: { title($0) == name }),
              AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else { fail("Cannot select " + name) }
        pause(0.4)
        items = children(item).first.map(children) ?? []
    }
    exit(0)
}

for name in CommandLine.arguments.dropFirst(2) {
    guard let item = items.first(where: {title($0) == name}),
          AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else { fail("Cannot open "+name) }
    pause(0.7)
    if children(item).first.map(frame)?.height ?? 0 == 0 {
        // AXPress can finish dismissing a previously tracked menu. Retry only
        // when there is no displayed menu, never when its contents differ.
        AXUIElementPerformAction(item, kAXPressAction as CFString)
        pause(0.7)
    }
    guard let menu = children(item).first else { fail("No open menu for "+name) }
    openMenus.append(menu)
    items = children(menu)
}
let bounds = frame(openMenus.last!)
guard bounds.width > 0, bounds.height > 0 else { fail("Menu is not displayed on the unlocked desktop") }
let path = CommandLine.arguments[1]
let capture = Process()
capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
capture.arguments = ["-x","-R"+[bounds.minX,bounds.minY,bounds.width,bounds.height].map { String(Int($0.rounded())) }.joined(separator: ","),path]
try capture.run()
capture.waitUntilExit()
guard capture.terminationStatus == 0 else { fail("Menu capture failed") }
let rows: [[String: Any]] = items.compactMap { item in
    let rect = frame(item)
    guard rect.height > 0, !title(item).isEmpty else { return nil }
    return ["title": title(item), "y": rect.midY-bounds.minY, "height":rect.height]
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
try VNImageRequestHandler(url: URL(fileURLWithPath: path)).perform([request])
let labels: [[String: Any]] = (request.results ?? []).compactMap { observation in
    guard let text = observation.topCandidates(1).first?.string else { return nil }
    // Request word boxes separately: OCR sometimes merges the glyph, title
    // and keyboard shortcut into a single observation.
    let firstWord = rows.first { abs(($0["y"] as! CGFloat) - (1-observation.boundingBox.midY)*bounds.height) < 9 }
        .flatMap { ($0["title"] as? String)?.split(separator: " ").first }
    let prefix = firstWord.flatMap { text.range(of: String($0).replacingOccurrences(of: "…", with: ""), options:.caseInsensitive) }
    let rect = prefix.flatMap { index in
        try? observation.topCandidates(1).first?.boundingBox(for: index)?.boundingBox
    } ?? observation.boundingBox
    return ["text":text, "x":rect.minX*bounds.width, "y":(1-rect.midY)*bounds.height]
}
let data = try JSONSerialization.data(withJSONObject: ["menus": roots.map(title), "rows":rows,
    "windows": (attribute(process, kAXWindowsAttribute) as? [AXUIElement] ?? []).map(title),
    "width":bounds.width, "height":bounds.height, "labels":labels])
FileHandle.standardOutput.write(data)
