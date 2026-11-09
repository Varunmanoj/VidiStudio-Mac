import SwiftUI
import AppKit
import CryptoKit

struct MediaTrackSelection {
    var original = true
    let audioMode = "selectable"
    var captionMode = "closed"
    var audio: [String: String] = [:]
    var captions: [String: String] = [:]
    var descriptions: [String: String] = [:]
    var adCaptions: Set<String> = []
    var transcriptCaptions: Set<String> = []

    func plan(media: String, format: String) -> [String: Any] {
        let a = audio.keys.sorted().map { ["language": $0, "resultID": audio[$0]!] }
        let c: [[String: String]] = media == "video" ? captions.keys.sorted().flatMap { code in
            var rows: [[String: String]] = []
            if transcriptCaptions.contains(code) { rows.append(["language": code, "transcriptID": captions[code]!, "descriptionsID": ""]) }
            if adCaptions.contains(code) { rows.append(["language": code, "transcriptID": captions[code]!, "descriptionsID": descriptions[code] ?? ""]) }
            return rows
        } : []
        return ["media": media, "format": format, "original": original, "audioMode": audioMode,
                "captionMode": captionMode, "audio": a, "captions": c]
    }
    func path(project: StudioProject, media: String, format: String) -> String {
        let codes = Array(Set(audio.keys).union(media == "video" ? Set(captions.keys) : [])).sorted()
        let languages = codes.isEmpty ? ["auto"] : codes
        var items = [media, format, audioMode, captionMode, original ? "original" : "no-original"]
        items += audio.keys.sorted().map { "a:" + audio[$0]! }
        if media == "video", let rows = plan(media: media, format: format)["captions"] as? [[String: String]] {
            items += rows.map { "s:" + $0["transcriptID"]! + ":" + $0["descriptionsID"]! }
        }
        let hash = SHA256.hash(data: Data(items.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined().prefix(12)
        let names = String((languages.map(OutputLanguage.title).joined(separator: " + ")).prefix(80))
        let name = String(project.name.unicodeScalars.prefix(40).map(String.init).joined()) + " [" + names + "]"
        return "exports/\(languages.joined(separator: "+"))/\(StudioExportAction.portableProjectName(name)) - Selected \(media == "video" ? "Video" : "Audio") Tracks \(hash).\(format)"
    }
    func valid(media: String) -> Bool {
        (media == "video" || original || !audio.isEmpty)
        && (media != "video" || captionMode != "open" || transcriptCaptions.count + adCaptions.count <= 1)
        && (media != "video" || captions.keys.allSatisfy { !adCaptions.contains($0) || !(descriptions[$0] ?? "").isEmpty })
    }
}

struct MediaTrackSelectionView: View {
    let project: StudioProject
    let media: String
    @Binding var selection: MediaTrackSelection
    private func captionBinding(_ code: String, ad: Bool, transcripts: [SavedLanguageResult], descriptions: [SavedLanguageResult]) -> Binding<Bool> {
        Binding(get: { ad ? selection.adCaptions.contains(code) : selection.transcriptCaptions.contains(code) }, set: { on in
            if on {
                if selection.captionMode == "open" { selection.captions = [:]; selection.transcriptCaptions = []; selection.adCaptions = [] }
                selection.captions[code] = selection.captions[code] ?? transcripts.first?.id
                if ad {
                    selection.adCaptions.insert(code)
                    selection.descriptions[code] = descriptions.first(where: { $0.id == selection.audio[code] })?.id ?? selection.descriptions[code] ?? descriptions.first?.id
                } else { selection.transcriptCaptions.insert(code) }
            } else {
                if ad { selection.adCaptions.remove(code) } else { selection.transcriptCaptions.remove(code) }
                if !selection.adCaptions.contains(code) && !selection.transcriptCaptions.contains(code) { selection.captions.removeValue(forKey: code) }
            }
        })
    }
    var body: some View {
        Section("Track Presentation") {
            LabeledContent("Audio Description", value: "Selectable tracks")
            ExportOptionToggle("Include Original Audio", isOn: $selection.original)
            if media == "video" {
                ExportOptionPicker("Captions", selection: $selection.captionMode) {
                    Text("Selectable closed captions").tag("closed")
                    Text("Burned into video · one language").tag("open")
                }.onChange(of: selection.captionMode) { _, mode in
                    if mode == "open", let first = selection.captions.keys.sorted().first {
                        selection.captions = [first: selection.captions[first]!]
                        let plain = selection.transcriptCaptions.contains(first)
                        selection.transcriptCaptions = plain ? [first] : []
                        selection.adCaptions = plain ? [] : [first]
                    }
                }
            }
        }
        ForEach(project.resultLanguages.sorted(), id: \.self) { code in
            Section(OutputLanguage.title(code)) {
                let audio = project.savedLanguageResults.filter { $0.state == "saved" && $0.language == code && ["descriptions", "adAudio"].contains($0.kind) && $0.hasContent }
                if !audio.isEmpty {
                    ExportOptionToggle("AD Audio", isOn: Binding(get: { selection.audio[code] != nil }, set: { on in
                        if on {
                            selection.audio[code] = audio.first!.id
                            if audio.first!.kind == "descriptions" { selection.descriptions[code] = audio.first!.id }
                        } else { selection.audio.removeValue(forKey: code) }
                    }))
                    if selection.audio[code] != nil {
                        ExportOptionPicker("Audio Saved Result", selection: Binding(get: { selection.audio[code] ?? "" }, set: { id in
                            selection.audio[code] = id
                            if audio.first(where: { $0.id == id })?.kind == "descriptions" { selection.descriptions[code] = id }
                        })) {
                            ForEach(audio) { result in SavedResultOption(result: result, project: project, selected: result.id == selection.audio[code], transcriptID: selection.captions[code]).tag(result.id) }
                        }
                    }
                }
                let transcripts = project.languageResults(kind: "transcript", language: code).filter(\.hasContent)
                if media == "video" && !transcripts.isEmpty {
                    let descriptions = project.languageResults(kind: "descriptions", language: code).filter(\.hasContent)
                    ExportOptionToggle("Transcript", isOn: captionBinding(code, ad: false, transcripts: transcripts, descriptions: descriptions))
                    ExportOptionToggle("AD Transcript", isOn: captionBinding(code, ad: true, transcripts: transcripts, descriptions: descriptions))
                        .disabled(descriptions.isEmpty)
                    if selection.captions[code] != nil {
                        ExportOptionPicker("Transcript Saved Result", selection: Binding(get: { selection.captions[code] ?? "" }, set: { selection.captions[code] = $0 })) {
                            ForEach(transcripts) { result in SavedResultOption(result: result, project: project, selected: result.id == selection.captions[code]).tag(result.id) }
                        }
                        if selection.adCaptions.contains(code) && !descriptions.contains(where: { $0.id == selection.audio[code] }) {
                            ExportOptionPicker("Description Saved Result", selection: Binding(get: { selection.descriptions[code] ?? "" }, set: { selection.descriptions[code] = $0 })) {
                                ForEach(descriptions) { result in SavedResultOption(result: result, project: project, selected: result.id == selection.descriptions[code], transcriptID: selection.captions[code]).tag(result.id) }
                            }
                        }
                    }
                }
            }
        }
    }
}


struct ExportOptionToggle: View {
    let title: String
    @Binding var isOn: Bool
    init(_ title: String, isOn: Binding<Bool>) { self.title = title; _isOn = isOn }
    var body: some View {
        Toggle(title, isOn: $isOn).contextMenu { Toggle(title, isOn: $isOn) }
    }
}

struct ExportOptionPicker<Value: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Value
    @ViewBuilder let content: () -> Content
    init(_ title: String, selection: Binding<Value>, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; _selection = selection; self.content = content
    }
    var body: some View {
        Picker(title, selection: $selection, content: content)
            .contextMenu { Picker(title, selection: $selection, content: content) }
    }
}
