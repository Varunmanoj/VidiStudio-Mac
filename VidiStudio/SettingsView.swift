import SwiftUI
import AppKit

private struct ProjectPlaybackPreferenceControls: View {
    let projectID: String
    let projectName: String
    @AppStorage private var narrationEnabled: Bool
    @AppStorage private var followEnabled: Bool

    init(projectID: String, projectName: String) {
        self.projectID = projectID
        self.projectName = projectName
        _narrationEnabled = AppStorage(
            wrappedValue: false,
            ProjectPlaybackPreferences.narrationKey(projectID)
        )
        _followEnabled = AppStorage(
            wrappedValue: true,
            ProjectPlaybackPreferences.followKey(projectID)
        )
    }

    var body: some View {
        Toggle("Narration during playback", isOn: $narrationEnabled)
            .accessibilityHint("Turns synchronized narration on or off for \(projectName) and remembers the choice for this project")
            .onChange(of: narrationEnabled) { _, enabled in
                ProjectPlaybackPreferences.announceNarrationChange(enabled, projectID: projectID)
            }
        Toggle("Follow synchronized transcript", isOn: $followEnabled)
            .accessibilityHint("Follows the active transcript or description while \(projectName) plays")
            .onChange(of: followEnabled) { _, enabled in
                ProjectPlaybackPreferences.announceFollowChange(enabled, projectID: projectID)
            }
    }
}

