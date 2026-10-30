import SwiftUI
import AppKit

struct ProjectGridView: View {
    let projects: [StudioProject]
    @Binding var selection: String?
    let busy: Bool
    @Binding var itemSize: Double
    var integrity: [String: ProjectIntegrityReport] = [:]
    var hasApiKey: Bool = true
    var apiKeyVerified: Bool? = nil
    var aiProcessingBlocked: Bool = false
    let open: (StudioProject) -> Void
    let openNewWindow: (StudioProject) -> Void
    let rename: (StudioProject) -> Void
    let delete: (StudioProject) -> Void
    let removeFromList: (StudioProject) -> Void
    let process: (StudioProject, String) -> Void
    let export: (StudioProject) -> Void
    let clear: (StudioProject) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: itemSize), spacing: 12)], spacing: 12) {
                ForEach(projects) { project in
                    Button {
                        selection = project.id
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ProjectThumbnail(project: project)
                                .frame(height: max(78, itemSize * 0.56)).frame(maxWidth: .infinity)
                                .clipped().background(.quaternary)
                            Text(project.name).font(.headline)
                                .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 5) {
                                Image(systemName: project.sourceIconName)
                                    .foregroundStyle(project.isYouTubeURLProject ? .red : .secondary)
                                    .help(project.sourceTitle)
                                    .accessibilityLabel(project.sourceTitle)
                                Text("\(timecode(project.duration)) · \(project.cues.count) descriptions")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let report = integrity[project.id], !report.isHealthy {
                                ProjectIntegrityBadge(report: report)
                            }
                            ProjectArtifactStatusRow(project: project)
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(selection == project.id ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { open(project) })
                    .accessibilityLabel("\(project.name), \(project.sourceTitle), duration \(timecode(project.duration)), \(project.projectBrowserAccessibilityLabel)\(integrity[project.id].flatMap { $0.isHealthy ? nil : ", \($0.accessibilityLabel)" } ?? "")")
                    .accessibilityHint("Double-click to open this project in a new window")
                    .accessibilityAction(named: "Open Project") { open(project) }
                    .accessibilityAddTraits(selection == project.id ? [.isSelected] : [])
                    .contextMenu {
                        Button("Open in New Window", systemImage: "macwindow.badge.plus") { openNewWindow(project) }
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
                        Button("Remove from List", systemImage: "minus.circle") { removeFromList(project) }
                            .accessibilityIdentifier("remove-from-list")
                            .help("Remove this entry from the list. The project files stay in their folder. Use Open Project to add it again.")
                            .disabled(busy)
                        Divider()
                        Button("Choose Content to Delete…", systemImage: "eraser", role: .destructive) { clear(project) }.disabled(busy || project.integrityPlaceholder == true || !project.hasGeneratedContent)
                        Button("Delete Project…", systemImage: "trash", role: .destructive) { delete(project) }.disabled(busy)
                    }
                }
            }.padding(12)
            if projects.isEmpty { Text("No projects to show").foregroundStyle(.secondary).padding() }
        }.accessibilityLabel("Project grid")
    }
}

struct ProjectThumbnail: View {
    let project: StudioProject
    @State private var thumbnail: NSImage?
    private var youtubeThumbnail: URL? {
        guard let source = project.youtubeURL, let url = URLComponents(string: source) else { return nil }
        let videoID = url.host == "youtu.be"
            ? url.path.split(separator: "/").first.map(String.init)
            : url.queryItems?.first(where: { $0.name == "v" })?.value
                ?? url.path.split(separator: "/").last.map(String.init)
        guard let videoID, videoID.count == 11,
              videoID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }
    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit()
            } else if let youtubeThumbnail {
                AsyncImage(url: youtubeThumbnail) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary)
            }
        }.accessibilityHidden(true)
            .task(id: project.thumbnails) {
                thumbnail = nil
                for path in project.thumbnails {
                    if let url = project.url(path), let image = NSImage(contentsOf: url) {
                        thumbnail = image
                        break
                    }
                }
            }
    }
}

@MainActor
struct ProjectBrowserActions {
    var showProjects: Binding<Bool>?
    var showInspector: Binding<Bool>?
    var grid: Binding<Bool>?
    var hasProject: Bool
    var listModel: StudioModel? = nil
    var preserveOpenProject = false
    var editorModel: StudioModel? = nil

    func canRun(_ command: String) -> Bool {
        guard let model = editorModel ?? listModel, let project = model.selected else { return false }
        if editorModel == nil && !model.listedProjects.contains(where: { $0.id == project.id }) { return false }
        return model.canManageProject(command, project: project)
    }

    var canRemoveFromList: Bool {
        guard let model = listModel, !model.busy, let project = model.selected, project.folder != nil else { return false }
        return model.listedProjects.contains { $0.id == project.id }
    }
    func run(_ command: String) {
        if command != "remove-from-list" {
            guard canRun(command), let model = editorModel ?? listModel, let project = model.selected else { return }
            model.requestProjectManagement(command, project: project)
            return
        }
        guard command == "remove-from-list", canRemoveFromList,
              let model = listModel, let project = model.selected else { return }
        let currentID = model.selectedID
        model.removeProjectFromList(project)
        if preserveOpenProject { model.selectedID = currentID }
    }
}
private struct ProjectBrowserKey: FocusedValueKey { typealias Value = ProjectBrowserActions }
extension FocusedValues {
    var projectBrowser: ProjectBrowserActions? {
        get { self[ProjectBrowserKey.self] }
        set { self[ProjectBrowserKey.self] = newValue }
    }
}
