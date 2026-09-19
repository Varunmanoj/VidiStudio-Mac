import SwiftUI

struct CreatedExportsView: View {
    @Bindable var studio: StudioModel
    let project: StudioProject

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Created Exports")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(ExportCategory.allCases) { kind in
                let paths = project.exports.filter { ExportCategory.resolve(path: $0) == kind }
                if !paths.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(kind == .text ? "Text and Subtitles" : kind.title, systemImage: kind.icon)
                            .font(.subheadline.bold())
                            .accessibilityAddTraits(.isHeader)

                        ForEach(paths, id: \.self) { path in
                            exportRow(path: path, kind: kind)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(kind == .text ? "Text and subtitle" : kind.title) exports")
                }
            }
        }
    }

    private func exportRow(path: String, kind: ExportCategory) -> some View {
        let filename = URL(fileURLWithPath: path).lastPathComponent
        return HStack(spacing: 6) {
            Button(filename, systemImage: kind.icon) {
                if let url = project.url(path) { NSWorkspace.shared.open(url) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("Open \(filename)")
            .disabled(studio.busy || project.url(path) == nil)

            Button("Show Export in Finder", systemImage: "folder") {
                if let url = project.url(path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .labelStyle(.iconOnly)
            .help("Show \(filename) in Finder")
            .disabled(studio.busy || project.url(path) == nil)

            Button("Delete Export…", systemImage: "trash", role: .destructive) {
                studio.confirmDeleteExport(project, path: path)
            }
            .labelStyle(.iconOnly)
            .help("Delete \(filename)")
            .disabled(studio.busy)
        }
    }
}
