import SwiftUI
import AppKit

struct ProjectAnalysisMenu: View {
    let project: StudioProject
    let busy: Bool
    let perform: (String) -> Void

    var body: some View {
        Menu("Analysis", systemImage: "sparkles") {
            Button(project.thumbnails.isEmpty ? "Generate Video Details & Timeline Pictures" : "Regenerate Video Details & Timeline Pictures…", systemImage: "photo.on.rectangle.angled") {
                perform("prepare-video")
            }
            .help("Refresh video details and timeline pictures without using AI")
            Divider()
            Button("Analyze Video…", systemImage: "sparkles") { perform("analyze") }
                .help("Generate the transcript, summary, and Audio Descriptions in sequence")
            Divider()
            Button(project.hasGeneratedTranscript ? "Regenerate Transcript…" : "Generate Transcript", systemImage: "text.bubble") {
                perform("transcribe")
            }
            Button(project.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Generate Summary" : "Regenerate Summary…", systemImage: "text.alignleft") {
                perform("generate-summary")
            }
            Button(project.cues.isEmpty ? "Generate Audio Descriptions" : "Regenerate Audio Descriptions…", systemImage: "sparkles") {
                perform("generate-ad-cues")
            }
            .disabled(!project.canGenerateDescriptions)
            .help(project.canGenerateDescriptions ? "Generate timed Audio Description text" : "Generate the transcript and summary first")
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

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("All Projects").font(.largeTitle.bold())
                    Text("\(filteredProjects.count) of \(projects.count) projects")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("New Project", systemImage: "plus", action: newProject)
                    .buttonStyle(.glassProminent)
                    .disabled(busy)
                Button("Open Project Folder", systemImage: "folder", action: openProjectFolder)
                    .disabled(busy)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            HStack(spacing: 12) {
                TextField("Search all projects", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)
                Spacer()
                Picker("Project source", selection: $sourceFilter) {
                    ForEach(ProjectSourceFilter.allCases) { filter in
                        Label(filter.title, systemImage: filter.iconName).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityLabel("Filter projects by source")
                .accessibilityHint("Show all projects, only local video file projects, or only YouTube video projects")
                .help("Filter projects by source")
                Picker("Project layout", selection: $grid) {
                    Label("List View", systemImage: "list.bullet").tag(false)
                    Label("Grid View", systemImage: "square.grid.2x2").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

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
                    }
                }
            } else if grid {
                ProjectGridView(
                    projects: filteredProjects,
                    selection: $selection,
                    busy: busy,
                    itemSize: $gridItemSize,
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
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Button("Show Selected Project in Finder", systemImage: "folder") {
                    guard let selection,
                          let folder = projects.first(where: { $0.id == selection })?.folder else { return }
                    NSWorkspace.shared.open(folder)
                }
                .labelStyle(.iconOnly)
                .help("Open the selected project’s folder in Finder")
                .accessibilityLabel("Show Selected Project in Finder")
                .disabled(busy || projects.first(where: { $0.id == selection })?.folder == nil)
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
        Button("Open in Project Folder", systemImage: "folder") {
            if let folder = project.folder { NSWorkspace.shared.open(folder) }
        }
        ProjectAnalysisMenu(project: project, busy: busy) { command in
            process(project, command)
        }
        ProjectExportButton(project: project, busy: busy) {
            export(project)
        }
        Divider()
        Button("Choose Content to Delete…", systemImage: "eraser", role: .destructive) {
            clear(project)
        }
        .disabled(busy || !project.hasGeneratedContent)
        Button("Delete Project…", systemImage: "trash", role: .destructive) {
            delete(project)
        }
        .disabled(busy)
    }
}
