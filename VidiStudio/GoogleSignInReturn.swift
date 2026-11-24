import Foundation

enum GoogleSignInReturn {
    static func response(cloud: Bool, receivedCode: Bool, bundle: Bundle = .main) -> Data {
        let service = cloud ? "Google Cloud" : "YouTube"
        let heading = receivedCode ? "Return to VidiStudio" : "Sign-in didn’t finish"
        let message = receivedCode
            ? "You’re done in the browser. VidiStudio will finish connecting your account."
            : "To try again, start a new sign-in in VidiStudio."
        let icon = bundle.url(forResource: "GoogleSignInAppIcon", withExtension: "png")
            .flatMap { try? Data(contentsOf: $0) }
            .map { "data:image/png;base64," + $0.base64EncodedString() }
        let fallback = "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><title>{{HEADING}} · VidiStudio</title><main><h1>{{HEADING}}</h1><p>{{MESSAGE}}</p><p>Close this tab and switch back to the app.</p></main></html>"
        let template = bundle.url(forResource: "GoogleSignInReturn", withExtension: "html")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? fallback
        let page = template
            .replacingOccurrences(of: "{{SERVICE}}", with: service)
            .replacingOccurrences(of: "{{HEADING}}", with: heading)
            .replacingOccurrences(of: "{{MESSAGE}}", with: message)
            .replacingOccurrences(of: "{{APP_ICON}}", with: icon.map { "<img src=\"\($0)\" alt=\"\">" } ?? "")
            .replacingOccurrences(of: "{{FAVICON}}", with: icon.map { "<link rel=\"icon\" href=\"\($0)\">" } ?? "")
        let header = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(page.utf8.count)",
            "Cache-Control: no-store",
            "Referrer-Policy: no-referrer",
            "Content-Security-Policy: default-src 'none'; img-src data:; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")
        return Data((header + page).utf8)
    }
}
