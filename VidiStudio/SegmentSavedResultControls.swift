import SwiftUI

/// Filter/sort dialogs use only the already viewed language's saved results.
struct SegmentSavedResultControls: View {
    let project: StudioProject
    let kinds: [String]
    let enabled: Bool
    let select: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(kinds, id: \.self) { kind in
                let results = project.languageResults(kind: kind, language: project.languageCode, includingDrafts: true)
                if !results.isEmpty {
                    Picker(SavedLanguageResult.savedResultsTitle(kind), selection: Binding(
                        get: { project.activeLanguageResultID(kind, language: project.languageCode) },
                        set: { id in
                            guard enabled, results.contains(where: { $0.id == id }), project.activeLanguageResultID(kind) != id else { return }
                            select(id)
                        })) {
                        ForEach(results) { result in
                            SavedResultOption(result: result, project: project, selected: result.id == project.activeLanguageResultID(kind)).tag(result.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!enabled)
                }
            }
        }
    }
}
