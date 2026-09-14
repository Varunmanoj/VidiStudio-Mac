import SwiftUI
import AppKit

struct ProjectGridView: View {
    let projects: [StudioProject]
    @Binding var selection: String?
    let busy: Bool
    @Binding var itemSize: Double
    let open: (StudioProject) -> Void
    let rename: (StudioProject) -> Void
    let delete: (StudioProject) -> Void
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
                            ProjectArtifactStatusRow(project: project)
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(selection == project.id ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { open(project) })
                    .accessibilityLabel("\(project.name), \(project.sourceTitle), duration \(timecode(project.duration)), \(project.projectBrowserAccessibilityLabel)")
                    .accessibilityHint("Double-click to open this project in a new window")
                    .accessibilityAction(named: "Open Project") { open(project) }
                    .accessibilityAddTraits(selection == project.id ? [.isSelected] : [])
                    .contextMenu {
                        Button("Open Project", systemImage: "macwindow.badge.plus") { open(project) }
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
                        Button("Choose Content to Delete…", systemImage: "eraser", role: .destructive) { clear(project) }.disabled(busy || !project.hasGeneratedContent)
                        Button("Delete Project…", systemImage: "trash", role: .destructive) { delete(project) }.disabled(busy)
                    }
                }
            }.padding(12)
            if projects.isEmpty { Text("No projects to show").foregroundStyle(.secondary).padding() }
        }.accessibilityLabel("Project grid")
    }
}

private struct ProjectThumbnail: View {
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

struct ProjectBrowserActions {
    var showProjects: Binding<Bool>?
    var showInspector: Binding<Bool>?
    var grid: Binding<Bool>?
    var hasProject: Bool
}
private struct ProjectBrowserKey: FocusedValueKey { typealias Value = ProjectBrowserActions }
extension FocusedValues {
    var projectBrowser: ProjectBrowserActions? {
        get { self[ProjectBrowserKey.self] }
        set { self[ProjectBrowserKey.self] = newValue }
    }
}
