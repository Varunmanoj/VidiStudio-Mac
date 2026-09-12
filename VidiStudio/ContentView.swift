import SwiftUI
import AVKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

private enum NewProjectSource: String, CaseIterable, Identifiable {
    case videoFile
    case youtube

    var id: Self { self }
    var title: String { self == .videoFile ? "Video File" : "YouTube Video" }
    var icon: String { self == .videoFile ? "film" : "play.rectangle" }
}

private struct NewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var studio: StudioModel
    @State private var source = NewProjectSource.videoFile
    @State private var videoURL: URL?
    @State private var youtubeURL = ""
    @State private var youtubePreview: YouTubeProjectPreview?
    @State private var youtubeFetchError: String?
    @State private var fetchingYouTube = false

    private var trimmedYouTubeURL: String {
        youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        source == .videoFile ? videoURL != nil : youtubePreview != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Project")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)
            Form {
            Section {
                Picker("Project type", selection: $source) {
                    ForEach(NewProjectSource.allCases) { option in
                        Label(option.title, systemImage: option.icon).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
                .accessibilityHint("Choose a video file from this Mac or enter a YouTube video link.")
            } header: {
                Text("Choose a project source")
            }

            Section {
                if source == .videoFile {
                    LabeledContent("Video file") {
                        Button(videoURL == nil ? "Choose Video…" : "Choose Different Video…", systemImage: "folder") {
                            chooseVideo()
                        }
                    }
                    Text(videoURL?.path ?? "No video selected")
                        .font(.caption)
                        .foregroundStyle(videoURL == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                        .accessibilityLabel(videoURL.map { "Selected video: \($0.lastPathComponent)" } ?? "No video selected")
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField("YouTube video URL", text: $youtubeURL, prompt: Text("https://www.youtube.com/watch?v=…"))
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("YouTube video URL")
                            Button("Fetch Details") {
                                Task { await fetchYouTubeDetails() }
                            }
                            .disabled(trimmedYouTubeURL.isEmpty || fetchingYouTube)
                            .accessibilityHint("Fetch the video's project name and thumbnail for review.")
                        }
                        if fetchingYouTube {
                            ProgressView("Fetching video details…")
                                .controlSize(.small)
                        }
                        if let youtubeFetchError {
                            Label(youtubeFetchError, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .accessibilityLabel("Could not fetch video details. \(youtubeFetchError)")
                        }
                        if let youtubePreview {
                            HStack(alignment: .top, spacing: 12) {
                                Image(nsImage: youtubePreview.thumbnail)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 180, height: 101)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .accessibilityLabel("Thumbnail for \(youtubePreview.title)")
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Project name")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(youtubePreview.title)
                                        .font(.headline)
                                        .textSelection(.enabled)
                                    Text(youtubePreview.canonicalURL)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(10)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                            Text("Review these details before creating the project.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(source.title)
            } footer: {
                Text(source == .videoFile
                     ? "VidiStudio copies the selected video into a new local project folder."
                     : "Fetch and review the video details first. VidiStudio stores the project locally; playback and analysis require an internet connection.")
            }

            Section {
                HStack {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Create Project", systemImage: "plus") { createProject() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canCreate)
                }
            }
            }
            .formStyle(.grouped)
        }
        .frame(width: 600, height: source == .youtube ? 570 : 410)
        .onChange(of: youtubeURL) {
            youtubePreview = nil
            youtubeFetchError = nil
        }
        .alert(studio.errorTitle, isPresented: Binding(get: { studio.error != nil }, set: { if !$0 { studio.dismissError() } })) {
            if studio.canRetryLastFailure {
                Button("Retry \(studio.lastFailureTitle ?? "Analysis")") { studio.retryLastFailure() }
            }
            Button("OK", role: .cancel) { studio.dismissError() }
        } message: {
            Text((studio.error ?? "") + (studio.canRetryLastFailure ? "\n\nThe app already retried automatically 3 times. You can retry manually once more." : ""))
        }
    }

    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Video"
        panel.message = "Choose the video file for this VidiStudio project."
        if panel.runModal() == .OK, let selectedURL = panel.url,
           studio.validateLocalVideoForCreation(selectedURL) {
            videoURL = selectedURL
        }
    }

    private func createProject() {
        let started: Bool
        switch source {
        case .videoFile:
            guard let videoURL else { return }
            started = studio.importVideo(at: videoURL)
        case .youtube:
            guard let youtubePreview else { return }
            started = studio.importYouTube(at: youtubePreview.canonicalURL, name: youtubePreview.title)
        }
        if started { dismiss() }
    }

    @MainActor
    private func fetchYouTubeDetails() async {
        let requestedURL = trimmedYouTubeURL
        guard studio.validateYouTubeForCreation(requestedURL) else { return }
        youtubePreview = nil
        youtubeFetchError = nil
        fetchingYouTube = true
        defer { fetchingYouTube = false }
        do {
            let preview = try await YouTubeProjectPreviewFetcher.fetch(requestedURL)
            guard requestedURL == trimmedYouTubeURL else { return }
            youtubePreview = preview
        } catch {
            guard requestedURL == trimmedYouTubeURL else { return }
            youtubeFetchError = error.localizedDescription
        }
    }
}

struct ContentView: View {
    @Bindable var studio: StudioModel
    @Environment(\.openWindow) private var openWindow
    @State private var search = ""
    @State private var sourceFilter = ProjectSourceFilter.all
    @State private var rename = ""
    @State private var renaming = false
    @State private var deletionProject: StudioProject?
    @AppStorage("projectBrowserGrid") private var projectGrid = false
    @AppStorage("projectGridItemSize") private var projectGridItemSize = 180.0

    private func openEditor(_ project: StudioProject) {
        studio.selectedID = project.id
        // The project ID is the WindowGroup value and therefore its window identity.
        // Reopening the same value activates that editor instead of creating a duplicate.
        openWindow(id: "project-editor", value: project.id)
    }

    var body: some View {
        ProjectBrowserPage(
            projects: studio.projects,
            search: $search,
            sourceFilter: $sourceFilter,
            grid: $projectGrid,
            gridItemSize: $projectGridItemSize,
            selection: $studio.selectedID,
            busy: studio.busy,
            newProject: { studio.isCreatingProject = true },
            openProjectFolder: {
                studio.openProject()
                if let project = studio.selected { openEditor(project) }
            },
            openEditor: openEditor,
            rename: { p in studio.selectedID = p.id; rename = p.name; renaming = true },
            delete: { studio.trashProject($0) },
            process: { p in studio.selectedID = p.id; studio.execute("analyze", project: p) },
            export: { project, action in
                studio.execute(action.command, extra: action.arguments, project: project)
            },
            clear: { deletionProject = $0 }
        )
        .background(WindowFitter().frame(width: 0, height: 0))
        .focusedSceneValue(\.projectBrowser, ProjectBrowserActions(
            showProjects: nil,
            showInspector: nil,
            grid: $projectGrid,
            hasProject: false,
            hasSelectedProject: studio.selected != nil,
            openSelectedProject: { if let project = studio.selected { openEditor(project) } }
        ))
        .preferredColorScheme(studio.settings.theme == "dark" ? .dark : studio.settings.theme == "light" ? .light : nil)
        .sheet(isPresented: $renaming) {
            VStack(spacing: 20) {
                TextField("Project name", text: $rename)
                HStack { Button("Cancel", role: .cancel) { renaming = false }; Button("Rename", systemImage: "pencil") { studio.execute("rename-project", extra: ["--name", rename]); renaming = false }.keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 420)
        }
        .sheet(item: $deletionProject) { project in
            GeneratedContentDeletionView(studio: studio, project: project)
        }
        .sheet(isPresented: $studio.isCreatingProject) {
            NewProjectView(studio: studio)
        }
        .alert(studio.errorTitle, isPresented: Binding(get: { studio.error != nil }, set: { if !$0 { studio.dismissError() } })) {
            if studio.canRetryLastFailure {
                Button("Retry \(studio.lastFailureTitle ?? "Analysis")") { studio.retryLastFailure() }
            }
            Button("OK", role: .cancel) { studio.dismissError() }
        } message: {
            Text((studio.error ?? "") + (studio.canRetryLastFailure ? "\n\nThe app already retried automatically 3 times. You can retry manually once more." : ""))
        }
        .onReceive(NotificationCenter.default.publisher(for: .vidiStudioSettingsDidChange)) { notification in
            guard let source = notification.object as? StudioModel,
                  source !== studio,
                  let settings = notification.userInfo?["settings"] as? StudioSettings else { return }
            studio.applyExternalSettings(settings)
        }
    }
}

struct ProjectEditorWindow: View {
    let projectID: String
    let openProjects: OpenProjectRegistry
    @State private var studio: StudioModel
    @State private var editorShortcutActions = EditorShortcutActions()
    @State private var showInspector = true
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    init(projectID: String, openProjects: OpenProjectRegistry) {
        self.projectID = projectID
        self.openProjects = openProjects
        let model = StudioModel()
        model.selectedID = projectID
        _studio = State(initialValue: model)
    }

    private func returnToAllProjects() {
        openWindow(id: "studio")
        dismiss()
    }

    var body: some View {
        GeometryReader { geometry in
            if let project = studio.selected {
                HStack(spacing: 0) {
                    ProjectEditor(
                        shortcutsBlocked: studio.error != nil,
                        studio: studio,
                        project: project,
                        shortcutActions: editorShortcutActions
                    )
                    .id(project.id)
                    .frame(width: max(0, geometry.size.width - (showInspector ? 273 : 0)), height: geometry.size.height)
                    if showInspector {
                        Divider()
                        ProcessingInspector(studio: studio, editorActions: editorShortcutActions)
                            .frame(width: 272, height: geometry.size.height)
                            .background(.bar)
                    }
                }
            } else {
                ContentUnavailableView("Project Unavailable", systemImage: "film", description: Text("The project may have moved or been deleted."))
            }
        }
        .background(WindowFitter().frame(width: 0, height: 0))
        .focusedSceneValue(\.projectBrowser, ProjectBrowserActions(
            showProjects: nil,
            showInspector: $showInspector,
            grid: nil,
            hasProject: studio.selected != nil,
            hasSelectedProject: false,
            openSelectedProject: nil
        ))
        // Keep the focused command bridge above the playhead-driven editor.
        // Its identity now remains stable while playback updates every 150 ms,
        // so an open menu does not get rebuilt and lose focus.
        .focusedSceneValue(\.editorShortcuts, studio.selected == nil ? nil : editorShortcutActions)
        .preferredColorScheme(studio.settings.theme == "dark" ? .dark : studio.settings.theme == "light" ? .light : nil)
        .navigationTitle(studio.selected?.name ?? "Project Editor")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Back to All Projects", systemImage: "chevron.backward", action: returnToAllProjects)
                    .labelStyle(.iconOnly)
                    .help("Return to all projects")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(showInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right") { showInspector.toggle() }
                    .labelStyle(.iconOnly)
            }
        }
        .alert(studio.errorTitle, isPresented: Binding(get: { studio.error != nil }, set: { if !$0 { studio.dismissError() } })) {
            if studio.canRetryLastFailure {
                Button("Retry \(studio.lastFailureTitle ?? "Analysis")") { studio.retryLastFailure() }
            }
            Button("OK", role: .cancel) { studio.dismissError() }
        } message: {
            Text((studio.error ?? "") + (studio.canRetryLastFailure ? "\n\nThe app already retried automatically 3 times. You can retry manually once more." : ""))
        }
        .onAppear {
            studio.reload()
            studio.selectedID = projectID
            openProjects.open(projectID, name: studio.selected?.name ?? "Project")
        }
        .onChange(of: studio.selected?.name) { _, name in
            if let name { openProjects.open(projectID, name: name) }
        }
        .onDisappear { openProjects.close(projectID) }
        .onReceive(NotificationCenter.default.publisher(for: .vidiStudioSettingsDidChange)) { notification in
            guard let settings = notification.userInfo?["settings"] as? StudioSettings else { return }
            guard let source = notification.object as? StudioModel, source !== studio else { return }
            studio.applyExternalSettings(settings)
        }
    }
}

struct ProcessingInspector: View {
    @Bindable var studio: StudioModel
    let editorActions: EditorShortcutActions

    private var currentComponent: GeneratedContentComponent? {
        switch editorActions.activeSection {
        case "transcript": return .transcript
        case "summary": return .summary
        case "descriptions": return .descriptions
        default: return nil
        }
    }

    private var currentSectionTitle: String? {
        switch editorActions.activeSection {
        case "transcript": return "Transcript"
        case "summary": return "Summary"
        case "descriptions": return "Descriptions"
        case "ad-overview": return "Narration"
        default: return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let p = studio.selected {
                    GroupBox("Analysis") {
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Run All Analysis", systemImage: "sparkles") { editorActions.run("analyze") }
                                .disabled(!editorActions.canRun("analyze"))
                                .help("Generate the transcript, summary, and audio descriptions in sequence")
                            Button { editorActions.run("regenerate-all") } label: {
                                HStack { MaterialIcon(glyph: ""); Text("Regenerate All…") }
                            }
                            .disabled(!editorActions.canRun("regenerate-all"))
                            .help("Delete generated analysis and recreate the transcript, summary, and descriptions")
                        }
                    }
                    if let sectionTitle = currentSectionTitle {
                        GroupBox(sectionTitle) {
                            VStack(alignment: .leading, spacing: 8) {
                                if let action = editorActions.currentGenerationAction,
                                   let title = editorActions.currentGenerationTitle {
                                    HStack(spacing: 6) {
                                        Button(title, systemImage: editorActions.currentGenerationIcon) {
                                            editorActions.run(action)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .disabled(!editorActions.canRun(action))
                                        .help(action == "generate-ad-cues" && !p.canGenerateDescriptions
                                            ? "Generate the transcript and summary first"
                                            : title.hasPrefix("Regenerate")
                                                ? "Replace the current \(sectionTitle.lowercased()) after confirmation"
                                                : "Generate the \(sectionTitle.lowercased()) for this project")
                                        if let component = currentComponent, component.hasContent(in: p) {
                                            Button("Delete \(component.title)", systemImage: "trash", role: .destructive) {
                                                studio.confirmDeleteGeneratedContent(p, component: component)
                                            }
                                            .labelStyle(.iconOnly)
                                            .help("Delete \(component.title.lowercased())")
                                            .disabled(studio.busy)
                                        }
                                    }
                                }
                                if editorActions.activeSection == "descriptions" || editorActions.activeSection == "ad-overview" {
                                    HStack(spacing: 6) {
                                        Button("Synthesize Narration", systemImage: "speaker.wave.2") {
                                            editorActions.run("synthesize-tts")
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .disabled(!editorActions.canRun("synthesize-tts"))
                                        .help("Create narration audio for all Audio Description segments")
                                        if GeneratedContentComponent.narration.hasContent(in: p) {
                                            Button("Delete Narration Audio", systemImage: "trash", role: .destructive) {
                                                studio.confirmDeleteGeneratedContent(p, component: .narration)
                                            }
                                            .labelStyle(.iconOnly)
                                            .help("Delete narration audio while keeping description text and timing")
                                            .disabled(studio.busy)
                                        }
                                    }
                                    Button("Synthesize Changed Segments", systemImage: "waveform") {
                                        editorActions.run("synthesize-changed")
                                    }
                                    .disabled(!editorActions.canRun("synthesize-changed"))
                                    .help("Recreate narration only for descriptions whose text changed")
                                }
                                if editorActions.activeSection == "descriptions" {
                                    HStack(spacing: 6) {
                                        Button("Undo Segment Edit", systemImage: "arrow.uturn.backward") { editorActions.run("undo") }
                                            .help("Undo the most recent saved description edit")
                                        Button("Redo", systemImage: "arrow.uturn.forward") { editorActions.run("redo") }
                                            .help("Redo the most recently undone description edit")
                                    }
                                    .disabled(studio.busy)
                                }
                            }
                        }
                    }
                    GroupBox("Export") {
                        ProjectExportMenu(
                            project: p,
                            busy: studio.busy,
                            perform: { action in studio.execute(action.command, extra: action.arguments) }
                        )
                        .help("Export video, narration audio, or text in the format you need")
                    }
                    GroupBox("Project") {
                        Button("Show Project in Finder", systemImage: "folder") { if let folder = p.folder { NSWorkspace.shared.open(folder) } }
                            .help("Open this project’s local folder in Finder")
                    }
                    if !p.exports.isEmpty {
                        GroupBox("Created Exports") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(p.exports, id: \.self) { path in
                                    HStack(spacing: 6) {
                                        Button(URL(fileURLWithPath: path).lastPathComponent, systemImage: "play.rectangle") {
                                            if let url = p.url(path) { NSWorkspace.shared.open(url) }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Button("Delete Export", systemImage: "trash", role: .destructive) {
                                            studio.confirmDeleteExport(p, path: path)
                                        }
                                        .labelStyle(.iconOnly)
                                        .help("Delete \(URL(fileURLWithPath: path).lastPathComponent)")
                                        .disabled(studio.busy)
                                    }
                                }
                            }
                        }
                    }
                }
            }.padding(20)
        }
    }
}

private struct TranscriptRow: Identifiable {
    let segment: Segment
    let isDescription: Bool
    var id: String { (isDescription ? "ad:" : "transcript:") + segment.id }
    var kind: String { isDescription ? "Audio description" : "Transcript" }
    var color: Color { isDescription ? .purple : .blue }
    var playbackLabel: String {
        "Play \(kind.lowercased()) from \(String(format: "%.3f", segment.start)) to \(String(format: "%.3f", segment.end)) seconds: \(segment.text)"
    }
}

struct ProjectEditor: View {
    var shortcutsBlocked = false
    @Bindable var studio: StudioModel
    let project: StudioProject
    let shortcutActions: EditorShortcutActions
    @State private var playback = PlaybackModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab = "transcript"
    @State private var requestedTitle = ""
    @State private var previewHidden = false
    @State private var previewHeight: CGFloat = 413
    @State private var previewHeightAtDragStart: CGFloat?
    @State private var cueToEdit: Segment?
    @State private var audioPreview: AVAudioPlayer?
    @State private var activePreviewCueID: String?
    @State private var previewPaused = false
    @State private var segmentScreenText: String?
    @State private var readingFrameForSegment = false
    @State private var followTranscript = true
    @State private var summaryReader = SummaryReadbackModel()
    private var transcriptRows: [TranscriptRow] {
        let dialogue = project.transcript.map { TranscriptRow(segment: $0, isDescription: false) }
        let descriptions = project.cues.map { TranscriptRow(segment: $0, isDescription: true) }
        let rows = tab == "descriptions" ? descriptions : tab == "ad-transcript" ? dialogue + descriptions : dialogue
        return rows.sorted {
            if $0.segment.start != $1.segment.start { return $0.segment.start < $1.segment.start }
            return $0.id < $1.id
        }
    }

    private var generationAction: (command: String, title: String, icon: String)? {
        switch tab {
        case "transcript":
            return ("transcribe", project.hasGeneratedTranscript ? "Regenerate Transcript" : "Generate Transcript", "text.bubble")
        case "summary":
            let hasSummary = !project.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return ("generate-summary", hasSummary ? "Regenerate Summary" : "Generate Summary", "text.alignleft")
        case "descriptions":
            return ("generate-ad-cues", project.cues.isEmpty ? "Generate Descriptions" : "Regenerate Descriptions", "sparkles")
        default:
            return nil
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Picker("Editor section", selection: $tab) {
                        Text("Transcript").tag("transcript")
                        Text("Summary").tag("summary")
                        Text("Descriptions").tag("descriptions")
                        Text("AD Overview").tag("ad-overview")
                        Text("AD Transcript").tag("ad-transcript")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 200)
                    Button(previewHidden ? "Show Preview" : "Hide Preview", systemImage: previewHidden ? "video" : "video.slash") {
                        playback.exitVideoFullScreen()
                        previewHidden.toggle()
                    }
                    .labelStyle(.iconOnly)
                    .help(previewHidden ? "Show video preview" : "Hide video preview to focus on editing")
                    Button("Full-Screen Video", systemImage: "arrow.up.left.and.arrow.down.right") {
                        previewHidden = false
                        DispatchQueue.main.async { playback.toggleVideoFullScreen() }
                    }
                    .labelStyle(.iconOnly)
                    .help("View video full screen; press Escape to return")
                    Button("Read Frame Text", systemImage: "text.viewfinder") {
                        readCurrentFrameText()
                    }
                    .labelStyle(.iconOnly)
                    .help("Extract text from the current video frame")
                    .disabled(studio.busy)
                    if tab == "transcript" || tab == "ad-transcript" || tab == "descriptions" {
                        Toggle("Narration", isOn: $playback.narrationEnabled)
                            .toggleStyle(.button)
                            .help("Play generated descriptions in sync with video")
                        Toggle("Follow", isOn: $followTranscript)
                            .toggleStyle(.button)
                            .help("Follow the active transcript or description")
                    }
                }
            }
            if let action = generationAction {
                Button(action.title, systemImage: action.icon) { studio.execute(action.command) }
                    .disabled(studio.busy || (action.command == "generate-ad-cues" && !project.canGenerateDescriptions))
                    .help(action.command == "generate-ad-cues" && !project.canGenerateDescriptions
                        ? "Generate the transcript and summary first"
                        : action.title.hasPrefix("Regenerate") ? "Replace the existing content after confirmation" : "Generate content for this section")
                    .fixedSize()
            }
            if tab == "descriptions" {
                Button("Add Segment", systemImage: "plus") { presentNewSegment() }
                    .disabled(studio.busy)
                    .fixedSize()
            }
        }
        .controlSize(.small)
        .padding(12)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var processingControlBar: some View {
        if studio.busy {
            HStack(spacing: 12) {
                Text(studio.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityLabel("Processing status: \(studio.message)")
                Spacer(minLength: 12)
                Button {
                    studio.process?.terminate()
                } label: {
                    HStack(spacing: 6) {
                        MaterialIcon(glyph: "\u{e047}")
                        Text("Cancel Processing")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .fixedSize()
                .accessibilityLabel("Cancel Processing")
                .accessibilityHint("Stops the current processing operation. Completed results remain saved.")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private var screenTextPresented: Binding<Bool> {
        Binding(
            get: { studio.screenText != nil && !readingFrameForSegment },
            set: { if !$0 { studio.screenText = nil } }
        )
    }

    private var screenTextReview: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Screen Text").font(.title2)
            ScrollView {
                Text(studio.screenText?.isEmpty == false ? studio.screenText! : "No readable text in this frame.")
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
            HStack {
                Button("Close") { studio.screenText = nil }
                Spacer()
                Button("Add as Description", systemImage: "text.badge.plus") {
                    cueToEdit = Segment(id: UUID().uuidString, start: studio.screenTimestamp, end: min(project.duration, studio.screenTimestamp + 3), text: studio.screenText ?? "", origin: "ai", aiOriginalText: studio.screenText)
                    studio.screenText = nil
                }
                .disabled(studio.screenText?.isEmpty != false)
            }
        }
        .padding(24)
        .frame(width: 540)
    }

    private func cueEditor(for cue: Segment) -> some View {
        CueEditor(
            cue: cue,
            duration: project.duration,
            transcript: project.transcript,
            otherDescriptions: project.cues.filter { $0.id != cue.id },
            capturedScreenText: $segmentScreenText,
            isReadingFrame: readingFrameForSegment,
            readFrame: readFrameForSegment
        ) { updated in
            var cues = project.cues.filter { $0.id != updated.id }
            cues.append(updated)
            studio.saveCues(cues)
        }
    }

    private func preparePlayback() {
        playback.observe()
        playback.narrationEnabled = ProjectPlaybackPreferences.narrationEnabled(project.id)
        followTranscript = ProjectPlaybackPreferences.followEnabled(project.id)
        guard !project.isYouTubeURLProject,
              !project.source.isEmpty,
              let url = project.url(project.source) else { return }
        playback.player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }

    private func handleBusyChange(_ busy: Bool) {
        if !busy, readingFrameForSegment, studio.screenText == nil { readingFrameForSegment = false }
        guard !busy else { return }
        updateYouTubeTitleIfNeeded(playback.videoTitle)
    }

    private func updateYouTubeTitleIfNeeded(_ title: String) {
        let youtubeID = project.youtubeURL?.components(separatedBy: "v=").last ?? ""
        let isPlaceholder = project.name == "YouTube video" || project.name == "YouTube Project" || project.name == "YouTube " + youtubeID
        guard !studio.busy, !title.isEmpty, requestedTitle != title, isPlaceholder else { return }
        requestedTitle = title
        studio.execute("update-metadata", extra: ["--name", title])
    }

    private func handleScreenText(_ text: String?) {
        guard readingFrameForSegment, let text else { return }
        segmentScreenText = text
        studio.screenText = nil
        readingFrameForSegment = false
    }

    private func playableNarrationURL(for cue: Segment) -> URL? {
        guard SynchronizedAudioStatus.resolve(
            cue: cue,
            project: project
        ) == .generated,
        let audio = cue.audio else { return nil }
        return project.url(audio)
    }

    private func previewNarration(for cue: Segment) {
        guard let url = playableNarrationURL(for: cue) else { return }
        if activePreviewCueID == cue.id, let audioPreview {
            if audioPreview.isPlaying {
                audioPreview.pause()
                previewPaused = true
            } else {
                audioPreview.play()
                previewPaused = false
            }
            return
        }
        do {
            stopNarrationPreview()
            let player = try AVAudioPlayer(contentsOf: url)
            audioPreview = player
            activePreviewCueID = cue.id
            previewPaused = false
            player.play()
        } catch {
            studio.error = "Could not play this segment’s narration: \(error.localizedDescription)"
        }
    }

    private func stopNarrationPreview() {
        audioPreview?.stop()
        audioPreview = nil
        activePreviewCueID = nil
        previewPaused = false
    }

    private func previewControlTitle(for cue: Segment) -> String {
        guard activePreviewCueID == cue.id else { return "Play Narration" }
        return audioPreview?.isPlaying == true ? "Pause Narration" : "Resume Narration"
    }

    private func previewControlIcon(for cue: Segment) -> String {
        activePreviewCueID == cue.id && audioPreview?.isPlaying == true ? "pause.circle" : "play.circle"
    }

    private var previewPane: some View {
        VStack(spacing: 0) {
            Group {
                if project.isYouTubeURLProject, let url = project.youtubeURL { YouTubePlayer(url: url, playback: playback) }
                else { NativeVideoPlayer(player: playback.player, playback: playback) }
            }
            .frame(minWidth: 0, idealWidth: 700, maxWidth: .infinity, minHeight: 120, idealHeight: 340, maxHeight: .infinity)
            .background(.black)
            TimelineView(project: project, playback: playback)
        }
    }

    @ViewBuilder
    private var editorPane: some View {
        VStack(spacing: 0) {
            processingControlBar
            editorToolbar
            if let error = playback.speechError { Text(error).foregroundStyle(.red).padding(8) }
            Divider()
            if studio.busy {
                VStack {
                    Spacer(minLength: 24)
                    ProgressView()
                        .controlSize(.large)
                        .scaleEffect(2)
                        .frame(width: 88, height: 88)
                        .accessibilityLabel("Processing")
                        .accessibilityValue(studio.message)
                        .accessibilityHint("VidiStudio is working. This indicator continues spinning until processing finishes.")
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tab == "ad-overview" {
                ADOverviewView(studio: studio, project: project)
            } else if tab == "summary" {
                SummaryReaderView(
                    markdown: project.summary.isEmpty ? "Generate a summary after transcription to capture the story and visual context." : project.summary,
                    model: summaryReader,
                    settings: studio.settings,
                    follow: followTranscript,
                    hasSummary: !project.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            } else {
                let segments = transcriptRows
                if segments.isEmpty {
                    ContentUnavailableView(tab == "descriptions" ? "Describe what matters" : "Your transcript appears here", systemImage: tab == "descriptions" ? "text.below.photo" : "text.bubble", description: Text(tab == "descriptions" ? "Generate descriptions from the inspector or add a segment manually." : tab == "ad-transcript" ? "Transcribe the video or add audio descriptions to see them together here." : "Use Transcribe Video in the inspector to begin."))
                } else {
                    ScrollViewReader { reader in
                    List(segments) { row in
                        let cue = row.segment
                        HStack(alignment: .top, spacing: 16) {
                            if tab == "transcript" || tab == "ad-transcript" {
                                Button {
                                    if row.isDescription { playback.narrationEnabled = true }
                                    playback.play(from: cue.start)
                                } label: {
                                    MaterialIcon(glyph: "\u{e037}")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(row.playbackLabel)
                                .help(row.playbackLabel)
                            }
                            Button { playback.seek(cue.start) } label: {
                                VStack { Text(timecode(cue.start)); Text(timecode(cue.end)).foregroundStyle(.secondary) }.monospacedDigit().font(.caption)
                            }.buttonStyle(.plain).help("Seek to \(timecode(cue.start))")
                            VStack(alignment: .leading, spacing: 6) {
                                if tab == "ad-transcript" {
                                    HStack(spacing: 6) {
                                        MaterialIcon(glyph: row.isDescription ? "\u{e050}" : "\u{e0b7}")
                                        Text(row.kind).font(.caption.bold())
                                    }
                                    .foregroundStyle(row.color)
                                }
                                if row.isDescription {
                                    DescriptionOriginLabel(origin: cue.provenance)
                                    SynchronizedAudioStatusLabel(
                                        status: .resolve(
                                            cue: cue,
                                            project: project
                                        )
                                    )
                                }
                                Text(cue.text).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if tab == "descriptions" {
                                Button(previewControlTitle(for: cue), systemImage: previewControlIcon(for: cue)) { previewNarration(for: cue) }
                                    .labelStyle(.iconOnly)
                                    .disabled(studio.busy || playableNarrationURL(for: cue) == nil)
                                    .help(playableNarrationURL(for: cue) == nil
                                        ? "Generate synchronized audio for this AD segment first"
                                        : "\(previewControlTitle(for: cue)) for this AD segment")
                                Button("Stop Narration", systemImage: "stop.circle") { stopNarrationPreview() }
                                    .labelStyle(.iconOnly)
                                    .disabled(studio.busy || activePreviewCueID != cue.id)
                                    .help(activePreviewCueID == cue.id
                                        ? "Stop this AD segment’s narration and return to the beginning"
                                        : "This AD segment’s narration is not active")
                                Button("Edit", systemImage: "pencil") {
                                    playback.pauseAndCaptureTime { _ in cueToEdit = cue }
                                }.labelStyle(.iconOnly).disabled(studio.busy)
                                Menu {
                                    Button(previewControlTitle(for: cue), systemImage: previewControlIcon(for: cue)) { previewNarration(for: cue) }
                                        .disabled(playableNarrationURL(for: cue) == nil)
                                    Button("Stop Narration", systemImage: "stop.circle") { stopNarrationPreview() }
                                        .disabled(activePreviewCueID != cue.id)
                                    Button("Rewrite to Fit", systemImage: "wand.and.stars") { studio.execute("rewrite-cue", extra: ["--segment", cue.id]) }
                                    Button("Synthesize This Segment", systemImage: "waveform") { studio.execute("synthesize-tts", extra: ["--segment", cue.id]) }
                                    Button("Delete Segment Audio", systemImage: "speaker.slash", role: .destructive) {
                                        studio.confirmDeleteSegmentAudio(project, cue: cue) {
                                            stopNarrationPreview()
                                            playback.stopNarrationPlayback()
                                        }
                                    }
                                    .disabled(cue.audio == nil)
                                    Button("Delete Segment", systemImage: "trash", role: .destructive) { studio.saveCues(project.cues.filter { $0.id != cue.id }) }
                                } label: { Image(systemName: "ellipsis") }
                                    .menuStyle(.borderlessButton)
                                    .menuIndicator(.hidden)
                                    .fixedSize()
                                    .disabled(studio.busy)
                                    .accessibilityLabel("Segment actions")
                            }
                        }.padding(.vertical, 8)
                            .accessibilityElement(children: .contain)
                            .id(row.id)
                            .listRowBackground(playback.time >= cue.start && playback.time < cue.end ? Color.accentColor.opacity(0.15) : Color.clear)
                            .contextMenu {
                                if row.isDescription {
                                    Button("Play from Description", systemImage: "play.fill") {
                                        playback.narrationEnabled = true
                                        playback.play(from: cue.start)
                                    }
                                    .help("Play the video from this description's start time with narration on")
                                    .accessibilityLabel("Play from description starting at \(timecode(cue.start))")
                                    Button("Skip to Description", systemImage: "forward.end.fill") {
                                        playback.seek(cue.start)
                                        playback.pausePlayback()
                                    }
                                    .help("Move the playhead to this description's start time and pause the video")
                                    .accessibilityLabel("Skip to description at \(timecode(cue.start)) and pause")
                                }
                            }
                    }.listStyle(.inset)
                    .onChange(of: segments.first(where: { playback.time >= $0.segment.start && playback.time < $0.segment.end })?.id) { _, id in
                        if followTranscript, let id { if reduceMotion { reader.scrollTo(id, anchor: .center) } else { withAnimation { reader.scrollTo(id, anchor: .center) } } }
                    }
                    }
                }
            }
        }
        .frame(minHeight: 180)
    }

    private var editorLayout: some View {
        GeometryReader { geometry in
            let dividerHeight: CGFloat = 6
            let maximumPreviewHeight = max(220, geometry.size.height - 180 - dividerHeight)
            let visiblePreviewHeight = min(max(220, previewHeight), maximumPreviewHeight)

            VStack(spacing: 0) {
                previewPane
                    .frame(height: previewHidden ? 0 : visiblePreviewHeight)
                    .clipped()
                    .accessibilityHidden(previewHidden)
                    .allowsHitTesting(!previewHidden)

                if !previewHidden {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 1)
                        .frame(height: dividerHeight)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if previewHeightAtDragStart == nil {
                                        previewHeightAtDragStart = visiblePreviewHeight
                                    }
                                    let proposed = (previewHeightAtDragStart ?? visiblePreviewHeight) + value.translation.height
                                    previewHeight = min(max(220, proposed), maximumPreviewHeight)
                                }
                                .onEnded { _ in previewHeightAtDragStart = nil }
                        )
                        .accessibilityElement()
                        .accessibilityLabel("Resize video preview")
                        .accessibilityValue("\(Int(visiblePreviewHeight)) points high")
                        .accessibilityAdjustableAction { direction in
                            let change: CGFloat = direction == .increment ? 40 : -40
                            previewHeight = min(max(220, visiblePreviewHeight + change), maximumPreviewHeight)
                        }
                }

                editorPane
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func runEditorShortcut(_ action: String) {
        switch action {
        case "preview": playback.exitVideoFullScreen(); previewHidden.toggle()
        case "fullscreen":
            previewHidden = false
            DispatchQueue.main.async { playback.toggleVideoFullScreen() }
        case "play": playback.togglePlayback()
        case "back": playback.seek(max(0, playback.time - 5))
        case "forward": playback.seek(min(project.duration, playback.time + 5))
        case "narration": playback.narrationEnabled.toggle()
        case "follow": followTranscript.toggle()
        case "descriptions", "transcript", "summary", "ad-transcript", "ad-overview": tab = action
        case "summary-play-pause": summaryReader.togglePlayPause()
        case "summary-stop": summaryReader.stop()
        case "summary-from-start": summaryReader.playFromStart()
        case "summary-from-selection": summaryReader.playFromSelection()
        case "summary-read-selection": summaryReader.readSelectedText()
        case "summary-read-sentence": summaryReader.readSentenceAtSelection()
        case "summary-next": summaryReader.next()
        case "summary-previous": summaryReader.previous()
        case "add": presentNewSegment()
        case "delete-narration": studio.confirmDeleteGeneratedContent(project, component: .narration)
        case "delete-transcript": studio.confirmDeleteGeneratedContent(project, component: .transcript)
        case "delete-summary": studio.confirmDeleteGeneratedContent(project, component: .summary)
        case "delete-descriptions": studio.confirmDeleteGeneratedContent(project, component: .descriptions)
        case "undo": studio.execute("undo-cues")
        case "redo": studio.execute("redo-cues")
        case "probe-video", "generate-thumbnails", "extract-audio", "synthesize-tts": studio.execute(action)
        case "synthesize-changed": studio.execute("synthesize-tts", extra: ["--changed"])
        case "show-in-finder": if let folder = project.folder { NSWorkspace.shared.open(folder) }
        case "analyze", "transcribe", "generate-summary", "regenerate-all": studio.execute(action)
        case "generate-ad-cues":
            if project.canGenerateDescriptions { studio.execute(action) }
        default: break
        }
    }

    private func refreshEditorShortcutActions(updateHandler: Bool = false) {
        if updateHandler {
            shortcutActions.handler = { action in runEditorShortcut(action) }
            shortcutActions.exportHandler = { action in
                studio.execute(action.command, extra: action.arguments)
            }
        }
        shortcutActions.previewHidden = previewHidden
        shortcutActions.available = !shortcutsBlocked && !studio.busy && cueToEdit == nil && studio.screenText == nil
        shortcutActions.activeSection = tab
        shortcutActions.canGenerateDescriptions = project.canGenerateDescriptions
        shortcutActions.hasNarrationAudio = GeneratedContentComponent.narration.hasContent(in: project)
        shortcutActions.hasDescriptions = GeneratedContentComponent.descriptions.hasContent(in: project)
        shortcutActions.hasGeneratedTranscript = GeneratedContentComponent.transcript.hasContent(in: project)
        shortcutActions.hasGeneratedSummary = GeneratedContentComponent.summary.hasContent(in: project)
        shortcutActions.hasLocalSource = !project.source.isEmpty
        shortcutActions.sourceHasAudio = project.hasAudio
        shortcutActions.isYouTubeProject = project.isYouTubeURLProject
        shortcutActions.exportableText = Set(["transcript", "summary", "descriptions", "combined"].filter { project.canExportText($0) })
        shortcutActions.summaryActive = (tab == "summary")
        shortcutActions.summaryReadable = !project.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !studio.busy
        shortcutActions.summaryIsReading = summaryReader.isReading
        shortcutActions.summaryIsPaused = summaryReader.isPaused
        shortcutActions.summaryHasSelection = summaryReader.hasReadableSelection
        shortcutActions.summaryHasTextSelection = summaryReader.hasNonEmptySelection
    }

    private var editorWithProjectUpdates: some View {
        editorLayout
        // ProjectEditorWindow owns the navigation title. Keeping a second title
        // on this playhead-driven subtree made AppKit clear and restore the
        // title while playback invalidated the view every 150 milliseconds.
        .onChange(of: studio.busy) { _, busy in handleBusyChange(busy) }
        .onChange(of: studio.screenText) { _, text in handleScreenText(text) }
        .onChange(of: playback.videoTitle) { _, title in updateYouTubeTitleIfNeeded(title) }
        .onChange(of: playback.duration) { _, duration in
            if !studio.busy, duration > 0, abs(duration - project.duration) > 0.5 { studio.execute("update-metadata", extra: ["--duration", String(duration)]) }
        }
    }

    private var editorWithPlaybackUpdates: some View {
        editorWithProjectUpdates
        .onChange(of: playback.time) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: playback.playing) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: studio.settings.narrationPlayback) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: studio.settings.soundWhenNarrationOff) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: studio.settings.soundWhenNarrationMissing) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: playback.narrationEnabled) { _, enabled in
            ProjectPlaybackPreferences.setNarrationEnabled(enabled, projectID: project.id)
            playback.syncNarration(project, settings: studio.settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vidiStudioProjectNarrationDidChange)) { notification in
            guard notification.userInfo?["projectID"] as? String == project.id,
                  let enabled = notification.userInfo?["enabled"] as? Bool,
                  playback.narrationEnabled != enabled else { return }
            playback.narrationEnabled = enabled
        }
        .onChange(of: followTranscript) { _, enabled in
            ProjectPlaybackPreferences.setFollowEnabled(enabled, projectID: project.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vidiStudioProjectFollowDidChange)) { notification in
            guard notification.userInfo?["projectID"] as? String == project.id,
                  let enabled = notification.userInfo?["enabled"] as? Bool,
                  followTranscript != enabled else { return }
            followTranscript = enabled
        }
        .onReceive(NotificationCenter.default.publisher(for: .vidiStudioNarrationAudioWillDelete)) { notification in
            guard notification.userInfo?["projectID"] as? String == project.id else { return }
            stopNarrationPreview()
            playback.stopNarrationPlayback()
        }
        .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in
            guard activePreviewCueID != nil, !previewPaused, audioPreview?.isPlaying != true else { return }
            stopNarrationPreview()
        }
    }

    private var editorWithVoiceUpdates: some View {
        editorWithPlaybackUpdates
        .onChange(of: studio.settings.systemVoice) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: studio.settings.systemSpeechRate) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: studio.settings.systemSpeechPitch) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: studio.settings.systemSpeechVolume) { _, _ in playback.syncNarration(project, settings: studio.settings) }
    }

    var body: some View {
        editorWithVoiceUpdates
        .onAppear {
            preparePlayback()
            refreshEditorShortcutActions(updateHandler: true)
        }
        .onDisappear {
            shortcutActions.available = false
            shortcutActions.handler = nil
            shortcutActions.exportHandler = nil
            playback.stop()
            stopNarrationPreview()
        }
        .onChange(of: previewHidden) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: shortcutsBlocked) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: cueToEdit?.id) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: studio.screenText) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: studio.busy) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: project.updatedAt) { _, _ in refreshEditorShortcutActions(updateHandler: true) }
        .onChange(of: tab) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: project.summary) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: summaryReader.isReading) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: summaryReader.isPaused) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: summaryReader.selectedRange) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: summaryReader.sentences.count) { _, _ in refreshEditorShortcutActions() }
        .sheet(isPresented: screenTextPresented) { screenTextReview }
        .sheet(item: $cueToEdit, onDismiss: {
            readingFrameForSegment = false
            segmentScreenText = nil
        }) { cue in cueEditor(for: cue) }
    }

    private func presentNewSegment() {
        playback.pauseAndCaptureTime { capturedTime in
            let latestStart = max(0, project.duration - 0.1)
            let start = max(0, min(capturedTime, latestStart))
            cueToEdit = Segment(
                id: UUID().uuidString,
                start: start,
                end: min(start + 3, project.duration),
                text: "",
                origin: "manual"
            )
        }
    }

    private func safeFrameTimestamp(_ requestedTimestamp: Double) -> Double {
        guard project.duration > 0 else { return 0 }
        return min(max(0, requestedTimestamp), max(0, project.duration - 0.1))
    }

    private func readCurrentFrameText() {
        studio.screenText = nil
        playback.pauseAndCaptureTime { capturedTime in
            let timestamp = safeFrameTimestamp(capturedTime)
            studio.execute("capture-frame", extra: ["--timestamp", String(timestamp)])
        }
    }

    private func readFrameForSegment(at timestamp: Double) {
        segmentScreenText = nil
        readingFrameForSegment = true
        studio.execute("capture-frame", extra: ["--timestamp", String(safeFrameTimestamp(timestamp))])
    }
}