struct SettingsView: View {
    @Bindable var studio: StudioModel
    @Bindable var openProjects: OpenProjectRegistry
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shortcutReferenceExpanded = false
    @State private var expandedPromptStages: Set<String> = []
    private var section: String { studio.settingsSection }
    private let sections = ["Appearance", "Projects", "Narration", "Gemini API", "Developer prompts", "Storage", "Help", "About"]
    private let sectionIcons = ["Appearance": "circle.lefthalf.filled", "Projects": "rectangle.stack", "Narration": "speaker.wave.2", "Gemini API": "sparkles", "Developer prompts": "text.bubble", "Storage": "folder", "Help": "questionmark.circle", "About": "info.circle"]
    private let promptStageOrder = ["multilingual_media", "transcript", "youtube_transcript", "summary", "audio_descriptions", "screen_text", "youtube_screen_text", "text_rewrite", "tts_audio"]
    private func prompt(_ stage: String, _ key: String) -> Binding<String> {
        Binding(get: { studio.settings.prompts[stage]?[key] ?? "" }, set: { studio.settings.prompts[stage, default: [:]][key] = $0 })
    }
    private var interfaceAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.22)
    }
    private func promptExpanded(_ stage: String) -> Binding<Bool> {
        Binding(
            get: { expandedPromptStages.contains(stage) },
            set: { expanded in
                if expanded {
                    expandedPromptStages.insert(stage)
                } else {
                    expandedPromptStages.remove(stage)
                }
            }
        )
    }
    private func promptTitle(_ stage: String) -> String {
        [
            "multilingual_media": "Multilingual Media",
            "audio_descriptions": "Audio Descriptions",
            "screen_text": "Screen Text",
            "text_rewrite": "Text Rewrite",
            "tts_audio": "Narration Audio",
            "youtube_screen_text": "YouTube Screen Text",
            "youtube_transcript": "YouTube Transcript",
        ][stage] ?? stage.replacingOccurrences(of: "_", with: " ").capitalized
    }
    private var orderedPromptStages: [String] {
        studio.settings.prompts.keys.sorted {
            let left = promptStageOrder.firstIndex(of: $0) ?? promptStageOrder.count
            let right = promptStageOrder.firstIndex(of: $1) ?? promptStageOrder.count
            return left == right ? $0 < $1 : left < right
        }
    }
    var body: some View {
        NavigationSplitView {
            List(sections, id: \.self, selection: $studio.settingsSection) { item in
                HStack(spacing: 10) {
                    Image(systemName: sectionIcons[item] ?? "gearshape")
                        .foregroundStyle(
                            Color(nsColor: item == section ? .alternateSelectedControlTextColor : .labelColor)
                        )
                        .frame(width: 18)

                    Text(item)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                }
                .help(item)
                .tag(item)
            }
                .listStyle(.sidebar)
                .tint(Color(nsColor: .controlAccentColor))
                .navigationTitle("Settings")
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 380)
        } detail: {
        Form {
            if section == "About" { AboutSettingsView() }
            if section == "Help" { Section("Help and keyboard shortcuts") {
                Button("Open VidiStudio Help", systemImage: "questionmark.circle") { StudioHelp.open() }
                DisclosureGroup("Keyboard shortcut reference", isExpanded: $shortcutReferenceExpanded) { ShortcutReferenceView() }
                    .animation(interfaceAnimation, value: shortcutReferenceExpanded)
            }
            }
            if section == "Appearance" { Section("Appearance and playback") {
                Picker("Appearance", selection: $studio.settings.theme) {
                    Label("System", systemImage: "desktopcomputer").tag("system"); Label("Light", systemImage: "sun.max").tag("light"); Label("Dark", systemImage: "moon").tag("dark")
                }
                Picker("Transcript overlay", selection: $studio.settings.captionDisplayMode) {
                    Text("Off").tag("off")
                    Text("Transcript").tag("transcript")
                    Text("AD Transcript").tag("ad-transcript")
                }
                .accessibilityHint("Choose whether video previews show no app transcript, spoken dialogue, or dialogue and audio descriptions")
                Text("Uses this project's transcript. macOS Captions preference can turn it on automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                GroupBox("Caption appearance") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Text size") {
                            HStack {
                                Slider(value: $studio.settings.captionFontSize, in: 14...48, step: 1)
                                    .frame(minWidth: 220)
                                    .accessibilityLabel("Caption text size")
                                    .accessibilityValue("\(Int(studio.settings.captionFontSize)) points")
                                Text("\(Int(studio.settings.captionFontSize)) pt")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }
                        GroupBox("Dialogue captions") {
                            VStack(alignment: .leading, spacing: 10) {
                                ColorPicker("Dialogue text color", selection: captionColorBinding(\.captionTextColor))
                                    .accessibilityHint("Changes dialogue caption text in the video preview and future open-caption exports")
                                ColorPicker("Dialogue background color", selection: captionColorBinding(\.captionBackgroundColor))
                                    .accessibilityHint("Changes dialogue caption backgrounds in the video preview and future open-caption exports")
                            }
                            .padding(.vertical, 2)
                        }
                        GroupBox("Audio description captions") {
                            VStack(alignment: .leading, spacing: 10) {
                                ColorPicker("Audio description text color", selection: captionColorBinding(\.adCaptionTextColor))
                                    .accessibilityHint("Changes audio description caption text in the video preview and future AD Transcript open-caption exports")
                                ColorPicker("Audio description background color", selection: captionColorBinding(\.adCaptionBackgroundColor))
                                    .accessibilityHint("Changes audio description caption backgrounds in the video preview and future AD Transcript open-caption exports")
                            }
                            .padding(.vertical, 2)
                        }
                        LabeledContent("Background opacity") {
                            HStack {
                                Slider(value: $studio.settings.captionBackgroundOpacity, in: 0...1, step: 0.05)
                                    .frame(minWidth: 220)
                                    .accessibilityLabel("Caption background opacity")
                                    .accessibilityValue(studio.settings.captionBackgroundOpacity.formatted(.percent.precision(.fractionLength(0))))
                                Text(studio.settings.captionBackgroundOpacity, format: .percent.precision(.fractionLength(0)))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }
                        Picker("Position", selection: $studio.settings.captionPosition) {
                            Text("Top").tag("top")
                            Text("Bottom").tag("bottom")
                        }
                        .pickerStyle(.segmented)
                        CaptionAppearancePreview(settings: studio.settings)
                        Button("Restore Caption Defaults", systemImage: "arrow.counterclockwise") {
                            studio.settings.restoreCaptionAppearanceDefaults()
                        }
                        .accessibilityHint("Restores caption size, colors, opacity, and position")
                    }
                    .padding(.vertical, 4)
                }
            }
            }
            if section == "Projects" {
                if openProjects.projects.isEmpty {
                    Section("Open projects") {
                        ContentUnavailableView("No Open Projects", systemImage: "rectangle.stack", description: Text("Open a project to manage its project-specific playback settings."))
                    }
                } else {
                    ForEach(openProjects.projects) { project in
                        Section(project.name) {
                            ProjectPlaybackPreferenceControls(projectID: project.id, projectName: project.name)
                        }
                    }
                }
            }
            if section == "Gemini API" { GeminiAPISettingsView(studio: studio) }
            if section == "Narration" { Section("Narration") {
                Picker("Speech engine", selection: $studio.settings.ttsMode) {
                    Label("Apple Voices", systemImage: "speaker.wave.2").tag("system")
                    Label("Gemini Voices", systemImage: "sparkles").tag("gemini")
                    if studio.settings.hasAzureSpeechKey {
                        Label("Azure Online Voices", systemImage: "cloud").tag("azure")
                    }
                }
                Picker("Narration during playback", selection: $studio.settings.narrationPlayback) {
                    Label("Play synthesized narration", systemImage: "play.circle").tag("generated")
                    Label("Preview segment text with Apple Speech", systemImage: "text.bubble").tag("device")
                }
                Toggle("Sound when narration is off", isOn: $studio.settings.soundWhenNarrationOff)
                Toggle("Sound when synthesized audio is unavailable", isOn: $studio.settings.soundWhenNarrationMissing)
                if studio.settings.ttsMode == "gemini" {
                    GeminiVoiceBrowser(studio: studio)
                }
                if studio.settings.ttsMode != "gemini" {
                    GroupBox("Voice controls") {
                        VStack(alignment: .leading, spacing: 14) {
                            speechSlider("Speech rate", value: $studio.settings.systemSpeechRate, range: 0.5...2.0)
                            speechSlider("Pitch", value: $studio.settings.systemSpeechPitch, range: 0.5...2.0)
                            speechSlider("Speech volume", value: $studio.settings.systemSpeechVolume, range: 0...1.0)
                            Button("Restore Defaults", systemImage: "arrow.counterclockwise") {
                                studio.settings.restoreSystemSpeechDefaults()
                            }
                            .accessibilityHint("Restores speech rate, pitch, and volume to their original values")
                        }
                        .padding(.vertical, 4)
                    }
                    if studio.settings.ttsMode == "azure" {
                        AzureVoiceBrowser(studio: studio)
                    } else {
                        SystemVoiceBrowser(settings: $studio.settings)
                    }
                }
                AzureSpeechKeySettings(studio: studio)
                GroupBox("Summary readback") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Reads the summary aloud and highlights the active sentence and word.")
                            .font(.caption).foregroundStyle(.secondary)
                        ColorPicker("Sentence highlight", selection: summaryColorBinding(\.summarySentenceHighlight))
                            .accessibilityLabel("Sentence highlight background color")
                            .accessibilityHint("Background color used for the summary text being read")
                        ColorPicker("Spoken word highlight", selection: summaryColorBinding(\.summaryWordHighlight))
                            .accessibilityLabel("Spoken word highlight background color")
                            .accessibilityHint("Background color used for the word currently spoken in the summary")
                        Button("Restore Highlight Defaults", systemImage: "arrow.counterclockwise") {
                            studio.settings.restoreSummaryHighlightDefaults()
                        }
                        .accessibilityHint("Restores the summary text and word highlight colors")
                    }
                    .padding(.vertical, 4)
                }
            }
            }
            if section == "Developer prompts" { Section("Developer prompts") {
                ForEach(orderedPromptStages, id: \.self) { stage in
                    DisclosureGroup(
                        promptTitle(stage),
                        isExpanded: promptExpanded(stage)
                    ) {
                        Text("System instruction").font(.caption)
                        TextEditor(text: prompt(stage, "system_instruction")).frame(minHeight: 90).accessibilityLabel("\(stage) system instruction")
                        Text("User prompt").font(.caption)
                        TextEditor(text: prompt(stage, "user_prompt")).frame(minHeight: 130).accessibilityLabel("\(stage) user prompt")
                    }
                    .animation(interfaceAnimation, value: expandedPromptStages.contains(stage))
                }
            }
            }
            if section == "Storage" { Section("Local storage and tools") {
                LabeledContent("Default folder for new projects") {
                    HStack {
                        TextField("Project folder", text: $studio.settings.libraryPath)
                            .accessibilityLabel("Default folder for new projects")
                        Button("Browse…", systemImage: "folder") {
                            studio.chooseProjectLibrary()
                        }
                        .disabled(studio.busy)
                    }
                }
                Text("New projects are created here and added to the project list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("FFmpeg") {
                    HStack {
                        TextField("FFmpeg path", text: $studio.settings.ffmpegPath)
                            .accessibilityLabel("FFmpeg executable path")
                        Button("Choose…", systemImage: "folder") { studio.chooseFFmpeg() }
                            .disabled(studio.busy)
                    }
                }
                LabeledContent("FFprobe") {
                    HStack {
                        TextField("FFprobe path", text: $studio.settings.ffprobePath)
                            .accessibilityLabel("FFprobe executable path")
                        Button("Choose…", systemImage: "folder") { studio.chooseFFprobe() }
                            .disabled(studio.busy)
                    }
                }
                Text("Leave these paths empty to use the media tools included with VidiStudio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Check VidiStudio", systemImage: "checkmark.shield") { studio.checkEngine() }.disabled(studio.busy)
                    switch studio.engineCheckStatus {
                    case .unchecked:
                        EmptyView()
                    case .checking:
                        ProgressView().controlSize(.small)
                        Text("Checking…").foregroundStyle(.secondary)
                    case .ready:
                        Label("VidiStudio is ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed:
                        Label("VidiStudio needs attention", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .accessibilityElement(children: .combine)
                if case .failed(let message) = studio.engineCheckStatus {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            }
            if section == "Gemini API" {
                Text("Your Gemini key is stored securely in your macOS Keychain and is never saved inside a project.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .lineLimit(nil)
        .formStyle(.grouped)
        .navigationTitle(section)
        }
        .safeAreaInset(edge: .top, spacing: 0) { ActiveExportProgressView() }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 850, idealWidth: 940, minHeight: 650, idealHeight: 740)
        .smoothPresentation()
        .onChange(of: studio.settings.ffmpegPath) { _, _ in studio.engineCheckStatus = .unchecked }
        .onChange(of: studio.settings.ffprobePath) { _, _ in studio.engineCheckStatus = .unchecked }
        .onAppear {
            if let section = SettingsSectionRequest.consume(), sections.contains(section) {
                studio.settingsSection = section
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vidiStudioOpenSettingsSection)) { _ in
            if let section = SettingsSectionRequest.consume(), sections.contains(section) {
                studio.settingsSection = section
            }
        }
        .preferredColorScheme(studio.settings.theme == "dark" ? .dark : studio.settings.theme == "light" ? .light : nil)
    }

    private func summaryColorBinding(_ keyPath: WritableKeyPath<StudioSettings, String>) -> Binding<Color> {
        Binding(
            get: { SummaryHighlightColor.color(from: studio.settings[keyPath: keyPath]) },
            set: { studio.settings[keyPath: keyPath] = SummaryHighlightColor.hex(from: $0) }
        )
    }

    private func captionColorBinding(_ keyPath: WritableKeyPath<StudioSettings, String>) -> Binding<Color> {
        Binding(
            get: { SummaryHighlightColor.color(from: studio.settings[keyPath: keyPath]) },
            set: { studio.settings[keyPath: keyPath] = SummaryHighlightColor.hex(from: $0) }
        )
    }

    private func speechSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: 0.05)
                .accessibilityLabel(title)
                .accessibilityValue(value.wrappedValue.formatted(.percent.precision(.fractionLength(0))))
        }
    }
}

