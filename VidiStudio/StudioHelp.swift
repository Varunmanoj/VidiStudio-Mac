import AppKit
import WebKit

@MainActor enum StudioHelp {
    static func openWebsite() {
        NSWorkspace.shared.open(URL(string: "https://vidistudio.varunmanojkumar.in/")!)
    }

    static let windowIdentifier = NSUserInterfaceItemIdentifier("vidistudio-help")
    private static let reader = HelpReader()
    static let guide = URL(string: "https://vidistudio.varunmanojkumar.in/docs")!

    static func open(anchor: String = "index") {
        reader.open(anchor == "exports" ? URL(string: "#docs-8-exports", relativeTo: guide)!.absoluteURL : guide)
    }
}

@MainActor private final class HelpReader: NSObject, WKNavigationDelegate {
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1050, height: 720),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
    private let content = NSView()
    private let spinner = NSProgressIndicator()
    private lazy var retryButton = NSButton(title: "Retry", target: self, action: #selector(retryGuide))
    private let configuration = WKWebViewConfiguration()
    private var reader: WKWebView?
    private var requestedURL = StudioHelp.guide
    private var navigation: WKNavigation?

    override init() {
        super.init()
        configuration.websiteDataStore = .nonPersistent()
        let browser = NSButton(title: "Open in Browser", target: self, action: #selector(openInBrowser))
        for button in [retryButton, browser] {
            let menu = NSMenu()
            menu.addItem(withTitle: button.title, action: button.action, keyEquivalent: "").target = self
            button.menu = menu
        }
        retryButton.isHidden = true
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.setAccessibilityLabel("Loading documentation")
        let header = NSStackView(views: [spinner, retryButton, browser])
        let root = NSView()
        root.addSubview(header)
        root.addSubview(content)
        header.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 6),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        window.contentView = root
        window.title = "VidiStudio Help"
        window.identifier = StudioHelp.windowIdentifier
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("VidiStudioHelpWindow")
        window.center()
    }

    func open(_ url: URL) {
        retryButton.isHidden = true
        requestedURL = url
        reader?.navigationDelegate = nil
        reader?.stopLoading()
        let view = WKWebView(frame: content.bounds, configuration: configuration)
        reader = view
        view.navigationDelegate = self
        view.autoresizingMask = [.width, .height]
        content.subviews = [view]
        setLoading(true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        navigation = view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
    }

    private func isGuide(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == StudioHelp.guide.host && ["/docs", "/docs/"].contains(url.path)
    }

    @objc private func retryGuide() {
        guard !retryButton.isHidden else { return }
        open(requestedURL)
    }

    @objc private func openInBrowser() {
        let url = reader?.url.flatMap { isGuide($0) ? $0 : nil } ?? requestedURL
        NSWorkspace.shared.open(url)
    }

    private func setLoading(_ loading: Bool) {
        spinner.isHidden = !loading
        if loading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    private func showMessage(_ message: String) {
        setLoading(false)
        reader?.navigationDelegate = nil
        reader = nil
        let label = NSTextField(wrappingLabelWithString: message)
        content.subviews = [label]
        retryButton.isHidden = false
        window.makeFirstResponder(retryButton)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -24)
        ])
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if action.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
        } else if action.targetFrame != nil && isGuide(url) {
            requestedURL = url
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated && ["http", "https"].contains(url.scheme) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame, let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
            decisionHandler(.cancel)
            if webView === reader { showMessage("Documentation is temporarily unavailable.") }
        } else { decisionHandler(.allow) }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === reader else { return }
        self.navigation = navigation
        setLoading(true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === reader && navigation === self.navigation { setLoading(false) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === reader, navigation === self.navigation else { return }
        if (error as NSError).code == NSURLErrorCancelled { setLoading(false) }
        else { showMessage("Documentation requires internet.") }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
    }
}
