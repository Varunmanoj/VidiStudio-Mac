import SwiftUI

enum GeneratedContentComponent: String, CaseIterable, Identifiable, Hashable {
    case transcript
    case summary
    case descriptions
    case narration
    case thumbnails
    case exports
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcript: return "Transcript"
        case .summary: return "Summary"
        case .descriptions: return "AD Descriptions"
        case .narration: return "Narration Audio"
        case .thumbnails: return "Thumbnails"
        case .exports: return "Exports"
        case .history: return "Segment Undo History"
        }
    }

    var explanation: String {
        switch self {
        case .transcript: return "Removes transcript dialogue, including those rows from AD Transcript."
        case .summary: return "Removes the generated video summary."
        case .descriptions: return "Removes every AD segment, its narration, and its rows from AD Transcript."
        case .narration: return "Removes synthesized audio while keeping AD text and timing."
        case .thumbnails: return "Removes generated timeline thumbnails."
        case .exports: return "Removes generated subtitle, audio, and video exports."
        case .history: return "Removes the saved transcript and AD segment undo and redo states."
        }
    }

    func hasContent(in project: StudioProject) -> Bool {
        switch self {
        case .transcript:
            return project.hasGeneratedTranscript
        case .summary:
            return !project.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || project.summaryGenerated == true
        case .descriptions:
            return !project.cues.isEmpty || project.descriptionsGenerated == true
        case .narration:
            return project.cues.contains { $0.audio != nil }
        case .thumbnails:
            return !project.thumbnails.isEmpty
        case .exports:
            return !project.exports.isEmpty || project.directoryHasContent("exports")
        case .history:
            return !(project.undoStack ?? []).isEmpty || !(project.redoStack ?? []).isEmpty
                || !(project.transcriptUndoStack ?? []).isEmpty || !(project.transcriptRedoStack ?? []).isEmpty
        }
    }
}

struct GeneratedContentDeletionView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var studio: StudioModel
    let project: StudioProject
    @State private var dialogSize = CGSize(width: 680, height: 520)
    @State private var language = "all"
    @State private var selection: Set<String> = []
    @State private var components: Set<String> = []
    @State private var exportPaths: Set<String> = []
    @State private var preview: ResultDeletionPreview?
    @State private var confirming = false
    private var results: [SavedLanguageResult] {
        project.savedLanguageResults.filter { result in
            (language == "all" || result.language == language) && (components.contains(result.kind)
                || (components.contains("narration") && result.kind == "descriptions")
                || (components.contains("history") && ["transcript", "descriptions"].contains(result.kind)))
        }
    }
    private var exports: [String] {
        project.exports.filter { language == "all" || (project.exportResults?[$0]?.matches(language) ?? (language == "auto")) }
    }
    private var request: [String: Any] {
        ["resultIDs": Array(selection), "components": Array(components), "exportPaths": Array(exportPaths)]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete Content by Language").font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            Picker("Language filter", selection: $language) {
                Text("All Languages").tag("all")
                ForEach(project.deletionLanguages, id: \.self) { code in
                    Text(OutputLanguage.title(code)).tag(code)
                }
            }.pickerStyle(.menu)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Content types").font(.headline)
                    ForEach(["transcript", "summary", "descriptions", "adAudio", "narration", "history", "thumbnails"], id: \.self) { kind in
                        Toggle(deletionTitle(kind), isOn: componentMembership(kind))

                    }
                    Divider()
                    HStack {
                        Text("Saved results").font(.headline)
                        Spacer()
                        Button("Select Visible Results") { selection.formUnion(results.map(\.id)) }
                    }
                    ForEach(results) { result in
                        let option = SavedResultOption(result: result, project: project,
                            selected: result.state == "saved" && project.activeLanguageResultID(result.kind, language: result.language) == result.id,
                            includesKind: true, includesLanguage: true, includesDraft: true,
                            currentSelectionLabel: "Selected (current saved result)")
                        Toggle(isOn: membership(result.id, in: $selection)) { option }
                            .accessibilityLabel(option.spokenLabel)
                            .accessibilityIdentifier("delete-saved-result-" + result.id)
                    }
                    Divider()
                    Text("Optional exports").font(.headline)
                    ForEach(exports, id: \.self) { path in
                        Toggle(URL(fileURLWithPath: path).lastPathComponent, isOn: membership(path, in: $exportPaths))
                    }
                }
            }
            Text("Selected: \(selection.count) results, \(exportPaths.count) exports")
                .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Delete Selected…", role: .destructive) {
                    studio.previewResultDeletion(request: request, project: project) { preview = $0; confirming = true }
                }
                    .disabled(studio.busy || ((selection.isEmpty || components.isEmpty) && exportPaths.isEmpty && !components.contains("thumbnails")))
            }.fixedSize(horizontal: false, vertical: true).layoutPriority(1)
        }.padding(24)
        .frame(width: min(680, dialogSize.width), height: min(650, dialogSize.height))
        .background(SegmentDialogViewport(size: $dialogSize).frame(width: 0, height: 0))
        .onAppear {
            if let component = studio.languageDeletionComponent {
                components = [component.rawValue]
                let kind = component == .narration || component == .history ? "descriptions" : component.rawValue
                language = component == .thumbnails || component == .exports || !project.deletionLanguages.contains(project.languageCode) ? "all" : project.languageCode
                if component == .exports { exportPaths = Set(project.exports) }
                let id = project.activeLanguageResultID(kind)
                if !id.isEmpty { selection = [id] }
            }
        }
        .onChange(of: components) { _, _ in selection.formIntersection(results.map(\.id)) }
        .onChange(of: language) { _, _ in selection.formIntersection(results.map(\.id)) }
        .confirmationDialog("Delete selected content permanently?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete Selected", role: .destructive) {
                studio.executeResultRequest("delete-results", request: request, project: project)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text((preview?.text ?? "") + "\nContent types: " + components.sorted().map(deletionTitle).joined(separator: ", "))
        }
    }
    private func deletionTitle(_ kind: String) -> String {
        switch kind {
        case "descriptions": "Description Segments and Audio"
        case "narration": "Description Audio Only (Keep Segments)"
        case "history": "Segment Undo History Only"
        case "thumbnails": "Thumbnails (Entire Project)"
        default: SavedLanguageResult.kindTitle(kind)
        }
    }
    private func componentMembership(_ kind: String) -> Binding<Bool> {
        Binding(get: { components.contains(kind) }, set: { enabled in
            if enabled {
                if kind == "descriptions" { components.remove("narration") }
                if kind == "narration" { components.remove("descriptions") }
                components.insert(kind)
            } else { components.remove(kind) }
        })
    }
    private func membership(_ value: String, in values: Binding<Set<String>>) -> Binding<Bool> {
        Binding(get: { values.wrappedValue.contains(value) }, set: {
            if $0 { values.wrappedValue.insert(value) } else { values.wrappedValue.remove(value) }
        })
    }
}
