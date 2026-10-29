import SwiftUI
import AppKit

struct ProjectAnalysisMenu: View {
    let project: StudioProject
    let busy: Bool
    var hasApiKey: Bool = true
    var apiKeyVerified: Bool? = nil
    var aiProcessingBlocked: Bool = false
    let perform: (String) -> Void

    private var hasValidApiKey: Bool { hasApiKey && apiKeyVerified != false && !aiProcessingBlocked }
    private var isApiKeyInvalid: Bool { hasApiKey && apiKeyVerified == false }
    private var aiBlockedHelp: String? { aiProcessingBlocked ? "Gemini AI processing is paused after a quota or service error. Retry AI from the warning banner or open Gemini settings." : nil }

    var body: some View {
        Menu("Analysis", systemImage: "sparkles") {
            Button(project.thumbnails.isEmpty ? "Generate Video Details & Timeline Pictures" : "Regenerate Video Details & Timeline Pictures…", systemImage: "photo.on.rectangle.angled") {
                perform("prepare-video")
            }
            .help("Refresh video details and timeline pictures without using AI")
            Divider()
            Button("Analyze Video…", systemImage: "sparkles") { perform("analyze") }
                .disabled(!hasValidApiKey)
                .help(aiBlockedHelp ?? (!hasApiKey ? "Enter your Gemini API key in Settings → Gemini API to analyze this video" : isApiKeyInvalid ? "Gemini API key is invalid — enter a valid key in Settings → Gemini API to analyze this video" : "Generate the transcript, summary, and Audio Descriptions in sequence"))
            Divider()
            Button(project.hasGeneratedTranscript ? "Regenerate Transcript…" : "Generate Transcript", systemImage: "text.bubble") {
                perform("transcribe")
            }
            .disabled(!hasValidApiKey)
            .help(aiBlockedHelp ?? (!hasApiKey ? "Enter your Gemini API key in Settings → Gemini API to transcribe speech" : isApiKeyInvalid ? "Gemini API key is invalid — enter a valid key in Settings → Gemini API to transcribe speech" : "Generate dialogue transcript using Gemini"))
            Button(project.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Generate Summary" : "Regenerate Summary…", systemImage: "text.alignleft") {
                perform("generate-summary")
            }
            .disabled(!hasValidApiKey)
            .help(aiBlockedHelp ?? (!hasApiKey ? "Enter your Gemini API key in Settings → Gemini API to generate summaries" : isApiKeyInvalid ? "Gemini API key is invalid — enter a valid key in Settings → Gemini API to generate summaries" : "Generate video summary using Gemini"))
            Button(project.cues.isEmpty ? "Generate Audio Descriptions" : "Regenerate Audio Descriptions…", systemImage: "sparkles") {
                perform("generate-ad-cues")
            }
            .disabled(!hasValidApiKey || !project.canGenerateDescriptions)
            .help(aiBlockedHelp ?? (!hasApiKey ? "Enter your Gemini API key in Settings → Gemini API to generate Audio Descriptions" : isApiKeyInvalid ? "Gemini API key is invalid — enter a valid key in Settings → Gemini API to generate Audio Descriptions" : project.canGenerateDescriptions ? "Generate timed Audio Description text" : "Generate the transcript and summary first"))
        }
        .disabled(busy)
    }
}

struct ProjectBrowserPage: View {
    let projects: [StudioProject]
    @Binding var search: String
    @Binding var sourceFilter: ProjectSourceFilter
    @Binding var grid: Bool
    @Binding var gridItemSize: Double
    @Binding var selection: String?
    let busy: Bool
    var integrity: [String: ProjectIntegrityReport] = [:]
    var hasApiKey: Bool = true
    var apiKeyVerified: Bool? = nil
    var aiProcessingBlocked: Bool = false
    var apiKeyVerificationMessage: String? = nil
    var openGeminiSettings: () -> Void = {}
    let newProject: () -> Void
    let openProjectFolder: () -> Void
    let openEditor: (StudioProject) -> Void
    let rename: (StudioProject) -> Void
    let delete: (StudioProject) -> Void
    let process: (StudioProject, String) -> Void
    let export: (StudioProject) -> Void
    let clear: (StudioProject) -> Void

    private var filteredProjects: [StudioProject] {
        projects.filter {
            (search.isEmpty || $0.name.localizedStandardContains(search)) && sourceFilter.matches($0)
        }
    }