struct TimelineView: View {
    let project: StudioProject
    let playback: PlaybackModel

    private var duration: Double { max(0, project.duration) }

    private var timelineValue: Binding<Double> {
        Binding {
            min(max(0, playback.time), duration)
        } set: { newValue in
            playback.seek(min(max(0, newValue), duration))
        }
    }

    private func preciseTimecode(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00.000" }
        let milliseconds = Int((max(0, seconds) * 1000).rounded())
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds / 60_000) % 60
        let wholeSeconds = (milliseconds / 1_000) % 60
        let remainder = milliseconds % 1_000
        return hours > 0
            ? String(format: "%02d:%02d:%02d.%03d", hours, minutes, wholeSeconds, remainder)
            : String(format: "%02d:%02d.%03d", minutes, wholeSeconds, remainder)
    }

    private func seek(at x: CGFloat, in width: CGFloat) {
        guard width > 0, duration > 0 else { return }
        playback.seek(duration * min(max(0, x / width), 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Timeline", systemImage: "film").font(.caption)
                Spacer()
                Text("\(preciseTimecode(playback.time)) / \(preciseTimecode(duration))")
                    .font(.caption)
                    .monospacedDigit()
                    .accessibilityLabel("Current time \(preciseTimecode(playback.time)), duration \(preciseTimecode(duration))")
            }
            GeometryReader { geometry in
                let timelineWidth = geometry.size.width
                let progress = duration > 0 ? min(max(0, playback.time / duration), 1) : 0
                let thumbnailCount = max(1, project.thumbnails.count)
                let thumbnailWidth = max(1, (timelineWidth - CGFloat(thumbnailCount - 1) * 2) / CGFloat(thumbnailCount))

                ZStack(alignment: .leading) {
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5).fill(.quaternary)
                            HStack(spacing: 2) {
                                ForEach(project.thumbnails, id: \.self) { path in
                                    if let url = project.url(path), let image = NSImage(contentsOf: url) {
                                        Image(nsImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: thumbnailWidth, height: 42)
                                            .clipped()
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { seek(at: $0.location.x, in: timelineWidth) }
                                )
                                .accessibilityRepresentation {
                                    Slider(value: timelineValue, in: 0...max(0.001, duration)) {
                                        Text("Video timeline")
                                    }
                                    .accessibilityValue("\(preciseTimecode(playback.time)) of \(preciseTimecode(duration))")
                                    .accessibilityHint("Adjust to seek through the video")
                                }
                        }
                        .frame(height: 42)
                        .clipShape(.rect(cornerRadius: 5))

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                            ForEach(project.cues) { cue in
                                Button { playback.seek(cue.start) } label: {
                                    RoundedRectangle(cornerRadius: 3).fill(.tint).overlay {
                                        Text(cue.text).font(.caption2).lineLimit(1).foregroundStyle(.white).padding(.horizontal, 4)
                                    }
                                }
                                .buttonStyle(.plain)
                                .frame(width: max(4, timelineWidth * (cue.end - cue.start) / max(1, duration)))
                                .offset(x: timelineWidth * cue.start / max(1, duration))
                                .accessibilityLabel("Description at \(timecode(cue.start)): \(cue.text)")
                            }
                        }
                        .frame(height: 26)
                    }

                    VStack(spacing: 0) {
                        Circle().fill(.white).frame(width: 10, height: 10)
                            .overlay { Circle().stroke(.tint, lineWidth: 2) }
                        Rectangle().fill(.tint).frame(width: 2)
                    }
                    .frame(width: 10, height: 72)
                    .position(x: min(max(5, timelineWidth * progress), max(5, timelineWidth - 5)), y: 36)
                    .shadow(color: .black.opacity(0.65), radius: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .frame(height: 72)
        }.padding(12)
    }
}

