import SwiftUI

struct EditorProjectBrowser: View {
    let projects: [StudioProject]
    let selectedID: String?
    @Binding var grid: Bool
    let busy: Bool
    let summaryEditing: Bool
    let openHere: (StudioProject) -> Void
    let openNewWindow: (StudioProject) -> Void
    let removeFromList: (StudioProject) -> Void
    let delete: (StudioProject) -> Void
    @State private var search = ""
    @State private var source = "all"

    private var filtered: [StudioProject] {
        projects.filter { (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) &&
            (source == "all" || $0.isYouTubeURLProject == (source == "youtube")) }
    }
    private var selected: StudioProject? { projects.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 10) {
            TextField("Search projects", text: $search)
                .accessibilityLabel("Search projects in this editor")
            Picker("Project source", selection: $source) {
                Text("All projects").tag("all")
                Text("Local videos").tag("local")
                Text("YouTube videos").tag("youtube")
            }.labelsHidden()
            if summaryEditing {
                Text("Finish editing the summary to switch projects.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if grid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 10) {
                        ForEach(filtered) { project in projectButton(project, thumbnail: true) }
                    }
                }
            } else {
                List(selection: Binding<String?>(get: { selectedID }, set: { id in
                    if let project = filtered.first(where: { $0.id == id }) { openHere(project) }
                })) {
                    ForEach(filtered) { project in
                        projectButton(project, thumbnail: false).tag(project.id)
                    }
                }
                .listStyle(.sidebar)
                .disabled(busy || summaryEditing)
            }
            if filtered.isEmpty { Text("No projects to show").foregroundStyle(.secondary) }
            HStack {
                Picker("Project layout", selection: $grid) {
                    Label("List", systemImage: "list.bullet").tag(false)
                    Label("Grid", systemImage: "square.grid.2x2").tag(true)
                }.pickerStyle(.segmented).labelsHidden()
                Button("Remove from List", systemImage: "minus.circle") { if let selected { removeFromList(selected) } }
                    .labelStyle(.iconOnly)
                    .help("Remove the selected project from the list and keep its files")
                    .accessibilityLabel("Remove selected project from list")
                    .disabled(selected == nil || busy || summaryEditing)
                Button("Delete Project…", systemImage: "trash", role: .destructive) { if let selected { delete(selected) } }
                    .labelStyle(.iconOnly)
                    .help("Move the selected project and its files to the Bin after confirmation")
                    .accessibilityLabel("Delete selected project")
                    .disabled(selected == nil || busy || summaryEditing)
            }.controlSize(.small)
        }
        .padding(12)
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 340, maxHeight: .infinity)
        .accessibilityLabel("Projects in this editor")
    }

    private func projectButton(_ project: StudioProject, thumbnail: Bool) -> some View {
        Button { openHere(project) } label: {
            VStack(alignment: .leading, spacing: 6) {
                if thumbnail {
                    ProjectThumbnail(project: project)
                        .frame(height: 76).frame(maxWidth: .infinity).clipped()
                }
                Text(project.name).lineLimit(2)
                if thumbnail { Text(timecode(project.duration)).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(thumbnail && project.id == selectedID ? Color.accentColor.opacity(0.18) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(busy || summaryEditing)
        .accessibilityLabel(project.name)
        .accessibilityHint("Open this project in the current editor window")
        .accessibilityAddTraits(project.id == selectedID ? [.isSelected] : [])
        .contextMenu {
            Button("Open in This Window", systemImage: "arrow.forward.square") { openHere(project) }
                .accessibilityIdentifier("open-project-here")
            Button("Open in New Window", systemImage: "macwindow.badge.plus") { openNewWindow(project) }
                .accessibilityIdentifier("open-editor-window")
            Divider()
            Button("Remove from List", systemImage: "minus.circle") { removeFromList(project) }
                .accessibilityIdentifier("remove-from-list")
                .help("Remove this entry from the list and keep its files")
            Button("Delete Project…", systemImage: "trash", role: .destructive) { delete(project) }
                .accessibilityIdentifier("trash-project")
        }
        .disabled(busy || summaryEditing)
    }
}
