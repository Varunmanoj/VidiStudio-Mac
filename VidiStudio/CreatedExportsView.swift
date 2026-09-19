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
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
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

            if kind == .video {
                if let information = project.exportMediaInfo?[path] {
                    DisclosureGroup("Exported Video Information") {
                        VStack(alignment: .leading, spacing: 5) {
                            informationRow("File", filename)
                            informationRow("Video Processing", information.videoProcessingDescription)
                            informationRow("Duration", information.durationDescription)
                            informationRow("Frame Rate", information.frameRateDescription)
                            informationRow("Resolution", information.resolutionDescription)
                            informationRow("Video", information.videoDescription)
                            informationRow("Video Bit Rate", information.videoBitRateDescription)
                            informationRow("Color / HDR", information.color)
                            informationRow("Audio", information.audio)
                            informationRow("Container", information.container)
                            informationRow("Exported Size", information.fileSizeDescription)
                        }
                        .font(.caption)
                        .padding(.top, 4)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Exported video information for \(filename)")
                    }
                    .font(.caption.weight(.semibold))
                } else {
                    Text("File quality details will appear after this legacy export is replaced.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func informationRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .help(value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}
