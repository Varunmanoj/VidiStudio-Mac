import SwiftUI

struct ProjectFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var source: ProjectSourceFilter
    @State var language: String
    @State var provider: String
    @State var sort: ProjectListSort
    let languageOptions: [OutputLanguage]
    let aiProviderOptions: [String]
    let onFilter: (ProjectSourceFilter, String, String, ProjectListSort) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filter Projects")
                .font(.title2.bold())
                .accessibilityHeading(.h1)
            Form {
                sourcePicker
                languagePicker
                providerPicker
                sortPicker
            }
            .formStyle(.grouped)
            .frame(height: 206)
            .contextMenu {
                sourcePicker
                languagePicker
                providerPicker
                sortPicker
                Divider()
                Button("Filter", systemImage: "line.3.horizontal.decrease.circle", action: apply)
                Button("Cancel", systemImage: "xmark", action: dismiss.callAsFunction)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
                Button("Filter", action: apply)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onChange(of: aiProviderOptions, initial: true) { _, options in
            if !options.contains(provider) { provider = "all" }
        }
    }

    private var sourcePicker: some View {
        Picker("Source", selection: $source) {
            ForEach(ProjectSourceFilter.allCases) { option in
                Label(option.title, systemImage: option.iconName).tag(option)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Source")
    }

    private var languagePicker: some View {
        Picker("Language", selection: $language) {
            Label("All Languages", systemImage: "globe").tag("all")
            ForEach(languageOptions) { option in
                Label(option.title, systemImage: "globe").tag(option.id)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Language")
    }

    private var providerPicker: some View {
        Picker("AI Provider", selection: $provider) {
            ForEach(aiProviderOptions, id: \.self) { option in
                Label(SavedAIProvider.projectFilterTitle(option), systemImage: SavedAIProvider.projectFilterIcon(option))
                    .tag(option)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("AI Provider")
    }

    private var sortPicker: some View {
        Picker("Sort by", selection: $sort) {
            ForEach(ProjectListSort.allCases, id: \.self) { option in
                Label(option.title, systemImage: option.icon).tag(option)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Sort by")
    }

    private func apply() {
        onFilter(source, language, provider, sort)
        dismiss()
    }
}
