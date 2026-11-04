import SwiftUI
import AppKit

/// Owns a project-scoped command model so Settings never retargets another editor.
struct ProjectSourcesSettingsView: View {
    let reference: OpenProjectReference
    let appSettings: StudioSettings
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
                Section("Project and media details") {
                DisclosureGroup("Show media details") {
                    InspectorInformationRow(label: "Name", value: project.name)
                    InspectorInformationRow(label: "Type", value: info.projectType)
                    InspectorInformationRow(label: "Duration", value: info.duration)
                    InspectorInformationRow(label: "Folder", value: info.projectFolder)
                    InspectorInformationRow(label: info.sourceDetailLabel, value: info.sourceDetail)
                    if let url = info.sourceURL { InspectorInformationRow(label: "Source URL", value: url) }
                    InspectorInformationRow(label: "Resolution", value: info.resolution)
                    InspectorInformationRow(label: "Frame rate", value: info.frameRate)
                    InspectorInformationRow(label: "Video format", value: info.videoCodec)
                    InspectorInformationRow(label: "Audio", value: info.audio)
                }
                }
                Section("Content sources") {
                        InspectorInformationRow(label: "Transcript", value: project.transcript.isEmpty ? "Not available" : project.transcriptAudioSource?.label ?? "Source not recorded")
                        InspectorInformationRow(label: "Summary", value: project.summary.isEmpty ? "Not available" : project.summaryOriginLabel.title + (project.summaryOriginSource.map { " · \($0)" } ?? ""))
                        InspectorInformationRow(label: "AD transcript", value: project.importedADTranscript?.sourceName ?? (project.cues.isEmpty ? "Not available" : "Project descriptions"))
                        InspectorInformationRow(label: "AD audio", value: project.importedAudioDescription?.sourceName ?? (project.hasNarrationAudio ? "Generated narration" : "Not available"))
                        if !project.isYouTubeURLProject { InspectorInformationRow(label: "Playback and export audio", value: "Original audio in the project video") }
                }
                if project.isYouTubeURLProject {
                    Section("Audio sources") {
                        YouTubeAudioSourceControls(studio: model, project: project, showsSection: false).padding(.vertical, 6)
                    }
                    Section("YouTube video") { HStack {
                        Button("YouTube Details & Captions…", systemImage: "captions.bubble") { youtubeDetails = true }
                        Button("Open in YouTube", systemImage: "arrow.up.right.square") { model.openYouTubeInBrowser(project) }
                    }.disabled(model.busy) }
                }
                Section("Import into this project") {
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
                        if project.isYouTubeURLProject {
                            Text("Import Transcript and Import Existing Assets also offer Download YouTube Captions. Caption downloads require video-edit permission.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.disabled(model.busy)
                }
                Section("Project actions") {
                HStack {
                    Button("Export…", systemImage: "square.and.arrow.up") { exporting = true }
                    Button("Open in Editor", systemImage: "pencil") { openWindow(id: "project-editor", value: project.id) }
                }.disabled(model.busy)
                HStack {
                    Button("Open Project Folder", systemImage: "folder") { if let folder = project.folder { NSWorkspace.shared.open(folder) } }
                    Button("Rename…", systemImage: "pencil.line") { rename(project) }
                }.disabled(model.busy)
                Text("Project source choices and imports are saved immediately. Narration engine and voice choices are managed in the Narration tab.")
                    .font(.caption).foregroundStyle(.secondary)
                }
                if model.busy {
                    HStack { ProgressView().controlSize(.small); Text(model.message); Button("Cancel") { model.cancelCurrentOperation() } }
                }
            } else { Text("This project is unavailable. Open its folder again from All Projects.").foregroundStyle(.secondary) }
        }
        .task(id: reference.id) { load() }
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
        if project == nil, let folder = reference.folder,
           let data = try? Data(contentsOf: folder.appendingPathComponent("project.json")),
           var value = try? JSONDecoder().decode(StudioProject.self, from: data) {
            value.folder = folder; model.projects.append(value)
        }
        model.selectedID = reference.id
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