    private var isFiltering: Bool {
        !search.isEmpty || sourceFilter != .all
    }

    private var selectedProjectFolder: URL? {
        guard let selection else { return nil }
        return projects.first(where: { $0.id == selection })?.folder
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("All Projects").font(.largeTitle.bold())
                Text("\(filteredProjects.count) of \(projects.count) projects")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            if !hasApiKey {
                HStack(spacing: 12) {
                    Image(systemName: "key.slash.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Gemini API Key Required")
                            .font(.headline)
                        Text("Enter your Gemini API key in Settings → Gemini API to enable video transcription, summaries, audio descriptions, and narration across VidiStudio.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Gemini API Settings…") {
                        openGeminiSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(12)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.orange.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            } else if apiKeyVerified == false {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Invalid Gemini API Key")
                            .font(.headline)
                        Text(apiKeyVerificationMessage ?? "The entered Gemini API key could not be verified. AI features are disabled across VidiStudio until a valid key is entered.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Gemini API Settings…") {
                        openGeminiSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(12)
                .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.red.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            Divider()

            if filteredProjects.isEmpty {
                ContentUnavailableView {
                    Label(isFiltering ? "No Matching Projects" : "No Projects", systemImage: "film.stack")
                } description: {
                    Text(isFiltering
                          ? "Try a different project name or source filter."
                          : "Create a project from a video file on this Mac or a YouTube video.")
                } actions: {
                    if isFiltering {
                        Button(sourceFilter == .all ? "Clear Search" : "Clear Search & Filters") {
                            search = ""
                            sourceFilter = .all
                        }
                    } else {
                        Button("New Project…", systemImage: "plus", action: newProject)
                            .disabled(busy)
                            .help("Create a new project")
                    }
                }
            } else if grid {
                ProjectGridView(
                    projects: filteredProjects,
                    selection: $selection,
                    busy: busy,
                    itemSize: $gridItemSize,
                    integrity: integrity,
                    hasApiKey: hasApiKey,
                    apiKeyVerified: apiKeyVerified,
                    aiProcessingBlocked: aiProcessingBlocked,
                    open: openEditor,
                    rename: rename,
                    delete: delete,
                    process: process,
                    export: export,
                    clear: clear
                )
            } else {
                Table(filteredProjects, selection: $selection) {
                    TableColumn("Name") { project in
                        HStack(spacing: 8) {
                            Image(systemName: project.sourceIconName)
                                .foregroundStyle(project.isYouTubeURLProject ? .red : .secondary)
                                .help(project.sourceTitle)
                                .accessibilityHidden(true)
                            Text(project.name)
                                .fontWeight(.medium)
                                .lineLimit(2)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Project name: \(project.name), source: \(project.sourceTitle)")
                    }
                    .width(min: 190, ideal: 280)
                    TableColumn("Status") { project in
                        if let report = integrity[project.id], !report.isHealthy {
                            ProjectIntegrityBadge(report: report)
                        } else {
                            Text("Healthy")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 92, ideal: 108, max: 140)
                    TableColumn("Duration") { project in
                        Text(timecode(project.duration))
                            .monospacedDigit()
                            .accessibilityLabel("Duration: \(timecode(project.duration))")
                    }
                    .width(min: 75, ideal: 90, max: 110)
                    TableColumn("AD Segments") { project in
                        Text(project.cues.count, format: .number)
                            .monospacedDigit()
                            .accessibilityLabel("\(project.cues.count) audio description \(project.cues.count == 1 ? "segment" : "segments")")
                    }
                    .width(min: 82, ideal: 95, max: 110)
                    TableColumn("Transcript") { project in
                        ProjectArtifactStatusIcon(project: project, kind: .transcript)
                    }
                    .width(min: 72, ideal: 82, max: 100)
                    TableColumn("Summary") { project in
                        ProjectArtifactStatusIcon(project: project, kind: .summary)
                    }
                    .width(min: 65, ideal: 78, max: 95)
                    TableColumn("AD") { project in
                        ProjectArtifactStatusIcon(project: project, kind: .descriptions)
                    }
                    .width(min: 44, ideal: 52, max: 65)
                    TableColumn("Video Export") { project in
                        ProjectArtifactStatusIcon(project: project, kind: .finalVideo, showsCount: true)
                    }
                    .width(min: 80, ideal: 92, max: 110)
                    TableColumn("Audio Export") { project in
                        ProjectArtifactStatusIcon(project: project, kind: .narrationAudio, showsCount: true)
                    }
                    .width(min: 80, ideal: 92, max: 110)
                }
                .contextMenu(forSelectionType: String.self) { identifiers in
                    if let identifier = identifiers.first,
                       let project = filteredProjects.first(where: { $0.id == identifier }) {
                        projectMenu(project)
                    }
                } primaryAction: { identifiers in
                    if let identifier = identifiers.first,
                       let project = filteredProjects.first(where: { $0.id == identifier }) {
                        openEditor(project)
                    }
                }
                .accessibilityLabel("All projects table")
            }
        }
        .navigationTitle("All Projects")
        .searchable(text: $search, placement: .toolbar, prompt: "Search projects")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Project source", selection: $sourceFilter) {
                    ForEach(ProjectSourceFilter.allCases) { filter in
                        Label(filter.title, systemImage: filter.iconName)
                            .accessibilityLabel(filter.accessibilityLabel)
                            .tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Filter projects by source")
                .accessibilityHint("Show all projects, only local video file projects, or only YouTube video projects")
                .help("Filter projects by source")

                Picker("Project layout", selection: $grid) {
                    Label("List View", systemImage: "list.bullet").tag(false)
                    Label("Grid View", systemImage: "square.grid.2x2").tag(true)
                }
                .pickerStyle(.segmented)

                Button("Open Project Folder", systemImage: "folder", action: openProjectFolder)
                    .disabled(busy)
                Button("New Project", systemImage: "plus", action: newProject)
                    .buttonStyle(.glassProminent)
                    .disabled(busy)
                    .help("Create a new project")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Button("Show Selected Project in Finder", systemImage: "folder") {
                    guard let folder = selectedProjectFolder else { return }
                    NSWorkspace.shared.open(folder)
                }
                .labelStyle(.iconOnly)
                .help("Open the selected project’s folder in Finder")
                .accessibilityLabel("Show Selected Project in Finder")
                .disabled(selectedProjectFolder == nil)
                Spacer()
                if grid {
                    Image(systemName: "square.grid.3x3")
                        .accessibilityHidden(true)
                    Slider(value: $gridItemSize, in: 140...300, step: 10)
                        .frame(width: 140)
                        .accessibilityLabel("Project icon size")
                        .accessibilityValue("\(Int(gridItemSize)) points")
                        .help("Resize project icons")
                    Image(systemName: "square.grid.2x2")
                        .font(.title3)
                        .accessibilityHidden(true)
                }
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                .help("Open VidiStudio Settings")
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
        .onKeyPress(.return) {
            guard let selection, let project = projects.first(where: { $0.id == selection }) else { return .ignored }
            rename(project)
            return .handled
        }
    }

    @ViewBuilder
    private func projectMenu(_ project: StudioProject) -> some View {
        Button("Open Project", systemImage: "macwindow.badge.plus") { openEditor(project) }
        Divider()
        Button("Rename", systemImage: "pencil") { rename(project) }
            .disabled(project.integrityPlaceholder == true)
        Button("Open in Project Folder", systemImage: "folder") {
            if let folder = project.folder { NSWorkspace.shared.open(folder) }
        }
        Button("Open Project Configuration", systemImage: "doc.text") {
            guard let url = project.folder?.appendingPathComponent("project.json"),
                  FileManager.default.fileExists(atPath: url.path) else { return }
            NSWorkspace.shared.open(url)
        }
        ProjectAnalysisMenu(project: project, busy: busy, hasApiKey: hasApiKey, apiKeyVerified: apiKeyVerified, aiProcessingBlocked: aiProcessingBlocked) { command in
            process(project, command)
        }
        .disabled(project.integrityPlaceholder == true)
        ProjectExportButton(project: project, busy: busy) {
            export(project)
        }
        .disabled(project.integrityPlaceholder == true)
        Divider()
        Button("Choose Content to Delete…", systemImage: "eraser", role: .destructive) {
            clear(project)
        }
        .disabled(busy || project.integrityPlaceholder == true || !project.hasGeneratedContent)
        Button("Delete Project…", systemImage: "trash", role: .destructive) {
            delete(project)
        }
        .disabled(busy)
    }
}
