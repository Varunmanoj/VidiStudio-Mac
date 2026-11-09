import SwiftUI

struct CreatedExportsView: View {
    @Bindable var studio: StudioModel
    let project: StudioProject
    @State private var languageFilter = "all"
    @State private var resultFilter = "all"
    @State private var selectedExport: ExportSelection?

    private var filteredPaths: [String] {
        project.exports.filter { path in
            (languageFilter == "all" || project.languagesForExport(path).contains(languageFilter))
            && (resultFilter == "all" || project.exportResults?[path]?.resultIDs.values.contains(resultFilter) == true)
        }
    }
    private var languageGroups: [String] {
        Array(Set(filteredPaths.map(project.languageGroupForExport))).sorted {
            $0 == "multilingual" ? $1 != "multilingual" : $1 == "multilingual" ? false : OutputLanguage.title($0) < OutputLanguage.title($1)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Created Exports")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ExportOptionPicker("Export language filter", selection: $languageFilter) {
                Text("All Languages").tag("all")
                ForEach(project.exportLanguageCodes, id: \.self) { code in Text(OutputLanguage.title(code)).tag(code) }
            }.pickerStyle(.menu)
            Picker("Saved result filter", selection: $resultFilter) {
                Text("All Saved Results").tag("all")
                ForEach(project.savedLanguageResults.filter { languageFilter == "all" || $0.language == languageFilter }) { result in
                    Text("\(OutputLanguage.title(result.language)) · \(result.kindTitle) · \(result.title)").tag(result.id)
                }
            }.pickerStyle(.menu)
            ForEach(languageGroups, id: \.self) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group == "multilingual" ? "Multilingual" : OutputLanguage.title(group))
                        .font(.subheadline.bold())
                        .accessibilityAddTraits(.isHeader)
                    ForEach(ExportCategory.allCases) { kind in
                        let paths = filteredPaths.filter { project.languageGroupForExport($0) == group && ExportCategory.resolve(path: $0) == kind }
                        if !paths.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(kind == .text ? "Text and Subtitles" : kind.title, systemImage: kind.icon)
                                    .font(.caption.bold())
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(paths, id: \.self) { path in
                                    VStack(alignment: .leading, spacing: 3) {
                                        exportRow(path: path, kind: kind)
                                        if group == "multilingual" {
                                            Text(project.languagesForExport(path).map(OutputLanguage.title).joined(separator: ", "))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(group == "multilingual" ? "Multilingual exports" : "\(OutputLanguage.title(group)) exports")
            }
        }
        .onChange(of: project.exportLanguageCodes) {
            if languageFilter != "all" && !project.exportLanguageCodes.contains(languageFilter) { languageFilter = "all" }
        }
        .onChange(of: languageFilter) { resultFilter = "all" }
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
                    let target = selection.isDirectory ? url.appendingPathComponent("index.html") : url
                    NSWorkspace.shared.open(target)
                }
                selectedExport = nil
            } label: {
                Label(selection.isDirectory ? "Open Web Player" : "Open File", systemImage: "arrow.up.forward.app")
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
                Label("Delete Export", systemImage: "trash")
            }
            .disabled(studio.busy)

            Button("Cancel", systemImage: "xmark", role: .cancel) {
                selectedExport = nil
            }
        } message: { selection in
            Text(selection.filename)
        }
    }

    private func exportRow(path: String, kind: ExportCategory) -> some View {
        let filename = URL(fileURLWithPath: path).lastPathComponent
        var isDirectory: ObjCBool = false
        if let url = project.url(path) {
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        }
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
            Label(filename, systemImage: kind.icon)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(filename)
                .frame(maxWidth: .infinity, alignment: .leading)
                if let source = project.exportAudioSources?[path] {
                    Text(source.label).font(.caption).foregroundStyle(.secondary)
                    if let name = source.adSourceName { Text("AD audio: \(name)").font(.caption).foregroundStyle(.secondary) }
                }
            }

            Button {
                selectedExport = ExportSelection(
                    path: path,
                    filename: filename,
                    isDirectory: isDirectory.boolValue
                )
            } label: {
                Image(systemName: "info.circle")
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
    let isDirectory: Bool
    var id: String { path }
}
