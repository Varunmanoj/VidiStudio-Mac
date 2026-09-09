import SwiftUI

enum GeneratedContentComponent: String, CaseIterable, Identifiable, Hashable {
    case transcript
    case summary
    case descriptions
    case narration
    case thumbnails
    case exports
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcript: return "Transcript"
        case .summary: return "Summary"
        case .descriptions: return "AD Descriptions"
        case .narration: return "Narration Audio"
        case .thumbnails: return "Thumbnails"
        case .exports: return "Exports"
        case .history: return "Edit History"
        }
    }

    var explanation: String {
        switch self {
        case .transcript: return "Removes transcript dialogue, including those rows from AD Transcript."
        case .summary: return "Removes the generated video summary."
        case .descriptions: return "Removes every AD segment, its narration, and its rows from AD Transcript."
        case .narration: return "Removes synthesized audio while keeping AD text and timing."
        case .thumbnails: return "Removes generated timeline thumbnails."
        case .exports: return "Removes generated subtitle, audio, and video exports."
        case .history: return "Removes saved AD edit undo and redo history."
        }
    }

    func hasContent(in project: StudioProject) -> Bool {
        switch self {
        case .transcript:
            return project.hasGeneratedTranscript
        case .summary:
            return !project.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || project.hasFile("metadata/summary.json")
        case .descriptions:
            return !project.cues.isEmpty || project.hasFile("audio-description/cues.json")
        case .narration:
            return project.cues.contains { $0.audio != nil }
        case .thumbnails:
            return !project.thumbnails.isEmpty
        case .exports:
            return !project.exports.isEmpty || project.directoryHasContent("exports")
        case .history:
            return project.directoryHasContent("metadata/history")
        }
    }
}

struct GeneratedContentDeletionView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var studio: StudioModel
    let project: StudioProject
    @State private var selection: Set<GeneratedContentComponent> = []

    private var available: Set<GeneratedContentComponent> {
        Set(GeneratedContentComponent.allCases.filter { $0.hasContent(in: project) })
    }

    private var selectAll: Binding<Bool> {
        Binding(
            get: { !available.isEmpty && selection == available },
            set: { selection = $0 ? available : [] }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Delete Generated Content")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Choose what to delete from “\(project.name)”. The project and original video or YouTube link are always kept.")
                .foregroundStyle(.secondary)

            Toggle("Select All", isOn: selectAll)
                .fontWeight(.semibold)
                .disabled(available.isEmpty)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                ForEach(GeneratedContentComponent.allCases) { component in
                    Toggle(isOn: Binding(
                        get: { selection.contains(component) },
                        set: { selected in
                            if selected { selection.insert(component) }
                            else { selection.remove(component) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(component.title)
                            Text(component.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!available.contains(component))
                    .accessibilityHint(available.contains(component) ? component.explanation : "This project has no \(component.title.lowercased()) to delete.")
                }
            }

            Text("Deleting selected content cannot be undone.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Delete Selected", systemImage: "trash", role: .destructive) {
                    studio.deleteGeneratedContent(project, components: selection)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty || studio.busy)
            }
        }
        .padding(24)
        .frame(width: 570)
    }
}
