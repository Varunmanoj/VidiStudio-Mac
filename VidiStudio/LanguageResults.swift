import SwiftUI
import AppKit
import AVFoundation

struct OutputLanguage: Identifiable, Hashable {
    let id: String
    let title: String
    static let options: [OutputLanguage] = {
        let url = Bundle.main.resourceURL?.appendingPathComponent("Engine/_internal/ai-defaults.json")
        let data = url.flatMap { try? Data(contentsOf: $0) }
        let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let values = json?["outputLanguageOptions"] as? [String: String] ?? [:]
        return [OutputLanguage(id: "auto", title: "Auto")] + values.map { OutputLanguage(id: $0.key, title: $0.value) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }()
    static func title(_ code: String) -> String { options.first { $0.id == code }?.title ?? code }
    static func projectFilterOptions(_ projects: [StudioProject]) -> [OutputLanguage] {
        let codes = Set(projects.flatMap(\.projectFilterLanguageCodes))
        return codes.map { OutputLanguage(id: $0, title: title($0)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

struct SavedLanguagePayload: Codable {
    var descriptionTimingAudit: DescriptionTimingAudit?
    var narrationEngine: String?
    var narrationVoice: String?
    var transcript: [Segment]?
    var summary: String?
    var cues: [Segment]?
    var importedAudioDescription: ImportedAudioDescription?
    var importedADTranscript: ImportedADTranscript?
    var undoStack: [[Segment]]?
    var redoStack: [[Segment]]?
    var transcriptUndoStack: [[Segment]]?
    var transcriptRedoStack: [[Segment]]?
    var referencedSegments: [Segment] {
        var rows = cues ?? []
        rows += (undoStack ?? []).flatMap { $0 }
        rows += (redoStack ?? []).flatMap { $0 }
        rows += (transcriptUndoStack ?? []).flatMap { $0 }
        rows += (transcriptRedoStack ?? []).flatMap { $0 }
        return rows
    }
    var preview: String {
        if let summary { return summary }
        if let audio = importedAudioDescription { return audio.sourceName }
        return (transcript ?? importedADTranscript?.segments ?? cues ?? []).map { $0.text }.joined(separator: "\n")
    }
}

struct SavedLanguageResult: Codable, Identifiable {
    var id: String
    var kind: String
    var language: String
    var version: Int
    var createdAt: Double
    var updatedAt: Double
    var origin: String
    var state: String
    var payload: SavedLanguagePayload
    var replacesResultID: String?
    var sourceResultIDs: [String: String]?
    var sourceAsset: SavedSourceAsset?
    var title: String {
        let date = Date(timeIntervalSince1970: createdAt).formatted(date: .abbreviated, time: .shortened)
        return "Version \(version) · \(origin.capitalized) · \(date)"
    }
    var hasContent: Bool {
        switch kind {
        case "transcript": !(payload.transcript ?? []).isEmpty
        case "summary": !(payload.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case "descriptions": !(payload.cues ?? []).isEmpty || !(payload.importedADTranscript?.segments ?? []).isEmpty
        default: !(payload.importedAudioDescription?.path ?? "").isEmpty
        }
    }
    var hasExportableText: Bool {
        switch kind {
        case "transcript": return (payload.transcript ?? []).contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        case "summary": return !(payload.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case "descriptions": return ((payload.cues ?? []) + (payload.importedADTranscript?.segments ?? [])).contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        default: return false
        }
    }
    var kindTitle: String { Self.kindTitle(kind) }
    static func savedResultsTitle(_ kind: String) -> String {
        switch kind {
        case "transcript": "Transcript Saved Results"
        case "summary": "Summary Saved Results"
        case "descriptions": "Description Saved Results"
        default: "Imported AD Audio Saved Results"
        }
    }
    static func kindTitle(_ kind: String) -> String {
        switch kind {
        case "transcript": "Transcript"
        case "summary": "Summary"
        case "descriptions": "Descriptions and Narration"
        default: "Imported AD Audio"
        }
    }
}

struct SavedSourceAsset: Codable {
    var path: String
    var sourceName: String?
}

struct ExportResultProvenance: Codable {
    var described: Bool?
    var languages: [String]?
    func matches(_ code: String) -> Bool { code == "all" || (languages ?? [language]).contains(code) }
    var language: String
    var resultIDs: [String: String]
    var createdAt: Double
}

extension StudioProject {
    var overviewLanguageCode: String { languageCode }
    var overviewProject: StudioProject {
        var value = self
        let code = overviewLanguageCode
        func result(_ kind: String) -> SavedLanguageResult? {
            savedLanguageResults.first { $0.id == activeLanguageResultID(kind, language: code) && $0.language == code && $0.state == "saved" }
        }
        let descriptions = result("descriptions")?.payload
        value.cues = descriptions?.cues ?? []
        value.transcript = result("transcript")?.payload.transcript ?? []
        value.importedADTranscript = descriptions?.importedADTranscript
        value.importedAudioDescription = result("adAudio")?.payload.importedAudioDescription
        value.descriptionTimingAudit = descriptions?.descriptionTimingAudit
        value.narrationEngine = descriptions?.narrationEngine
        value.narrationVoice = descriptions?.narrationVoice
        return value
    }
    var overviewMatchesEditingResult: Bool { overviewLanguageCode == languageCode }
    var languageCode: String { selectedLanguage ?? "auto" }
    func sectionLanguage(_ kind: String) -> String { sectionLanguages?[kind] ?? languageCode }
    func operationLanguage(_ command: String) -> String {
        guard ["transcribe", "generate-summary", "generate-ad-cues", "import-transcript", "import-summary", "import-ad-transcript", "import-ad-audio"].contains(command) else { return languageCode }
        let kind: String?
        switch command {
        case "transcribe", "import-transcript", "reanalyze-transcript-segment", "undo-transcript", "redo-transcript": kind = "transcript"
        case "generate-summary", "save-summary", "import-summary": kind = "summary"
        case "generate-ad-cues", "synthesize-tts", "save-cues", "rewrite-cue", "reanalyze-segment", "import-ad-transcript", "import-segment-narration", "delete-segment-audio", "undo-cues", "redo-cues": kind = "descriptions"
        case "import-ad-audio": kind = "adAudio"
        default: kind = nil
        }
        return kind.map(sectionLanguage) ?? languageCode
    }
    var savedLanguageResults: [SavedLanguageResult] {
        if let languageResults { return languageResults }
        var results: [SavedLanguageResult] = []
        for kind in ["transcript", "summary", "descriptions", "adAudio"] {
            let content = kind == "transcript" ? !transcript.isEmpty : kind == "summary" ? !summary.isEmpty : kind == "descriptions" ? (!cues.isEmpty || importedADTranscript?.segments.isEmpty == false) : importedAudioDescription != nil
            if content {
                results.append(SavedLanguageResult(id: id + "-legacy-" + kind, kind: kind, language: "auto", version: 1,
                    createdAt: createdAt, updatedAt: updatedAt, origin: kind == "summary" ? summaryOrigin ?? "unknown" : "unknown", state: "saved",
                    payload: SavedLanguagePayload(transcript: kind == "transcript" ? transcript : nil, summary: kind == "summary" ? summary : nil,
                        cues: kind == "descriptions" ? cues : nil, importedAudioDescription: kind == "adAudio" ? importedAudioDescription : nil,
                        importedADTranscript: kind == "descriptions" ? importedADTranscript : nil)))
            }
        }
        return results
    }
    func languageResults(kind: String, language: String? = nil, includingDrafts: Bool = false) -> [SavedLanguageResult] {
        savedLanguageResults.filter { $0.kind == kind && $0.language == (language ?? languageCode) && (includingDrafts || $0.state == "saved") }
            .sorted { $0.createdAt > $1.createdAt }
    }
    func activeLanguageResultID(_ kind: String, language: String? = nil) -> String {
        let code = language ?? languageCode
        return activeResultIDs?[code]?[kind] ?? languageResults(kind: kind, language: code).first?.id ?? ""
    }
    var availableViewingLanguages: [String] {
        Array(Set(savedLanguageResults.map(\.language))).sorted()
    }
    func viewingLanguageTitle(_ code: String) -> String {
        let kinds = Set(savedLanguageResults.filter { $0.language == code }.map(\.kind))
        let names = ["transcript", "summary", "descriptions", "adAudio"].filter(kinds.contains).map { kind in
            ["transcript": "Transcript", "summary": "Summary", "descriptions": "Descriptions", "adAudio": "AD Audio"][kind]!
        }
        return OutputLanguage.title(code) + (names.isEmpty ? "" : " (" + names.joined(separator: ", ") + ")")
    }
    var deletionLanguages: [String] {
        let exportLanguages = exports.flatMap { path in
            exportResults?[path]?.languages ?? [exportResults?[path]?.language ?? "auto"]
        }
        return Array(Set(savedLanguageResults.map(\.language) + exportLanguages)).sorted {
            OutputLanguage.title($0).localizedStandardCompare(OutputLanguage.title($1)) == .orderedAscending
        }
    }
    var resultLanguages: [String] { Array(Set(savedLanguageResults.map(\.language))).sorted() }
    var projectFilterLanguageCodes: [String] {
        Array(Set(savedLanguageResults.filter {
            $0.state == "saved" && $0.hasContent && !$0.language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.map(\.language))).sorted()
    }
    func matchesLanguage(_ code: String) -> Bool { code == "all" || projectFilterLanguageCodes.contains(code) }
}

struct OutputLanguagePicker: View {
    var title = "Language"
    @Binding var selection: String
    var includesAll = false
    var includesAuto = true
    var includesFollowProject = false
    var options: [OutputLanguage] = OutputLanguage.options
    var body: some View {
        Picker(title, selection: $selection) {
            if includesAll { Text("All Languages").tag("all") }
            if includesFollowProject { Text("Follow Project Language").tag("project") }
            ForEach(options.filter { includesAuto || $0.id != "auto" }) { option in Text(option.title).tag(option.id) }
        }.pickerStyle(.menu)
            .accessibilityLabel(title)
    }
}

struct LanguageResultControls: View {
    @Bindable var studio: StudioModel
    let project: StudioProject
    @Bindable var editorActions: EditorShortcutActions
    var showsSection = true
    var showsCopyControls = true
    var kindsOverride: [String]? = nil
    var editModeToggle: (() -> Void)? = nil
    @State private var review: SavedLanguageResult?
    @State private var assigning: SavedLanguageResult?
    @State private var assignment = "auto"
    @State private var resultFilter = "all"
    private var visibleKinds: [String] {
        if let kindsOverride { return kindsOverride }
        return editorActions.savedResultKinds
    }
    private func run(_ command: String, _ arguments: [String] = []) {
        guard editorActions.available, !editorActions.hasUnsavedSummaryEdits else { return }
        if !["select-result", "review-result", "select-overview-language", "select-view-result", "select-language"].contains(command) {
            guard editorActions.canChangeLanguage else { return }
        }
        editorActions.languageAction?(command, arguments)
    }
    var body: some View {
        Group {
            if showsSection { InspectorSection("Language and Saved Results") { controls } }
            else { controls }
        }
        .disabled(studio.busy)
        .sheet(item: $review) { result in LanguageResultReview(studio: studio, project: project, result: result, resolveAction: { run("review-result", $0) }) }
        .sheet(item: $assigning) { result in
            VStack(alignment: .leading, spacing: 18) {
                Text("Assign Language").font(.title2.bold()).accessibilityAddTraits(.isHeader).accessibilityHeading(.h1)
                Text("\(result.kindTitle) · \(result.title)")
                OutputLanguagePicker(selection: $assignment)
                HStack {
                    Button("Cancel") { assigning = nil }
                    Spacer()
                    Button("Assign Language") {
                        run("assign-result-language", ["--language", assignment, "--result-id", result.id])
                        assigning = nil
                    }.keyboardShortcut(.defaultAction).disabled(!editorActions.canChangeLanguage)
                }
            }.padding(24).frame(width: 480)
        }
    }
    @ViewBuilder private var controls: some View {

            if showsCopyControls {
                Button(editorActions.currentSectionCopyTitle, systemImage: "doc.on.doc") { editorActions.copyCurrentSection() }
                    .disabled(!editorActions.canRun("copy-to"))
            }
            if let editModeToggle {
                Button(editorActions.segmentEditMode ? "Finish Editing Languages" : "Edit Languages", action: editModeToggle)
                    .disabled(!editorActions.available || editorActions.hasUnsavedSummaryEdits)
            } else if editorActions.segmentEditingAvailable {
                Button(editorActions.segmentEditModeTitle, systemImage: editorActions.segmentEditMode ? "checkmark" : "pencil") { editorActions.run("segment-edit-mode") }
                    .disabled(!editorActions.canRun("segment-edit-mode"))
            }
            if editorActions.hasUnsavedSummaryEdits {
                Text("Save or cancel summary edits first.").font(.caption).foregroundStyle(.secondary)
            }
            Picker(editorActions.segmentEditMode ? "Edit Project Language" : "View Project Language", selection: Binding(get: {
                editorActions.segmentEditMode || project.availableViewingLanguages.contains(project.languageCode) ? project.languageCode : "unavailable"
            }, set: { code in if code != "unavailable" { run("select-language", ["--language", code]) } })) {
                if !editorActions.segmentEditMode && !project.availableViewingLanguages.contains(project.languageCode) {
                    Text("No saved content selected").tag("unavailable")
                }
                ForEach(OutputLanguage.options.filter { editorActions.segmentEditMode || project.availableViewingLanguages.contains($0.id) }) { option in
                    Text(project.viewingLanguageTitle(option.id)).tag(option.id)
                }
            }.pickerStyle(.menu).disabled(!editorActions.available || editorActions.hasUnsavedSummaryEdits || (!editorActions.segmentEditMode && project.availableViewingLanguages.isEmpty))
            if editorActions.segmentEditMode {
                Button("Keep All Sections in Sync") { run("sync-section-languages") }
                    .help("Return every section to Follow Project Language; saved results are preserved")
                    .disabled(!editorActions.canChangeLanguage)
            }
            ForEach(visibleKinds, id: \.self) { kind in
                OutputLanguagePicker(title: "\(SavedLanguageResult.kindTitle(kind)) Generation Language", selection: Binding(get: {
                    project.sectionLanguages?[kind] ?? "project"
                }, set: { code in
                    let arguments = code == "project" ? ["--section", kind, "--follow-project"] : ["--section", kind, "--language", code]
                    run("select-section-language", arguments)
                }), includesFollowProject: true).disabled(!editorActions.canChangeLanguage)
                let overview = editorActions.activeSection == "ad-overview"
                let code = overview ? project.overviewLanguageCode : project.languageCode
                let results = project.languageResults(kind: kind, language: code, includingDrafts: true)
                if !results.isEmpty {
                    Picker(SavedLanguageResult.savedResultsTitle(kind), selection: Binding(get: { project.activeLanguageResultID(kind, language: code) }, set: {
                        if !$0.isEmpty { run("select-result", ["--result-id", $0]) }
                    })) {
                        if project.activeLanguageResultID(kind, language: code).isEmpty {
                            Text("Choose a result").tag("")
                        }
                        ForEach(results) { result in SavedResultOption(result: result, project: project, selected: result.id == project.activeLanguageResultID(kind, language: code)).tag(result.id) }
                    }.pickerStyle(.menu).disabled(editorActions.hasUnsavedSummaryEdits || !editorActions.available)
                    if editorActions.segmentEditMode, let selected = results.first(where: { $0.id == project.activeLanguageResultID(kind, language: code) }) {
                        Button("Assign Language to \(selected.kindTitle)…") { assigning = selected; assignment = selected.language }
                            .font(.caption)
                            .disabled(!editorActions.canChangeLanguage)
                    }
                } else {
                    Text("No saved \(SavedLanguageResult.kindTitle(kind).lowercased()) in \(OutputLanguage.title(code)).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            let drafts = project.savedLanguageResults.filter { visibleKinds.contains($0.kind) && $0.state == "draft" && (resultFilter == "all" || $0.language == resultFilter) }
            if project.savedLanguageResults.contains(where: { visibleKinds.contains($0.kind) && $0.state == "draft" }) {
                OutputLanguagePicker(title: "Review language filter", selection: $resultFilter, includesAll: true)
                ForEach(drafts) { result in
                    Button("Review \(OutputLanguage.title(result.language)) \(result.kindTitle)…") { review = result }
                        .disabled(editorActions.hasUnsavedSummaryEdits || !editorActions.available)
                }
            }

    }

}

private struct LanguageResultReview: View {
    @Bindable var studio: StudioModel
    let project: StudioProject
    let result: SavedLanguageResult
    let resolveAction: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var audioPreview: AVPlayer?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review \(OutputLanguage.title(result.language)) \(result.kindTitle)").font(.title2.bold()).accessibilityAddTraits(.isHeader).accessibilityHeading(.h1)
            HStack(alignment: .top) {
                preview("Selected saved result", project.savedLanguageResults.first { $0.id == result.replacesResultID }?.payload.preview ?? "No previous result")
                preview("New result", result.payload.preview)
            }
            HStack {
                if let old = project.savedLanguageResults.first(where: { $0.id == result.replacesResultID }) { audioButton("Preview Saved Narration", old) }
                audioButton("Preview New Narration", result)
                Button("Stop Preview") { audioPreview?.pause(); audioPreview = nil }
            }
            HStack {
                Button("Review Later") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Discard New", role: .destructive) { resolve("discard") }
                Spacer()
                Button("Replace Selected", role: .destructive) { resolve("replace") }.disabled(result.replacesResultID == nil)
                Button("Keep Both") { resolve("keep") }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(minWidth: 720, minHeight: 480)
        .onDisappear { audioPreview?.pause(); audioPreview = nil }
    }
    private func preview(_ title: String, _ text: String) -> some View {
        GroupBox(title) { ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
    }
    @ViewBuilder private func audioButton(_ title: String, _ item: SavedLanguageResult) -> some View {
        if let path = item.payload.importedAudioDescription?.path ?? item.payload.cues?.compactMap(\.audio).first, let url = project.url(path) {
            Button(title) { audioPreview?.pause(); audioPreview = AVPlayer(url: url); audioPreview?.play() }
                .help("Preview the first available narration audio in this result")
        }
    }
    private func resolve(_ disposition: String) {
        resolveAction(["--result-id", result.id, "--disposition", disposition])
        dismiss()
    }
}

struct ResultDeletionPreview: Decodable {
    var selectedResultCount: Int
    var exportCount: Int
    var fileCount: Int
    var files: [String]
    var text: String { "\(selectedResultCount) affected results, \(exportCount) exports, and \(fileCount) files.\n" + files.prefix(12).joined(separator: "\n") + (files.count > 12 ? "\n…and \(files.count - 12) more files." : "") }
}

extension StudioModel {
    func previewResultDeletion(request: [String: Any], project: StudioProject, completion: @escaping (ResultDeletionPreview) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-delete-preview-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let input = dir.appendingPathComponent("request.json"), output = dir.appendingPathComponent("preview.json")
            try JSONSerialization.data(withJSONObject: request).write(to: input, options: .atomic)
            execute("preview-delete-results", extra: ["--input", input.path, "--output", output.path], project: project) { result in
                defer { try? FileManager.default.removeItem(at: dir) }
                if result != nil, let data = try? Data(contentsOf: output), let preview = try? JSONDecoder().decode(ResultDeletionPreview.self, from: data) { completion(preview) }
            }
        } catch { try? FileManager.default.removeItem(at: dir); self.error = error.localizedDescription }
    }

    func executeResultRequest(_ command: String, request: [String: Any], project: StudioProject) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-results-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let input = dir.appendingPathComponent("request.json")
            try JSONSerialization.data(withJSONObject: request).write(to: input, options: .atomic)
            execute(command, extra: ["--input", input.path], project: project, cleanupURL: dir)
        } catch {
            try? FileManager.default.removeItem(at: dir)
            self.error = error.localizedDescription
        }
    }

    func sourceResultArguments(_ command: String, project: StudioProject) -> [String]? {
        let kinds = command == "generate-ad-cues" ? ["transcript", "summary"] : command == "generate-summary" ? ["transcript"] : []
        var arguments: [String] = []
        for kind in kinds {
            if !project.activeLanguageResultID(kind).isEmpty { continue }
            let choices = project.savedLanguageResults.filter { $0.kind == kind && $0.state == "saved" }
            guard !choices.isEmpty else { error = "Create or import a \(kind) to use as source context first."; return nil }
            let alert = NSAlert()
            alert.messageText = "Choose source \(kind)"
            alert.informativeText = "Choose existing content as context. The new result will use \(OutputLanguage.title(project.operationLanguage(command)))."
            let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 28))
            picker.addItems(withTitles: choices.map { "\(OutputLanguage.title($0.language)) · \($0.title)" })
            alert.accessoryView = picker
            alert.addButton(withTitle: "Continue"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            arguments += ["--source-\(kind)-id", choices[picker.indexOfSelectedItem].id]
        }
        return arguments
    }
}

struct ExportLanguageSelectionView: View {
    let project: StudioProject
    @Binding var languages: Set<String>
    @Binding var selections: [String: [String: String]]
    var body: some View {
        Section("Languages and Saved Results") {
            ForEach(Array(Set(project.resultLanguages + [project.languageCode])).sorted(), id: \.self) { code in
                Toggle(OutputLanguage.title(code), isOn: Binding(get: { languages.contains(code) }, set: {
                    if $0 { languages.insert(code) } else { languages.remove(code) }
                }))
                if languages.contains(code) {
                    ForEach(["transcript", "summary", "descriptions", "adAudio"], id: \.self) { kind in
                        let results = project.languageResults(kind: kind, language: code).filter { kind == "adAudio" ? $0.hasContent : $0.hasExportableText }
                        if !results.isEmpty {
                            Picker(SavedLanguageResult.kindTitle(kind), selection: Binding(get: {
                                selections[code]?[kind] ?? project.activeLanguageResultID(kind, language: code)
                            }, set: { selections[code, default: [:]][kind] = $0 })) {
                                ForEach(results) { result in SavedResultOption(result: result, project: project, selected: result.id == (selections[code]?[kind] ?? project.activeLanguageResultID(kind, language: code)), transcriptID: selections[code]?["transcript"]).tag(result.id) }
                            }.pickerStyle(.menu)
                        }
                    }

                }
            }
        }
    }
}


struct LanguageCopySelection: Identifiable {
    let id = UUID()
    var kinds = ["transcript", "summary", "descriptions"]
    var segmentIDs: [String: [String]] = [:]
}

struct LanguageCopyView: View {
    @Bindable var studio: StudioModel
    let project: StudioProject
    let selection: LanguageCopySelection
    let canCopy: () -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var source: String
    @State private var target: String
    @State private var kinds: Set<String>
    @State private var versions: [String: String] = [:]
    @State private var selectedOnly: Bool
    @State private var translateText = true
    private let copyKinds = ["transcript", "summary", "descriptions"]

    init(studio: StudioModel, project: StudioProject, selection: LanguageCopySelection, canCopy: @escaping () -> Bool) {
        self.studio = studio; self.project = project; self.selection = selection; self.canCopy = canCopy
        _source = State(initialValue: project.languageCode)
        _target = State(initialValue: project.languageCode == "auto" ? "en" : project.languageCode)
        _kinds = State(initialValue: Set(selection.kinds))
        _selectedOnly = State(initialValue: false)
    }
    private func results(_ kind: String) -> [SavedLanguageResult] {
        project.languageResults(kind: kind, language: source).filter { $0.hasContent }
    }
    private func selectedID(_ kind: String) -> String {
        let rows = results(kind)
        let id = versions[kind] ?? project.activeLanguageResultID(kind, language: source)
        return rows.first { $0.id == id }?.id ?? rows.first?.id ?? ""
    }
    private var included: [String] { copyKinds.filter { kinds.contains($0) && !results($0).isEmpty && (!selectedOnly || selection.segmentIDs[$0] != nil) } }
    private var canSubmit: Bool {
        canCopy() && source != target && !included.isEmpty && (!translateText || (studio.hasValidApiKey && target != "auto"))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Copy and Translate").font(.title2.bold()).accessibilityAddTraits(.isHeader).accessibilityHeading(.h1)
            OutputLanguagePicker(title: "Source Language", selection: $source)
                .disabled(selectedOnly)
                .onChange(of: source) { versions = [:] }
            Toggle("Translate Text", isOn: $translateText)
                .onChange(of: translateText) { if translateText && target == "auto" { target = "en" } }
            OutputLanguagePicker(title: "Target Language", selection: $target, includesAuto: !translateText)
            if source == target {
                Text("Choose a different target language.").font(.caption).foregroundStyle(.secondary)
            } else if translateText && !studio.hasValidApiKey {
                Text(studio.hasApiKey ? "Gemini is unavailable. Check connection and API key." : "Add a Gemini API key in Settings.").font(.caption).foregroundStyle(.secondary)
            }
            if !selection.segmentIDs.isEmpty { Toggle("Selected Segments Only", isOn: $selectedOnly).onChange(of: selectedOnly) { if selectedOnly { source = project.languageCode; versions = [:] } } }
            HStack {
                Text("Content").font(.headline).accessibilityAddTraits(.isHeader).accessibilityHeading(.h2)
                Spacer()
                Button("Select All") { kinds = Set(copyKinds); selectedOnly = false }
            }
            ForEach(copyKinds, id: \.self) { kind in
                Toggle(SavedLanguageResult.kindTitle(kind), isOn: Binding(get: { kinds.contains(kind) }, set: {
                    if $0 { kinds.insert(kind) } else { kinds.remove(kind) }
                })).disabled(results(kind).isEmpty || (selectedOnly && selection.segmentIDs[kind] == nil))
                if included.contains(kind) {
                    if selectedOnly { Text("\(selection.segmentIDs[kind]?.count ?? 0) selected segments").font(.caption) }
                    else {
                        Picker(SavedLanguageResult.savedResultsTitle(kind), selection: Binding(get: { selectedID(kind) }, set: { versions[kind] = $0 })) {
                            ForEach(results(kind)) { Text($0.title).tag($0.id) }
                        }.pickerStyle(.menu)
                    }
                }
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(translateText ? "Translate and Copy" : "Copy") {
                    guard canSubmit else { return }
                    let ids = Dictionary(uniqueKeysWithValues: included.map { ($0, selectedID($0)) })
                    let segments = selectedOnly ? selection.segmentIDs.filter { included.contains($0.key) } : [:]
                    studio.copyLanguageResults(request: ["sourceLanguage": source, "targetLanguage": target,
                        "kinds": included, "resultIDs": ids, "segmentIDs": segments], project: project, translating: translateText)
                    dismiss()
                }.keyboardShortcut(.defaultAction).disabled(!canSubmit)
            }
        }.padding(24).frame(width: 520).disabled(studio.busy)
    }
}

extension StudioModel {
    func copyLanguageResults(request: [String: Any], project: StudioProject, translating: Bool) {
        let input = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-copy-\(UUID().uuidString).json")
        do {
            try JSONSerialization.data(withJSONObject: request).write(to: input, options: .atomic)
            execute(translating ? "translate-results" : "copy-results", extra: ["--input", input.path], project: project) { _ in try? FileManager.default.removeItem(at: input) }
        } catch { self.error = error.localizedDescription }
    }
}


struct ADAudioReadiness: Identifiable {
    let language: String
    let total: Int
    let ready: Int
    var id: String { language }
    var complete: Bool { total > 0 && ready == total }
    var title: String { "\(OutputLanguage.title(language)) · \(ready)/\(total) AD audio" }
    var accessibilityLabel: String {
        let name = OutputLanguage.title(language)
        if total == 0 { return "\(name): No AD segments. AD narration is not ready." }
        if complete { return "\(name): All \(total) AD segments have usable text and audio." }
        return "\(name): \(ready) of \(total) AD segments have usable text and audio. \(total - ready) missing or unusable. Exports using generated AD narration require complete audio."
    }
}

extension StudioProject {
    func adAudioReadiness(language code: String) -> ADAudioReadiness {
        var view = self
        if code != languageCode {
            let rid = activeLanguageResultID("descriptions", language: code)
            view.cues = savedLanguageResults.first { $0.kind == "descriptions" && $0.language == code && $0.id == rid }?.payload.cues ?? []
        }
        return ADAudioReadiness(language: code, total: view.cues.count, ready: view.cues.filter(view.hasUsableExportNarration).count)
    }
    var adAudioReadinessByLanguage: [ADAudioReadiness] {
        let codes = Set(savedLanguageResults.filter { $0.kind == "descriptions" && $0.hasContent }.map(\.language)).union([languageCode])
        return codes.sorted { $0 == languageCode ? $1 != languageCode : $1 == languageCode ? false : $0 < $1 }.map { adAudioReadiness(language: $0) }
    }
}


extension StudioProject {
    func languagesForExport(_ path: String) -> [String] {
        if let result = exportResults?[path] {
            let codes = result.languages?.isEmpty == false ? result.languages! : [result.language]
            return Array(Set(codes)).sorted()
        }
        let parts = path.split(separator: "/")
        if parts.count > 2 && parts[0] == "exports" {
            return Array(Set(parts[1].split(separator: "+").map(String.init))).sorted()
        }
        return ["auto"]
    }
    var exportLanguageCodes: [String] { Array(Set(exports.flatMap(languagesForExport))).sorted() }
    func languageGroupForExport(_ path: String) -> String {
        let codes = languagesForExport(path)
        return codes.count > 1 ? "multilingual" : codes.first ?? "auto"
    }
}


struct InspectorContentStatus: Identifiable {
    let language: String
    let complete: Bool
    let title: String
    let accessibilityLabel: String
    var id: String { language }
    static func kind(for section: String) -> String? {
        switch section {
        case "transcript", "summary": return section
        case "descriptions", "ad-overview", "ad-transcript": return "descriptions"
        default: return nil
        }
    }
}

extension StudioProject {
    func inspectorContentStatus(section: String, language code: String) -> InspectorContentStatus? {
        guard let kind = InspectorContentStatus.kind(for: section) else { return nil }
        if kind == "descriptions" {
            let status = adAudioReadiness(language: code)
            return InspectorContentStatus(language: code, complete: status.complete, title: status.title, accessibilityLabel: status.accessibilityLabel)
        }
        let resultID = activeLanguageResultID(kind, language: code)
        let payload = savedLanguageResults.first { $0.kind == kind && $0.language == code && $0.id == resultID }?.payload
        let available: Bool
        let count: Int
        if kind == "transcript" {
            let rows = code == languageCode ? transcript : payload?.transcript ?? []
            count = rows.count
            available = rows.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } else {
            let text = code == languageCode ? summary : payload?.summary ?? ""
            count = text.count
            available = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let name = kind == "transcript" ? "Transcript" : "Summary"
        let state = available ? "available" : "unavailable"
        return InspectorContentStatus(language: code, complete: available,
            title: "\(OutputLanguage.title(code)) · \(count.formatted()) \(name) \(kind == "transcript" ? "segments" : "characters")",
            accessibilityLabel: "\(OutputLanguage.title(code)): \(count) \(name.lowercased()) \(kind == "transcript" ? "segments" : "characters"). \(name) \(state) in the selected result.")
    }
    func inspectorContentStatuses(section: String) -> [InspectorContentStatus] {
        guard let kind = InspectorContentStatus.kind(for: section) else { return [] }
        let codes = Set(savedLanguageResults.filter { $0.kind == kind && $0.hasContent }.map(\.language)).union([languageCode])
        return codes.sorted { $0 == languageCode ? $1 != languageCode : $1 == languageCode ? false : $0 < $1 }
            .compactMap { inspectorContentStatus(section: section, language: $0) }
    }
    func segmentNumbers(isDescription: Bool) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: (isDescription ? cues : transcript).enumerated().map { ($0.element.id, $0.offset + 1) })
    }
}
