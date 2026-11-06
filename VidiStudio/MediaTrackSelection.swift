import SwiftUI
import AppKit
import CryptoKit

struct MediaTrackSelection {
    var original = true
    var audioMode = "selectable"
    var captionMode = "closed"
    var audio: [String: String] = [:]
    var captions: [String: String] = [:]
    var descriptions: [String: String] = [:]
    var adCaptions: Set<String> = []

    func plan(media: String, format: String) -> [String: Any] {
        let a = audio.keys.sorted().map { ["language": $0, "resultID": audio[$0]!] }
        let c = media == "video" ? captions.keys.sorted().map { code in
            ["language": code, "transcriptID": captions[code]!, "descriptionsID": adCaptions.contains(code) ? (descriptions[code] ?? "") : ""]
        } : []
        return ["media": media, "format": format, "original": original, "audioMode": audioMode,
                "captionMode": captionMode, "audio": a, "captions": c]
    }
    func path(project: StudioProject, media: String, format: String) -> String {
        let codes = Array(Set(audio.keys).union(media == "video" ? Set(captions.keys) : [])).sorted()
        let languages = codes.isEmpty ? ["auto"] : codes
        var items = [media, format, audioMode, captionMode, original ? "original" : "no-original"]
        items += audio.keys.sorted().map { "a:" + audio[$0]! }
        if media == "video" { items += captions.keys.sorted().map { "s:" + captions[$0]! + ":" + (adCaptions.contains($0) ? descriptions[$0] ?? "" : "") } }
        let hash = SHA256.hash(data: Data(items.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined().prefix(12)
        let names = String((languages.map(OutputLanguage.title).joined(separator: " + ")).prefix(80))
        let name = String(project.name.unicodeScalars.prefix(40).map(String.init).joined()) + " [" + names + "]"
        return "exports/\(languages.joined(separator: "+"))/\(StudioExportAction.portableProjectName(name)) - Selected \(media == "video" ? "Video" : "Audio") Tracks \(hash).\(format)"
    }
    func valid(media: String) -> Bool {
        (media == "video" || original || !audio.isEmpty)
        && (audioMode != "mixed" || audio.count <= 1)
        && (media != "video" || captionMode != "open" || captions.count <= 1)
        && (media != "video" || captions.keys.allSatisfy { !adCaptions.contains($0) || !(descriptions[$0] ?? "").isEmpty })
    }
}

struct MediaTrackSelectionView: View {
    let project: StudioProject
    let media: String
    @Binding var selection: MediaTrackSelection
    var body: some View {
        Section("Track Presentation") {
            Picker("Audio Description", selection: $selection.audioMode) {
                Text("Selectable tracks").tag("selectable")
                Text("Mixed into audio · one language").tag("mixed")
            }.onChange(of: selection.audioMode) { _, mode in
                if mode == "mixed", let first = selection.audio.keys.sorted().first { selection.audio = [first: selection.audio[first]!] }
            }
            if selection.audioMode == "selectable" || selection.audio.isEmpty {
                Toggle("Include Original Audio", isOn: $selection.original)
            }
            if media == "video" {
                Picker("Captions", selection: $selection.captionMode) {
                    Text("Selectable closed captions").tag("closed")
                    Text("Burned into video · one language").tag("open")
                }.onChange(of: selection.captionMode) { _, mode in
                    if mode == "open", let first = selection.captions.keys.sorted().first { selection.captions = [first: selection.captions[first]!] }
                }
            }
        }
        ForEach(project.resultLanguages.sorted(), id: \.self) { code in
            Section(OutputLanguage.title(code)) {
                let audio = project.savedLanguageResults.filter { $0.state == "saved" && $0.language == code && ["descriptions", "adAudio"].contains($0.kind) && $0.hasContent }
                if !audio.isEmpty {
                    Toggle("AD Audio", isOn: Binding(get: { selection.audio[code] != nil }, set: { on in
                        if on {
                            if selection.audioMode == "mixed" { selection.audio = [:] }
                            selection.audio[code] = audio.first!.id
                            if audio.first!.kind == "descriptions" { selection.descriptions[code] = audio.first!.id }
                        } else { selection.audio.removeValue(forKey: code) }
                    }))
                    if selection.audio[code] != nil {
                        Picker("Audio Saved Result", selection: Binding(get: { selection.audio[code] ?? "" }, set: { id in
                            selection.audio[code] = id
                            if audio.first(where: { $0.id == id })?.kind == "descriptions" { selection.descriptions[code] = id }
                        })) {
                            ForEach(audio) { result in SavedResultOption(result: result, project: project, selected: result.id == selection.audio[code], transcriptID: selection.captions[code]).tag(result.id) }
                        }
                    }
                }
                let transcripts = project.languageResults(kind: "transcript", language: code).filter(\.hasContent)
                if media == "video" && !transcripts.isEmpty {
                    Toggle("Captions", isOn: Binding(get: { selection.captions[code] != nil }, set: { on in
                        if on {
                            if selection.captionMode == "open" { selection.captions = [:] }
                            selection.captions[code] = transcripts.first!.id
                        } else { selection.captions.removeValue(forKey: code) }
                    }))
                    if selection.captions[code] != nil {
                        Picker("Transcript Saved Result", selection: Binding(get: { selection.captions[code] ?? "" }, set: { selection.captions[code] = $0 })) {
                            ForEach(transcripts) { result in SavedResultOption(result: result, project: project, selected: result.id == selection.captions[code]).tag(result.id) }
                        }
                        let descriptions = project.languageResults(kind: "descriptions", language: code).filter(\.hasContent)
                        Toggle("AD Transcript", isOn: Binding(get: { selection.adCaptions.contains(code) }, set: { on in
                            if on { selection.adCaptions.insert(code); selection.descriptions[code] = descriptions.first(where: { $0.id == selection.audio[code] })?.id ?? selection.descriptions[code] ?? descriptions.first?.id }
                            else { selection.adCaptions.remove(code) }
                        })).disabled(descriptions.isEmpty)
                        if selection.adCaptions.contains(code) && !descriptions.contains(where: { $0.id == selection.audio[code] }) {
                            Picker("Description Saved Result", selection: Binding(get: { selection.descriptions[code] ?? "" }, set: { selection.descriptions[code] = $0 })) {
                                ForEach(descriptions) { result in SavedResultOption(result: result, project: project, selected: result.id == selection.descriptions[code], transcriptID: selection.captions[code]).tag(result.id) }
                            }
                        }
                    }
                }
            }
        }
    }
}