private struct TimecodeInput: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    private func componentBinding(
        divisor: Double,
        modulus: Int? = nil,
        allowed: ClosedRange<Int>
    ) -> Binding<Int> {
        Binding {
            let whole = Int(max(0, value) / divisor)
            return modulus.map { whole % $0 } ?? whole
        } set: { newValue in
            let oldComponent = modulus.map { Int(max(0, value) / divisor) % $0 }
                ?? Int(max(0, value) / divisor)
            let clamped = min(max(newValue, allowed.lowerBound), allowed.upperBound)
            value = min(max(value + Double(clamped - oldComponent) * divisor, range.lowerBound), range.upperBound)
        }
    }

    private var milliseconds: Binding<Int> {
        Binding {
            Int((max(0, value) * 1000).rounded()) % 1000
        } set: { newValue in
            let old = Int((max(0, value) * 1000).rounded()) % 1000
            let clamped = min(max(newValue, 0), 999)
            value = min(max(value + Double(clamped - old) / 1000, range.lowerBound), range.upperBound)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.headline).accessibilityAddTraits(.isHeader)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    unitHeading("Hours", width: 60)
                    separatorSpace()
                    unitHeading("Minutes", width: 72)
                    separatorSpace()
                    unitHeading("Seconds", width: 72)
                    separatorSpace()
                    unitHeading("Milliseconds", width: 104)
                }
                GridRow {
                    timePart("Hours", value: componentBinding(divisor: 3600, allowed: 0...99), width: 60, digits: 2)
                    Text(":").accessibilityHidden(true)
                    timePart("Minutes", value: componentBinding(divisor: 60, modulus: 60, allowed: 0...59), width: 72, digits: 2)
                    Text(":").accessibilityHidden(true)
                    timePart("Seconds", value: componentBinding(divisor: 1, modulus: 60, allowed: 0...59), width: 72, digits: 2)
                    Text(".").accessibilityHidden(true)
                    timePart("Milliseconds", value: milliseconds, width: 104, digits: 3)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func timePart(_ name: String, value: Binding<Int>, width: CGFloat, digits: Int) -> some View {
        let bounds = name == "Hours" ? 0...99 : name == "Milliseconds" ? 0...999 : 0...59
        return Stepper(value: value, in: bounds, step: 1) {
            Text(value.wrappedValue, format: .number.precision(.integerLength(digits)))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
            .monospacedDigit()
            .frame(width: width)
            .focusable()
            .onKeyPress(.upArrow) {
                value.wrappedValue = min(bounds.upperBound, value.wrappedValue + 1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                value.wrappedValue = max(bounds.lowerBound, value.wrappedValue - 1)
                return .handled
            }
            .accessibilityLabel("\(label) \(name.lowercased())")
            .accessibilityValue(String(value.wrappedValue))
            .help("Use Up Arrow or Down Arrow to change \(name.lowercased()) by one")
    }

    private func unitHeading(_ name: String, width: CGFloat) -> some View {
        Text(name)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
            .accessibilityHidden(true)
    }

    private func separatorSpace() -> some View {
        Color.clear.frame(width: 5, height: 1).accessibilityHidden(true)
    }
}

struct CueEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cue: Segment
    @State private var frameTextStatus: String?
    let duration: Double
    let transcript: [Segment]
    let otherDescriptions: [Segment]
    @Binding var capturedScreenText: String?
    let isReadingFrame: Bool
    let readFrame: (Double) -> Void
    let save: (Segment) -> Void
    init(cue: Segment, duration: Double, transcript: [Segment], otherDescriptions: [Segment], capturedScreenText: Binding<String?>, isReadingFrame: Bool, readFrame: @escaping (Double) -> Void, save: @escaping (Segment) -> Void) {
        _cue = State(initialValue: cue)
        self.duration = duration
        self.transcript = transcript
        self.otherDescriptions = otherDescriptions
        _capturedScreenText = capturedScreenText
        self.isReadingFrame = isReadingFrame
        self.readFrame = readFrame
        self.save = save
    }
    private var segmentDuration: String {
        String(format: "%.3f seconds", max(0, cue.end - cue.start))
    }
    private var hasInvalidRange: Bool {
        !cue.start.isFinite || !cue.end.isFinite || cue.start < 0 || cue.end <= cue.start || cue.end > duration
    }
    private var transcriptOverlaps: [Segment] {
        transcript.filter(overlapsCurrentCue).sorted { $0.start < $1.start }
    }
    private var descriptionOverlaps: [Segment] {
        otherDescriptions.filter(overlapsCurrentCue).sorted { $0.start < $1.start }
    }
    private var timingErrors: [String] {
        var errors: [String] = []
        if !cue.start.isFinite || !cue.end.isFinite {
            errors.append("Start and end times must be valid numbers.")
        } else if cue.start < 0 || cue.end > duration {
            errors.append("The segment must remain inside the video duration.")
        } else if cue.end <= cue.start {
            errors.append("End time must be after start time.")
        }
        errors += descriptionOverlaps.map {
            "Overlaps audio description \(preciseRange($0)): \(excerpt($0.text))"
        }
        errors += transcriptOverlaps.map {
            "Overlaps transcript \(preciseRange($0)): \(excerpt($0.text))"
        }
        return errors
    }
    private var saveDisabled: Bool {
        cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || hasInvalidRange
            || !transcriptOverlaps.isEmpty
            || !descriptionOverlaps.isEmpty
    }
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 22) {
                    TimecodeInput(label: "Start time", value: $cue.start, range: 0...max(0, duration))
                    HStack {
                        Spacer()
                        Text("Duration \(segmentDuration)")
                            .font(.title3.bold())
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Segment duration: \(segmentDuration)")
                    }
                    TimecodeInput(label: "End time", value: $cue.end, range: 0...max(0, duration))
                    if !timingErrors.isEmpty {
                        timingValidationView
                    }
                }
            } header: {
                Text("Timing")
            }
            Section {
                HStack {
                    Spacer()
                    Button {
                        frameTextStatus = nil
                        readFrame(cue.start)
                    } label: {
                        if isReadingFrame {
                            Label("Reading Frame Text…", systemImage: "text.viewfinder")
                        } else {
                            Label("Read Frame Text", systemImage: "text.viewfinder")
                        }
                    }
                    .disabled(isReadingFrame)
                    .help("Read text from the video frame at the segment start time and use it as the description")
                    .accessibilityHint("Replaces the description with text found at the segment start time.")
                }
                TextEditor(text: $cue.text)
                    .frame(height: 140)
                    .accessibilityLabel("Audio description text")
                if let frameTextStatus {
                    Text(frameTextStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(frameTextStatus)
                }
            } header: {
                Text("Description")
            }
            Section {
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Save Segment", systemImage: "checkmark") { save(cue); dismiss() }.keyboardShortcut(.defaultAction)
                    .disabled(saveDisabled)
                    .help(saveDisabled && !timingErrors.isEmpty ? "Resolve timing errors before saving this segment" : "Save this audio description segment")
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: capturedScreenText) { _, text in
            guard let text else { return }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                frameTextStatus = "No readable text was found at the segment start time."
            } else {
                cue.text = text
                cue.origin = "ai"
                cue.aiOriginalText = text
                frameTextStatus = "Screen text added to the description."
            }
            capturedScreenText = nil
        }
        .navigationTitle(cue.text.isEmpty ? "Add Audio Description Segment" : "Edit Audio Description Segment")
        .frame(width: 560, height: 590)
    }

    private var timingValidationView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MaterialIcon(glyph: "\u{e000}")
                    .foregroundStyle(.red)
                Text(timingErrors.count == 1 ? "Timing error" : "\(timingErrors.count) timing errors")
                    .font(.headline)
                    .foregroundStyle(.red)
            }
            ForEach(Array(timingErrors.enumerated()), id: \.offset) { _, error in
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Adjust the start or end time so the audio description plays only in a clear gap.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.1), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Timing validation error. \(timingErrors.joined(separator: " "))")
        .accessibilityHint("Adjust the start or end time before saving the segment.")
    }

    private func overlapsCurrentCue(_ segment: Segment) -> Bool {
        cue.start < segment.end && cue.end > segment.start
    }

    private func preciseRange(_ segment: Segment) -> String {
        "\(preciseTimecode(segment.start)) to \(preciseTimecode(segment.end))"
    }

    private func preciseTimecode(_ seconds: Double) -> String {
        let milliseconds = Int((max(0, seconds) * 1000).rounded())
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds / 60_000) % 60
        let wholeSeconds = (milliseconds / 1000) % 60
        let remainder = milliseconds % 1000
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, wholeSeconds, remainder)
    }

    private func excerpt(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard collapsed.count > 80 else { return collapsed }
        return String(collapsed.prefix(77)) + "…"
    }
}
