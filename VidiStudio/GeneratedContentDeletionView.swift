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
        case .history: return "Segment Undo History"
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
        case .history: return "Removes the saved transcript and AD segment undo and redo states."
        }
    }

    func hasContent(in project: StudioProject) -> Bool {
        switch self {
        case .transcript:
            return project.hasGeneratedTranscript
        case .summary:
            return !project.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || project.summaryGenerated == true
        case .descriptions:
            return !project.cues.isEmpty || project.descriptionsGenerated == true
        case .narration:
            return project.cues.contains { $0.audio != nil }
        case .thumbnails:
            return !project.thumbnails.isEmpty
        case .exports:
            return !project.exports.isEmpty || project.directoryHasContent("exports")
        case .history:
            return !(project.undoStack ?? []).isEmpty || !(project.redoStack ?? []).isEmpty
                || !(project.transcriptUndoStack ?? []).isEmpty || !(project.transcriptRedoStack ?? []).isEmpty
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

    private var effectiveSelection: Set<GeneratedContentComponent> {
        guard selection.contains(.descriptions), available.contains(.narration) else { return selection }
        return selection.union([.narration])
    }

    private var selectAll: Binding<Bool> {
        Binding(
            get: { !available.isEmpty && effectiveSelection == available },
            set: { selection = $0 ? available : [] }
        )
    }

    private func selectionBinding(for component: GeneratedContentComponent) -> Binding<Bool> {
        Binding(
            get: { effectiveSelection.contains(component) },
            set: { selected in
                if selected { selection.insert(component) }
                else { selection.remove(component) }
            }
        )
    }

    private func explanation(for component: GeneratedContentComponent) -> String {
        if component == .narration, selection.contains(.descriptions), available.contains(.narration) {
            return "Included automatically because deleting AD Descriptions also removes their narration audio."
        }
        return component.explanation
    }

    private func isDisabled(_ component: GeneratedContentComponent) -> Bool {
        !available.contains(component)
            || (component == .narration && selection.contains(.descriptions))
    }

    private func accessibilityHint(for component: GeneratedContentComponent) -> String {
        if component == .narration, selection.contains(.descriptions), available.contains(.narration) {
            return "Selected automatically and cannot be changed while AD Descriptions is selected."
        }
        return available.contains(component)
            ? component.explanation
            : "This project has no \(component.title.lowercased()) to delete."
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
                    Toggle(isOn: selectionBinding(for: component)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(component.title)
                            Text(explanation(for: component))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isDisabled(component))
                    .accessibilityHint(accessibilityHint(for: component))
                }
            }

            Text("Deleting selected content cannot be undone.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Delete Selected…", systemImage: "trash", role: .destructive) {
                    if studio.confirmDeleteGeneratedContent(project, components: effectiveSelection) {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(effectiveSelection.isEmpty || studio.busy)
            }
        }
        .padding(24)
        .frame(width: 570)
    }
}
