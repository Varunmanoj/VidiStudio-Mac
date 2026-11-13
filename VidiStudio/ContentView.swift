import SwiftUI
import AppKit
import AVKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

/// Opens the project's project.json in the default app for JSON files so its
/// settings can be inspected or edited as text.
@MainActor
func openProjectConfiguration(_ project: StudioProject, studio: StudioModel) {
    guard studio.canManageProject("open-configuration", project: project) else { return }
    guard let url = project.folder?.appendingPathComponent("project.json"),
          FileManager.default.fileExists(atPath: url.path) else { return }
    NSWorkspace.shared.open(url)
}

private enum NewProjectSource: String, CaseIterable, Identifiable {
    case videoFile
    case youtube

    var id: Self { self }
    var title: String { self == .videoFile ? "Video File" : "YouTube Video" }
    var icon: String { self == .videoFile ? "film" : "play.rectangle" }
}

private enum NewProjectAssetMode: String, CaseIterable, Identifiable {
    case create, existing
    var id: Self { self }
    var title: String { self == .create ? "Create Audio Description in VidiStudio" : "I already have Audio Description files" }
    var detail: String {
        self == .create
            ? "Generate a transcript, summary, and descriptions after creating the project."
            : "Bring an existing transcript, summary, AD transcript, or AD audio and combine it with this video."
    }
}

private struct NewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Bindable var studio: StudioModel
    @State private var source = NewProjectSource.videoFile
    @State private var assetMode = NewProjectAssetMode.create
    @State private var assets = ImportAssetSelection()
    @State private var showingAssetImport = false
    @State private var createdProject: StudioProject?
    @State private var videoURL: URL?
    @State private var youtubeURL = ""
    @State private var youtubePreview: YouTubeProjectPreview?
    @State private var youtubeFetchError: String?
    @State private var fetchingYouTube = false
    @State private var chooseYouTubeCaptions = false

    private var trimmedYouTubeURL: String {
        youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        source == .videoFile ? videoURL != nil : youtubePreview != nil && ConnectivityService.shared.available(.youtube)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("My YouTube Videos…") { openWindow(id: "youtube-browser") }
            if source == .youtube { Toggle("Choose YouTube captions after creating", isOn: $chooseYouTubeCaptions) }
            Text("New Project")
                .font(.title2.bold()).accessibilityAddTraits(.isHeader).accessibilityHeading(.h1)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)
            ConnectivityBanner()
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
                        .help("Choose the local video file for this project")
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
                            .help("Fetch the video's project name and thumbnail for review.")
                            .accessibilityHint("Fetch the video's project name and thumbnail for review.")
                            .requiresInternet(.youtube)
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
                        }
                    }
                }
            } header: {
                Text(source.title)
            }

            Section {
                Picker("Audio Description", selection: $assetMode) {
                    ForEach(NewProjectAssetMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .accessibilityHint("Choose whether to create descriptions in VidiStudio or bring existing assets.")
                Text(assetMode.detail).font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Audio Description")
            }

            if assetMode == .existing {
                Section("Bring existing assets") {
                    existingAssetRow(.transcript, url: $assets.transcript)
                    existingAssetRow(.summary, url: $assets.summary)
                    existingAssetRow(.adTranscript, url: $assets.adTranscript)
                    if assets.adTranscript != nil {
                        Picker("AD transcript type", selection: $assets.adTranscriptMode) {
                            ForEach(ImportedADTranscriptMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        Text(assets.adTranscriptMode.detail).font(.caption).foregroundStyle(.secondary)
                    }
                        Divider()
                        existingAssetRow(.audio, url: $assets.adAudio)
                        if assets.adAudio != nil {
                            Picker("Audio type", selection: $assets.adAudioMode) {
                                ForEach(ImportedADAudioMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            Text(assets.adAudioMode.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(source == .youtube ? "Combining creates described audio using the selected original soundtrack." : "Combining creates Original Audio and language-labelled Audio Description tracks that viewers can switch between.")
                            .font(.caption).foregroundStyle(.secondary)
                }
            }

            if source == .youtube {
                Section("Original audio (optional)") {
                    OriginalAudioImportFields(selection: $assets)
                }
            }

            Section {
                HStack {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    if assetMode == .existing, assets.adAudio != nil {
                        Button("Create Project & Combine", systemImage: "waveform.badge.plus") { createProject(combine: true) }
                            .disabled(!canCreate || studio.busy)
                            .help("Create the project, import these assets, and combine the described audio track")
                            .requiresInternet(source == .youtube ? .youtube : nil)
                    }
                    Button(assetMode == .existing ? "Create Project & Open Editor" : "Create Project", systemImage: "plus") { createProject(combine: false) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canCreate || studio.busy)
                        .help("Create this project. A Gemini key is not required; AI actions can be configured later.")
                        .requiresInternet(source == .youtube ? .youtube : nil)
                }
            }
            }
            .formStyle(.grouped)
        }
        .frame(width: 640, height: source == .youtube ? 640 : assetMode == .existing ? 700 : 480)
        .onChange(of: youtubeURL) {
            youtubePreview = nil
            youtubeFetchError = nil
        }
        .alert(studio.errorTitle, isPresented: Binding(get: { studio.error != nil }, set: { if !$0 { studio.dismissError() } })) {
            if let recovery = studio.youtubeAudioExportRecovery {
                Button("Choose Audio File…") { studio.chooseAudioForFailedExport(recovery) }
                    .disabled(studio.busy)
                Button("Cancel", role: .cancel) { studio.dismissError() }
            } else {
                Button("OK", role: .cancel) { studio.dismissError() }
            }
        } message: {
            Text(studio.error ?? "")
        }
        .sheet(isPresented: $showingAssetImport) {
            if let createdProject {
                ImportExistingAssetsView(
                    studio: studio,
                    project: createdProject,
                    selection: assets,
                    title: "Create Project & Open Editor",
                    primaryTitle: "Create Project & Open Editor",
                    combineTitle: "Create Project & Combine",
                    onFinished: { result in finishCreation(result ?? createdProject) }
                )
            }
        }
    }

    @ViewBuilder
    private func existingAssetRow(_ kind: ImportFileKind, url: Binding<URL?>) -> some View {
        LabeledContent(kind.title) {
            HStack(spacing: 8) {
                Text(url.wrappedValue?.lastPathComponent ?? "None")
                    .foregroundStyle(url.wrappedValue == nil ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Button("Choose…") {
                    if let selected = kind.choose() { url.wrappedValue = selected }
                }
                .help("Choose a \(kind.title.lowercased()) file")
                if url.wrappedValue != nil {
                    Button("Remove", systemImage: "xmark.circle") { url.wrappedValue = nil }
                        .labelStyle(.iconOnly)
                        .help("Remove this selection")
                }
            }
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

    private func createProject(combine: Bool) {
        var imports = assetMode == .existing ? assets : ImportAssetSelection()
        if source == .youtube {
            imports.originalAudio = assets.originalAudio
            imports.originalAudioPlayback = assets.originalAudioPlayback
            imports.originalAudioTranscription = assets.originalAudioTranscription
        } else { imports.originalAudio = nil }
        let finished: (StudioProject?) -> Void = { project in
            guard let project else { return }
            createdProject = project
            if imports.hasAny {
                if imports.hasTextNeedingTiming {
                    showingAssetImport = true
                } else {
                    studio.importAssets(imports, into: project, combine: combine && imports.adAudio != nil) { result in
                        if let result { finishCreation(result) }
                    }
                }
            } else {
                finishCreation(project)
            }
        }
        if let createdProject { finished(createdProject); return }
        let started: Bool
        switch source {
        case .videoFile:
            guard let videoURL else { return }
            started = studio.importVideo(at: videoURL, completion: finished)
        case .youtube:
            guard let youtubePreview else { return }
            started = studio.importYouTube(at: youtubePreview.canonicalURL, name: youtubePreview.title, completion: finished)
        }
        _ = started
    }

    private func finishCreation(_ project: StudioProject) {
        studio.selectedID = project.id
        dismiss()
        DispatchQueue.main.async {
            openWindow(id: "project-editor", value: project.id)
            if chooseYouTubeCaptions { studio.youtubeDetailAction = "youtube-captions"; openWindow(id: "youtube-details") }
        }
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
            youtubeFetchError = UserFacingIssue.youtubePreview.message
            UserFacingIssueReporter.record(error.localizedDescription, context: "Load YouTube video details")
        }
    }
}

struct ContentView: View {
    @Bindable var studio: StudioModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var search = ""
    @State private var sourceFilter = ProjectSourceFilter.all
    @State private var rename = ""
    @State private var renaming = false
    @State private var renamingTarget: StudioProject?
    @State private var deletionProject: StudioProject?
    @State private var exportProject: StudioProject?
    @AppStorage("projectBrowserGrid") private var projectGrid = false
    @AppStorage("projectGridItemSize") private var projectGridItemSize = 180.0

    private func openEditor(_ project: StudioProject) {
        if project.youtubeMetadata?.visibility == "private" { studio.error = "Private Video Cannot Be Opened. Signing in to Google does not give Gemini access."; return }
        ProjectOpenHistory.record(project)
        studio.selectedID = project.id
        // The project ID is the WindowGroup value and therefore its window identity.
        // Reopening the same value activates that editor instead of creating a duplicate.
        openWindow(id: "project-editor", value: project.id)
    }

    private func openEditorNewWindow(_ project: StudioProject) {
        guard !studio.busy else { return }
        openWindow(id: "project-editor", value: ProjectEditorWindowValue.newWindow(for: project.id))
    }

    private func handleSharedURL(_ url: URL) {
        guard let source = VidiStudioShareLink.parse(url) else {
            studio.errorTitle = "Unsupported Shared Item"
            studio.error = "VidiStudio can create a project from one local video file or a supported YouTube video link."
            return
        }
        guard !studio.busy else {
            studio.errorTitle = "VidiStudio Is Busy"
            studio.error = "Wait for the current operation to finish, then share the video again."
            return
        }

        studio.dismissError()
        NSApp.activate(ignoringOtherApps: true)
        switch source {
        case .videoFile(let fileURL):
            if let existing = studio.existingProject(forVideoAt: fileURL) {
                openEditor(existing)
                return
            }
            _ = studio.importVideo(at: fileURL) { project in
                if let project { openEditor(project) }
            }
        case .youtube(let webURL):
            let rawURL = webURL.absoluteString
            if let existing = studio.existingProject(forYouTubeURL: rawURL) {
                openEditor(existing)
                return
            }
            _ = studio.importYouTube(at: rawURL) { project in
                if let project { openEditor(project) }
            }
        }
    }

    var body: some View {
        ProjectBrowserPage(
            studio: studio,
            projects: studio.listedProjects,
            search: $search,
            sourceFilter: $sourceFilter,
            grid: $projectGrid,
            gridItemSize: $projectGridItemSize,
            selection: $studio.selectedID,
            busy: studio.busy,
            integrity: studio.projectIntegrity,
            hasApiKey: studio.hasApiKey,
            apiKeyVerified: studio.apiKeyVerified,
            aiProcessingBlocked: studio.isAIProcessingBlocked,
            apiKeyVerificationMessage: studio.apiKeyVerificationMessage,
            openGeminiSettings: {
                studio.settingsSection = "Gemini API"
                SettingsSectionRequest.request("Gemini API")
                openSettings()
            },
            newProject: { studio.beginNewProject() },
            openProjectFolder: {
                studio.openProject()
                if let project = studio.selected { openEditor(project) }
            },
            openEditor: openEditor,
            openNewWindow: openEditorNewWindow,
            rename: { studio.requestProjectManagement("rename-project", project: $0) },
            delete: { studio.confirmTrashProject($0) },
            removeFromList: { studio.removeProjectFromList($0) },
            process: { p, command in studio.selectedID = p.id; studio.execute(command, project: p) },
            export: { exportProject = $0 },
            clear: { deletionProject = $0 }
        )
        .onReceive(NotificationCenter.default.publisher(for: ProjectListVisibility.didChange)) { _ in
            studio.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vidiStudioProjectDeleted)) { _ in if !studio.busy { studio.reload() } }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                ConnectivityBanner()
                AIServiceIssueBanner(studio: studio)
                ActiveExportProgressView()
                DeletionProgressBanner()
            }
        }
        .background(WindowFitter().frame(width: 0, height: 0))
        .preferredColorScheme(studio.settings.theme == "dark" ? .dark : studio.settings.theme == "light" ? .light : nil)
        .sheet(isPresented: $renaming) {
            VStack(spacing: 20) {
                TextField("Project name", text: $rename)
                HStack { Button("Cancel", role: .cancel) { renaming = false }; Button("Rename", systemImage: "pencil") { studio.execute("rename-project", extra: ["--name", rename], project: renamingTarget); renaming = false }.keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 420)
        }
        .sheet(item: $deletionProject) { project in
            GeneratedContentDeletionView(studio: studio, project: project)
        }
        .sheet(item: $exportProject) { project in
            ExportDialog(project: project, busy: studio.busy, studio: studio) { action, replacingExisting in
                studio.execute(
                    action.command,
                    extra: action.arguments(replacingExisting: replacingExisting),
                    project: project
                )
            }
        }
        .sheet(isPresented: $studio.isCreatingProject) {
            NewProjectView(studio: studio)
        }
        .alert(studio.errorTitle, isPresented: Binding(get: { studio.error != nil }, set: { if !$0 { studio.dismissError() } })) {
            if let recovery = studio.youtubeAudioExportRecovery {
                Button("Choose Audio File…") { studio.chooseAudioForFailedExport(recovery) }
                    .disabled(studio.busy)
                Button("Cancel", role: .cancel) { studio.dismissError() }
            } else {
                Button("OK", role: .cancel) { studio.dismissError() }
            }
        } message: {
            Text(studio.error ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .vidiStudioSettingsDidChange)) { notification in
            guard let source = notification.object as? StudioModel,
                  source !== studio,
                  let settings = notification.userInfo?["settings"] as? StudioSettings else { return }
            studio.applyExternalSettings(settings)
        }
        .onChange(of: studio.projectManagementRequest?.id) { _, _ in
            guard let request = studio.projectManagementRequest else { return }
            studio.projectManagementRequest = nil
            switch request.action {
            case "rename-project":
                studio.selectedID = request.project.id
                rename = request.project.name
                renamingTarget = request.project
                renaming = true
            case "trash-project": studio.confirmTrashProject(request.project)
            case "youtube-open-browser": studio.openYouTubeInBrowser(request.project)
            case "project-settings": SettingsSectionRequest.requestProject(request.project); openSettings()
            case "show-in-finder": if let folder = request.project.folder { NSWorkspace.shared.open(folder) }
            case "open-configuration": openProjectConfiguration(request.project, studio: studio)
            default: break
            }
        }
        .onOpenURL(perform: handleSharedURL)
        .task {
            studio.refreshProjectIntegrity()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { break }
                studio.refreshProjectIntegrity()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            studio.refreshProjectIntegrity()
        }
        // Opening the library does not require Gemini access. Check a key in
        // Gemini API Settings or when an AI operation is requested instead.
    }
}

struct ProjectEditorWindow: View {
    let projectID: String
    @Binding var windowProjectID: String?
    @Environment(\.openWindow) private var openWindow
    @State private var windowOwner = UUID()
    @State private var showProjects = false
    @Environment(\.accessibilityReduceMotion) private var reduceProjectMotion
    @AppStorage("editorProjectBrowserGrid") private var projectGrid = false
    let openProjects: OpenProjectRegistry
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var studio: StudioModel
    @State private var editorShortcutActions = EditorShortcutActions()
    private var editorWindowTitle: String {
        studio.selected.map { editorShortcutActions.windowTitle(projectName: $0.name) } ?? "Project Editor"
    }
    @State private var youtubeOpening = false
    @State private var youtubeOpeningIssue: String?
    @State private var showInspector = true
    @State private var showingExportDialog = false
    @State private var renamingProject = false
    @State private var renamingTarget: StudioProject?
    @State private var projectName = ""
    init(projectID: String, windowProjectID: Binding<String?>, openProjects: OpenProjectRegistry) {
        _windowProjectID = windowProjectID
        self.projectID = projectID
        self.openProjects = openProjects
        let model = StudioModel()
        model.selectedID = projectID
        _studio = State(initialValue: model)
    }

    private var projectBrowserVisibility: Binding<Bool> {
        Binding(get: { showProjects }, set: { visible in
            withAnimation(reduceProjectMotion ? nil : .smooth(duration: 0.22)) {
                showProjects = visible
            }
        })
    }

    var body: some View {
        NavigationSplitView(columnVisibility: Binding(
            get: { showProjects ? .all : .detailOnly },
            set: { projectBrowserVisibility.wrappedValue = $0 != .detailOnly }
        )) {
            EditorProjectBrowser(projects: studio.listedProjects, selectedID: studio.selectedID,
                grid: $projectGrid, busy: studio.busy, summaryEditing: editorShortcutActions.summaryEditing,
                openHere: switchProject, openNewWindow: openProjectInNewWindow,
                removeFromList: removeProjectFromList, delete: deleteProject,
                openSettings: { studio.requestProjectManagement("project-settings", project: $0) })
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
                .toolbar(removing: .sidebarToggle)
        } detail: {
        VStack(spacing: 0) {
            if !studio.hasApiKey {
                HStack(spacing: 12) {
                    Image(systemName: "key.slash.fill")
                        .foregroundStyle(.orange)
                        .imageScale(.medium)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gemini API Key Required")
                            .font(.subheadline.bold())
                        Text("Enter your Gemini API key in Settings to enable video transcription, summaries, audio descriptions, and Gemini features.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Gemini API Settings…") {
                        studio.settingsSection = "Gemini API"
                        SettingsSectionRequest.request("Gemini API")
                        openSettings()
                    }
                    .controlSize(.small)
                    .help("Open Settings → Gemini API to enter or replace the key")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.orange.opacity(0.3)), alignment: .bottom)
            } else if studio.isApiKeyInvalid {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                        .imageScale(.medium)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Invalid Gemini API Key")
                            .font(.subheadline.bold())
                        Text(studio.apiKeyVerificationMessage ?? "The entered Gemini API key could not be verified. AI features are disabled until a valid key is entered.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Gemini API Settings…") {
                        studio.settingsSection = "Gemini API"
                        SettingsSectionRequest.request("Gemini API")
                        openSettings()
                    }
                    .controlSize(.small)
                    .help("Open Settings → Gemini API to enter or replace the key")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.12))
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.red.opacity(0.3)), alignment: .bottom)
            }
            if let project = studio.selected,
               let report = studio.projectIntegrity[project.id],
               !report.isHealthy {
                ProjectIntegrityBanner(
                    project: project,
                    report: report,
                    busy: studio.busy,
                    narrationActionEnabled: studio.settings.ttsMode != "gemini" || studio.hasValidApiKey,
                    showInFinder: {
                        if let folder = project.folder { NSWorkspace.shared.open(folder) }
                    },
                    regenerateNarration: {
                        studio.execute("synthesize-tts", extra: ["--changed"], project: project)
                    },
                    regenerateVideoArtifacts: {
                        studio.execute("prepare-video", project: project)
                    },
                    deleteProject: {
                        deleteProject(project)
                    },
                    showImportReport: project.lastImportReport == nil ? nil : {
                        if let report = project.lastImportReport {
                            studio.importReports = [report]
                        }
                    }
                )
            }
            Group {
                if let issue = youtubeOpeningIssue {
                    ContentUnavailableView("YouTube Video Cannot Be Opened", systemImage: "exclamationmark.triangle", description: Text(issue))
                } else if youtubeOpening {
                    ProgressView("Checking YouTube video availability")
                } else if let project = studio.selected {
                    if project.integrityPlaceholder == true || studio.integrityReport(for: project).manifestUnreadable {
                        DamagedProjectPlaceholderView(
                            project: project,
                            report: studio.integrityReport(for: project),
                            busy: studio.busy,
                            showInFinder: {
                                if let folder = project.folder { NSWorkspace.shared.open(folder) }
                            },
                            deleteProject: {
                                deleteProject(project)
                            }
                        )
                    } else {
                        ProjectEditor(
                            shortcutsBlocked: studio.error != nil,
                            studio: studio,
                            project: project,
                            shortcutActions: editorShortcutActions,
                            inspectorVisible: showInspector,
                            showExportDialog: { showingExportDialog = true },
                            renameProject: { studio.requestProjectManagement("rename-project", project: project) },
                            trashProject: { deleteProject(project) }
                        )
                        .id(project.id)
                    }
                } else {
                    ContentUnavailableView("Project Unavailable", systemImage: "film", description: Text("The project may have moved or been deleted. Return to All Projects to reopen it."))
                }
            }
        }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $studio.languageDeletionProject) { project in
            GeneratedContentDeletionView(studio: studio, project: project)
        }
        .inspector(isPresented: $showInspector) {
            ProcessingInspector(
                studio: studio,
                editorActions: editorShortcutActions,
                showExportDialog: { showingExportDialog = true },
                deleteProject: { deleteProject($0) }
            )
            .inspectorColumnWidth(min: 250, ideal: 272, max: 340)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                ConnectivityBanner()
                AIServiceIssueBanner(studio: studio)
                ActiveExportProgressView()
                DeletionProgressBanner()
            }
        }
        .smoothPresentation()
        .background(WindowFitter().frame(width: 0, height: 0))
        .focusedSceneValue(\.projectBrowser, ProjectBrowserActions(
            showProjects: projectBrowserVisibility,
            showInspector: $showInspector,
            grid: $projectGrid,
            hasProject: studio.selected != nil,
            listModel: showProjects ? studio : nil,
            preserveOpenProject: true,
            editorModel: studio
        ))
        // Keep the focused command bridge above the playhead-driven editor.
        // Its identity now remains stable while playback updates every 150 ms,
        // so an open menu does not get rebuilt and lose focus.
        .focusedSceneValue(\.editorShortcuts, studio.selected == nil ? nil : editorShortcutActions)
        .preferredColorScheme(studio.settings.theme == "dark" ? .dark : studio.settings.theme == "light" ? .light : nil)
        .contextMenu {
            if let project = studio.selected {
                if editorShortcutActions.isCommandVisible("copy-to") {
                    Button("Copy and Translate…", systemImage: "doc.on.doc") { editorShortcutActions.run("copy-to") }
                        .disabled(!editorShortcutActions.canRun("copy-to"))
                }
                Button("Open Project Settings…", systemImage: "gearshape") { studio.requestProjectManagement("project-settings", project: project) }
                    .disabled(!studio.canManageProject("project-settings", project: project))
            }
        }
        .navigationTitle(editorWindowTitle)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Text(editorWindowTitle).font(.headline).accessibilityElement(children: .ignore).accessibilityLabel(editorWindowTitle).accessibilityAddTraits(.isHeader).accessibilityHeading(.h1).lineLimit(1)
                    Button("Rename Project", systemImage: "pencil") {
                        if let project = studio.selected { studio.requestProjectManagement("rename-project", project: project) }
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("rename-project-title")
                    .accessibilityLabel("Rename project")
                    .help("Rename this project")
                    .disabled(studio.selected.map { !studio.canManageProject("rename-project", project: $0) } ?? true)
                }
                .accessibilityElement(children: .contain)
            }
            ToolbarItem(placement: .navigation) {
                Toggle(isOn: projectBrowserVisibility) { Label("Project List", systemImage: "sidebar.left") }
                    .toggleStyle(.button)
                    .accessibilityValue(showProjects ? "Shown" : "Hidden")
                    .accessibilityIdentifier("show-projects")
                    .labelStyle(.iconOnly)
                    .help(showProjects ? "Hide the project list" : "Show projects to switch in this window")
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $showInspector) { Label("Inspector", systemImage: "sidebar.right") }
                    .toggleStyle(.button)
                    .accessibilityValue(showInspector ? "Shown" : "Hidden")
                    .accessibilityIdentifier("show-inspector")
                    .labelStyle(.iconOnly)
                    .help(showInspector ? "Hide the inspector" : "Show project and section details")
            }
        }
        .alert(studio.errorTitle, isPresented: Binding(get: { studio.error != nil }, set: { if !$0 { studio.dismissError() } })) {
            if let recovery = studio.youtubeAudioExportRecovery {
                Button("Choose Audio File…") { studio.chooseAudioForFailedExport(recovery) }
                    .disabled(studio.busy)
                Button("Cancel", role: .cancel) { studio.dismissError() }
            } else {
                Button("OK", role: .cancel) { studio.dismissError() }
            }
        } message: {
            Text(studio.error ?? "")
        }
        .sheet(isPresented: $renamingProject) {
            VStack(spacing: 20) {
                TextField("Project name", text: $projectName)
                HStack {
                    Button("Cancel", role: .cancel) { renamingProject = false }
                    Button("Rename", systemImage: "pencil") {
                        if let project = renamingTarget {
                            studio.execute("rename-project", extra: ["--name", projectName], project: project)
                        }
                        renamingProject = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 420)
        }
        .sheet(isPresented: $showingExportDialog) {
            if let project = studio.selected {
                ExportDialog(project: project, busy: studio.busy, studio: studio) { action, replacingExisting in
                    studio.execute(
                        action.command,
                        extra: action.arguments(replacingExisting: replacingExisting),
                        project: project
                    )
                }
            }
        }
        .onChange(of: studio.projectManagementRequest?.id) { _, _ in
            guard let request = studio.projectManagementRequest else { return }
            studio.projectManagementRequest = nil
            switch request.action {
            case "rename-project":
                projectName = request.project.name
                renamingTarget = request.project
                renamingProject = true
            case "trash-project": deleteProject(request.project)
            case "youtube-open-browser": studio.openYouTubeInBrowser(request.project)
            case "project-settings": SettingsSectionRequest.requestProject(request.project); openSettings()
            case "show-in-finder": if let folder = request.project.folder { NSWorkspace.shared.open(folder) }
            case "open-configuration": openProjectConfiguration(request.project, studio: studio)
            default: break
            }
        }
        .sheet(isPresented: $studio.showingYouTubeDetails) {
            if let project = studio.selected { ScrollView { YouTubeDetailsView(studio: studio, project: project, startWithCaptions: studio.youtubeDetailAction == "youtube-captions") } }
        }
        .onAppear {
            studio.reload()
            studio.selectedID = projectID
            if let project = studio.selected { ProjectOpenHistory.record(project) }
            editorShortcutActions.youtubeHandler = { action in
                if action == "youtube-refresh" { studio.youtubeInspectorRefresh = UUID(); showInspector = true }
                else { studio.youtubeDetailAction = action; studio.showingYouTubeDetails = true }
            }
            studio.refreshProjectIntegrity(for: projectID)
            openProjects.open(projectID, name: studio.selected?.name ?? "Project", folder: studio.selected?.folder, owner: windowOwner, actions: editorShortcutActions)
        }
        .task(id: studio.selectedID) {
            guard let project = studio.selected, project.isYouTubeURLProject, let id = project.youtubeURL.flatMap(StudioModel.youtubeVideoID) else { youtubeOpeningIssue = nil; return }
            youtubeOpening = true; youtubeOpeningIssue = nil
            do {
                let video = try await YouTubeService.shared.video(id)
                try video.requireAvailable()
                guard !Task.isCancelled else { return }
                studio.saveYouTubeMetadata(video, project: project)
            } catch {
                if !Task.isCancelled { youtubeOpeningIssue = error.localizedDescription }
            }
            youtubeOpening = false
        }
        .task(id: projectID) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { break }
                studio.refreshProjectIntegrity(for: studio.selectedID ?? projectID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            studio.refreshProjectIntegrity(for: studio.selectedID ?? projectID)
        }
        .onChange(of: studio.selected?.name) { _, name in
            if let name, let currentID = studio.selectedID { openProjects.open(currentID, name: name, folder: studio.selected?.folder, owner: windowOwner, actions: editorShortcutActions) }
        }
        .onDisappear { openProjects.close(studio.selectedID ?? projectID, owner: windowOwner) }
        .onReceive(NotificationCenter.default.publisher(for: .vidiStudioProjectDeleted)) { notification in
            guard let deletedID = notification.userInfo?["projectID"] as? String else { return }
            let currentID = ProjectEditorWindowValue.projectID(from: windowProjectID ?? projectID)
            if currentID == deletedID {
                openProjects.close(deletedID, owner: windowOwner)
                editorShortcutActions.summaryEditing = false
                openWindow(id: "studio")
                dismissWindow(id: "project-editor", value: windowProjectID ?? projectID)
            } else if !studio.busy { studio.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProjectListVisibility.didChange)) { _ in studio.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .vidiStudioSettingsDidChange)) { notification in
            guard let settings = notification.userInfo?["settings"] as? StudioSettings else { return }
            guard let source = notification.object as? StudioModel, source !== studio else { return }
            studio.applyExternalSettings(settings)
        }
    }

    private func openProjectInNewWindow(_ project: StudioProject) {
        guard !studio.busy else { return }
        openWindow(id: "project-editor", value: ProjectEditorWindowValue.newWindow(for: project.id))
    }

    private func switchProject(_ project: StudioProject) {
        guard !studio.busy, !editorShortcutActions.summaryEditing else { return }
        guard studio.selectedID != project.id else { return }
        let oldID = studio.selectedID
        studio.reload()
        guard let target = studio.projects.first(where: { $0.id == project.id }) else { return }
        if let oldID, oldID != target.id { openProjects.close(oldID, owner: windowOwner) }
        studio.selectedID = target.id
        ProjectOpenHistory.record(target)
        windowProjectID = ProjectEditorWindowValue.replacingProject(in: windowProjectID ?? projectID, with: target.id)
        openProjects.open(target.id, name: target.name, folder: target.folder, owner: windowOwner, actions: editorShortcutActions)
    }

    private func removeProjectFromList(_ project: StudioProject) {
        guard !studio.busy, !editorShortcutActions.summaryEditing else { return }
        let currentID = studio.selectedID
        studio.removeProjectFromList(project)
        // Removing a list entry does not close the project already open here.
        studio.selectedID = currentID
    }

    private func deleteProject(_ project: StudioProject) {
        guard !studio.busy else { return }
        studio.confirmTrashProject(project)
    }
}

