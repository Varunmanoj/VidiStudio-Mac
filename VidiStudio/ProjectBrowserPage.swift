import SwiftUI
import AppKit

struct ProjectBrowserPage: View {
    let projects: [StudioProject]
    @Binding var search: String
    @Binding var grid: Bool
    @Binding var gridItemSize: Double
    @Binding var selection: String?
    let busy: Bool
    let newProject: () -> Void
    let openProjectFolder: () -> Void
    let openEditor: (StudioProject) -> Void
    let rename: (StudioProject) -> Void
    let delete: (StudioProject) -> Void
    let process: (StudioProject) -> Void
    let clear: (StudioProject) -> Void

    private var filteredProjects: [StudioProject] {
        projects.filter { search.isEmpty || $0.name.localizedStandardContains(search) }
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
                    Label(search.isEmpty ? "No Projects" : "No Matching Projects", systemImage: "film.stack")
                } description: {
                    Text(search.isEmpty
                         ? "Create a project from a video file on this Mac or a YouTube video."
                         : "Try a different project name or clear the search field.")
                } actions: {
                    if search.isEmpty {
                        Button("New Project…", systemImage: "plus", action: newProject)
                    } else {
                        Button("Clear Search") { search = "" }
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
                    clear: clear
                )
            } else {
                List(filteredProjects, selection: $selection) { project in
                    HStack(spacing: 12) {
                        MaterialIcon(glyph: "\u{e02c}")
                            .font(.title2)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(project.name).font(.headline)
                            Text("\(timecode(project.duration)) · \(project.cues.count) descriptions · \(project.status)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .tag(project.id)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(project.name), \(timecode(project.duration)), \(project.cues.count) descriptions, \(project.status)")
                    .accessibilityHint("Double-click to open this project in a new window")
                    .accessibilityAction(named: "Open Project") { openEditor(project) }
                    .onTapGesture(count: 2) { openEditor(project) }
                    .contextMenu { projectMenu(project) }
                }
                .listStyle(.inset)
                .accessibilityLabel("All projects list")
            }
        }
        .navigationTitle("All Projects")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                .help("Open VidiStudio Settings")
                .accessibilityLabel("Settings")
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
        Button(project.canReprocess ? "Reprocess Video" : "Process Video", systemImage: "sparkles") {
            process(project)
        }
        .disabled(busy)
        Divider()
        Button("Choose Content to Delete…", systemImage: "eraser", role: .destructive) {
            clear(project)
        }
        .disabled(busy || !project.hasGeneratedContent)
        Button("Delete Project", systemImage: "trash", role: .destructive) {
            delete(project)
        }
        .disabled(busy)
    }
}
