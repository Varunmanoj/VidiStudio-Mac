import SwiftUI

struct CreatedExportsView: View {
    @Bindable var studio: StudioModel
    let project: StudioProject
    @State private var selectedExport: ExportSelection?

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
        .confirmationDialog(
            "Export Information",
            isPresented: Binding(
                get: { selectedExport != nil },
                set: { if !$0 { selectedExport = nil } }
            ),
            titleVisibility: .visible,
            presenting: selectedExport
        ) { selection in
            Button {
                if let url = project.url(selection.path) {
                    NSWorkspace.shared.open(url)
                }
                selectedExport = nil
            } label: {
                Label("Open File", systemImage: "arrow.up.forward.app")
            }
            .disabled(studio.busy || project.url(selection.path) == nil)

            Button {
                if let url = project.url(selection.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                selectedExport = nil
            } label: {
                Label("Open Folder", systemImage: "folder")
            }
            .disabled(studio.busy || project.url(selection.path) == nil)

            Button(role: .destructive) {
                studio.deleteExport(project, path: selection.path)
                selectedExport = nil
            } label: {
                Label("Delete File", systemImage: "trash")
            }
            .disabled(studio.busy)

            Button("Cancel", role: .cancel) {
                selectedExport = nil
            }
        } message: { selection in
            Text(selection.filename)
        }
    }

    private func exportRow(path: String, kind: ExportCategory) -> some View {
        let filename = URL(fileURLWithPath: path).lastPathComponent
        return HStack(spacing: 8) {
            Label(filename, systemImage: kind.icon)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(filename)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                selectedExport = ExportSelection(path: path, filename: filename)
            } label: {
                Image(systemName: "eye.circle")
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .buttonStyle(.borderless)
            .help("Show information for \(filename)")
            .accessibilityLabel("Information for \(filename)")
            .disabled(studio.busy)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ExportSelection: Identifiable {
    let path: String
    let filename: String
    var id: String { path }
}