struct ProcessingInspector: View {
    @Bindable var studio: StudioModel
    let editorActions: EditorShortcutActions
    let showExportDialog: () -> Void
    let deleteProject: (StudioProject) -> Void

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
        default: return nil
        }
    }

    private var currentSectionKeys: [String] {
        switch editorActions.activeSection {
        case "transcript": return ["transcript"]
        case "summary": return ["summary"]
        case "descriptions", "ad-overview": return ["descriptions"]
        default: return []
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
            if let project = studio.selected {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 10) {
                        LanguageResultControls(studio: studio, project: project, editorActions: editorActions)
                        ProjectVideoInformationView(project: project)
                        if ["descriptions", "ad-overview"].contains(editorActions.activeSection) {
                            InspectorSection("Audio Description") {
                                InspectorInformationRow(label: "Total AD characters", value: (editorActions.activeSection == "ad-overview" ? project.overviewProject : project).descriptionCharacterCount.formatted())
                                    .font(.caption)
                                ADAudioReadinessIndicator(status: (editorActions.activeSection == "ad-overview" ? project.overviewProject : project).adAudioReadiness(language: project.languageCode))
                            }
                        }
                        if project.isYouTubeURLProject { YouTubeInspectorInformationView(studio: studio, project: project) }
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let report = studio.projectIntegrity[project.id], report.problems.count > 1 {
                        ProjectIntegrityDialogButton(
                            report: report,
                            busy: studio.busy,
                            narrationActionEnabled: studio.settings.ttsMode != "gemini" || studio.hasValidApiKey,
                            showInFinder: {
                                if let folder = project.folder { NSWorkspace.shared.open(folder) }
                            },
                            regenerateNarration: {
                                studio.execute("synthesize-tts", extra: ["--changed"], project: project)
                            },
                            regenerateVideoArtifacts: {
                                studio.execute("prepare-video", project: project)
                            },
                            deleteProject: {
                                deleteProject(project)
                            },
                            showImportReport: project.lastImportReport == nil ? nil : {
                                if let report = project.lastImportReport {
                                    studio.importReports = [report]
                                }
                            }
                        )
                        .padding(.top, 4)
                    }
                }
                Divider()
            }

                    if let p = studio.selected {
                        YouTubeAudioSourceControls(studio: studio, project: p)
                        if let sectionTitle = currentSectionTitle {
                            InspectorSection(editorActions.activeSection == "descriptions" ? "AD Segment Generation" : sectionTitle) {
                            VStack(alignment: .leading, spacing: 8) {
                                if !studio.hasApiKey && editorActions.currentGenerationAction != "prepare-video" {
                                    HStack(spacing: 6) {
                                        Image(systemName: "key.slash.fill")
                                            .foregroundStyle(.orange)
                                            .font(.caption)
                                        Text("Gemini API key required to generate \(sectionTitle.lowercased()).")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else if studio.isApiKeyInvalid && editorActions.currentGenerationAction != "prepare-video" {
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.octagon.fill")
                                            .foregroundStyle(.red)
                                            .font(.caption)
                                        Text("Gemini API key is invalid — update in Settings → Gemini API to generate \(sectionTitle.lowercased()).")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                let sectionState = studio.sectionProcessingState(for: currentSectionKeys)
                                if sectionState.isProcessing {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.small)
                                            .accessibilityHidden(true)
                                        Text(sectionState == .queued
                                            ? "Waiting to generate \(sectionTitle.lowercased())…"
                                            : studio.processingStageTitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(sectionState == .queued
                                        ? "Waiting to generate \(sectionTitle.lowercased())"
                                        : studio.processingStageTitle)
                                }
                                if let action = editorActions.currentGenerationAction,
                                   let title = editorActions.currentGenerationTitle {
                                    HStack(spacing: 6) {
                                        Button(title, systemImage: editorActions.currentGenerationIcon) {
                                            editorActions.run(action)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .disabled(!editorActions.canRun(action))
                                        .help(!studio.hasApiKey && action != "prepare-video"
                                            ? "Enter your Gemini API key in Settings → Gemini API to enable this feature"
                                            : studio.isApiKeyInvalid && action != "prepare-video"
                                                ? "Gemini API key is invalid — enter a valid key in Settings → Gemini API to enable this feature"
                                                : action == "generate-ad-cues" && !p.canGenerateDescriptions
                                                    ? "Generate the transcript and summary first"
                                                    : action == "prepare-video"
                                                        ? "Read video details and create timeline pictures without using AI"
                                                        : title.hasPrefix("Regenerate")
                                                            ? "Regenerate the current \(sectionTitle.lowercased()) after confirmation"
                                                            : "Generate the \(sectionTitle.lowercased()) for this project")
                                        .requiresInternet(OnlineRequirements.services(action, project: p, settings: studio.settings).first)
                                        if let component = currentComponent, component.hasContent(in: p) {
                                            Button("Delete \(component.title)…", systemImage: "trash", role: .destructive) {
                                                studio.confirmDeleteGeneratedContent(p, component: component)
                                            }
                                            .labelStyle(.iconOnly)
                                            .help("Delete \(component.title.lowercased())")
                                            .disabled(studio.busy)
                                        }
                                    }
                                }
                                if ["transcript", "descriptions"].contains(editorActions.activeSection) {
                                    HStack(spacing: 6) {
                                        Button("Undo Segment Edit", systemImage: "arrow.uturn.backward") { editorActions.run("undo") }
                                            .help("Undo the most recent saved segment edit")
                                            .disabled(!editorActions.canRun("undo"))
                                        Button("Redo", systemImage: "arrow.uturn.forward") { editorActions.run("redo") }
                                            .help("Redo the most recently undone segment edit")
                                            .disabled(!editorActions.canRun("redo"))
                                    }
                                    .disabled(studio.busy)
                                }
                            }
                            }
                        }
                        if ["summary", "descriptions", "ad-overview", "ad-transcript"].contains(editorActions.activeSection) {
                            InspectorSection("Narration Audio") {
                                VStack(alignment: .leading, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        LabeledContent("Engine") {
                                            Text(NarrationVoiceFormatting.engineDisplayName(studio.settings.currentNarrationEngine))
                                                .multilineTextAlignment(.trailing)
                                        }
                                        LabeledContent("Language") {
                                            Text(studio.settings.currentNarrationLanguage)
                                                .multilineTextAlignment(.trailing)
                                        }
                                        LabeledContent("Voice") {
                                            Text(NarrationVoiceFormatting.voiceDisplayName(studio.settings.currentNarrationVoice))
                                                .multilineTextAlignment(.trailing)
                                        }
                                    }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("Engine: \(NarrationVoiceFormatting.engineDisplayName(studio.settings.currentNarrationEngine)), Language: \(studio.settings.currentNarrationLanguage), Voice: \(NarrationVoiceFormatting.voiceDisplayName(studio.settings.currentNarrationVoice))")
                                    if ["descriptions", "ad-transcript"].contains(editorActions.activeSection) {
                                    if studio.settings.ttsMode == "gemini" {
                                        if !studio.hasApiKey {
                                            HStack(spacing: 6) {
                                                Image(systemName: "key.slash.fill")
                                                    .foregroundStyle(.orange)
                                                    .font(.caption)
                                                Text("Gemini API key required for Gemini TTS narration.")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        } else if studio.isApiKeyInvalid {
                                            HStack(spacing: 6) {
                                                Image(systemName: "exclamationmark.octagon.fill")
                                                    .foregroundStyle(.red)
                                                    .font(.caption)
                                                Text("Gemini API key is invalid — update in Settings → Gemini API for Gemini TTS narration.")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    if studio.isSynthesizingNarration {
                                        HStack(spacing: 6) {
                                            ProgressView()
                                                .controlSize(.small)
                                                .accessibilityHidden(true)
                                            Image(systemName: "waveform.circle.fill")
                                                .foregroundStyle(Color.accentColor)
                                                .accessibilityHidden(true)
                                            Text(studio.activeNarrationStatusText)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.primary)
                                        }
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel(studio.activeNarrationStatusText)
                                    }
                                    HStack(spacing: 6) {
                                        Button(
                                            studio.isSynthesizingNarration
                                                ? (studio.narratingSegmentIndex.map { "Synthesizing AD \($0)…" } ?? "Synthesizing…")
                                                : p.allADAudioTitle,
                                            systemImage: studio.isSynthesizingNarration ? "rays" : "speaker.wave.2"
                                        ) {
                                            editorActions.run("synthesize-tts")
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .disabled(!editorActions.canRun("synthesize-tts"))
                                        .help(studio.settings.ttsMode == "gemini" && !studio.hasApiKey
                                            ? "Enter your Gemini API key in Settings → Gemini API to synthesize Gemini TTS narration"
                                            : studio.settings.ttsMode == "gemini" && studio.isApiKeyInvalid
                                                ? "Gemini API key is invalid — enter a valid key in Settings → Gemini API to synthesize Gemini TTS narration"
                                                : "Create narration audio for all Audio Description segments")
                                        .requiresInternet(studio.settings.ttsMode == "gemini" ? .gemini : nil)
                                        if studio.isSynthesizingNarration {
                                            ProgressView()
                                                .controlSize(.small)
                                                .accessibilityLabel("Synthesizing narration")
                                        } else if GeneratedContentComponent.narration.hasContent(in: p) {
                                            Button("Delete Narration Audio…", systemImage: "trash", role: .destructive) {
                                                studio.confirmDeleteGeneratedContent(p, component: .narration)
                                            }
                                            .labelStyle(.iconOnly)
                                            .help("Delete narration audio while keeping description text and timing")
                                            .disabled(studio.busy)
                                        }
                                    }
                                    Button("Generate Missing or Changed AD Audio", systemImage: "waveform") {
                                        editorActions.run("synthesize-changed")
                                    }
                                    .disabled(!editorActions.canRun("synthesize-changed"))
                                    .help(studio.settings.ttsMode == "gemini" && !studio.hasApiKey
                                        ? "Enter your Gemini API key in Settings → Gemini API to synthesize changed segments"
                                        : studio.settings.ttsMode == "gemini" && studio.isApiKeyInvalid
                                            ? "Gemini API key is invalid — enter a valid key in Settings → Gemini API to synthesize changed segments"
                                            : "Generate missing audio and replace audio with text, timing, or generation issues; keep current audio")
                                    .requiresInternet(studio.settings.ttsMode == "gemini" ? .gemini : nil)
                                    }
                                }
                            }
                        }
                        if !p.isYouTubeURLProject {
                            AnalysisVideoStatusView(studio: studio, project: p)
                        }
                        InspectorSection("Export") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    ProjectExportButton(
                                        project: p,
                                        busy: studio.busy,
                                        showDialog: showExportDialog
                                    )
                                    .help("Export video, narration audio, or text in the format you need (Command-Shift-E)")
                                    if let status = (editorActions.activeSection == "ad-overview" ? p.overviewProject : p).inspectorContentStatus(section: editorActions.activeSection, language: p.languageCode) {
                                        InspectorContentStatusIndicator(status: status, iconOnly: true)
                                    }
                                }
                                ForEach((editorActions.activeSection == "ad-overview" ? p.overviewProject : p).inspectorContentStatuses(section: editorActions.activeSection)) { status in
                                    InspectorContentStatusIndicator(status: status)
                                }
                                if !p.exports.isEmpty {
                                    Divider()
                                    CreatedExportsView(studio: studio, project: p)
                                }
                            }
                        }
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
            .accessibilityLabel("Editor inspector")
            Divider()
            HStack {
                if let p = studio.selected {
                    Button("Show Project in Finder", systemImage: "folder") {
                        if let folder = p.folder { NSWorkspace.shared.open(folder) }
                    }
                    .labelStyle(.iconOnly)
                    .help("Open this project’s folder in Finder")
                    .accessibilityLabel("Show Project in Finder")
                    .disabled(p.folder == nil)
                    if studio.settings.developerMode {
                        Button("Open Project Configuration", systemImage: "doc.text") {
                            openProjectConfiguration(p, studio: studio)
                        }
                        .labelStyle(.iconOnly)
                        .help("Open this project’s project.json in the default editor")
                        .accessibilityLabel("Open Project Configuration")
                        .disabled(p.folder == nil)
                    }
                }
                Spacer()
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                .help("Open VidiStudio Settings")
                .accessibilityLabel("Settings")
            }
            .accessibilityGroup("Inspector utilities")
            .controlSize(.regular)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

private struct AnalysisVideoStatusView: View {
    @Bindable var studio: StudioModel
    let project: StudioProject

    var body: some View {
        InspectorSection("Video Analysis Availability") {
            SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
                let video = project.geminiVideo
                let remaining = max(0, (video?.expiresAt ?? 0) - context.date.timeIntervalSince1970)
                let ready = video?.state == "ACTIVE" && remaining > 0
                let processing = video?.state == "PROCESSING"
                let previouslyPrepared = video?.state == "UNAVAILABLE" && remaining > 0
                let preparation = studio.videoPreparationActivity?.projectID == project.id
                    ? studio.videoPreparationActivity : nil
                HStack(spacing: 10) {
                    if let preparation {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.red)
                            .accessibilityLabel(preparation.message)
                    } else {
                        Image(systemName: statusSymbol(video, remaining: remaining))
                            .font(.title2)
                            .foregroundStyle(statusColor(video, remaining: remaining))
                            .accessibilityLabel(accessibilityStatus(video, remaining: remaining))
                    }

                    if let preparation {
                        Text(preparation.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if remaining > 0, ready || processing || previouslyPrepared {
                        Text(duration(remaining))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityHidden(true)
                    }

                    Spacer(minLength: 8)

                    if !ready && !processing && !previouslyPrepared && preparation == nil {
                        Button("Prepare Video for Analysis", systemImage: "arrow.up.circle") {
                            studio.execute("prepare-analysis-video", project: project)
                        }
                        .labelStyle(.iconOnly)
                        .help(!studio.hasApiKey ? "Enter your Gemini API key in Settings → Gemini API to prepare video for analysis" : studio.isApiKeyInvalid ? "Gemini API key is invalid — enter a valid key in Settings → Gemini API to prepare video for analysis" : "Prepare video for analysis")
                        .requiresInternet(.gemini)
                        .accessibilityLabel("Prepare video for analysis")
                        .disabled(studio.busy || !studio.hasValidApiKey)
                    }

                    if video != nil {
                        Button("Refresh Status", systemImage: "arrow.clockwise") {
                            studio.execute("check-video-availability", project: project)
                        }
                        .labelStyle(.iconOnly)
                        .help(!studio.hasApiKey ? "Enter your Gemini API key in Settings → Gemini API to check video analysis status" : studio.isApiKeyInvalid ? "Gemini API key is invalid — enter a valid key in Settings → Gemini API to check video analysis status" : "Refresh video analysis status")
                        .requiresInternet(.gemini)
                        .accessibilityLabel("Refresh video analysis status")
                        .disabled(studio.busy || !studio.hasValidApiKey)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                if !studio.hasApiKey {
                    Text("Gemini API key required to upload or check video analysis status.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if studio.isApiKeyInvalid {
                    Text("Gemini API key is invalid — update in Settings → Gemini API to upload or check video analysis status.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func duration(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        let days = value / 86_400
        let hours = value / 3_600 % 24
        let minutes = value / 60 % 60
        let seconds = value % 60
        return "\(quantity(days, singular: "day")), \(quantity(hours, singular: "hour")), \(quantity(minutes, singular: "minute")), \(quantity(seconds, singular: "second"))"
    }

    private func quantity(_ value: Int, singular: String) -> String {
        "\(value) \(value == 1 ? singular : singular + "s")"
    }

    private func statusSymbol(_ video: AnalysisVideoAvailability?, remaining: Double) -> String {
        if video?.state == "ACTIVE" && remaining > 0 { return "checkmark.circle.fill" }
        if video?.state == "PROCESSING" { return "hourglass.circle.fill" }
        if video?.state == "UNAVAILABLE" && remaining > 0 { return "questionmark.circle.fill" }
        return "info.circle.fill"
    }

    private func statusColor(_ video: AnalysisVideoAvailability?, remaining: Double) -> Color {
        if video?.state == "ACTIVE" && remaining > 0 { return .green }
        if video?.state == "PROCESSING" { return .orange }
        if video?.state == "UNAVAILABLE" && remaining > 0 { return .orange }
        return .red
    }

    private func accessibilityStatus(_ video: AnalysisVideoAvailability?, remaining: Double) -> String {
        let current = status(video, remaining: remaining)
        if remaining > 0, ["ACTIVE", "PROCESSING", "UNAVAILABLE"].contains(video?.state ?? "") {
            return "\(current). Availability remaining: \(duration(remaining))."
        }
        return current
    }

    private func status(_ video: AnalysisVideoAvailability?, remaining: Double) -> String {
        guard let video else { return "Video needs preparation" }
        if video.state == "UNAVAILABLE", remaining > 0 {
            return "Video was previously prepared; current availability has not been verified"
        }
        if video.state == "MISSING" { return "Video needs preparation again" }
        if remaining <= 0 { return "Video availability has expired" }
        switch video.state {
        case "ACTIVE": return "Video last confirmed ready for analysis"
        case "PROCESSING": return "Video is being prepared"
        case "FAILED": return "Video preparation failed"
        default: return "Video availability needs checking"
        }
    }
}

private struct ProjectVideoInformationView: View {
    let information: ProjectVideoInformation

    init(project: StudioProject) {
        information = ProjectVideoInformation(project: project)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InspectorSection("Project Information") {
                VStack(alignment: .leading, spacing: 5) {
                    informationRow("Name", information.projectName)
                    informationRow("Type", information.projectType)
                    informationRow("Project Size", information.projectSize)
                    informationRow("Folder", information.projectFolder)
                }
                .font(.caption)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Project information")
            }
            InspectorSection("Video Information") {
                VStack(alignment: .leading, spacing: 5) {
                    informationRow(information.sourceDetailLabel, information.sourceDetail)
                    if let sourceURL = information.sourceURL {
                        informationRow("Source URL", sourceURL)
                    }
                    InspectorInformationRow(label: "Duration", value: information.duration, spokenValue: information.spokenDuration)
                    informationRow("Frame Rate", information.frameRate)
                    informationRow("Resolution", information.resolution)
                    informationRow("Video", information.videoCodec)
                    informationRow("Video Bit Rate", information.videoBitRate)
                    informationRow("Color / HDR", information.color)
                    informationRow("Audio", information.audio)
                    informationRow("Container", information.container)
                    informationRow("Source Size", information.sourceFileSize)
                }
                .font(.caption)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Video information")
            }
        }
    }

    private func informationRow(_ label: String, _ value: String) -> some View {
        InspectorInformationRow(label: label, value: value)
    }
}



private enum SegmentSort: String, CaseIterable {
    case start
    case durationAscending
    case durationDescending
    case origin

    var title: String {
        switch self {
        case .start: return "Start Time"
        case .durationAscending: return "Duration — Shortest First"
        case .durationDescending: return "Duration — Longest First"
        case .origin: return "Origin"
        }
    }
}

private enum SegmentAudioFilter: String, CaseIterable, Identifiable {
    case all, withAudio, withoutAudio
    var id: Self { self }
    var title: String {
        switch self {
        case .all: return "All descriptions"
        case .withAudio: return "Has audio"
        case .withoutAudio: return "Missing audio"
        }
    }
}

private struct SegmentFilter: Equatable {
    var origins: Set<DescriptionOrigin> = []
    var audio: SegmentAudioFilter = .all
    var ranges = SegmentRangeFilter()

    var isActive: Bool { !origins.isEmpty || audio != .all || ranges.isActive }

    func matches(_ row: TranscriptRow, project: StudioProject, number: Int = 0) -> Bool {
        guard ranges.matches(id: row.id, number: number, isDescription: row.isDescription, start: row.segment.start, end: row.segment.end) else { return false }
        if !origins.isEmpty && !origins.contains(row.segment.provenance) { return false }
        guard row.isDescription, audio != .all else { return true }
        let hasAudio = row.segment.audio.map { project.hasFile($0) } ?? false
        return audio == .withAudio ? hasAudio : !hasAudio
    }
}

private struct TranscriptRow: Identifiable, Hashable {
    var segment: Segment
    let isDescription: Bool
    var id: String { (isDescription ? "ad:" : "transcript:") + segment.id }
    var kind: String { isDescription ? "Audio description" : "Transcript" }
    var color: Color { isDescription ? .purple : .blue }
    var timingAnnouncement: String {
        "Start time: \(NarrationTimeFormat.spokenTime(segment.start)), End time: \(NarrationTimeFormat.spokenTime(segment.end)), Duration: \(NarrationTimeFormat.spokenDuration(max(0, segment.end - segment.start)))"
    }
    func accessibilityLabel(segmentNumber: Int) -> String {
        "\(kind) segment \(segmentNumber), \(timingAnnouncement), \(segment.text)"
    }
    var playbackLabel: String {
        "Play \(kind.lowercased()). \(timingAnnouncement). \(segment.text)"
    }
}

private struct SegmentEditBatch: Identifiable {
    let id = UUID()
    let rows: [TranscriptRow]
    var selectedID: String? = nil
}

private struct TranscriptCaptionOverlay: View {
    let project: StudioProject
    let playbackTime: Double
    let settings: StudioSettings

    private struct Row: Identifiable {
        let segment: Segment
        let isDescription: Bool

        var id: String { (isDescription ? "ad:" : "transcript:") + segment.id }
        var text: String {
            isDescription ? "Audio description: \(segment.text)" : segment.text
        }
    }

    private var activeRows: [Row] {
        let segments: [(segment: Segment, isDescription: Bool)]
        switch settings.captionDisplayMode {
        case "transcript":
            segments = project.transcript.map { ($0, false) }
        case "ad-transcript":
            segments = project.transcript.map { ($0, false) } + project.cues.map { ($0, true) }
        default:
            return []
        }
        return segments
            .filter { playbackTime >= $0.segment.start && playbackTime < $0.segment.end }
            .sorted {
                if $0.segment.start != $1.segment.start { return $0.segment.start < $1.segment.start }
                return $0.segment.id < $1.segment.id
            }
            .map { Row(segment: $0.segment, isDescription: $0.isDescription) }
    }

    var body: some View {
        if !activeRows.isEmpty {
            VStack(spacing: 6) {
                ForEach(activeRows) { row in
                    Text(row.text)
                        .font(.system(size: settings.captionFontSize, weight: .semibold))
                        .foregroundStyle(SummaryHighlightColor.color(from: row.isDescription ? settings.adCaptionTextColor : settings.captionTextColor))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            SummaryHighlightColor.color(from: row.isDescription ? settings.adCaptionBackgroundColor : settings.captionBackgroundColor)
                                .opacity(settings.captionBackgroundOpacity),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
            }
                .padding(16)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Inline spinner shown inside a section while its stage runs (or while it
/// waits its turn). It replaces only the section body, so the editor toolbar,
/// preview, timeline, and inspector stay available for navigation.
private struct SectionProcessingIndicator: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .scaleEffect(1.6)
                .frame(width: 64, height: 64)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if !detail.isEmpty {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, detail].filter { !$0.isEmpty }.joined(separator: ". "))
        .accessibilityHint("VidiStudio is working. This indicator continues spinning until the section finishes.")
    }
}

struct ProjectEditor: View {
    var shortcutsBlocked = false
    @Bindable var studio: StudioModel
    let project: StudioProject
    let shortcutActions: EditorShortcutActions
    let inspectorVisible: Bool
    let showExportDialog: () -> Void
    let renameProject: () -> Void
    let trashProject: () -> Void
    @State private var playback = PlaybackModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab = "transcript"
    @State private var requestedTitle = ""
    @State private var previewHidden = false
    @AppStorage("timelineVisible") private var timelineVisible = true
    @AppStorage("thumbnailImagesVisible") private var thumbnailImagesVisible = false
    @State private var previewHeight: CGFloat = 413
    @State private var previewHeightAtDragStart: CGFloat?
    @State private var validationHighlightID: String?
    @State private var validationShowcaseActive = false
    @State private var validationShowcaseTask: Task<Void, Never>?
    @State private var segmentEditorHint = ""
    @State private var validationRequest: (() -> Void)?
    @State private var segmentToEdit: TranscriptRow?
    @State private var segmentBatchToEdit: SegmentEditBatch?
    @State private var segmentEditMode = false
    @State private var selectedSegmentIDs: Set<String> = []
    @State private var audioPreview: AVAudioPlayer?
    @State private var activePreviewCueID: String?
    @State private var previewPaused = false
    @State private var segmentScreenText: String?
    @State private var readingFrameForSegment = false
    @State private var followTranscript = true
    @State private var summaryReader = SummaryReadbackModel()
    @State private var summaryEditMode = false
    @State private var languageContextChanging = false
    @State private var summaryDraftText = ""
    @State private var summaryDraftOrigin: SummaryOrigin = .unknown
    @State private var showingImportAssets = false
    @State private var showingAudioSources = false
    @State private var importScope: ImportScope?
    @State private var showingTranscriptTimingEditor = false
    @State private var showingBulkShift = false
    @State private var copySelection: LanguageCopySelection?
    @State private var showingLanguageResults = false
    @State private var showingSegmentFilter = false
    @State private var showingSegmentSort = false
    @State private var showingJumpToTime = false
    @State private var segmentFilters: [String: SegmentFilter] = [:]
    private var segmentFilter: SegmentFilter {
        get { segmentFilters[segmentFilterKey] ?? SegmentFilter() }
        nonmutating set { segmentFilters[segmentFilterKey] = newValue }
    }
    private var segmentFilterKey: String {
        let kinds = tab == "transcript" ? ["transcript"] : tab == "descriptions" ? ["descriptions"] : ["transcript", "descriptions"]
        return ([tab, project.languageCode] + kinds.map { project.activeLanguageResultID($0) }).joined(separator: ":")
    }
    @State private var segmentSorts: [String: SegmentSort] = [:]
    private var segmentSort: SegmentSort {
        get { segmentSorts[segmentFilterKey] ?? .start }
        nonmutating set { segmentSorts[segmentFilterKey] = newValue }
    }
    @State private var confirmBulkNarration = false
    @State private var narrationImportCue: Segment?
    private var transcriptRows: [TranscriptRow] {
        let dialogue = project.transcript.map { TranscriptRow(segment: $0, isDescription: false) }
        let descriptions = project.cues.map { TranscriptRow(segment: $0, isDescription: true) }
        let rows = tab == "descriptions" ? descriptions : tab == "ad-transcript" ? dialogue + descriptions : dialogue
        let transcriptNumbers = project.segmentNumbers(isDescription: false)
        let descriptionNumbers = project.segmentNumbers(isDescription: true)
        return sortRows(rows.filter {
            segmentFilter.matches($0, project: project, number: ($0.isDescription ? descriptionNumbers : transcriptNumbers)[$0.segment.id] ?? 0)
                || $0.id == validationHighlightID
        })
    }

    private func sortRows(_ rows: [TranscriptRow]) -> [TranscriptRow] {
        func originRank(_ row: TranscriptRow) -> Int {
            DescriptionOrigin.editableCases.firstIndex(of: row.segment.provenance) ?? DescriptionOrigin.editableCases.count
        }
        return rows.sorted { left, right in
            switch segmentSort {
            case .start:
                break
            case .durationAscending, .durationDescending:
                let leftDuration = left.segment.end - left.segment.start
                let rightDuration = right.segment.end - right.segment.start
                if abs(leftDuration - rightDuration) > 0.0005 {
                    return segmentSort == .durationAscending ? leftDuration < rightDuration : leftDuration > rightDuration
                }
            case .origin:
                let leftRank = originRank(left), rightRank = originRank(right)
                if leftRank != rightRank { return leftRank < rightRank }
            }
            if left.segment.start != right.segment.start { return left.segment.start < right.segment.start }
            return left.id < right.id
        }
    }

    private var generationAction: (command: String, title: String, icon: String)? {
        switch tab {
        case "transcript":
            return ("transcribe", project.hasGeneratedTranscript ? "Regenerate Transcript…" : "Generate Transcript", "text.bubble")
        case "summary":
            let hasSummary = !project.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return ("generate-summary", hasSummary ? "Regenerate Summary…" : "Generate Summary", "text.alignleft")
        case "descriptions":
            return ("generate-ad-cues", project.cues.isEmpty ? "Generate Audio Descriptions" : "Regenerate Audio Descriptions…", "sparkles")
        default:
            return nil
        }
    }

    private var captionControlsAvailable: Bool {
        ["transcript", "descriptions", "ad-transcript"].contains(tab)
    }

    private var segmentEditingAvailable: Bool {
        captionControlsAvailable
    }

    private var editorSectionAccessibilityTitle: String {
        ["transcript": "Transcript", "summary": "Summary", "descriptions": "Descriptions", "ad-overview": "AD Overview", "ad-transcript": "AD Transcript"][tab] ?? "Editor"
    }

    private var segmentSectionTitle: String {
        switch tab {
        case "transcript": return "Transcript"
        case "descriptions": return "Audio Description"
        case "ad-transcript": return "AD Transcript"
        default: return ""
        }
    }

    private var narrationControlAvailable: Bool {
        ["descriptions", "ad-transcript"].contains(tab) && !project.cues.isEmpty
    }

    private var followControlAvailable: Bool {
        switch tab {
        case "transcript": return !project.transcript.isEmpty
        case "descriptions": return !project.cues.isEmpty
        case "ad-transcript": return !project.transcript.isEmpty || !project.cues.isEmpty
        default: return false
        }
    }

    private var captionOverlayTitle: String {
        switch studio.settings.captionDisplayMode {
        case "transcript": return "Transcript"
        case "ad-transcript": return "AD Transcript"
        default: return "Off"
        }
    }

    private var captionOverlayIcon: String {
        switch studio.settings.captionDisplayMode {
        case "transcript": return "captions.bubble.fill"
        case "ad-transcript": return "text.quote"
        default: return "captions.bubble"
        }
    }

    private var captionOverlayColor: Color {
        switch studio.settings.captionDisplayMode {
        case "transcript": return .blue
        case "ad-transcript": return .purple
        default: return .secondary
        }
    }

    private var availableCaptionDisplayModes: [String] {
        var modes = ["off"]
        if !project.transcript.isEmpty { modes.append("transcript") }
        if !project.transcript.isEmpty || !project.cues.isEmpty { modes.append("ad-transcript") }
        return modes
    }

    private var interfaceAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.22)
    }

    /// Section keys shown by each editor tab. A tab can surface more than one
    /// stage (AD Transcript combines the transcript and description stages).
    private func processingSections(for tab: String) -> [String] {
        switch tab {
        case "transcript": return ["transcript"]
        case "summary": return ["summary"]
        case "descriptions": return ["descriptions"]
        case "ad-overview": return ["descriptions"]
        case "ad-transcript": return ["transcript", "descriptions"]
        default: return []
        }
    }

    private var currentProcessingState: SectionProcessingState {
        studio.sectionProcessingState(for: processingSections(for: tab))
    }

    private var showsProjectStatusBar: Bool {
        studio.busy && studio.exportActivity == nil
    }

    private var sectionProcessingName: String {
        switch tab {
        case "transcript": return "the transcript"
        case "summary": return "the summary"
        case "descriptions", "ad-overview", "ad-transcript": return "audio descriptions"
        default: return "this section"
        }
    }

    private func cycleCaptionDisplayMode() {
        let modes = availableCaptionDisplayModes
        guard modes.count > 1 else {
            studio.settings.captionDisplayMode = "off"
            return
        }
        let currentIndex = modes.firstIndex(of: studio.settings.captionDisplayMode) ?? 0
        studio.settings.captionDisplayMode = modes[(currentIndex + 1) % modes.count]
    }

    @ViewBuilder
    private var sectionGenerationButton: some View {
        if let action = generationAction {
            Button(action.title, systemImage: action.icon) { studio.execute(action.command) }
                .accessibilityLabel(action.title)
                .disabled(studio.busy || !studio.hasValidApiKey || (action.command == "generate-ad-cues" && !project.canGenerateDescriptions))
                .help(action.title + ". " + (!studio.hasApiKey
                    ? "Enter your Gemini API key in Settings → Gemini API to enable this feature"
                    : studio.isApiKeyInvalid
                        ? "Gemini API key is invalid — enter a valid key in Settings → Gemini API to enable this feature"
                        : action.command == "generate-ad-cues" && !project.canGenerateDescriptions
                            ? "Generate the transcript and summary first"
                            : action.command == "prepare-video" ? "Read video details and create timeline pictures without using AI" : action.title.hasPrefix("Regenerate") ? "Regenerate the existing content after confirmation" : "Generate content for this section"))
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if project.isYouTubeURLProject {
                        Button("Audio Sources…", systemImage: "waveform") { showingAudioSources = true }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Audio Sources")
                            .help("Audio Sources: choose audio for playback, exports, and transcription")
                        Image(systemName: project.audioSources?.playback == "imported" ? "doc.waveform" : "play.rectangle")
                            .accessibilityLabel("Playing: \(project.audioSources?.playback == "imported" ? "Imported audio: \(project.originalAudio?.sourceName ?? "Missing file")" : "YouTube audio")")
                            .help("Playing: \(project.audioSources?.playback == "imported" ? "Imported audio: \(project.originalAudio?.sourceName ?? "Missing file")" : "YouTube audio")")
                    }
                    Button("Import Existing Assets", systemImage: "square.and.arrow.down") {
                        showingImportAssets = true
                    }
                    .labelStyle(.iconOnly)
                    .disabled(studio.busy)
                    .help("Import a transcript, summary, AD transcript, or AD audio into this project")
                    .accessibilityLabel("Import Existing Assets")
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
                    if currentProcessingState.isProcessing {
                        ProgressView().controlSize(.small)
                            .accessibilityLabel("\(studio.processingStageTitle) in this section")
                            .accessibilityIdentifier("editor-section-processing")
                    }
                    if tab == "descriptions" || tab == "ad-transcript" {
                        let origins = Set(project.cues.map(\.provenance))
                        if origins.count > 1 {
                            Label("Mixed origins", systemImage: "circle.hexagongrid")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .help("This section contains more than one provenance label. Each row keeps its own origin.")
                        } else if let origin = origins.first {
                            DescriptionOriginLabel(origin: origin)
                                .help("Every description in this section has this provenance label.")
                        }
                    }
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
                    if tab == "descriptions" || tab == "ad-transcript" {
                        Button("Read Frame Text", systemImage: "text.viewfinder") {
                            readCurrentFrameText()
                        }
                        .labelStyle(.iconOnly)
                        .help(!studio.hasApiKey ? "Enter your Gemini API key in Settings → Gemini API to read frame text" : studio.isApiKeyInvalid ? "Gemini API key is invalid — enter a valid key in Settings → Gemini API to read frame text" : "Extract text from the current video frame")
                        .requiresInternet(.gemini)
                        .disabled(studio.busy || !studio.hasValidApiKey)
                    }
                    if captionControlsAvailable {
                        Menu {
                            Button("Off", systemImage: studio.settings.captionDisplayMode == "off" ? "checkmark" : "captions.bubble") {
                                studio.settings.captionDisplayMode = "off"
                            }
                            Button("Transcript", systemImage: studio.settings.captionDisplayMode == "transcript" ? "checkmark" : "captions.bubble.fill") {
                                studio.settings.captionDisplayMode = "transcript"
                            }
                            .disabled(project.transcript.isEmpty)
                            Button("AD Transcript", systemImage: studio.settings.captionDisplayMode == "ad-transcript" ? "checkmark" : "text.quote") {
                                studio.settings.captionDisplayMode = "ad-transcript"
                            }
                            .disabled(project.transcript.isEmpty && project.cues.isEmpty)
                        } label: {
                            Label("Transcript Overlay: \(captionOverlayTitle)", systemImage: captionOverlayIcon)
                                .labelStyle(.iconOnly)
                                .foregroundStyle(captionOverlayColor)
                        } primaryAction: {
                            cycleCaptionDisplayMode()
                        }
                        .tint(captionOverlayColor)
                        .accessibilityLabel("Transcript overlay: \(captionOverlayTitle)")
                        .accessibilityHint("Activate to cycle the overlay mode, or open the menu to choose Off, Transcript, or AD Transcript")
                        .help("Transcript overlay is \(captionOverlayTitle). Click to cycle modes or open the menu for a direct choice. YouTube's own captions and shortcuts remain available.")
                    }
                    if tab == "transcript" || tab == "ad-transcript" || tab == "descriptions" {
                        if tab == "descriptions" || tab == "ad-transcript" {
                            Toggle("Narration", isOn: $playback.narrationEnabled)
                                .toggleStyle(.button)
                                .disabled(!narrationControlAvailable)
                                .help(narrationControlAvailable
                                    ? "Play generated descriptions in sync with video"
                                    : "Generate or add an Audio Description segment to use Narration")
                                .accessibilityHint(narrationControlAvailable
                                    ? "Turns Audio Description playback on or off"
                                    : "Unavailable because this project has no Audio Description segments")
                        }
                        Toggle("Follow", isOn: $followTranscript)
                            .toggleStyle(.button)
                            .disabled(!followControlAvailable)
                            .help(followControlAvailable
                                ? "Follow the active transcript or description"
                                : "Add or generate content for this section to use Follow")
                            .accessibilityHint(followControlAvailable
                                ? "Keeps the active segment visible during playback"
                                : "Unavailable because this section has no transcript or description segments")
                    }
                }
            }
            if filterableTab && segmentFilter.isActive {
                Button("Clear Filter", systemImage: "xmark.circle") { shortcutActions.run("clear-segment-filter") }
                    .labelStyle(.iconOnly).fixedSize()
                    .accessibilityIdentifier("clear-segment-filter")
                    .help("Clear Filter")
                    .disabled(!shortcutActions.canRun("clear-segment-filter"))
            }
            if filterableTab && segmentSort != .start {
                Button("Clear Sort", systemImage: "arrow.uturn.backward") { shortcutActions.run("clear-segment-sort") }
                    .labelStyle(.iconOnly).fixedSize()
                    .accessibilityIdentifier("clear-segment-sort")
                    .help("Clear Sort: restore Start Time order")
                    .disabled(!shortcutActions.canRun("clear-segment-sort"))
            }
            sectionGenerationButton
                .labelStyle(.iconOnly)
                .fixedSize()
            if tab == "descriptions" || tab == "transcript" {
                Menu {
                    Button(tab == "transcript" ? "Add Transcript Segment" : "Add Audio Description Segment", systemImage: "plus") {
                        presentNewSegment(isDescription: tab == "descriptions")
                    }
                    .disabled(!canCreateSegment)
                    Divider()
                    Button(tab == "transcript" ? "Import Transcript…" : "Import Descriptions…", systemImage: "square.and.arrow.down") {
                        importScope = tab == "transcript" ? .transcript : .descriptions
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .disabled(studio.busy)
                .fixedSize()
                .accessibilityLabel(tab == "transcript" ? "Add or import transcript" : "Add or import descriptions")
                .help(tab == "transcript"
                    ? "Add a transcript segment manually or import a transcript"
                    : "Add an Audio Description segment manually or import AD descriptions")
            }
            if tab == "summary" {
                Menu {
                    Button("Write Summary", systemImage: "square.and.pencil") { startSummaryEditing() }
                    Button("Import Summary…", systemImage: "square.and.arrow.down") { importScope = .summary }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .disabled(studio.busy || summaryEditMode)
                .fixedSize()
                .accessibilityLabel("Add or import summary")
                .help("Write a summary manually or import a Markdown or TXT summary")
                Button(summaryEditMode ? "Done" : "Edit", systemImage: summaryEditMode ? "checkmark" : "pencil") {
                    toggleSummaryEditMode()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .keyboardShortcut(summaryEditMode ? .defaultAction : nil)
                .disabled(studio.busy)
                .fixedSize()
                .accessibilityLabel(summaryEditMode ? "Done editing summary" : "Edit summary")
                .accessibilityHint(summaryEditMode ? "Saves your changes and returns to the reading view" : "Edit the summary directly right inside like a notepad")
                .help(summaryEditMode ? "Save summary changes and finish editing" : "Edit the summary directly like a notepad")
            }
            if segmentEditingAvailable {
                if segmentEditMode {
                    Menu("Selection", systemImage: "checklist") {
                        if tab == "transcript" || tab == "ad-transcript" {
                            Button("Select All Transcripts", systemImage: "text.bubble") {
                                selectedSegmentIDs = Set(transcriptRows.filter { !$0.isDescription }.map(\.id))
                                refreshEditorShortcutActions()
                            }
                        }
                        if tab == "descriptions" || tab == "ad-transcript" {
                            Button("Select All Descriptions", systemImage: "text.below.photo") {
                                selectedSegmentIDs = Set(transcriptRows.filter(\.isDescription).map(\.id))
                                refreshEditorShortcutActions()
                            }
                            Button("Select Descriptions with Audio", systemImage: "speaker.wave.2") {
                                selectedSegmentIDs = Set(transcriptRows.filter { $0.isDescription && segmentHasAudio($0.segment) }.map(\.id))
                                refreshEditorShortcutActions()
                            }
                            Button("Select Descriptions without Audio", systemImage: "speaker.slash") {
                                selectedSegmentIDs = Set(transcriptRows.filter { $0.isDescription && !segmentHasAudio($0.segment) }.map(\.id))
                                refreshEditorShortcutActions()
                            }
                        }
                        if !availableOrigins.isEmpty {
                            Menu("Select by Origin") {
                                ForEach(availableOrigins, id: \.self) { origin in
                                    Button(origin.title) {
                                        selectedSegmentIDs = Set(transcriptRows.filter { $0.segment.provenance == origin }.map(\.id))
                                        refreshEditorShortcutActions()
                                    }
                                }
                            }
                        }
                        Button("Select All Segments", systemImage: "checkmark.square") {
                            selectedSegmentIDs = Set(transcriptRows.map(\.id))
                            refreshEditorShortcutActions()
                        }
                        .disabled(selectedSegmentIDs.count == transcriptRows.count)
                        Button("Deselect All", systemImage: "square") {
                            selectedSegmentIDs.removeAll()
                            refreshEditorShortcutActions()
                        }
                        .disabled(selectedSegmentIDs.isEmpty)
                        Button("Invert Selection", systemImage: "arrow.triangle.2.circlepath") {
                            selectedSegmentIDs = Set(transcriptRows.map(\.id)).subtracting(selectedSegmentIDs)
                            refreshEditorShortcutActions()
                        }
                        .disabled(transcriptRows.isEmpty)
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Selection")
                    .fixedSize()
                    Menu("Set Origin", systemImage: "tag") {
                        ForEach(DescriptionOrigin.editableCases, id: \.self) { origin in
                            Button {
                                setOriginForSelection(origin)
                            } label: {
                                Label(origin.title, systemImage: origin.iconName)
                            }
                        }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(selectedSegmentIDs.isEmpty || studio.busy)
                    .fixedSize()
                    .help("Change the provenance label for every selected transcript or description segment")
                    Button("Shift Timing…", systemImage: "clock.arrow.circlepath") {
                        showingBulkShift = true
                    }
                    .labelStyle(.iconOnly)
                    .disabled(selectedSegmentIDs.isEmpty || studio.busy)
                    .fixedSize()
                    .help("Move every selected segment earlier or later by the same offset")
                    if tab == "descriptions" || tab == "ad-transcript" {
                        Button("Generate Narration for Selected…", systemImage: "speaker.wave.2") {
                            confirmBulkNarration = true
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel(bulkNarrationLabel)
                        .accessibilityHint("Only selected Audio Description segments are narrated; selected transcript segments are ignored")
                        .disabled(selectedDescriptionIDs.isEmpty || studio.busy || !bulkNarrationAvailable)
                        .fixedSize()
                        .help(bulkNarrationUnavailableReason ?? "\(bulkNarrationLabel). Generates audio for the selected descriptions only, one after another, using the currently selected narration voice. Transcript segments are not narrated.")
                    }
                    if tab == "transcript" {
                        Button("Merge Selected", systemImage: "rectangle.compress.vertical") {
                            mergeSelectedTranscript()
                        }
                        .labelStyle(.iconOnly)
                        .disabled(!canMergeSelected || studio.busy)
                        .fixedSize()
                        .help(canMergeSelected ? "Combine the selected adjacent transcript segments into one" : "Select two or more consecutive transcript segments to merge")
                    }
                    Button("Edit Selected…", systemImage: "square.and.pencil") {
                        presentBulkSegmentEditor()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(selectedSegmentIDs.isEmpty)
                    .fixedSize()
                    .help("Edit the timing and text of every selected segment")
                    Button("Delete Selected…", systemImage: "trash", role: .destructive) {
                        deleteSelectedSegments()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(selectedSegmentIDs.isEmpty)
                    .fixedSize()
                    .help("Delete the selected segments after confirmation")
                }
                Button(segmentEditMode ? "Done" : "Edit", systemImage: segmentEditMode ? "checkmark" : "pencil") {
                    shortcutActions.run("segment-edit-mode")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(studio.busy)
                .fixedSize()
                .accessibilityLabel(segmentEditMode ? "Done editing \(segmentSectionTitle) segments" : "Edit \(segmentSectionTitle) segments")
                .help(segmentEditMode ? "Finish editing \(segmentSectionTitle.lowercased()) segments" : "Edit \(segmentSectionTitle.lowercased()) segments")
                .accessibilityHint(segmentEditMode ? "Returns this section to view mode" : "Shows selection, editing, and deletion controls for segments")
            }
        }
        .controlSize(.small)
        .padding(12)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityGroup("\(editorSectionAccessibilityTitle) controls")
    }

    @ViewBuilder
    private var processingControlBar: some View {
        if showsProjectStatusBar {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(studio.processingStageTitle)
                        .font(.callout.weight(.semibold))
                    Text(studio.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if studio.contentTransferCommand != nil {
                        if let fraction = studio.contentTransferProgress {
                            ProgressView(value: fraction).progressViewStyle(.linear)
                                .accessibilityLabel(studio.processingStageTitle)
                                .accessibilityValue("\(Int(fraction * 100)) percent")
                        } else { ProgressView().progressViewStyle(.linear).accessibilityLabel(studio.processingStageTitle) }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(studio.processingStageTitle). \(studio.message)")
                .accessibilityValue(studio.contentTransferProgress.map { "\(Int($0 * 100)) percent" } ?? "")
                Spacer(minLength: 12)
                Button {
                    studio.cancelCurrentOperation()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.circle").accessibilityHidden(true)
                        Text("Cancel Processing")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .fixedSize()
                .accessibilityLabel("Cancel Processing")
                .accessibilityHint("Stops the current processing operation. Completed results remain saved.")
                .help("Stop the current AI processing or export. Completed results remain saved.")
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
            Text("Screen Text").font(.title2).accessibilityAddTraits(.isHeader).accessibilityHeading(.h1)
            ScrollView {
                Text(studio.screenText?.isEmpty == false ? studio.screenText! : "No readable text in this frame.")
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
            HStack {
                Button("Close") { studio.screenText = nil }
                    .help("Close the screen text review without changing the project")
                Spacer()
                Button("Add as Description", systemImage: "text.badge.plus") {
                    presentSegmentEditor(TranscriptRow(
                        segment: Segment(id: UUID().uuidString, start: studio.screenTimestamp, end: min(project.duration, studio.screenTimestamp + 3), text: studio.screenText ?? "", origin: "ai", aiOriginalText: studio.screenText),
                        isDescription: true
                    ), adding: true)
                    studio.screenText = nil
                }
                .disabled(!canCreateSegment || studio.screenText?.isEmpty != false)
                .help("Create an Audio Description segment from the text found in this frame")
            }
        }
        .padding(24)
        .frame(width: 540)
    }

    private func segmentEditor(for row: TranscriptRow) -> some View {
        let readFrameAction: ((Double) -> Void)? = (tab == "descriptions" || tab == "ad-transcript") && row.isDescription
            ? { timestamp in readFrameForSegment(at: timestamp) }
            : nil
        return SegmentEditor(
            row: row,
            soundWhenTimingInvalid: studio.settings.soundWhenTimingInvalid,
            initialHint: segmentEditorHint,
            showIssues: { draft, hint, targets in
                segmentEditorHint = hint
                validationRequest = { showcaseValidationIssues(targets) { segmentToEdit = draft } }
                segmentToEdit = nil
            },
            duration: project.duration,
            transcript: project.transcript,
            descriptions: project.cues,
            capturedScreenText: $segmentScreenText,
            isReadingFrame: readingFrameForSegment,
            readFrame: readFrameAction,
            canReanalyze: (!row.isDescription || project.canGenerateDescriptions) && !studio.busy && studio.hasValidApiKey,
            hasApiKey: studio.hasApiKey,
            apiKeyVerified: studio.apiKeyVerified,
            reanalyze: { segment, hint in
                studio.reanalyzeSegment(segment, hint: hint, isDescription: row.isDescription)
            }
        ) { updated in
            saveEditedRows([updated])
        }
    }

    /// The editor draft stays in the completion closure while the sheet is hidden.
    private func showcaseValidationIssues(_ targets: [TranscriptRow], resume: @escaping () -> Void) {
        guard !targets.isEmpty, !validationShowcaseActive else { return }
        let originalTab = tab
        let originalEditMode = segmentEditMode
        let originalSelection = selectedSegmentIDs
        validationShowcaseActive = true
        playback.stopPlayback()
        validationShowcaseTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(350))
                for (index, target) in targets.enumerated() {
                    try Task.checkCancellation()
                    tab = target.isDescription ? "descriptions" : "transcript"
                    validationHighlightID = target.id
                    NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                        userInfo: [.announcement: "Validation issue \(index + 1) of \(targets.count). \(target.kind) segment #\(project.segmentNumbers(isDescription: target.isDescription)[target.segment.id] ?? 0), \(preciseSegmentTimecode(target.segment.start)) to \(preciseSegmentTimecode(target.segment.end)): \(target.segment.text)", .priority: NSAccessibilityPriorityLevel.high.rawValue])
                    try await Task.sleep(for: .seconds(2))
                }
            } catch { /* Return to Edit cancels the remaining highlights. */ }
            guard validationShowcaseActive else { return }
            validationHighlightID = nil
            tab = originalTab
            // A fresh task allows the restoration delay even after cancellation.
            validationShowcaseTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard validationShowcaseActive else { return }
                segmentEditMode = originalEditMode
                selectedSegmentIDs = originalSelection
                validationShowcaseActive = false
                validationShowcaseTask = nil
                resume()
            }
        }
    }

    private func saveEditedRows(_ updatedRows: [TranscriptRow]) {
        guard canCreateSegment, updatedRows.count <= 1 || segmentEditMode else { return }
        let transcriptUpdates = Dictionary(uniqueKeysWithValues: updatedRows.filter { !$0.isDescription }.map { ($0.segment.id, $0.segment) })
        let descriptionUpdates = Dictionary(uniqueKeysWithValues: updatedRows.filter(\.isDescription).map { ($0.segment.id, $0.segment) })
        var transcript = project.transcript.map { transcriptUpdates[$0.id] ?? $0 }
        var descriptions = project.cues.map { descriptionUpdates[$0.id] ?? $0 }
        for row in updatedRows where row.isDescription && !project.cues.contains(where: { $0.id == row.segment.id }) {
            descriptions.append(row.segment)
        }
        for row in updatedRows where !row.isDescription && !project.transcript.contains(where: { $0.id == row.segment.id }) {
            transcript.append(row.segment)
        }
        transcript.sort { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
        descriptions.sort { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
        studio.saveSegments(transcript, cues: descriptions)
    }

    private func preparePlayback() {
        playback.observe()
        playback.syncNarration(project, settings: studio.settings)
        playback.narrationEnabled = ProjectPlaybackPreferences.narrationEnabled(folder: project.folder, projectID: project.id)
        followTranscript = ProjectPlaybackPreferences.followEnabled(folder: project.folder, projectID: project.id)
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

    private func playNarrationPreview(for cue: Segment) {
        guard let url = playableNarrationURL(for: cue) else { return }
        do {
            stopNarrationPreview()
            let player = try AVAudioPlayer(contentsOf: url)
            audioPreview = player
            activePreviewCueID = cue.id
            previewPaused = false
            player.play()
        } catch {
            studio.present(.narrationPlayback, technicalDetails: error.localizedDescription, context: "Play narration preview")
        }
    }

    private func toggleNarrationPreviewPause() {
        guard let audioPreview, activePreviewCueID != nil else { return }
        if audioPreview.isPlaying {
            audioPreview.pause()
            previewPaused = true
        } else if audioPreview.play() {
            previewPaused = false
        } else {
            stopNarrationPreview()
        }
    }

    private func stopNarrationPreview() {
        audioPreview?.stop()
        audioPreview = nil
        activePreviewCueID = nil
        previewPaused = false
    }

    private func selectionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedSegmentIDs.contains(id) },
            set: { selected in
                if selected { selectedSegmentIDs.insert(id) }
                else { selectedSegmentIDs.remove(id) }
                refreshEditorShortcutActions()
            }
        )
    }

    private var canCreateSegment: Bool { captionControlsAvailable && !studio.busy }
    private var canOpenSegmentEditor: Bool { canCreateSegment }

    private func presentSegmentEditor(_ row: TranscriptRow, adding: Bool = false) {
        guard adding ? canCreateSegment : canOpenSegmentEditor else { return }
        playback.pauseAndCaptureTime { _ in
            guard adding ? canCreateSegment : canOpenSegmentEditor else { return }
            segmentEditorHint = ""
            segmentToEdit = row
        }
    }

    private func presentBulkSegmentEditor() {
        guard segmentEditMode && canOpenSegmentEditor else { return }
        let selected = transcriptRows.filter { selectedSegmentIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        playback.pauseAndCaptureTime { _ in
            guard segmentEditMode && canOpenSegmentEditor else { return }
            segmentBatchToEdit = SegmentEditBatch(rows: selected)
        }
    }




    private func segmentDurationText(_ segment: Segment) -> String {
        NarrationTimeFormat.mediaDuration(max(0, segment.end - segment.start))
    }

    private func segmentDurationLabel(for segment: Segment) -> some View {
        Text(segmentDurationText(segment))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityLabel("Duration \(NarrationTimeFormat.spokenDuration(max(0, segment.end - segment.start)))")
    }

    private func segmentHasAudio(_ segment: Segment) -> Bool {
        segment.audio.map { project.hasFile($0) } ?? false
    }

    private var selectedDescriptions: [Segment] {
        selectedRows.filter(\.isDescription).map(\.segment)
    }

    private var selectedDescriptionIDs: [String] { selectedDescriptions.map(\.id) }

    private var bulkNarrationCounts: (new: Int, existing: Int) {
        selectedDescriptions.reduce(into: (0, 0)) { counts, segment in
            if segmentHasAudio(segment) { counts.existing += 1 }
            else { counts.new += 1 }
        }
    }

    private var bulkNarrationLabel: String {
        let counts = bulkNarrationCounts
        if counts.existing == 0 {
            return "Generate Audio for \(counts.new) Description\(counts.new == 1 ? "" : "s")"
        }
        if counts.new == 0 {
            return "Regenerate Audio for \(counts.existing) Description\(counts.existing == 1 ? "" : "s")"
        }
        return "Generate Audio for \(counts.new) New and Regenerate Audio for \(counts.existing) Existing Description\(counts.existing == 1 ? "" : "s")"
    }

    private var bulkNarrationAvailable: Bool {
        guard !selectedDescriptionIDs.isEmpty, !studio.busy else { return false }
        return studio.settings.ttsMode != "gemini" || studio.hasValidApiKey
    }

    private var bulkNarrationUnavailableReason: String? {
        if selectedDescriptionIDs.isEmpty { return "Select one or more descriptions; transcript segments do not have narration." }
        if studio.settings.ttsMode == "gemini" && !studio.hasApiKey {
            return "Enter your Gemini API key in Settings → Gemini API to generate Gemini narration."
        }
        if studio.settings.ttsMode == "gemini" && studio.isApiKeyInvalid {
            return "The Gemini API key is invalid. Update it in Settings → Gemini API to generate narration."
        }
        return nil
    }

    private func generateNarrationForSelectedDescriptions() {
        let ids = selectedDescriptionIDs
        guard !ids.isEmpty, bulkNarrationAvailable else { return }
        studio.execute("synthesize-tts", extra: ids.flatMap { ["--segments", $0] }, project: project)
    }


    private var filterableTab: Bool {
        tab == "transcript" || tab == "descriptions" || tab == "ad-transcript"
    }

    private var segmentFilterTitle: String {
        switch tab {
        case "transcript": return "Filter Transcript…"
        case "descriptions": return "Filter Descriptions…"
        case "ad-transcript": return "Filter AD Transcript…"
        default: return "Filter Segments…"
        }
    }

    private var filterSegmentOptions: [SegmentFilterOption] {
        let dialogue = tab == "descriptions" ? [] : project.transcript.enumerated().map {
            SegmentFilterOption(id: "transcript:" + $0.element.id, number: $0.offset + 1, isDescription: false,
                start: $0.element.start, end: $0.element.end, text: $0.element.text)
        }
        let descriptions = tab == "transcript" ? [] : project.cues.enumerated().map {
            SegmentFilterOption(id: "ad:" + $0.element.id, number: $0.offset + 1, isDescription: true,
                start: $0.element.start, end: $0.element.end, text: $0.element.text)
        }
        return dialogue + descriptions
    }

    private var availableOrigins: [DescriptionOrigin] {
        let segments: [Segment]
        switch tab {
        case "descriptions": segments = project.cues
        case "ad-transcript": segments = project.transcript + project.cues
        default: segments = project.transcript
        }
        let present = Set(segments.map(\.provenance))
        return DescriptionOrigin.editableCases.filter { present.contains($0) }
    }

    private var selectedRows: [TranscriptRow] {
        transcriptRows.filter { selectedSegmentIDs.contains($0.id) }
    }

    private func updateSelectedSegments(_ update: (inout Segment) -> Void) {
        guard !studio.busy else { return }
        var transcript = project.transcript
        var cues = project.cues
        for row in selectedRows {
            if row.isDescription {
                if let index = cues.firstIndex(where: { $0.id == row.segment.id }) { update(&cues[index]) }
            } else if let index = transcript.firstIndex(where: { $0.id == row.segment.id }) {
                update(&transcript[index])
            }
        }
        studio.saveSegments(transcript, cues: cues)
    }

    private func setOriginForSelection(_ origin: DescriptionOrigin) {
        guard !selectedRows.isEmpty else { return }
        updateSelectedSegments { segment in
            segment.origin = origin.rawValue
            segment.originOverride = true
        }
    }

    private func shiftSelectedSegments(_ offset: Double) -> String? {
        let rows = selectedRows
        guard !rows.isEmpty else { return "Select at least one segment first." }
        guard offset.isFinite, abs(offset) > 0.0001 else { return "Enter a non-zero offset in seconds." }
        let lowest = rows.map(\.segment.start).min() ?? 0
        let highest = rows.map(\.segment.end).max() ?? 0
        guard lowest + offset >= -0.001, highest + offset <= project.duration + 0.001 else {
            return "The shifted selection would move outside the video. Choose a smaller offset."
        }
        updateSelectedSegments { segment in
            segment.start += offset
            segment.end += offset
        }
        return nil
    }

    private var canMergeSelected: Bool {
        guard tab == "transcript", selectedRows.count > 1 else { return false }
        let indices = selectedRows.compactMap { row in
            project.transcript.firstIndex(where: { $0.id == row.segment.id })
        }.sorted()
        guard indices.count == selectedRows.count else { return false }
        return zip(indices, indices.dropFirst()).allSatisfy { $1 == $0 + 1 }
    }

    private func mergeSelectedTranscript() {
        guard canMergeSelected, !studio.busy else { return }
        let rows = selectedRows.sorted {
            if $0.segment.start != $1.segment.start { return $0.segment.start < $1.segment.start }
            return $0.id < $1.id
        }
        guard let first = rows.first, let last = rows.last else { return }
        let ids = Set(rows.map { $0.segment.id })
        let origins = Set(rows.map(\.segment.provenance))
        var merged = first.segment
        merged.end = last.segment.end
        merged.text = rows.map { $0.segment.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        merged.speaker = rows.compactMap(\.segment.speaker).first
        merged.audio = nil
        merged.audioText = nil
        merged.audioDuration = nil
        merged.audioSettings = nil
        merged.audioEngine = nil
        merged.audioVoice = nil
        merged.audioStart = nil
        merged.audioEnd = nil
        merged.audioError = nil
        merged.audioOrigin = nil
        merged.audioSourceName = nil
        merged.origin = (origins.count == 1 ? origins.first ?? .unknown : .unknown).rawValue
        merged.originOverride = true
        let insertionIndex = project.transcript.firstIndex(where: { $0.id == first.segment.id })
            ?? project.transcript.count
        var transcript = project.transcript.filter { !ids.contains($0.id) }
        transcript.insert(merged, at: min(insertionIndex, transcript.count))
        studio.saveSegments(transcript, cues: project.cues)
        selectedSegmentIDs = Set([transcript.first(where: { $0.id == merged.id })?.id].compactMap { $0 })
        refreshEditorShortcutActions()
    }

    private func deleteSelectedSegments() {
        let selected = transcriptRows.filter { selectedSegmentIDs.contains($0.id) }
        let transcriptIDs = Set(selected.filter { !$0.isDescription }.map { $0.segment.id })
        let descriptionIDs = Set(selected.filter(\.isDescription).map { $0.segment.id })
        if studio.confirmDeleteSegments(
            project,
            transcriptIDs: transcriptIDs,
            descriptionIDs: descriptionIDs,
            beforeDelete: {
                stopNarrationPreview()
                playback.stopNarrationPlayback()
            }
        ) {
            selectedSegmentIDs.removeAll()
            segmentEditMode = false
            refreshEditorShortcutActions()
        }
    }

    private func previewPrimaryControlTitle(for cue: Segment) -> String {
        activePreviewCueID == cue.id ? (previewPaused ? "Resume Narration" : "Pause Narration") : "Play Narration"
    }

    private func previewPrimaryControlIcon(for cue: Segment) -> String {
        activePreviewCueID == cue.id && !previewPaused ? "pause.circle" : "play.circle"
    }

    private var previewPane: some View {
        VStack(spacing: 0) {
            ZStack(alignment: studio.settings.captionPosition == "top" ? .top : .bottom) {
                Group {
                    if project.isYouTubeURLProject, let url = project.youtubeURL { YouTubePlayer(url: url, playback: playback, useOriginalAudio: project.audioSources?.playback == "imported") }
                    else { NativeVideoPlayer(player: playback.player, playback: playback) }
                }
                TranscriptCaptionOverlay(
                    project: project,
                    playbackTime: playback.time,
                    settings: studio.settings
                )
            }
            .frame(minWidth: 0, idealWidth: 700, maxWidth: .infinity, minHeight: 120, idealHeight: 340, maxHeight: .infinity)
            .background(.black)
            if timelineVisible {
                TimelineView(project: project, playback: playback, thumbnailImagesVisible: thumbnailImagesVisible)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .animation(interfaceAnimation, value: timelineVisible)
    }

    @ViewBuilder
    private var editorPane: some View {
        VStack(spacing: 0) {
            processingControlBar
            if project.hasDescriptionTimingIssues {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Description timing needs attention")
                            .font(.subheadline.weight(.semibold))
                        Text("\(project.descriptionTimingIssueCount) segment\(project.descriptionTimingIssueCount == 1 ? "" : "s") overlap dialogue or another description. Described exports are blocked until they are retimed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Review Descriptions") { tab = "descriptions" }
                        .help("Open Descriptions to retime the affected segments")
                    if let report = project.lastImportReport {
                        Button("Import Report…") { studio.importReports = [report] }
                            .help("Review the import report that flagged these segments")
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.orange.opacity(0.12))
                .accessibilityGroup("Description timing issues")
            }
            Text(["transcript": "Transcript", "summary": "Summary", "descriptions": "Descriptions", "ad-overview": "AD Overview", "ad-transcript": "AD Transcript"][tab] ?? "Editor")
                .font(.headline).accessibilityAddTraits(.isHeader).accessibilityHeading(.h2).padding(.horizontal, 12)
            editorToolbar
            if let error = playback.speechError { Text(error).foregroundStyle(.red).padding(8) }
            Divider()
            if currentProcessingState.isProcessing {
                SectionProcessingIndicator(
                    title: currentProcessingState == .queued ? "Waiting to process \(sectionProcessingName)" : studio.processingStageTitle,
                    detail: currentProcessingState == .queued
                        ? "This section updates automatically when its turn arrives. You can keep working in other sections."
                        : studio.message
                )
            } else if tab == "ad-overview" {
                ADOverviewView(studio: studio, project: project)
            } else if tab == "summary" {
                if summaryEditMode {
                    SummaryMarkdownEditorView(
                        text: $summaryDraftText,
                        origin: $summaryDraftOrigin,
                        onCancel: {
                            summaryDraftText = project.summary
                            summaryDraftOrigin = project.summaryOriginLabel
                            summaryEditMode = false
                            refreshEditorShortcutActions()
                        }
                    ).disabled(languageContextChanging)
                } else if project.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    summaryEmptyState
                } else {
                    SummaryReaderView(
                        markdown: project.summary,
                        model: summaryReader,
                        settings: studio.settings,
                        follow: followTranscript,
                        hasSummary: !project.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        origin: project.summary.isEmpty ? nil : project.summaryOriginLabel,
                        showZoomSlider: previewHidden,
                        onEdit: { startSummaryEditing() }
                    )
                }
            } else {
                let segments = transcriptRows
                if segments.isEmpty {
                    ContentUnavailableView {
                        Label(tab == "descriptions" ? "Describe what matters" : "Your transcript appears here", systemImage: tab == "descriptions" ? "text.below.photo" : "text.bubble")
                    } description: {
                        Text(tab == "descriptions" ? "Generate descriptions, import existing descriptions, or add a segment manually." : tab == "ad-transcript" ? "Transcribe the video or add audio descriptions to see them together here." : "Generate a transcript or import an existing transcript to begin.")
                    } actions: {
                        if (tab == "transcript" && project.transcript.isEmpty) || (tab == "descriptions" && project.cues.isEmpty) {
                            sectionGenerationButton
                            Button(tab == "transcript" ? "Import Transcript…" : "Import Descriptions…", systemImage: "square.and.arrow.down") {
                                importScope = tab == "transcript" ? .transcript : .descriptions
                            }
                            .disabled(studio.busy)
                        }
                    }
                } else {
                    ScrollViewReader { reader in
                    let transcriptNumbers = project.segmentNumbers(isDescription: false)
                    let descriptionNumbers = project.segmentNumbers(isDescription: true)
                    List(segments) { row in
                        let cue = row.segment
                        let segmentNumber = (row.isDescription ? descriptionNumbers : transcriptNumbers)[cue.id] ?? 0
                        let adNumber: Int? = row.isDescription ? segmentNumber : nil
                        let isNarratingCue = row.isDescription && studio.isSegmentNarrating(cue.id)
                        let isQueuedCue = row.isDescription && studio.isSegmentQueuedForNarration(cue.id)
                        HStack(alignment: .top, spacing: 16) {
                            if segmentEditMode {
                                Toggle("Select \(row.kind.lowercased()) segment at \(NarrationTimeFormat.spokenTime(cue.start))", isOn: selectionBinding(for: row.id))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                    .accessibilityLabel("Select \(row.kind.lowercased()) segment at \(NarrationTimeFormat.spokenTime(cue.start))")
                            }
                            Button {
                                if row.isDescription { playback.narrationEnabled = true }
                                playback.goTo(cue.start)
                            } label: {
                                Image(systemName: "play.fill").accessibilityHidden(true)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(row.playbackLabel)
                            .help(row.playbackLabel)
                            Text("#\(segmentNumber)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 28, alignment: .trailing)
                                .accessibilityLabel("\(row.kind) segment \(segmentNumber)")
                            Button { playback.seek(cue.start) } label: {
                                VStack { Text(timecode(cue.start)); Text(timecode(cue.end)).foregroundStyle(.secondary) }.monospacedDigit().font(.caption)
                            }.buttonStyle(.plain)
                                .accessibilityLabel("Seek to segment start. \(row.timingAnnouncement)")
                                .accessibilityHint("Moves the video to this segment’s start time")
                                .help("Seek to \(timecode(cue.start))")
                            VStack(alignment: .leading, spacing: 6) {
                                if tab == "ad-transcript" {
                                    HStack(spacing: 6) {
                                        Image(systemName: row.isDescription ? "text.below.photo" : "text.bubble").accessibilityHidden(true)
                                        Text(row.kind).font(.caption.bold())
                                    }
                                    .foregroundStyle(row.color)
                                }
                                if !row.isDescription {
                                    HStack(spacing: 8) {
                                        DescriptionOriginLabel(origin: cue.provenance)
                                        Spacer(minLength: 8)
                                        segmentDurationLabel(for: cue)
                                    }
                                }
                                if row.isDescription {
                                    HStack(spacing: 8) {
                                        DescriptionOriginLabel(origin: cue.provenance)
                                        Spacer(minLength: 8)
                                        segmentDurationLabel(for: cue)
                                    }
                                    if project.descriptionTimingAudit?.segments.contains(where: { $0.id == cue.id }) == true {
                                        Label("Overlap", systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.orange)
                                            .help("This description overlaps dialogue or another description. Described exports are blocked until it is retimed.")
                                            .accessibilityLabel("Description timing overlaps. Needs retiming.")
                                    }
                                    SynchronizedAudioStatusLabel(
                                        status: .resolve(
                                            cue: cue,
                                            project: project
                                        ),
                                        detail: cue.narrationVoiceSummary,
                                        adNumber: adNumber,
                                        isNarrating: isNarratingCue,
                                        isQueued: isQueuedCue
                                    )
                                }
                                Text(cue.text).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if isNarratingCue {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .accessibilityHidden(true)
                                    Image(systemName: "waveform")
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityHidden(true)
                                    Text("Generating…")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Generating narration audio for AD segment \(adNumber ?? 0)")
                            } else if isQueuedCue {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(.orange)
                                        .accessibilityHidden(true)
                                    Text("Queued")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Queued for narration generation")
                            }
                            if row.isDescription && (tab == "descriptions" || tab == "ad-transcript") {
                                Button(previewPrimaryControlTitle(for: cue), systemImage: previewPrimaryControlIcon(for: cue)) {
                                    runSegmentRowAction("segment-one-preview", row: row)
                                }
                                    .labelStyle(.iconOnly)
                                    .disabled(studio.busy || playableNarrationURL(for: cue) == nil)
                                    .help(playableNarrationURL(for: cue) == nil
                                        ? "Generate synchronized audio for this AD segment first"
                                        : "\(previewPrimaryControlTitle(for: cue)) for this AD segment")
                                if activePreviewCueID == cue.id {
                                    Button("Stop Narration", systemImage: "stop.circle") {
                                        runSegmentRowAction("segment-one-preview-stop", row: row)
                                    }
                                    .labelStyle(.iconOnly)
                                    .disabled(studio.busy)
                                    .help("Stop narration for this AD segment")
                                }
                            }
                            if segmentEditMode {
                                Button("Edit \(row.kind) Segment", systemImage: "pencil") {
                                    presentSegmentEditor(row)
                                }
                                .labelStyle(.iconOnly)
                                .disabled(studio.busy)
                                .help("Edit \(row.kind.lowercased()) text and timing")
                                if row.isDescription {
                                    SegmentActionsMenu(actions: [
                                        .init(title: shortcutActions.segmentCommandTitle("segment-one-rewrite", kind: row.isDescription ? "descriptions" : "transcript", hasAudio: cue.audio != nil), systemImage: "sparkles", enabled: canRunSegmentRowAction("segment-one-rewrite", row: row)) {
                                            runSegmentRowAction("segment-one-rewrite", row: row)
                                        },
                                        .init(title: shortcutActions.segmentCommandTitle("segment-one-synthesize", kind: row.isDescription ? "descriptions" : "transcript", hasAudio: cue.audio != nil), systemImage: "waveform", enabled: canRunSegmentRowAction("segment-one-synthesize", row: row)) {
                                            runSegmentRowAction("segment-one-synthesize", row: row)
                                        },
                                        .init(title: shortcutActions.segmentCommandTitle("segment-one-import-audio", kind: row.isDescription ? "descriptions" : "transcript", hasAudio: cue.audio != nil), systemImage: "square.and.arrow.down", enabled: canRunSegmentRowAction("segment-one-import-audio", row: row)) {
                                            runSegmentRowAction("segment-one-import-audio", row: row)
                                        },
                                        .init(title: shortcutActions.segmentCommandTitle("segment-one-delete-audio", kind: row.isDescription ? "descriptions" : "transcript", hasAudio: cue.audio != nil), systemImage: "speaker.slash", enabled: canRunSegmentRowAction("segment-one-delete-audio", row: row), separatorBefore: true) {
                                            runSegmentRowAction("segment-one-delete-audio", row: row)
                                        },
                                        .init(title: shortcutActions.segmentCommandTitle("segment-one-delete", kind: row.isDescription ? "descriptions" : "transcript", hasAudio: cue.audio != nil), systemImage: "trash", enabled: canRunSegmentRowAction("segment-one-delete", row: row)) {
                                            runSegmentRowAction("segment-one-delete", row: row)
                                        },
                                    ])
                                    .fixedSize()
                                    .disabled(studio.busy)
                                } else {
                                    SegmentActionsMenu(actions: [
                                        .init(title: shortcutActions.segmentCommandTitle("segment-one-edit", kind: row.isDescription ? "descriptions" : "transcript", hasAudio: cue.audio != nil), systemImage: "pencil", enabled: canRunSegmentRowAction("segment-one-edit", row: row)) {
                                            runSegmentRowAction("segment-one-edit", row: row)
                                        },
                                        .init(title: shortcutActions.segmentCommandTitle("segment-one-reanalyze", kind: row.isDescription ? "descriptions" : "transcript", hasAudio: cue.audio != nil), systemImage: "sparkles", enabled: canRunSegmentRowAction("segment-one-reanalyze", row: row)) {
                                            runSegmentRowAction("segment-one-reanalyze", row: row)
                                        },
                                        .init(title: shortcutActions.segmentCommandTitle("segment-one-delete", kind: row.isDescription ? "descriptions" : "transcript", hasAudio: cue.audio != nil), systemImage: "trash", enabled: canRunSegmentRowAction("segment-one-delete", row: row), separatorBefore: true) {
                                            runSegmentRowAction("segment-one-delete", row: row)
                                        },
                                    ])
                                    .fixedSize()
                                    .disabled(studio.busy)
                                }
                            }
                        }.padding(.vertical, 8)
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel(row.accessibilityLabel(segmentNumber: segmentNumber))
                            .id(row.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                guard segmentEditMode else { return }
                                presentSegmentEditor(row)
                            }
                            .listRowBackground(
                                isNarratingCue
                                    ? Color.accentColor.opacity(0.22)
                                    : (playback.time >= cue.start && playback.time < cue.end ? Color.accentColor.opacity(0.15) : Color.clear)
                            )
                            .listRowBackground(validationHighlightID == row.id ? Color.orange.opacity(0.25) : Color.clear)
                            .overlay {
                                if validationHighlightID == row.id {
                                    RoundedRectangle(cornerRadius: 6).stroke(.orange, lineWidth: 3)
                                        .allowsHitTesting(false)
                                }
                            }
                            .accessibilityValue(validationHighlightID == row.id ? "Timing validation issue" : "")
                            .contextMenu { segmentRowContextMenu(row) }
                    }.listStyle(.inset)
                    .accessibilityLabel("\(editorSectionAccessibilityTitle) segments")
                    .onAppear { if let id = validationHighlightID { reader.scrollTo(id, anchor: .center) } }
                    .onChange(of: validationHighlightID) { _, id in
                        if let id { reader.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: segments.first(where: { playback.time >= $0.segment.start && playback.time < $0.segment.end })?.id) { _, id in
                        if followTranscript && !validationShowcaseActive, let id { if reduceMotion { reader.scrollTo(id, anchor: .center) } else { withAnimation { reader.scrollTo(id, anchor: .center) } } }
                    }
                    }
                }
            }
        }
        .frame(minHeight: 180)
        .accessibilityGroup("\(editorSectionAccessibilityTitle) editor")
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
                        .transition(.opacity)
                }

                editorPane
                    .frame(maxHeight: .infinity)
            }
            .animation(interfaceAnimation, value: previewHidden)
        }
    }

    private func canRunSegmentRowAction(_ action: String, row: TranscriptRow) -> Bool {
        let kind = row.isDescription ? "descriptions" : "transcript"
        guard shortcutActions.available, shortcutActions.rowCommandVisible(action, kind: kind) else { return false }
        let isPreviewing = row.isDescription && activePreviewCueID == row.segment.id
        return shortcutActions.canRunRowCommand(action, kind: kind, hasAudio: row.segment.audio != nil,
            audioReady: action == "segment-one-preview" && !isPreviewing && playableNarrationURL(for: row.segment) != nil,
            isPreviewing: isPreviewing)
    }

    @ViewBuilder private func segmentRowContextMenu(_ row: TranscriptRow) -> some View {
        if shortcutActions.rowCommandVisible("segment-one-edit", kind: row.isDescription ? "descriptions" : "transcript") {
            Button(shortcutActions.segmentCommandTitle("segment-one-edit", kind: row.isDescription ? "descriptions" : "transcript", hasAudio: row.segment.audio != nil, isPreviewing: row.isDescription && activePreviewCueID == row.segment.id, isPaused: previewPaused), systemImage: "pencil") {
                runSegmentRowAction("segment-one-edit", row: row)
            }
            .disabled(!canRunSegmentRowAction("segment-one-edit", row: row))
        }
        Divider()
        if shortcutActions.rowCommandVisible("segment-one-play", kind: row.isDescription ? "descriptions" : "transcript") {
            Button(shortcutActions.segmentCommandTitle("segment-one-play", kind: row.isDescription ? "descriptions" : "transcript", hasAudio: row.segment.audio != nil, isPreviewing: row.isDescription && activePreviewCueID == row.segment.id, isPaused: previewPaused), systemImage: "play.fill") {
                runSegmentRowAction("segment-one-play", row: row)
            }
            .disabled(!canRunSegmentRowAction("segment-one-play", row: row))
        }
        if shortcutActions.rowCommandVisible("segment-one-skip", kind: row.isDescription ? "descriptions" : "transcript") {
            Button(shortcutActions.segmentCommandTitle("segment-one-skip", kind: row.isDescription ? "descriptions" : "transcript", hasAudio: row.segment.audio != nil, isPreviewing: row.isDescription && activePreviewCueID == row.segment.id, isPaused: previewPaused), systemImage: "forward.end.fill") {
                runSegmentRowAction("segment-one-skip", row: row)
            }
            .disabled(!canRunSegmentRowAction("segment-one-skip", row: row))
        }
        if row.isDescription { Divider() }
        if shortcutActions.rowCommandVisible("segment-one-preview", kind: row.isDescription ? "descriptions" : "transcript") {
            Button(shortcutActions.segmentCommandTitle("segment-one-preview", kind: row.isDescription ? "descriptions" : "transcript", hasAudio: row.segment.audio != nil, isPreviewing: row.isDescription && activePreviewCueID == row.segment.id, isPaused: previewPaused), systemImage: previewPrimaryControlIcon(for: row.segment)) {
                runSegmentRowAction("segment-one-preview", row: row)
            }
            .disabled(!canRunSegmentRowAction("segment-one-preview", row: row))
        }
        if row.isDescription && activePreviewCueID == row.segment.id {
            Button("Stop Narration", systemImage: "stop.circle") {
                runSegmentRowAction("segment-one-preview-stop", row: row)
            }
            .disabled(!canRunSegmentRowAction("segment-one-preview-stop", row: row))
        }
        if row.isDescription { Divider() }
        if shortcutActions.rowCommandVisible("segment-one-synthesize", kind: row.isDescription ? "descriptions" : "transcript") {
            Button(shortcutActions.segmentCommandTitle("segment-one-synthesize", kind: row.isDescription ? "descriptions" : "transcript", hasAudio: row.segment.audio != nil, isPreviewing: row.isDescription && activePreviewCueID == row.segment.id, isPaused: previewPaused), systemImage: "waveform") {
                runSegmentRowAction("segment-one-synthesize", row: row)
            }
            .disabled(!canRunSegmentRowAction("segment-one-synthesize", row: row))
        }
        if shortcutActions.rowCommandVisible("segment-one-rewrite", kind: row.isDescription ? "descriptions" : "transcript") {
            Button(shortcutActions.segmentCommandTitle("segment-one-rewrite", kind: row.isDescription ? "descriptions" : "transcript", hasAudio: row.segment.audio != nil, isPreviewing: row.isDescription && activePreviewCueID == row.segment.id, isPaused: previewPaused), systemImage: "sparkles") {
                runSegmentRowAction("segment-one-rewrite", row: row)
            }
            .disabled(!canRunSegmentRowAction("segment-one-rewrite", row: row))
        }
        if shortcutActions.rowCommandVisible("segment-one-import-audio", kind: row.isDescription ? "descriptions" : "transcript") {
            Button(shortcutActions.segmentCommandTitle("segment-one-import-audio", kind: row.isDescription ? "descriptions" : "transcript", hasAudio: row.segment.audio != nil, isPreviewing: row.isDescription && activePreviewCueID == row.segment.id, isPaused: previewPaused), systemImage: "square.and.arrow.down") {
                runSegmentRowAction("segment-one-import-audio", row: row)
            }
            .disabled(!canRunSegmentRowAction("segment-one-import-audio", row: row))
        }
        if row.isDescription { Divider() }
        if shortcutActions.rowCommandVisible("segment-one-delete-audio", kind: row.isDescription ? "descriptions" : "transcript") {
            Button(shortcutActions.segmentCommandTitle("segment-one-delete-audio", kind: row.isDescription ? "descriptions" : "transcript", hasAudio: row.segment.audio != nil, isPreviewing: row.isDescription && activePreviewCueID == row.segment.id, isPaused: previewPaused), systemImage: "speaker.slash") {
                runSegmentRowAction("segment-one-delete-audio", row: row)
            }
            .disabled(!canRunSegmentRowAction("segment-one-delete-audio", row: row))
        }
        if !row.isDescription { Divider() }
        if shortcutActions.rowCommandVisible("segment-one-reanalyze", kind: row.isDescription ? "descriptions" : "transcript") {
            Button(shortcutActions.segmentCommandTitle("segment-one-reanalyze", kind: row.isDescription ? "descriptions" : "transcript", hasAudio: row.segment.audio != nil, isPreviewing: row.isDescription && activePreviewCueID == row.segment.id, isPaused: previewPaused), systemImage: "sparkles") {
                runSegmentRowAction("segment-one-reanalyze", row: row)
            }
            .disabled(!canRunSegmentRowAction("segment-one-reanalyze", row: row))
        }
        if !row.isDescription { Divider() }
        if shortcutActions.rowCommandVisible("segment-one-delete", kind: row.isDescription ? "descriptions" : "transcript") {
            Button(shortcutActions.segmentCommandTitle("segment-one-delete", kind: row.isDescription ? "descriptions" : "transcript", hasAudio: row.segment.audio != nil, isPreviewing: row.isDescription && activePreviewCueID == row.segment.id, isPaused: previewPaused), systemImage: "trash") {
                runSegmentRowAction("segment-one-delete", row: row)
            }
            .disabled(!canRunSegmentRowAction("segment-one-delete", row: row))
        }
    }

    private func runSegmentRowAction(_ action: String, row: TranscriptRow) {
        guard transcriptRows.contains(where: { $0.id == row.id }) else { return }
        guard canRunSegmentRowAction(action, row: row) else { return }
        let cue = row.segment
        switch action {
        case "segment-one-edit": presentSegmentEditor(row)
        case "segment-one-play":
            if row.isDescription { playback.narrationEnabled = true }
            playback.play(from: cue.start)
        case "segment-one-skip": playback.seek(cue.start); playback.pausePlayback()
        case "segment-one-preview":
            if activePreviewCueID == cue.id { toggleNarrationPreviewPause() }
            else { playNarrationPreview(for: cue) }
        case "segment-one-preview-stop": stopNarrationPreview()
        case "segment-one-synthesize": studio.execute("synthesize-tts", extra: ["--segment", cue.id])
        case "segment-one-rewrite": studio.execute("rewrite-cue", extra: ["--segment", cue.id])
        case "segment-one-import-audio": chooseNarrationAudio(for: cue)
        case "segment-one-delete-audio":
            studio.confirmDeleteSegmentAudio(project, cue: cue) {
                stopNarrationPreview(); playback.stopNarrationPlayback()
            }
        case "segment-one-reanalyze": studio.reanalyzeSegment(cue, hint: "", isDescription: false)
        case "segment-one-delete":
            if row.isDescription {
                studio.confirmDeleteSegment(project, cue: cue) {
                    stopNarrationPreview(); playback.stopNarrationPlayback()
                }
            } else {
                studio.confirmDeleteSegments(project, transcriptIDs: [cue.id], descriptionIDs: [], beforeDelete: {})
            }
        default: break
        }
    }

    private func runEditorShortcut(_ action: String) {
        if action.hasPrefix("segment-one-") {
            guard shortcutActions.canRun(action), selectedSegmentIDs.count == 1, selectedRows.count == 1,
                  let row = selectedRows.first else { return }
            runSegmentRowAction(action, row: row)
            return
        }
        switch action {
        case "preview": playback.exitVideoFullScreen(); previewHidden.toggle()
        case "toggle-timeline": timelineVisible.toggle()
        case "toggle-thumbnail-images": thumbnailImagesVisible.toggle()
        case "fullscreen":
            previewHidden = false
            DispatchQueue.main.async {
                playback.toggleVideoFullScreen()
                refreshEditorShortcutActions()
            }
        case "play": playback.togglePlayback()
        case "stop": playback.stopPlayback()
        case "back": playback.seekRelative(-5, duration: project.duration)
        case "forward": playback.seekRelative(5, duration: project.duration)
        case "jump-to-time": showingJumpToTime = true
        case "narration": playback.narrationEnabled.toggle()
        case "caption-cycle": cycleCaptionDisplayMode()
        case "caption-off": studio.settings.captionDisplayMode = "off"
        case "caption-transcript": studio.settings.captionDisplayMode = "transcript"
        case "caption-ad-transcript": studio.settings.captionDisplayMode = "ad-transcript"
        case "follow": followTranscript.toggle()
        case "segment-edit-mode":
            if tab == "summary" {
                toggleSummaryEditMode()
            } else {
                segmentEditMode.toggle()
                if !segmentEditMode { selectedSegmentIDs.removeAll() }
                refreshEditorShortcutActions()
            }
        case "segment-select-all":
            selectedSegmentIDs = Set(transcriptRows.map(\.id))
            refreshEditorShortcutActions()
        case "segment-deselect-all":
            selectedSegmentIDs.removeAll()
            refreshEditorShortcutActions()
        case "segment-edit-selected": presentBulkSegmentEditor()
        case "copy-to": presentCopyAndTranslate(currentSectionOnly: false)
        case "language-results": showingLanguageResults = true
        case "filter-segments": if filterableTab { showingSegmentFilter = true }
        case "sort-segments": if filterableTab { showingSegmentSort = true }
        case "clear-segment-filter":
            segmentFilter = SegmentFilter()
            selectedSegmentIDs.removeAll()
            refreshEditorShortcutActions()
        case "clear-segment-sort":
            segmentSort = .start
            selectedSegmentIDs.removeAll()
            refreshEditorShortcutActions()
        case "sort-start": segmentSort = .start; refreshEditorShortcutActions()
        case "sort-duration-asc": segmentSort = .durationAscending; refreshEditorShortcutActions()
        case "sort-duration-desc": segmentSort = .durationDescending; refreshEditorShortcutActions()
        case "sort-origin": segmentSort = .origin; refreshEditorShortcutActions()
        case "segment-delete-selected": deleteSelectedSegments()
        case "descriptions", "transcript", "summary", "ad-transcript", "ad-overview": tab = action
        case "summary-zoom-in": summaryReader.zoomIn()
        case "summary-zoom-out": summaryReader.zoomOut()
        case "summary-zoom-reset": summaryReader.setZoom(1)
        case "summary-play-pause": summaryReader.togglePlayPause()
        case "summary-play":
            if summaryReader.isPaused { summaryReader.play() }
            else if !summaryReader.isReading { summaryReader.togglePlayPause() }
        case "summary-pause": summaryReader.pause()
        case "summary-stop": summaryReader.stop()
        case "summary-previous-sentence": summaryReader.playPreviousSentence()
        case "summary-next-sentence": summaryReader.playNextSentence()
        case "summary-previous-paragraph": summaryReader.playPreviousParagraph()
        case "summary-next-paragraph": summaryReader.playNextParagraph()
        case "summary-from-start": summaryReader.playFromStart()
        case "summary-from-selection": summaryReader.playFromSelection()
        case "summary-read-selection": summaryReader.readSelectedText()
        case "add": presentNewSegment(isDescription: tab == "descriptions")
        case "reanalyze-selection": presentNewSegment(isDescription: tab == "descriptions")
        case "delete-narration": studio.confirmDeleteGeneratedContent(project, component: .narration)
        case "delete-transcript": studio.confirmDeleteGeneratedContent(project, component: .transcript)
        case "delete-summary": studio.confirmDeleteGeneratedContent(project, component: .summary)
        case "delete-descriptions": studio.confirmDeleteGeneratedContent(project, component: .descriptions)
        case "undo": studio.execute(tab == "transcript" ? "undo-transcript" : "undo-cues")
        case "redo": studio.execute(tab == "transcript" ? "redo-transcript" : "redo-cues")
        case "synthesize-tts": studio.execute(action)
        case "synthesize-changed": studio.execute("synthesize-tts", extra: ["--changed"])
        case "review-narration-issues": studio.narrationFailureReport = studio.narrationIssueReport(for: project)
        case "review-narration-voices": studio.narrationVoiceReport = studio.narrationVoiceUsageReport(for: project)
        case "show-in-finder": if let folder = project.folder { NSWorkspace.shared.open(folder) }
        case "open-configuration": openProjectConfiguration(project, studio: studio)
        case "import-assets": showingImportAssets = true
        case "import-transcript": importScope = .transcript
        case "import-summary": importScope = .summary
        case "import-descriptions": importScope = .descriptions
        case "import-original-audio": importScope = .originalAudio
        case "import-ad-audio": importScope = .adAudio
        case "rename-project": renameProject()
        case "trash-project": trashProject()
        case "delete-project": trashProject()
        case "delete-content": studio.confirmDeleteGeneratedContent(project, components: [])
        case "analyze", "prepare-video", "transcribe", "generate-summary": studio.execute(action)
        case "generate-ad-cues":
            if project.canGenerateDescriptions { studio.execute(action) }
        default: break
        }
    }

    private var summaryEmptyState: some View {
        ContentUnavailableView {
            Label("Write or bring a summary", systemImage: "text.alignleft")
        } description: {
        } actions: {
            sectionGenerationButton
            Button("Import Summary…", systemImage: "square.and.arrow.down") { chooseSummaryToImport() }
                .disabled(studio.busy)
                .help("Import a Markdown or TXT summary without a transcript or API key")
        }
    }

    private func chooseSummaryToImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["md", "markdown", "txt"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import Summary"
        panel.message = "Choose a Markdown or TXT summary."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var selection = ImportAssetSelection()
        selection.summary = url
        studio.importAssets(selection, into: project, combine: false)
    }

    private func startSummaryEditing() {
        summaryReader.stop()
        summaryDraftText = project.summary
        summaryDraftOrigin = project.summaryOriginLabel
        summaryEditMode = true
        refreshEditorShortcutActions()
    }

    private var hasUnsavedSummaryEdits: Bool {
        summaryEditMode && (summaryDraftText.trimmingCharacters(in: .whitespacesAndNewlines) != project.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            || summaryDraftOrigin != project.summaryOriginLabel)
    }

    private func runLanguageAction(_ command: String, arguments: [String], settingsEditMode: Bool = false, fromSettings: Bool = false) {
        guard !studio.busy, !languageContextChanging, !hasUnsavedSummaryEdits,
              segmentToEdit == nil, segmentBatchToEdit == nil else { return }
        let changesLanguage = ["select-section-language", "sync-section-languages", "assign-result-language"].contains(command)
        guard !changesLanguage || settingsEditMode || (tab == "summary" ? summaryEditMode : segmentEditMode) else { return }
        stopNarrationPreview()
        summaryReader.stop()
        languageContextChanging = true
        studio.execute(command, extra: arguments, project: project) { updated in
            if let updated, summaryEditMode {
                summaryDraftText = updated.summary
                summaryDraftOrigin = updated.summaryOriginLabel
            }
            languageContextChanging = false
            refreshEditorShortcutActions()
            if fromSettings { NotificationCenter.default.post(name: .vidiStudioLanguageDidChange, object: nil, userInfo: ["projectID": project.id]) }
        }
    }

    private func commitSummaryEdits() {
        let trimmed = summaryDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let originChanged = summaryDraftOrigin != project.summaryOriginLabel
        if trimmed != project.summary.trimmingCharacters(in: .whitespacesAndNewlines) || originChanged {
            studio.saveSummary(summaryDraftText, origin: originChanged ? summaryDraftOrigin : nil)
        }
        summaryEditMode = false
        refreshEditorShortcutActions()
    }

    private func toggleSummaryEditMode() {
        if summaryEditMode {
            commitSummaryEdits()
        } else {
            startSummaryEditing()
        }
    }

    private func presentCopyAndTranslate(currentSectionOnly: Bool) {
        guard shortcutActions.canRun("copy-to") else { return }
        var ids: [String: [String]] = [:]
        for row in selectedRows { ids[row.isDescription ? "descriptions" : "transcript", default: []].append(row.segment.id) }
        copySelection = LanguageCopySelection(kinds: shortcutActions.copyKinds(currentSectionOnly: currentSectionOnly), segmentIDs: ids)
    }

    private func refreshEditorShortcutActions(updateHandler: Bool = false) {
        if updateHandler {
            shortcutActions.handler = { action in runEditorShortcut(action) }
            shortcutActions.copyHandler = { currentSectionOnly in presentCopyAndTranslate(currentSectionOnly: currentSectionOnly) }
            shortcutActions.exportHandler = showExportDialog
            shortcutActions.languageAction = { command, arguments in runLanguageAction(command, arguments: arguments) }
            shortcutActions.settingsLanguageAction = { command, arguments, editing in runLanguageAction(command, arguments: arguments, settingsEditMode: editing, fromSettings: true) }
        }
        shortcutActions.hasCopyableResults = project.savedLanguageResults.contains { ["transcript", "summary", "descriptions"].contains($0.kind) && $0.state == "saved" && $0.hasContent }
        shortcutActions.hasUnsavedSummaryEdits = hasUnsavedSummaryEdits
        shortcutActions.canJumpToTime = project.duration.isFinite && project.duration > 0
        shortcutActions.videoIsPlaying = playback.playbackActive
        shortcutActions.videoPlaybackStarted = playback.videoPlaybackStarted
        shortcutActions.previewHidden = previewHidden
        shortcutActions.isVideoFullScreen = playback.isVideoFullScreen
        shortcutActions.timelineVisible = timelineVisible
        shortcutActions.thumbnailImagesVisible = thumbnailImagesVisible
        shortcutActions.available = !shortcutsBlocked && !studio.busy && !showingJumpToTime && segmentToEdit == nil && segmentBatchToEdit == nil && studio.screenText == nil
        shortcutActions.activeSection = tab
        if shortcutActions.resultProject?.id != project.id || shortcutActions.resultProject?.updatedAt != project.updatedAt || shortcutActions.resultProject?.languageCode != project.languageCode {
            shortcutActions.resultProject = project
        }
        shortcutActions.viewingLanguage = project.languageCode
        shortcutActions.viewingLanguages = OutputLanguage.options.filter { project.availableViewingLanguages.contains($0.id) }
            .map { OutputLanguage(id: $0.id, title: project.viewingLanguageTitle($0.id)) }
        shortcutActions.canImportOriginalAudio = project.isYouTubeURLProject
        shortcutActions.captionDisplayMode = studio.settings.captionDisplayMode
        shortcutActions.hasTranscriptText = !project.transcript.isEmpty
        shortcutActions.canToggleNarration = narrationControlAvailable
        shortcutActions.canToggleFollow = followControlAvailable
        shortcutActions.canAddSegment = tab == "descriptions" || tab == "transcript"
        switch tab {
        case "transcript": shortcutActions.addSegmentTitle = "Add Transcript Segment"
        case "descriptions": shortcutActions.addSegmentTitle = "Add Audio Description Segment"
        default: shortcutActions.addSegmentTitle = "Add Segment"
        }
        if tab == "summary" {
            shortcutActions.segmentEditingAvailable = true
            shortcutActions.segmentEditMode = summaryEditMode
            shortcutActions.segmentEditModeTitle = summaryEditMode ? "Done Editing Summary" : "Edit Summary"
        } else {
            shortcutActions.segmentEditingAvailable = segmentEditingAvailable
            shortcutActions.segmentEditMode = segmentEditMode
            shortcutActions.segmentEditModeTitle = segmentEditMode ? "Done Editing Segments" : "Edit \(segmentSectionTitle) Segments"
        shortcutActions.filterTitle = segmentFilterTitle
        shortcutActions.segmentFilterActive = filterableTab && segmentFilter.isActive
        shortcutActions.sortTitle = switch tab {
        case "transcript": "Sort Transcripts…"
        case "descriptions": "Sort Descriptions…"
        case "ad-transcript": "Sort AD Transcript…"
        default: "Sort Segments…"
        }
        shortcutActions.segmentSort = segmentSort.rawValue
        }
        shortcutActions.segmentCount = transcriptRows.count
        shortcutActions.selectedSegmentCount = selectedRows.count
        let singleRow = selectedSegmentIDs.count == 1 && selectedRows.count == 1 ? selectedRows.first : nil
        shortcutActions.selectedSegmentKind = singleRow.map { $0.isDescription ? "descriptions" : "transcript" }
        shortcutActions.selectedSegmentHasAudio = singleRow?.segment.audio != nil
        shortcutActions.selectedSegmentAudioReady = singleRow.map { playableNarrationURL(for: $0.segment) != nil } ?? false
        shortcutActions.selectedSegmentPreviewing = singleRow.map { $0.isDescription && activePreviewCueID == $0.segment.id } ?? false
        shortcutActions.segmentPreviewPaused = shortcutActions.selectedSegmentPreviewing && previewPaused
        shortcutActions.canGenerateDescriptions = project.canGenerateDescriptions
        shortcutActions.canUndoSegment = !(tab == "transcript" ? project.transcriptUndoStack ?? [] : project.undoStack ?? []).isEmpty
        shortcutActions.canRedoSegment = !(tab == "transcript" ? project.transcriptRedoStack ?? [] : project.redoStack ?? []).isEmpty
        shortcutActions.hasNarrationAudio = GeneratedContentComponent.narration.hasContent(in: project)
        shortcutActions.hasDescriptions = GeneratedContentComponent.descriptions.hasContent(in: project)
        shortcutActions.descriptionCount = project.cues.count
        shortcutActions.hasChangedNarration = project.canGenerateMissingOrChangedAudio
        shortcutActions.hasGeneratedTranscript = GeneratedContentComponent.transcript.hasContent(in: project)
        shortcutActions.hasGeneratedSummary = GeneratedContentComponent.summary.hasContent(in: project)
        shortcutActions.youtubeProject = project.isYouTubeURLProject
        shortcutActions.hasApiKey = studio.hasApiKey
        shortcutActions.apiKeyVerified = studio.apiKeyVerified
        shortcutActions.aiProcessingBlocked = studio.isAIProcessingBlocked
        shortcutActions.ttsUsesGemini = (studio.settings.ttsMode == "gemini")
        shortcutActions.hasGeneratedThumbnails = !project.thumbnails.isEmpty
        shortcutActions.isSynthesizingNarration = studio.isSynthesizingNarration
        shortcutActions.narratingSegmentIndex = studio.narratingSegmentIndex
        shortcutActions.narratingTotalCount = studio.narratingTotalCount > 0 ? studio.narratingTotalCount : project.cues.count
        shortcutActions.summaryActive = (tab == "summary")
        shortcutActions.summaryEditing = (tab == "summary" && summaryEditMode)
        shortcutActions.summaryReadable = !project.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !studio.busy
        shortcutActions.summaryZoom = summaryReader.zoom
        shortcutActions.summaryIsReading = summaryReader.isReading
        shortcutActions.summaryIsPaused = summaryReader.isPaused
        shortcutActions.summaryCanGoToPreviousSentence = summaryReader.canGoToPreviousSentence
        shortcutActions.summaryCanGoToNextSentence = summaryReader.canGoToNextSentence
        shortcutActions.summaryCanGoToPreviousParagraph = summaryReader.canGoToPreviousParagraph
        shortcutActions.summaryCanGoToNextParagraph = summaryReader.canGoToNextParagraph
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
            if !studio.busy, duration > 0, abs(duration - project.duration) > 0.001 { studio.execute("update-metadata", extra: ["--duration", String(duration)]) }
        }
    }

    private var editorWithPlaybackUpdates: some View {
        editorWithProjectUpdates
        .onChange(of: playback.time) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: playback.playing) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: playback.videoPlaybackStarted) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: project.audioSources) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: project.originalAudio) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: project.duration) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: studio.settings.narrationPlayback) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: studio.settings.soundWhenNarrationOff) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: studio.settings.soundWhenNarrationMissing) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: playback.narrationEnabled) { _, enabled in
            ProjectPlaybackPreferences.setNarrationEnabled(enabled, folder: project.folder, projectID: project.id)
            playback.syncNarration(project, settings: studio.settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vidiStudioProjectNarrationDidChange)) { notification in
            guard notification.userInfo?["projectID"] as? String == project.id,
                  let enabled = notification.userInfo?["enabled"] as? Bool,
                  playback.narrationEnabled != enabled else { return }
            playback.narrationEnabled = enabled
        }
        .onChange(of: activePreviewCueID) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: previewPaused) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: followTranscript) { _, enabled in
            ProjectPlaybackPreferences.setFollowEnabled(enabled, folder: project.folder, projectID: project.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vidiStudioProjectFollowDidChange)) { notification in
            guard notification.userInfo?["projectID"] as? String == project.id,
                  let enabled = notification.userInfo?["enabled"] as? Bool,
                  followTranscript != enabled else { return }
            followTranscript = enabled
        }
        .onReceive(NotificationCenter.default.publisher(for: .vidiStudioLanguageWillChange)) { notification in
            guard notification.userInfo?["projectID"] as? String == project.id else { return }
            stopNarrationPreview(); summaryReader.stop(); playback.stopNarrationPlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vidiStudioLanguageDidChange)) { notification in
            guard notification.userInfo?["projectID"] as? String == project.id, !hasUnsavedSummaryEdits, !studio.busy else { return }
            studio.reload()
            if let updated = studio.selected {
                if summaryEditMode { summaryDraftText = updated.summary; summaryDraftOrigin = updated.summaryOriginLabel }
                playback.syncNarration(updated, settings: studio.settings)
            }
            refreshEditorShortcutActions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vidiStudioNarrationAudioWillDelete)) { notification in
            guard notification.userInfo?["projectID"] as? String == project.id else { return }
            stopNarrationPreview()
            playback.stopNarrationPlayback()
        }
        .task(id: activePreviewCueID) {
            guard let cueID = activePreviewCueID else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                guard activePreviewCueID == cueID else { return }
                if !previewPaused, audioPreview?.isPlaying != true {
                    stopNarrationPreview()
                    return
                }
            }
        }
    }

    private var editorWithVoiceUpdates: some View {
        editorWithPlaybackUpdates
        .onChange(of: studio.settings.systemVoice) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: studio.settings.systemSpeechRate) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: studio.settings.systemSpeechPitch) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: studio.settings.systemSpeechVolume) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: timelineVisible) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: thumbnailImagesVisible) { _, _ in refreshEditorShortcutActions() }
    }

    private var editorWithSummaryUpdates: some View {
        editorWithVoiceUpdates
        .onChange(of: project.summary) { _, newSummary in
            if !summaryEditMode {
                summaryDraftText = newSummary
            }
            refreshEditorShortcutActions()
        }
        .onChange(of: segmentEditMode) { _, editing in
            if !editing { segmentToEdit = nil; segmentBatchToEdit = nil }
            refreshEditorShortcutActions()
        }
        .onChange(of: summaryEditMode) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: summaryDraftText) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: summaryDraftOrigin) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: summaryReader.zoom) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: summaryReader.isReading) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: summaryReader.isPaused) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: summaryReader.currentIndex) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: summaryReader.selectedRange) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: summaryReader.sentences.count) { _, _ in refreshEditorShortcutActions() }
    }

    private var editorWithShortcutUpdates: some View {
        editorWithSummaryUpdates
        .onChange(of: previewHidden) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: shortcutsBlocked) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: showingJumpToTime) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: segmentToEdit?.id) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: segmentBatchToEdit?.id) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: studio.screenText) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: studio.busy) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: studio.isSynthesizingNarration) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: studio.narratingSegmentID) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: studio.narratingSegmentIndex) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: project.updatedAt) { _, _ in
            // Any saved project change ends summary playback so the reader never
            // narrates text that is about to be replaced.
            summaryReader.stop()
            refreshEditorShortcutActions(updateHandler: true)
        }
        .onChange(of: playback.playing) { _, playing in
            if playing { summaryReader.stop() }
            refreshEditorShortcutActions()
        }
        .onChange(of: playback.buffering) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: studio.settings.captionDisplayMode) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: studio.hasApiKey) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: studio.apiKeyVerified) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: studio.settings.ttsMode) { _, _ in refreshEditorShortcutActions() }
        .onChange(of: tab) { oldTab, _ in
            if oldTab == "summary" && summaryEditMode {
                commitSummaryEdits()
            }
            selectedSegmentIDs.removeAll()
            segmentEditMode = false
            refreshEditorShortcutActions()
        }
    }

    var body: some View {
        editorWithShortcutUpdates
        .disabled(validationShowcaseActive)
        .overlay(alignment: .bottom) {
            if validationShowcaseActive {
                Button("Return to Edit", systemImage: "arrow.uturn.backward") { validationShowcaseTask?.cancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("validation-return-to-edit")
                    .contextMenu { Button("Return to Edit") { validationShowcaseTask?.cancel() } }
                    .padding(12)
                    .background(.regularMaterial, in: .rect(cornerRadius: 10))
                    .padding()
            }
        }
        .onAppear {
            preparePlayback()
            refreshEditorShortcutActions(updateHandler: true)
        }
        .onDisappear {
            validationShowcaseActive = false
            validationShowcaseTask?.cancel()
            validationRequest = nil
            shortcutActions.available = false
            shortcutActions.summaryEditing = false
            shortcutActions.handler = nil
            shortcutActions.copyHandler = nil
            shortcutActions.exportHandler = nil
            playback.stop()
            summaryReader.stop()
            stopNarrationPreview()
        }
        .sheet(isPresented: screenTextPresented) { screenTextReview }
        .sheet(item: $segmentToEdit, onDismiss: {
            readingFrameForSegment = false
            segmentScreenText = nil
            if let request = validationRequest {
                validationRequest = nil
                request()
            }
        }) { row in segmentEditor(for: row) }
        .sheet(item: $segmentBatchToEdit, onDismiss: {
            if let request = validationRequest { validationRequest = nil; request() }
        }) { batch in
            BulkSegmentEditor(
                rows: batch.rows,
                soundWhenTimingInvalid: studio.settings.soundWhenTimingInvalid,
                selectedID: batch.selectedID,
                showIssues: { rows, selectedID, targets in
                    validationRequest = {
                        showcaseValidationIssues(targets) {
                            segmentBatchToEdit = SegmentEditBatch(rows: rows, selectedID: selectedID)
                        }
                    }
                    segmentBatchToEdit = nil
                },
                allRows: project.transcript.map { TranscriptRow(segment: $0, isDescription: false) }
                    + project.cues.map { TranscriptRow(segment: $0, isDescription: true) },
                duration: project.duration
            ) { updatedRows in
                saveEditedRows(updatedRows)
                selectedSegmentIDs.removeAll()
                segmentEditMode = false
            }
        }
        .sheet(item: $studio.narrationFailureReport) { report in
            NarrationFailuresView(report: report)
        }
        .sheet(item: $studio.narrationVoiceReport) { report in
            NarrationVoicesView(report: report)
        }
        .sheet(isPresented: $showingImportAssets) {
            ImportExistingAssetsView(studio: studio, project: project)
        }
        .sheet(isPresented: $showingAudioSources) {
            VStack(alignment: .leading, spacing: 16) {
                YouTubeAudioSourceControls(studio: studio, project: project)
                Button("Done") { showingAudioSources = false }.keyboardShortcut(.defaultAction)
            }.padding(20).frame(width: 620)
        }
        .sheet(item: $importScope) { scope in
            ImportExistingAssetsView(studio: studio, project: project, scope: scope)
        }
        .sheet(isPresented: Binding(
            get: { !studio.importReports.isEmpty },
            set: { if !$0 { studio.clearImportReports() } }
        )) {
            ImportReportSheet(
                reports: studio.importReports,
                canEditTranscriptTimings: !project.transcript.isEmpty && studio.importReports.contains { $0.kind == "transcript" || $0.kind == "narration" },
                onEditTranscriptTimings: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showingTranscriptTimingEditor = true
                    }
                },
                onReviewDescriptions: { tab = "descriptions" },
                onReviewTranscript: { tab = "transcript" },
                onClose: { studio.clearImportReports() }
            )
        }
        .sheet(isPresented: $showingTranscriptTimingEditor) {
            TranscriptTimingEditorView(studio: studio, project: project)
        }
        .sheet(isPresented: $showingBulkShift) {
            BulkShiftTimingView(count: selectedRows.count, duration: project.duration, apply: shiftSelectedSegments)
        }
        .sheet(item: $copySelection) { selection in
            LanguageCopyView(studio: studio, project: project, selection: selection, canCopy: { shortcutActions.canRun("copy-to") })
        }
        .sheet(isPresented: $showingLanguageResults) {
            ScrollView { LanguageResultControls(studio: studio, project: project, editorActions: shortcutActions).padding(24) }.frame(width: 520, height: 600)
        }
        .sheet(isPresented: $showingJumpToTime) {
            JumpToTimeView(position: playback.time, duration: project.duration) { seconds in
                guard !studio.busy else { return }
                stopNarrationPreview()
                playback.goTo(seconds)
            }
        }
        .sheet(isPresented: $showingSegmentSort) {
            VStack(alignment: .leading, spacing: 16) {
                SegmentSavedResultControls(project: project, kinds: tab == "transcript" ? ["transcript"] : tab == "descriptions" ? ["descriptions"] : ["transcript", "descriptions"],
                    enabled: !studio.busy && !languageContextChanging) { id in runLanguageAction("select-result", arguments: ["--result-id", id]) }
                SegmentSortView(title: shortcutActions.sortTitle.replacingOccurrences(of: "…", with: ""), initial: segmentSort) {
                    segmentSort = $0
                    selectedSegmentIDs.removeAll()
                    refreshEditorShortcutActions()
                }
            }.padding(20).frame(width: 620)
        }
        .sheet(isPresented: $showingSegmentFilter) {
            VStack {
                SegmentSavedResultControls(project: project, kinds: tab == "transcript" ? ["transcript"] : tab == "descriptions" ? ["descriptions"] : ["transcript", "descriptions"],
                    enabled: !studio.busy && !languageContextChanging) { id in runLanguageAction("select-result", arguments: ["--result-id", id]) }
                    .padding(.horizontal, 20).padding(.top, 16)
                SegmentFilterView(
                title: segmentFilterTitle.replacingOccurrences(of: "…", with: ""),
                origins: availableOrigins,
                showsAudio: tab != "transcript",
                showsTranscript: tab != "descriptions",
                options: filterSegmentOptions,
                duration: project.duration,
                initial: segmentFilter,
                onApply: { filter in
                    segmentFilter = filter
                    selectedSegmentIDs.formIntersection(Set(transcriptRows.map(\.id)))
                    refreshEditorShortcutActions()
                }
            )
            .id(segmentFilterKey)
            }
        }
        .alert("Generate narration for selected descriptions?", isPresented: $confirmBulkNarration) {
            Button("Generate", role: .destructive) { generateNarrationForSelectedDescriptions() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(bulkNarrationLabel)
        }
    }

    private func presentNewSegment(isDescription: Bool) {
        guard canCreateSegment else { return }
        playback.pauseAndCaptureTime { capturedTime in
            guard canCreateSegment else { return }
            let latestStart = max(0, project.duration - 0.1)
            let start = max(0, min(capturedTime, latestStart))
            segmentToEdit = TranscriptRow(
                segment: Segment(
                    id: UUID().uuidString,
                    start: start,
                    end: min(start + 3, project.duration),
                    text: "",
                    origin: "manual"
                ),
                isDescription: isDescription
            )
        }
    }

    private func safeFrameTimestamp(_ requestedTimestamp: Double) -> Double {
        guard project.duration > 0 else { return 0 }
        return min(max(0, requestedTimestamp), max(0, project.duration - 0.1))
    }

    private func chooseNarrationAudio(for cue: Segment) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["wav", "mp3", "m4a", "aac", "flac"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import Narration"
        panel.message = "Choose narration audio for AD segment at \(NarrationTimeFormat.spokenTime(cue.start)). It must fit inside the segment."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if cue.audio != nil {
            let alert = NSAlert()
            alert.messageText = "Replace this segment's narration audio?"
            alert.informativeText = "The imported audio will be saved as an alternative after validation. Review it afterward to keep both, replace the selected result, or discard the new result."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Replace")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        studio.importSegmentNarration(url, into: cue, project: project, replacingExisting: cue.audio != nil)
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
    let thumbnailImagesVisible: Bool

    private let trackLabelWidth: CGFloat = 132
    private let trackSpacing: CGFloat = 8
    private let rowSpacing: CGFloat = 4
    private let thumbnailHeight: CGFloat = 42
    private let transportHeight: CGFloat = 34
    private let segmentHeight: CGFloat = 26

    private var duration: Double { max(0, project.duration) }

    private var seekTrackHeight: CGFloat { thumbnailImagesVisible ? thumbnailHeight : 16 }

    private var tracksHeight: CGFloat {
        seekTrackHeight + rowSpacing + transportHeight + rowSpacing + segmentHeight + rowSpacing + segmentHeight
    }

    private var timelineValue: Binding<Double> {
        Binding {
            min(max(0, playback.time), duration)
        } set: { newValue in
            playback.seek(min(max(0, newValue), duration))
        }
    }

    private func preciseTimecode(_ seconds: Double) -> String {
        NarrationTimeFormat.timestamp(seconds)
    }

    private func seek(at x: CGFloat, in width: CGFloat) {
        guard width > 0, duration > 0 else { return }
        playback.seek(duration * min(max(0, x / width), 1))
    }

    private func trackLabel(_ title: String, systemImage: String, height: CGFloat) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2)
            .lineLimit(1)
            .frame(width: trackLabelWidth, height: height, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHeading(.h3)
    }

    private let playheadRed = Color(red: 229 / 255, green: 43 / 255, blue: 50 / 255)

    /// Spoken transcript bars follow the macOS system accent color, matching
    /// the Windows track's use of that platform's accent color.
    private let transcriptTrackColor = Color.accentColor

    /// DarkGoldenrod (#B8860B), the same description color used by Windows.
    private let descriptionTrackColor = Color(
        red: 184 / 255,
        green: 134 / 255,
        blue: 11 / 255
    )

    private func seekSurface(width: CGFloat, accessible: Bool = true) -> some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        playback.isScrubbing = true
                        seek(at: gesture.location.x, in: width)
                    }
                    .onEnded { gesture in
                        seek(at: gesture.location.x, in: width)
                        playback.isScrubbing = false
                    }
            )
            .accessibilityRepresentation {
                if accessible {
                    Slider(value: timelineValue, in: 0...max(0.001, duration)) {
                        Text("Video timeline")
                    }
                    .accessibilityValue("\(NarrationTimeFormat.spokenTime(playback.time)) of \(NarrationTimeFormat.spokenProjectDuration(duration))")
                    .accessibilityHint("Adjust to seek through the video")
                }
            }
    }

    private func thumbnailTrack(width: CGFloat) -> some View {
        let thumbnailCount = max(1, project.thumbnails.count)
        let thumbnailWidth = max(1, (width - CGFloat(thumbnailCount - 1) * 2) / CGFloat(thumbnailCount))

        return ZStack {
            RoundedRectangle(cornerRadius: 5).fill(.quaternary)
            if project.thumbnails.isEmpty {
                Text("No thumbnails")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 2) {
                ForEach(project.thumbnails, id: \.self) { path in
                    if let url = project.url(path), let image = NSImage(contentsOf: url) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: thumbnailWidth, height: thumbnailHeight)
                            .clipped()
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            seekSurface(width: width, accessible: true)
        }
        .frame(width: width, height: thumbnailHeight)
        .clipShape(.rect(cornerRadius: 5))
    }

    private var transportControls: some View {
        VideoPlaybackControls(playback: playback, duration: duration)
            .frame(height: transportHeight)
    }

    private func segmentTrack(
        _ segments: [Segment],
        title: String,
        color: Color,
        width: CGFloat
    ) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            if segments.isEmpty {
                Text("No \(title.lowercased()) segments")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            ForEach(segments) { segment in
                let start = min(max(0, segment.start), max(0, duration))
                let end = min(max(start, segment.end), max(0, duration))
                Button { playback.seek(start) } label: {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .overlay {
                            Text(segment.text)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                        }
                }
                .buttonStyle(.plain)
                .frame(width: max(4, width * (end - start) / max(1, duration)))
                .offset(x: width * start / max(1, duration))
                .accessibilityLabel("\(title) at \(NarrationTimeFormat.spokenTime(start)): \(segment.text)")
                .accessibilityHint("Activate to seek to this segment")
            }
            seekSurface(width: width, accessible: false)
        }
        .frame(width: width, height: segmentHeight)
        .clipShape(.rect(cornerRadius: 4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Timeline", systemImage: "film").font(.caption).accessibilityElement(children: .ignore).accessibilityLabel("Timeline").accessibilityAddTraits(.isHeader).accessibilityHeading(.h2)
                Spacer()
                Text("\(preciseTimecode(playback.time)) / \(preciseTimecode(duration))")
                    .font(.caption)
                    .monospacedDigit()
                    .accessibilityLabel("Current time \(NarrationTimeFormat.spokenTime(playback.time)), duration \(NarrationTimeFormat.spokenProjectDuration(duration))")
            }
            GeometryReader { geometry in
                let timelineWidth = max(1, geometry.size.width - trackLabelWidth - trackSpacing)
                let progress = duration > 0 ? min(max(0, playback.time / duration), 1) : 0

                ZStack(alignment: .topLeading) {
                    VStack(spacing: rowSpacing) {
                        HStack(spacing: trackSpacing) {
                            if thumbnailImagesVisible {
                                trackLabel("Thumbnails", systemImage: "photo.on.rectangle", height: thumbnailHeight)
                                thumbnailTrack(width: timelineWidth)
                            } else {
                                trackLabel("Video Position", systemImage: "slider.horizontal.3", height: seekTrackHeight)
                                seekSurface(width: timelineWidth)
                                    .frame(width: timelineWidth, height: seekTrackHeight)
                                    .background(.quaternary, in: .rect(cornerRadius: 4))
                            }
                        }
                        transportControls
                        HStack(spacing: trackSpacing) {
                            trackLabel("Transcript", systemImage: "text.bubble", height: segmentHeight)
                            segmentTrack(
                                project.transcript,
                                title: "Transcript",
                                color: transcriptTrackColor,
                                width: timelineWidth
                            )
                        }
                        HStack(spacing: trackSpacing) {
                            trackLabel("Audio Description", systemImage: "text.below.photo", height: segmentHeight)
                            segmentTrack(
                                project.cues,
                                title: "Audio description",
                                color: descriptionTrackColor,
                                width: timelineWidth
                            )
                        }
                    }

                    // Prominent red playhead synchronized across all tracks
                    VStack(spacing: 0) {
                        // Thumbnail track playhead handle and needle
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 12, height: 12)
                            Circle()
                                .strokeBorder(playheadRed, lineWidth: 2.5)
                                .frame(width: 12, height: 12)
                            Circle()
                                .fill(playheadRed)
                                .frame(width: 4, height: 4)
                        }
                        .shadow(color: .black.opacity(0.45), radius: 1, x: 0, y: 0.5)

                        RoundedRectangle(cornerRadius: 1)
                            .fill(playheadRed)
                            .frame(width: 3, height: seekTrackHeight - 12)
                            .overlay {
                                RoundedRectangle(cornerRadius: 1)
                                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                            }
                            .shadow(color: .black.opacity(0.65), radius: 1.5, x: 0, y: 1)

                        // Transport gap connecting guide
                        Rectangle()
                            .fill(playheadRed.opacity(0.45))
                            .frame(width: 1.5, height: rowSpacing + transportHeight + rowSpacing)

                        // Transcript & Audio Description downward pointer and needle
                        DownwardTriangle()
                            .fill(playheadRed)
                            .frame(width: 14, height: 8)
                            .overlay {
                                DownwardTriangle()
                                    .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                            }
                            .shadow(color: .black.opacity(0.65), radius: 1.5, x: 0, y: 1)

                        RoundedRectangle(cornerRadius: 1)
                            .fill(playheadRed)
                            .frame(width: 3, height: segmentHeight * 2 + rowSpacing - 8)
                            .overlay {
                                RoundedRectangle(cornerRadius: 1)
                                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                            }
                            .shadow(color: .black.opacity(0.65), radius: 1.5, x: 0, y: 1)
                    }
                    .frame(width: 14, height: tracksHeight)
                    .position(
                        x: trackLabelWidth + trackSpacing + min(max(7, timelineWidth * progress), max(7, timelineWidth - 7)),
                        y: tracksHeight / 2
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .frame(height: tracksHeight)
        }.padding(12)
        .accessibilityGroup("Timeline")
    }
}