private struct CaptionAppearancePreview: View {
    let settings: StudioSettings

    var body: some View {
        ZStack(alignment: settings.captionPosition == "top" ? .top : .bottom) {
            Rectangle()
                .fill(.black)
                .overlay {
                    LinearGradient(colors: [.blue.opacity(0.55), .purple.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            VStack(spacing: 6) {
                previewCaption(
                    "Dialogue caption preview",
                    textColor: settings.captionTextColor,
                    backgroundColor: settings.captionBackgroundColor
                )
                previewCaption(
                    "Audio description: A person enters the room.",
                    textColor: settings.adCaptionTextColor,
                    backgroundColor: settings.adCaptionBackgroundColor
                )
            }
                .padding(14)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dialogue and audio description caption appearance preview")
        .accessibilityValue("Separate dialogue and audio description colors, \(Int(settings.captionFontSize)) point text, positioned at the \(settings.captionPosition)")
    }

    private func previewCaption(_ text: String, textColor: String, backgroundColor: String) -> some View {
        Text(text)
            .font(.system(size: settings.captionFontSize, weight: .semibold))
            .foregroundStyle(SummaryHighlightColor.color(from: textColor))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                SummaryHighlightColor.color(from: backgroundColor)
                    .opacity(settings.captionBackgroundOpacity),
                in: RoundedRectangle(cornerRadius: 6)
            )
    }
}
