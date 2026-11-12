import SwiftUI
import AppKit

/// Owns a project-scoped command model so Settings never retargets another editor.
struct ProjectSourcesSettingsView: View {
    let reference: OpenProjectReference
    let appSettings: StudioSettings
    @Bindable var openProjects: OpenProjectRegistry
    @State private var languageActions = EditorShortcutActions()
    private var languageAvailable: Bool { !model.busy && openProjects.languageSettingsAvailable(for: reference.id) }
    private var pendingSummary: Bool { openProjects.languageEditors(for: reference.id).contains { $0.hasUnsavedSummaryEdits } }
    @Environment(\.openWindow) private var openWindow
    @State private var model = StudioModel(persistSelection: false)
    @State private var importScope: ImportScope?
    @State private var exporting = false
    @State private var youtubeDetails = false
    @State private var editingTimings = false
    private var project: StudioProject? { model.projects.first { $0.id == reference.id } }

    var body: some View {
        Group {
            if let project {
                let info = ProjectVideoInformation(project: project)
                Section {
                    LanguageResultControls(studio: model, project: project, editorActions: languageActions, showsSection: false, showsCopyControls: false,
                        kindsOverride: ["transcript", "summary", "descriptions", "adAudio"], editModeToggle: {
                            languageActions.segmentEditMode.toggle()
                        })
                } header: { Text("Language and Saved Results").accessibilityAddTraits(.isHeader).accessibilityHeading(.h2) }
                Section {
                DisclosureGroup("Show media details") {
                    InspectorInformationRow(label: "Name", value: project.name)
                    InspectorInformationRow(label: "Type", value: info.projectType)
                    InspectorInformationRow(label: "Duration", value: info.duration, spokenValue: info.spokenDuration)
                    InspectorInformationRow(label: "Folder", value: info.projectFolder)
                    InspectorInformationRow(label: info.sourceDetailLabel, value: info.sourceDetail)
                    if let url = info.sourceURL { InspectorInformationRow(label: "Source URL", value: url) }
                    InspectorInformationRow(label: "Resolution", value: info.resolution)
                    InspectorInformationRow(label: "Frame rate", value: info.frameRate)
                    InspectorInformationRow(label: "Video format", value: info.videoCodec)
                    InspectorInformationRow(label: "Audio", value: info.audio)
                }
                } header: { Text("Project and media details").accessibilityAddTraits(.isHeader).accessibilityHeading(.h2) }
                Section {
                        InspectorInformationRow(label: "Transcript", value: project.transcript.isEmpty ? "Not available" : project.transcriptAudioSource?.label ?? "Source not recorded")
                        InspectorInformationRow(label: "Summary", value: project.summary.isEmpty ? "Not available" : project.summaryOriginLabel.title + (project.summaryOriginSource.map { " · \($0)" } ?? ""))
                        InspectorInformationRow(label: "AD transcript", value: project.importedADTranscript?.sourceName ?? (project.cues.isEmpty ? "Not available" : "Project descriptions"))
                        InspectorInformationRow(label: "AD audio", value: project.importedAudioDescription?.sourceName ?? (project.hasNarrationAudio ? "Generated narration" : "Not available"))
                        if !project.isYouTubeURLProject { InspectorInformationRow(label: "Playback and export audio", value: "Original audio in the project video") }
                } header: { Text("Content sources").accessibilityAddTraits(.isHeader).accessibilityHeading(.h2) }
                if project.isYouTubeURLProject {
                    Section {
                        YouTubeAudioSourceControls(studio: model, project: project, showsSection: false).padding(.vertical, 6)
                    } header: { Text("Audio sources").accessibilityAddTraits(.isHeader).accessibilityHeading(.h2) }
                    Section { HStack {
                        Button("YouTube Details & Captions…", systemImage: "captions.bubble") { youtubeDetails = true }
                        Button("Open in YouTube", systemImage: "arrow.up.right.square") { model.openYouTubeInBrowser(project) }
                    }.disabled(model.busy) } header: { Text("YouTube video").accessibilityAddTraits(.isHeader).accessibilityHeading(.h2) }
                }
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            importButton("Import Transcript…", scope: .transcript)
                            importButton("Import Summary…", scope: .summary)
                        }
                        HStack {
                            importButton("Import Descriptions…", scope: .descriptions)
                            importButton("Import AD Audio…", scope: .adAudio)
                        }
                        HStack {
                            importButton("Import Existing Assets…", scope: .all)
                            if project.isYouTubeURLProject { importButton("Import Original Audio…", scope: .originalAudio) }
                        }
                    }.disabled(model.busy)
                } header: { Text("Import into this project").accessibilityAddTraits(.isHeader).accessibilityHeading(.h2) }
                Section {
                HStack {
                    Button("Export…", systemImage: "square.and.arrow.up") { exporting = true }
                    Button("Open in Editor", systemImage: "pencil") { openWindow(id: "project-editor", value: project.id) }
                }.disabled(model.busy)
                HStack {
                    Button("Open Project Folder", systemImage: "folder") { if let folder = project.folder { NSWorkspace.shared.open(folder) } }
                    Button("Rename…", systemImage: "pencil.line") { rename(project) }
                }.disabled(model.busy)
                } header: { Text("Project actions").accessibilityAddTraits(.isHeader).accessibilityHeading(.h2) }
                if model.busy {
                    HStack { ProgressView().controlSize(.small); Text(model.message); Button("Cancel") { model.cancelCurrentOperation() } }
                }
            } else { Text("This project is unavailable. Open its folder again from All Projects.").foregroundStyle(.secondary) }
        }
        .task(id: reference.id) { load(); configureLanguages() }
        .onChange(of: languageAvailable) { _, _ in configureLanguages() }
        .onChange(of: pendingSummary) { _, _ in configureLanguages() }
        .onReceive(NotificationCenter.default.publisher(for: .vidiStudioLanguageDidChange)) { note in
            if note.userInfo?["projectID"] as? String == reference.id { load(); configureLanguages() }
        }
        .onChange(of: appSettings) { _, value in model.applyExternalSettings(value) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in if !model.busy { load() } }
        .sheet(item: $importScope) { scope in
            if let project { ImportExistingAssetsView(studio: model, project: project, scope: scope) }
        }
        .sheet(isPresented: $exporting) {
            if let project { ExportDialog(project: project, busy: model.busy, studio: model) { action, replace in
                model.execute(action.command, extra: action.arguments(replacingExisting: replace), project: project)
            } }
        }
        .sheet(isPresented: $youtubeDetails) {
            if let project { ScrollView { YouTubeDetailsView(studio: model, project: project, startWithCaptions: true) } }
        }
        .sheet(isPresented: Binding(get: { !model.importReports.isEmpty && importScope == nil }, set: { if !$0 { model.clearImportReports() } })) {
            ImportReportSheet(reports: model.importReports, canEditTranscriptTimings: !(project?.transcript.isEmpty ?? true), showsReviewActions: false,
                onEditTranscriptTimings: { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { editingTimings = true } },
                onClose: { model.clearImportReports() })
        }
        .sheet(isPresented: $editingTimings) { if let project { TranscriptTimingEditorView(studio: model, project: project) } }
        .alert(model.errorTitle, isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.dismissError() } })) {
            Button("OK", role: .cancel) { model.dismissError() }
        } message: { Text(model.error ?? "") }
    }
    private func importButton(_ title: String, scope: ImportScope) -> some View {
        Button(title, systemImage: "square.and.arrow.down") { importScope = scope }
    }
    private func load() {
        model.applyExternalSettings(appSettings)
        model.reload()
        if project == nil, let folder = reference.folder, let value = StudioModel.loadProject(at: folder) { model.projects.append(value) }
        model.selectedID = reference.id
    }
    private func configureLanguages() {
        languageActions.available = languageAvailable
        languageActions.hasUnsavedSummaryEdits = pendingSummary
        languageActions.activeSection = "descriptions"
        languageActions.languageAction = { command, arguments in
            guard languageAvailable, !pendingSummary, let project else { return }
            let editing = ["select-section-language", "sync-section-languages", "assign-result-language"].contains(command)
            guard !editing || languageActions.segmentEditMode else { return }
            NotificationCenter.default.post(name: .vidiStudioLanguageWillChange, object: nil, userInfo: ["projectID": project.id])
            if let editor = openProjects.languageEditors(for: project.id).first, let action = editor.settingsLanguageAction {
                action(command, arguments, languageActions.segmentEditMode)
            } else {
                model.execute(command, extra: arguments, project: project) { _ in
                    NotificationCenter.default.post(name: .vidiStudioLanguageDidChange, object: nil, userInfo: ["projectID": project.id])
                }
            }
        }
    }
    private func rename(_ project: StudioProject) {
        let dialog = NSAlert(); dialog.messageText = "Rename project"
        let field = NSTextField(string: project.name); field.frame.size = NSSize(width: 320, height: 24)
        dialog.accessoryView = field; dialog.addButton(withTitle: "Rename"); dialog.addButton(withTitle: "Cancel")
        guard dialog.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != project.name else { return }
        model.execute("rename-project", extra: ["--name", name], project: project)
    }
}
