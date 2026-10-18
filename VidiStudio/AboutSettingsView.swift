import AppKit
import SwiftUI

private struct BundledMediaLicense: Decodable {
    let version: String
    let license: String
}

struct AboutSettingsView: View {
    @State private var openError: String?

    private var licensesURL: URL? {
        Bundle.main.resourceURL?.appending(path: "Engine/licenses", directoryHint: .isDirectory)
    }

    private var mediaLicense: BundledMediaLicense? {
        guard let url = licensesURL?.appending(path: "media-license-summary.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BundledMediaLicense.self, from: data)
    }

    var body: some View {
        Section("VidiStudio") {
            LabeledContent("App version", value: AppVersionInfo.version)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("App version, \(AppVersionInfo.version)")
        }

        Section("FFmpeg") {
            Text("VidiStudio bundles FFmpeg and FFprobe for media processing and export.")
            if let mediaLicense {
                LabeledContent("Bundled version", value: mediaLicense.version)
                LabeledContent("License", value: mediaLicense.license)
            } else {
                Text("Bundled FFmpeg license details are unavailable.")
                    .foregroundStyle(.secondary)
            }
            Text("Uses FFmpeg libraries (GPL build with x264/x265).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open FFmpeg License", systemImage: "doc.text") {
                openLicenseFile("FFmpeg-GPLv3.txt")
            }
            .accessibilityHint("Opens the GPL version 3 license included with the bundled FFmpeg build")
            Link("FFmpeg licensing and source information", destination: URL(string: "https://ffmpeg.org/legal.html")!)
        }

        Section("Third-party notices") {
            Text("License files for bundled libraries, engine packages, and fonts.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Third-Party License Index", systemImage: "list.bullet.rectangle") {
                openLicenseFile("THIRD-PARTY-LICENSES.txt")
            }
            Button("Show All License Files in Finder", systemImage: "folder") {
                guard let licensesURL else { return }
                open(licensesURL)
            }
        }
        .alert("Could Not Open License File", isPresented: Binding(
            get: { openError != nil },
            set: { if !$0 { openError = nil } }
        )) {
            Button("OK") { openError = nil }
        } message: {
            Text(openError ?? "The file could not be opened.")
        }
    }

    private func openLicenseFile(_ name: String) {
        guard let licensesURL else {
            openError = "The bundled license folder is missing."
            return
        }
        open(licensesURL.appending(path: name))
    }

    private func open(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path), NSWorkspace.shared.open(url) else {
            openError = "The bundled license file could not be found or opened."
            return
        }
    }
}
