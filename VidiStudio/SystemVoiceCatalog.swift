import SwiftUI
import AppKit

struct SystemVoice: Identifiable, Sendable {
    var name: String
    var language: String
    var sample: String
    var id: String { name + language }
    var languageName: String { Locale.current.localizedString(forIdentifier: language) ?? language }
}
@MainActor @Observable final class SystemVoiceCatalog {
    var voices: [SystemVoice] = []
    var error: String?
    private var sampleProcess: Process?
    func refresh() async {
        let result = await Task.detached { () -> [SystemVoice] in
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            process.arguments = ["-v", "?"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let pattern = #"^(.+?)\s+([a-z]{2,3}_[A-Za-z_]+)\s+#\s*(.*)$"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            var seen = Set<String>()
            return String(decoding: data, as: UTF8.self).components(separatedBy: .newlines).compactMap { line in
                let ns = line as NSString
                guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
                let voice = SystemVoice(name: ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces), language: ns.substring(with: match.range(at: 2)), sample: ns.substring(with: match.range(at: 3)))
                return seen.insert(voice.id).inserted ? voice : nil
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }.value
        voices = result
        error = result.isEmpty ? "No system voices were available. Install a voice in macOS Accessibility settings, then refresh." : nil
    }
    func preview(_ voice: SystemVoice) {
        stop()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = (voice.name.isEmpty ? [] : ["-v", voice.name]) + ["--", voice.sample]
        do { try process.run(); sampleProcess = process } catch { self.error = error.localizedDescription }
    }
    func stop() { if sampleProcess?.isRunning == true { sampleProcess?.terminate() }; sampleProcess = nil }
}

struct SystemVoiceBrowser: View {
    @Binding var selectedVoice: String
    @State private var catalog = SystemVoiceCatalog()
    @State private var language = "all"
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Language and region", selection: $language) {
                Text("All languages").tag("all")
                ForEach(Array(Set(catalog.voices.map(\.language))).sorted(), id: \.self) { code in
                    Text(Locale.current.localizedString(forIdentifier: code) ?? code).tag(code)
                }
            }
            TextField("Search voices", text: $search).textFieldStyle(.roundedBorder)
            HStack {
                Button("Use system default voice") { selectedVoice = "" }
                Button("Play Selected Voice", systemImage: "play.circle") {
                    catalog.preview(catalog.voices.first { $0.name == selectedVoice } ?? SystemVoice(name: selectedVoice, language: "", sample: "This is a sample of audio description narration in VidiStudio."))
                }
            }
            Text("Selected: \(selectedVoice.isEmpty ? "System default" : selectedVoice)").font(.callout)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(catalog.voices.filter { (language == "all" || $0.language == language) && (search.isEmpty || $0.name.localizedStandardContains(search) || $0.languageName.localizedStandardContains(search)) }) { voice in
                        HStack {
                            Button { selectedVoice = voice.name } label: {
                                HStack { Image(systemName: selectedVoice == voice.name ? "checkmark.circle.fill" : "circle"); VStack(alignment: .leading) { Text(voice.name); Text(voice.languageName).font(.caption).foregroundStyle(.secondary) } }
                            }.buttonStyle(.plain).accessibilityLabel("Select \(voice.name), \(voice.languageName)").accessibilityAddTraits(selectedVoice == voice.name ? .isSelected : [])
                            Spacer()
                            Button("Speak Sample", systemImage: "play.circle") { catalog.preview(voice) }.labelStyle(.iconOnly).accessibilityLabel("Speak sample of \(voice.name), \(voice.languageName)")
                        }
                        Divider()
                    }
                }.padding(4)
            }.frame(minHeight: 200, idealHeight: 280, maxHeight: 320)
            HStack {
                Button("Refresh Voices") { Task { await catalog.refresh() } }
                Button("Stop Sample") { catalog.stop() }
                Button("Open macOS Voice Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess")!)
                }
            }
            Text("Lists voices available to macOS speech on this Mac. Download additional languages and enhanced voices in System Settings → Accessibility → Read & Speak, then refresh.").font(.caption).foregroundStyle(.secondary)
            if let error = catalog.error { Text(error).foregroundStyle(.red) }
        }.task { await catalog.refresh() }.onDisappear { catalog.stop() }
    }
}