private struct DownwardTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct TimecodeInput: View {
    let label: String
    @Binding var value: Double

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
            value = max(0, value + Double(clamped - oldComponent) * divisor)
        }
    }

    private var milliseconds: Binding<Int> {
        Binding {
            Int((max(0, value) * 1000).rounded()) % 1000
        } set: { newValue in
            let old = Int((max(0, value) * 1000).rounded()) % 1000
            let clamped = min(max(newValue, 0), 999)
            value = max(0, value + Double(clamped - old) / 1000)
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

private func preciseSegmentTimecode(_ seconds: Double) -> String {
    NarrationTimeFormat.timestamp(seconds)
}

private func segmentExcerpt(_ text: String) -> String {
    let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    guard collapsed.count > 80 else { return collapsed }
    return String(collapsed.prefix(77)) + "…"
}

private func segmentValidationTargets(for row: TranscriptRow, among rows: [TranscriptRow]) -> [TranscriptRow] {
    guard row.segment.start.isFinite, row.segment.end.isFinite else { return [] }
    return rows.filter { $0.id != row.id && row.segment.start < $0.segment.end && row.segment.end > $0.segment.start }
        .sorted { ($0.segment.start, $0.id) < ($1.segment.start, $1.id) }
}

private struct ShowValidationIssueButton: View {
    let targets: [TranscriptRow]
    let show: () -> Void
    private var title: String {
        if !targets.isEmpty && targets.allSatisfy(\.isDescription) { return "Show Description" }
        if !targets.isEmpty && targets.allSatisfy({ !$0.isDescription }) { return "Show Transcript" }
        return targets.count > 1 ? "Show Validation Issues" : "Show Validation Issue"
    }
    var body: some View {
        Button(title, systemImage: "scope", action: show)
            .accessibilityIdentifier("show-validation-issue")
            .keyboardShortcut("v", modifiers: [.command, .option])
            .help("Locate the affected timing or briefly highlight conflicting segments")
            .contextMenu {
                Button(title) { show() }
                    .accessibilityIdentifier("show-validation-issue-menu")
            }
    }
}

private func segmentValidationErrors(for row: TranscriptRow, among rows: [TranscriptRow], duration: Double, numberingRows: [TranscriptRow]? = nil) -> [String] {
    let segment = row.segment
    var errors: [String] = []
    if !segment.start.isFinite || !segment.end.isFinite {
        errors.append("Start and end times must be valid numbers.")
    } else if segment.start < 0 || segment.end < 0 || segment.start > duration || segment.end > duration {
        errors.append("Start and end times must be within \(preciseSegmentTimecode(duration)) (video duration).")
    } else if segment.end <= segment.start {
        errors.append("End time must be after start time.")
    }
    let overlaps = segmentValidationTargets(for: row, among: rows)
    errors += overlaps.map { other in
        let kind = other.isDescription ? "audio description" : "transcript"
        // Match the editor's per-kind numbering in the selected result, independent
        // of filters, display sorting, or reordered unsaved bulk drafts.
        let number = (numberingRows ?? rows).filter { $0.isDescription == other.isDescription }
            .firstIndex { $0.id == other.id }.map { $0 + 1 }
        let numberedKind = number.map { "\(kind) segment #\($0)" } ?? kind
        return "Overlaps \(numberedKind) \(preciseSegmentTimecode(other.segment.start)) to \(preciseSegmentTimecode(other.segment.end)): \(segmentExcerpt(other.segment.text))"
    }
    return errors
}

private struct SegmentTimingValidationView: View {
    let errors: [String]
    let isDescription: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                    .foregroundStyle(.red)
                Text(errors.count == 1 ? "Timing error" : "\(errors.count) timing errors")
                    .font(.headline)
                    .foregroundStyle(.red)
            }
            ForEach(Array(errors.enumerated()), id: \.offset) { _, error in
                Text(error)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(isDescription
                ? "Adjust the start or end time so the audio description plays only in a clear gap."
                : "Adjust the start or end time so transcript and Audio Description segments do not overlap.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.1), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Timing validation error. \(errors.joined(separator: " "))")
        .accessibilityHint("Adjust the start or end time before saving the segment.")
    }
}

private struct SegmentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var row: TranscriptRow
    @State private var frameTextStatus: String?
    @State private var reanalysisHint = ""
    @State private var validationFlash = false
    let showIssues: (TranscriptRow, String, [TranscriptRow]) -> Void
    let soundWhenTimingInvalid: Bool
    @State private var validationSound = TimingValidationSound()
    @State private var dialogSize = CGSize(width: 780, height: 580)
    let duration: Double
    let transcript: [Segment]
    let descriptions: [Segment]
    @Binding var capturedScreenText: String?
    let isReadingFrame: Bool
    let readFrame: ((Double) -> Void)?
    let canReanalyze: Bool
    let hasApiKey: Bool
    let apiKeyVerified: Bool?

    private var hasValidApiKey: Bool { hasApiKey && apiKeyVerified != false && ConnectivityService.shared.available(.gemini) }
    private var isApiKeyInvalid: Bool { hasApiKey && apiKeyVerified == false }
    let reanalyze: (Segment, String) -> Void
    let save: (TranscriptRow) -> Void

    init(row: TranscriptRow, soundWhenTimingInvalid: Bool, initialHint: String = "", showIssues: @escaping (TranscriptRow, String, [TranscriptRow]) -> Void, duration: Double, transcript: [Segment], descriptions: [Segment], capturedScreenText: Binding<String?>, isReadingFrame: Bool, readFrame: ((Double) -> Void)?, canReanalyze: Bool, hasApiKey: Bool, apiKeyVerified: Bool? = nil, reanalyze: @escaping (Segment, String) -> Void, save: @escaping (TranscriptRow) -> Void) {
        _row = State(initialValue: row)
        _reanalysisHint = State(initialValue: initialHint)
        self.showIssues = showIssues
        self.soundWhenTimingInvalid = soundWhenTimingInvalid
        self.duration = duration
        self.transcript = transcript
        self.descriptions = descriptions
        _capturedScreenText = capturedScreenText
        self.isReadingFrame = isReadingFrame
        self.readFrame = readFrame
        self.canReanalyze = canReanalyze
        self.hasApiKey = hasApiKey
        self.apiKeyVerified = apiKeyVerified
        self.reanalyze = reanalyze
        self.save = save
    }

    private var allRows: [TranscriptRow] {
        transcript.map { TranscriptRow(segment: $0, isDescription: false) }
            + descriptions.map { TranscriptRow(segment: $0, isDescription: true) }
    }
    private var segmentDuration: String {
        String(format: "%.3f seconds", max(0, row.segment.end - row.segment.start))
    }
    private var timingErrors: [String] {
        segmentValidationErrors(for: row, among: allRows, duration: duration)
    }
    private var saveDisabled: Bool {
        row.segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !timingErrors.isEmpty
    }

    private var editorTitle: String {
        row.segment.text.isEmpty
            ? (row.isDescription ? "Add Audio Description Segment" : "Add Transcript Segment")
            : "Edit \(row.kind) Segment"
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(editorTitle).font(.title2.bold()).accessibilityAddTraits(.isHeader).accessibilityHeading(.h1)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 16)
            Divider()
            ScrollViewReader { validationReader in
            Form {
            Section {
                VStack(alignment: .leading, spacing: 22) {
                    TimecodeInput(label: "Start time", value: $row.segment.start)
                    HStack {
                        Spacer()
                        Text("Duration \(segmentDuration)")
                            .font(.title3.bold())
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Segment duration: \(NarrationTimeFormat.spokenDuration(max(0, row.segment.end - row.segment.start)))")
                    }
                    TimecodeInput(label: "End time", value: $row.segment.end)
                    if !timingErrors.isEmpty {
                        SegmentTimingValidationView(errors: timingErrors, isDescription: row.isDescription)
                            .id("timing-validation")
                            .overlay { if validationFlash { RoundedRectangle(cornerRadius: 8).stroke(.orange, lineWidth: 3) } }
                    }
                }
            } header: {
                Text("Timing")
            }
            Section("Provenance") {
                Picker("Origin", selection: Binding(
                    get: { row.segment.provenance },
                    set: { value in
                        row.segment.origin = value.rawValue
                        row.segment.originOverride = true
                    }
                )) {
                    ForEach(DescriptionOrigin.editableCases, id: \.self) { origin in
                        Label(origin.title, systemImage: origin.iconName).tag(origin)
                    }
                }
                .pickerStyle(.menu)
                .help("Choose a provenance label. The manual choice persists and is never guessed from the text.")
            }
            Section {
                TextEditor(text: $row.segment.text)
                    .frame(minHeight: row.isDescription ? 190 : 140)
                    .accessibilityLabel(row.isDescription ? "Audio description text" : "Transcript text")
                if let readFrame {
                    HStack {
                        Spacer()
                        Button {
                            frameTextStatus = nil
                            readFrame(row.segment.start)
                        } label: {
                            if isReadingFrame {
                                Label("Reading Frame Text…", systemImage: "text.viewfinder")
                            } else {
                                Label("Read Frame Text", systemImage: "text.viewfinder")
                            }
                        }
                        .disabled(isReadingFrame || !hasValidApiKey)
                        .help(!hasApiKey ? "Enter your Gemini API key in Settings → Gemini API to read frame text" : isApiKeyInvalid ? "Gemini API key is invalid — enter a valid key in Settings → Gemini API to read frame text" : "Read text from the video frame at the segment start time and use it as the description")
                        .requiresInternet(.gemini)
                        .accessibilityHint("Replaces the description with text found at the segment start time.")
                    }
                }
                if let frameTextStatus {
                    Text(frameTextStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(frameTextStatus)
                }
            } header: {
                Text(row.isDescription ? "Description" : "Transcript")
            }
            Group {
                Section {
                    if !hasApiKey {
                        HStack(spacing: 6) {
                            Image(systemName: "key.slash.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("Gemini API key required to re-analyze segments.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if isApiKeyInvalid {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                            Text("Gemini API key is invalid — update in Settings → Gemini API to re-analyze segments.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextEditor(text: $reanalysisHint)
                        .frame(minHeight: 120)
                        .accessibilityLabel("Hint for Gemini")
                        .accessibilityHint(row.isDescription ? "Enter optional guidance about the visual detail Gemini should examine in the selected time range." : "Enter optional guidance about dialogue or languages in the selected range. The hint is not inserted as transcript text.")
                    HStack {
                        Spacer()
                        Button {
                            reanalyze(row.segment, reanalysisHint.trimmingCharacters(in: .whitespacesAndNewlines))
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "magnifyingglass").accessibilityHidden(true)
                                Text("Re-Analyze This Segment")
                            }
                        }
                        .disabled(!canReanalyze || !hasValidApiKey || isReadingFrame || !row.segment.start.isFinite || !row.segment.end.isFinite || row.segment.start < 0 || row.segment.end <= row.segment.start || row.segment.end > duration)
                        .keyboardShortcut("r", modifiers: [.command, .option])
                        .help(!hasApiKey ? "Enter your Gemini API key in Settings → Gemini API to re-analyze this segment" : isApiKeyInvalid ? "Gemini API key is invalid — enter a valid key in Settings → Gemini API to re-analyze this segment" : (row.isDescription ? "Look closely at this time range using the optional hint and adjust nearby descriptions to fit. Generate a transcript and summary first." : "Generate transcript segments using the selected range, multilingual settings and optional hint. No transcript or summary is required. Audio-only transcription models use the configured YouTube video transcription model for range analysis."))
                        .requiresInternet(.gemini)
                        .accessibilityHint("Uses the separate Gemini hint to update this range and nearby segments. Use Undo Segment Edit to restore them.")
                    }
                } header: {
                    Text("Hint for Gemini (Optional)")
                }
            }
            }
            .formStyle(.grouped)
            .defaultScrollAnchor(.top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                if !timingErrors.isEmpty {
                    ShowValidationIssueButton(targets: segmentValidationTargets(for: row, among: allRows)) {
                        let targets = segmentValidationTargets(for: row, among: allRows)
                        if targets.isEmpty {
                            validationReader.scrollTo("timing-validation", anchor: .center)
                            validationFlash = true
                        } else { showIssues(row, reanalysisHint, targets) }
                    }
                    .disabled(isReadingFrame)
                }
                Button("Save Segment", systemImage: "checkmark") { guard !saveDisabled else { return }; save(row); dismiss() }.keyboardShortcut(.defaultAction)
                    .disabled(saveDisabled)
                    .help(saveDisabled && !timingErrors.isEmpty ? "Resolve timing errors before saving this segment" : "Save this \(row.kind.lowercased()) segment")
            }.padding(.horizontal, 20).padding(.vertical, 14)
            }
        }
        .onChange(of: timingErrors, initial: true) { _, errors in
            validationSound.update(errors: errors, enabled: soundWhenTimingInvalid)
        }
        .onDisappear { validationSound.stop() }
        .task(id: validationFlash) {
            guard validationFlash else { return }
            try? await Task.sleep(for: .seconds(2))
            validationFlash = false
        }
        .onChange(of: capturedScreenText) { _, text in
            guard let text else { return }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                frameTextStatus = "No readable text was found at the segment start time."
            } else {
                row.segment.text = text
                row.segment.origin = "ai"
                row.segment.aiOriginalText = text
                frameTextStatus = "Screen text added to the description."
            }
            capturedScreenText = nil
        }
        .navigationTitle(editorTitle)
        .frame(width: dialogSize.width, height: dialogSize.height)
        .background(SegmentDialogViewport(size: $dialogSize).frame(width: 0, height: 0))
    }
}

private struct BulkSegmentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [TranscriptRow]
    @State private var selectedID: String?
    let showIssues: ([TranscriptRow], String?, [TranscriptRow]) -> Void
    let soundWhenTimingInvalid: Bool
    @State private var validationSound = TimingValidationSound()
    @State private var validationFlash = false
    let allRows: [TranscriptRow]
    let duration: Double
    let save: ([TranscriptRow]) -> Void

    init(rows: [TranscriptRow], soundWhenTimingInvalid: Bool, selectedID: String? = nil, showIssues: @escaping ([TranscriptRow], String?, [TranscriptRow]) -> Void, allRows: [TranscriptRow], duration: Double, save: @escaping ([TranscriptRow]) -> Void) {
        _rows = State(initialValue: rows)
        _selectedID = State(initialValue: selectedID ?? rows.first?.id)
        self.showIssues = showIssues
        self.soundWhenTimingInvalid = soundWhenTimingInvalid
        self.allRows = allRows
        self.duration = duration
        self.save = save
    }

    private var combinedRows: [TranscriptRow] {
        let editedIDs = Set(rows.map(\.id))
        return allRows.filter { !editedIDs.contains($0.id) } + rows
    }

    private func errors(for row: TranscriptRow) -> [String] {
        segmentValidationErrors(for: row, among: combinedRows, duration: duration, numberingRows: allRows)
    }

    private var saveDisabled: Bool {
        rows.contains {
            $0.segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !errors(for: $0).isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { validationReader in
            HSplitView {
                List(selection: $selectedID) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(row.kind) · \(timecode(row.segment.start))")
                                .font(.headline)
                            Text(segmentExcerpt(row.segment.text))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            if !errors(for: row).isEmpty {
                                Label("Needs correction", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(row.id)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(row.kind) segment at \(NarrationTimeFormat.spokenTime(row.segment.start)): \(row.segment.text)")
                    }
                }
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 300)

                if let selectedID, let index = rows.firstIndex(where: { $0.id == selectedID }) {
                    let timingErrors = errors(for: rows[index])
                    Form {
                        Section("Timing") {
                            VStack(alignment: .leading, spacing: 22) {
                                TimecodeInput(label: "Start time", value: $rows[index].segment.start)
                                HStack {
                                    Spacer()
                                    Text("Duration \(String(format: "%.3f seconds", max(0, rows[index].segment.end - rows[index].segment.start)))")
                                        .font(.title3.bold())
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                TimecodeInput(label: "End time", value: $rows[index].segment.end)
                                if !timingErrors.isEmpty {
                                    SegmentTimingValidationView(errors: timingErrors, isDescription: rows[index].isDescription)
                                        .id("timing-validation")
                                        .overlay { if validationFlash { RoundedRectangle(cornerRadius: 8).stroke(.orange, lineWidth: 3) } }
                                }
                            }
                        }
                        Section(rows[index].isDescription ? "Description" : "Transcript") {
                            TextEditor(text: $rows[index].segment.text)
                                .frame(minHeight: 170)
                                .accessibilityLabel(rows[index].isDescription ? "Audio description text" : "Transcript text")
                        }
                    }
                    .formStyle(.grouped)
                    .frame(minWidth: 520)
                } else {
                    ContentUnavailableView("Select a segment", systemImage: "text.cursor", description: Text("Choose one of the selected segments to edit its timing and text."))
                        .frame(minWidth: 520)
                }
            }
            Divider()
            HStack {
                Text("\(rows.count) selected")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(rows.count) segments selected for bulk editing")
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                if rows.contains(where: { !errors(for: $0).isEmpty }) {
                    let invalidRow = rows.first { $0.id == selectedID && !errors(for: $0).isEmpty }
                        ?? rows.first { !errors(for: $0).isEmpty }!
                    let targets = segmentValidationTargets(for: invalidRow, among: combinedRows)
                    ShowValidationIssueButton(targets: targets) {
                        if targets.isEmpty {
                            selectedID = invalidRow.id
                            validationReader.scrollTo("timing-validation", anchor: .center)
                            validationFlash = true
                        } else { showIssues(rows, selectedID, targets) }
                    }
                }
                Button("Save All", systemImage: "checkmark") {
                    guard !saveDisabled else { return }
                    save(rows)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(saveDisabled)
                .help(saveDisabled ? "Resolve every empty-text or timing error before saving" : "Save changes to all selected segments")
            }
            .padding(16)
            }
        }
        .onChange(of: rows.flatMap { errors(for: $0) }, initial: true) { _, errors in
            validationSound.update(errors: errors, enabled: soundWhenTimingInvalid)
        }
        .onDisappear { validationSound.stop() }
        .task(id: validationFlash) {
            guard validationFlash else { return }
            try? await Task.sleep(for: .seconds(2))
            validationFlash = false
        }
        .navigationTitle("Edit Selected Segments")
        .frame(width: 880, height: 620)
    }
}

// MARK: - Bulk timing shift

private struct BulkShiftTimingView: View {
    @Environment(\.dismiss) private var dismiss
    let count: Int
    let duration: Double
    let apply: (Double) -> String?

    @State private var offsetText = "1.0"
    @State private var error: String?

    private var offset: Double? {
        Double(offsetText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Shift Selected Timing")
                .font(.title2.bold()).accessibilityAddTraits(.isHeader).accessibilityHeading(.h1).padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 4)
            Text("Selected segments")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.bottom, 12)
            Form {
                TextField("Offset in seconds", text: $offsetText)
                    .help("Enter a positive or negative number of seconds")
                Text("The selection must stay inside the video (0–\(importClock(duration))).")
                    .font(.caption).foregroundStyle(.secondary)
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Shift Timing", systemImage: "clock.arrow.circlepath") {
                    guard let offset else {
                        error = "Enter a valid number of seconds."
                        return
                    }
                    if let message = apply(offset) { error = message }
                    else { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 440, height: 280)
    }
}

// MARK: - Segment filters

private struct SegmentFilterView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let origins: [DescriptionOrigin]
    let showsAudio: Bool
    let showsTranscript: Bool
    let options: [SegmentFilterOption]
    let duration: Double
    let onApply: (SegmentFilter) -> Void

    @State private var selectedOrigins: Set<DescriptionOrigin>
    @State private var audio: SegmentAudioFilter
    @State private var ranges: SegmentRangeFilter

    private var rangeError: String? {
        ranges.error(transcriptCount: options.filter { !$0.isDescription }.count,
            descriptionCount: options.filter(\.isDescription).count, duration: duration,
            availableIDs: Set(options.map(\.id)))
    }

    init(title: String, origins: [DescriptionOrigin], showsAudio: Bool, showsTranscript: Bool, options: [SegmentFilterOption], duration: Double, initial: SegmentFilter,
         onApply: @escaping (SegmentFilter) -> Void) {
        self.title = title
        self.origins = origins
        self.showsAudio = showsAudio
        self.showsTranscript = showsTranscript
        self.options = options
        self.duration = duration
        self.onApply = onApply
        _selectedOrigins = State(initialValue: initial.origins)
        _audio = State(initialValue: initial.audio)
        _ranges = State(initialValue: initial.ranges)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader).accessibilityHeading(.h1).padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 4)
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.bottom, 12)
            Form {
                SegmentRangeFilterControls(options: options, showsTranscript: showsTranscript, showsDescriptions: showsAudio,
                    duration: duration, ranges: $ranges)
                if let rangeError {
                    Text(rangeError).foregroundStyle(.red).accessibilityLabel("Filter error. \(rangeError)")
                }
                Section("Origin") {
                    if origins.isEmpty {
                        Text("No origin labels are present in this section.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(origins, id: \.self) { origin in
                            Toggle(origin.title, isOn: Binding(
                                get: { selectedOrigins.contains(origin) },
                                set: { selected in
                                    if selected { selectedOrigins.insert(origin) }
                                    else { selectedOrigins.remove(origin) }
                                }
                            ))
                        }
                    }
                }
                if showsAudio {
                    Section("Audio") {
                        Picker("Audio", selection: $audio) {
                            ForEach(SegmentAudioFilter.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.radioGroup)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Clear Filter") {
                    onApply(SegmentFilter())
                    dismiss()
                }
                .disabled(selectedOrigins.isEmpty && audio == .all && !ranges.isActive)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Apply Filter", systemImage: "line.3.horizontal.decrease.circle") {
                    guard rangeError == nil else { return }
                    onApply(SegmentFilter(origins: selectedOrigins, audio: audio, ranges: ranges))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rangeError != nil)
            }
            .padding(20)
        }
        .frame(width: 660, height: 640)
    }
}


private struct SegmentSortView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @State private var sort: SegmentSort
    let apply: (SegmentSort) -> Void
    init(title: String, initial: SegmentSort, apply: @escaping (SegmentSort) -> Void) {
        self.title = title; _sort = State(initialValue: initial); self.apply = apply
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader).accessibilityHeading(.h1)
            Picker("Sort by", selection: $sort) {
                ForEach(SegmentSort.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.radioGroup)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Apply Sort") { apply(sort); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}
