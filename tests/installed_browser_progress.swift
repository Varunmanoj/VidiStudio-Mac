// Exercise the installed app from a cold or running state. Arguments: YouTube ID and expected project title substring.
import AppKit
import ApplicationServices

guard CommandLine.arguments.count == 3, CGPreflightScreenCaptureAccess() else {
    fatalError("Supply the video ID and title, and run with Screen Recording access")
}
let id = CommandLine.arguments[1], expected = CommandLine.arguments[2]
let target = URL(string: "vidistudio://share?kind=youtube&source=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3D" + id)!
let launcher = Process()
launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
launcher.arguments = [target.absoluteString]
try launcher.run()
let deadline = Date().addingTimeInterval(30)
var application = NSRunningApplication.runningApplications(withBundleIdentifier: "Varunmanojkumar.VidiStudio").first
var sawProgress = false
while Date() < deadline {
    if application == nil { application = NSRunningApplication.runningApplications(withBundleIdentifier: "Varunmanojkumar.VidiStudio").first }
    // Sample the compositor independently of the main thread while the editor is being laid out.
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    let titles = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == application?.processIdentifier }
        .compactMap { $0[kCGWindowName as String] as? String }
    let visible = titles.contains("Opening YouTube project…")
    sawProgress = sawProgress || visible
    if sawProgress && !visible && titles.contains(where: { $0.contains(expected) }) {
        print("PASS native spinner appeared and cleared with the expected editor open for " + expected)
        exit(0)
    }
    Thread.sleep(forTimeInterval: 0.02)
}
print("FAIL observed progress:", sawProgress, "expected editor:", expected)
exit(1)
