import SwiftUI
import AppKit
import CoreText

/// Status belongs to the result payload, never the currently displayed cue list.
struct SavedResultStatus {
    let allAudio: Bool
    let exportReady: Bool
    init(_ result: SavedLanguageResult, project: StudioProject, transcriptID: String? = nil) {
        var view = project
        view.cues = result.payload.cues ?? []
        view.transcript = project.savedLanguageResults.first { $0.id == (transcriptID ?? project.activeLanguageResultID("transcript", language: result.language)) }?.payload.transcript ?? []
        allAudio = result.kind == "descriptions" && view.hasCompleteExportNarration()
        let timingValid = !view.cues.enumerated().contains { index, cue in
            view.transcript.contains { cue.start < $0.end && cue.end > $0.start } ||
            view.cues.enumerated().contains { other, row in other != index && cue.start < row.end && cue.end > row.start }
        }
        if result.kind == "descriptions" { exportReady = result.state == "saved" && allAudio && timingValid }
        else if result.kind == "adAudio", let path = result.payload.importedAudioDescription?.path,
                let url = project.url(path), let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) {
            exportReady = result.state == "saved" && values.isRegularFile == true && (values.fileSize ?? 0) > 0
        } else { exportReady = result.state == "saved" && result.kind != "adAudio" && result.hasContent }
    }
    func labels(selected: Bool) -> [String] {
        (selected ? ["Selected"] : []) + (allAudio ? ["All AD segments have audio"] : []) + (exportReady ? ["Export ready"] : [])
    }
}

struct SavedResultOption: View {
    let result: SavedLanguageResult
    let project: StudioProject
    let selected: Bool
    var transcriptID: String? = nil
    var includesKind = false
    var includesLanguage = false
    var includesDraft = false
    var currentSelectionLabel = "Selected"
    private var title: String {
        (includesLanguage ? OutputLanguage.title(result.language) + " · " : "") +
        (includesKind ? result.kindTitle + " · " : "") + result.title +
        (includesDraft && result.state == "draft" ? " · Review draft" : "")
    }
    var statusLabels: [String] {
        SavedResultStatus(result, project: project, transcriptID: transcriptID).labels(selected: selected)
            .map { $0 == "Selected" ? currentSelectionLabel : $0 }
    }
    var spokenLabel: String { ([title] + statusLabels).joined(separator: ", ") }
    var body: some View {
        let status = SavedResultStatus(result, project: project, transcriptID: transcriptID)
        let labels = statusLabels
        Label {
            Text(title)
        } icon: {
            Image(nsImage: statusImage(status))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .help(labels.joined(separator: ", "))
    }
    private static let iconFont: NSFont = {
        if let url = Bundle.main.url(forResource: "MaterialSymbolsRounded", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return NSFont(name: "MaterialSymbolsRounded-Regular", size: 16) ?? NSFont.systemFont(ofSize: 16)
    }()
    private func statusImage(_ status: SavedResultStatus) -> NSImage {
        let glyphs = (selected ? ["\u{e86c}"] : []) + (status.allAudio ? ["\u{e050}"] : []) + (status.exportReady ? ["\u{e163}"] : [])
        let image = NSImage(size: NSSize(width: max(1, glyphs.count * 18), height: 18), flipped: false) { _ in
            let font = Self.iconFont
            for (index, glyph) in glyphs.enumerated() {
                (glyph as NSString).draw(at: NSPoint(x: index * 18, y: 0), withAttributes: [.font: font, .foregroundColor: NSColor.labelColor])
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Saved result status: " + statusLabels.joined(separator: ", ")
        return image
    }
}
