import SwiftUI

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
    private var section: String { studio.settingsSection }
    private let sections = ["Appearance", "Projects", "Narration", "Gemini API", "Developer prompts", "Storage", "Help"]
    private let sectionIcons = ["Appearance": "circle.lefthalf.filled", "Projects": "rectangle.stack", "Narration": "speaker.wave.2", "Gemini API": "sparkles", "Developer prompts": "text.bubble", "Storage": "folder", "Help": "questionmark.circle"]
    private func prompt(_ stage: String, _ key: String) -> Binding<String> {
        Binding(get: { studio.settings.prompts[stage]?[key] ?? "" }, set: { studio.settings.prompts[stage, default: [:]][key] = $0 })
    }
    var body: some View {
        NavigationSplitView {
            List(sections, id: \.self, selection: $studio.settingsSection) { item in
                Label(item, systemImage: sectionIcons[item] ?? "gearshape").tag(item)
            }
                .navigationTitle("Settings")
                .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
        Form {
            if section == "Help" { Section("Help and keyboard shortcuts") {
                Button("Open VidiStudio Help", systemImage: "questionmark.circle") { StudioHelp.open() }
                LabeledContent("App version", value: AppVersionInfo.display)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("App version, \(AppVersionInfo.display)")
                DisclosureGroup("Keyboard shortcut reference") { ShortcutReferenceView() }
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
                Text("When VidiStudio has no saved choice, macOS Accessibility → Captions → Prefer closed captions and SDH turns the Transcript overlay on automatically. You can change this choice here at any time. The overlay uses the transcript saved in this VidiStudio project. For YouTube projects, YouTube's own captions, transcript, and keyboard shortcuts remain unchanged; turn one display off if both would be shown.")
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
                    Label("Apple on-device voices · offline", systemImage: "speaker.wave.2").tag("system"); Label("Gemini TTS", systemImage: "sparkles").tag("gemini")
                }
                Picker("Narration during playback", selection: $studio.settings.narrationPlayback) {
                    Label("Play synthesized narration", systemImage: "play.circle").tag("generated")
                    Label("Preview segment text with Apple Speech", systemImage: "text.bubble").tag("device")
                }
                Text("Play synthesized narration to hear each saved file with the voice it was created with; changing the current voice does not replace it. Apple Speech previews segment text immediately with the latest voice settings and does not create audio files. Seeking or resuming restarts the active segment. Your playback choice is saved automatically.").font(.caption).foregroundStyle(.secondary)
                Toggle("Sound when narration is off", isOn: $studio.settings.soundWhenNarrationOff)
                Text("Play a player sound once when entering an AD segment while Narration is off.").font(.caption).foregroundStyle(.secondary)
                Toggle("Sound when synthesized audio is unavailable", isOn: $studio.settings.soundWhenNarrationMissing)
                Text("Play a player sound when Narration is on and synthesized playback is selected, but the segment's saved audio is missing or outdated. No extra sound accompanies live Apple Speech. Turn both options off for no AD indication sounds.").font(.caption).foregroundStyle(.secondary)
                if studio.settings.ttsMode == "gemini" {
                    GeminiVoiceBrowser(studio: studio)
                }
                if studio.settings.ttsMode != "gemini" || studio.settings.narrationPlayback == "device" {
                    Text("Live Apple Speech uses the Apple voice, speech rate, pitch, and volume below, including when Gemini is selected for generating saved narration. System default follows the voice selected for the current language in macOS Accessibility → Read & Speak.")
                        .font(.caption).foregroundStyle(.secondary)
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
                    SystemVoiceBrowser(settings: $studio.settings)
                }
                GroupBox("Summary readback") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("The Summary tab reads sentences aloud with the Apple voice above and highlights the active sentence and spoken word. The summary scrolls automatically to the sentence being read.")
                            .font(.caption).foregroundStyle(.secondary)
                        ColorPicker("Sentence highlight", selection: summaryColorBinding(\.summarySentenceHighlight))
                            .accessibilityLabel("Sentence highlight background color")
                            .accessibilityHint("Background color used for the summary sentence being read")
                        ColorPicker("Spoken word highlight", selection: summaryColorBinding(\.summaryWordHighlight))
                            .accessibilityLabel("Spoken word highlight background color")
                            .accessibilityHint("Background color used for the word currently spoken in the summary")
                        Button("Restore Highlight Defaults", systemImage: "arrow.counterclockwise") {
                            studio.settings.restoreSummaryHighlightDefaults()
                        }
                        .accessibilityHint("Restores the summary sentence and word highlight colors")
                    }
                    .padding(.vertical, 4)
                }
            }
            }
            if section == "Developer prompts" { Section("Developer prompts") {
                ForEach(studio.settings.prompts.keys.sorted(), id: \.self) { stage in
                    DisclosureGroup(stage.replacingOccurrences(of: "_", with: " ").capitalized) {
                        Text("System instruction").font(.caption)
                        TextEditor(text: prompt(stage, "system_instruction")).frame(minHeight: 90).accessibilityLabel("\(stage) system instruction")
                        Text("User prompt").font(.caption)
                        TextEditor(text: prompt(stage, "user_prompt")).frame(minHeight: 130).accessibilityLabel("\(stage) user prompt")
                    }
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
                Text("New projects are created here. The project list scans this folder and any project folders you open directly.")
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
                    Button("Check Engine", systemImage: "checkmark.shield") { studio.checkEngine() }.disabled(studio.busy)
                    switch studio.engineCheckStatus {
                    case .unchecked:
                        EmptyView()
                    case .checking:
                        ProgressView().controlSize(.small)
                        Text("Checking…").foregroundStyle(.secondary)
                    case .ready:
                        Label("Engine ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed:
                        Label("Engine needs attention", systemImage: "xmark.circle.fill")
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
                Text("Your Gemini key stays on this Mac and is never saved inside a project.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).navigationTitle(section)
        }
        .background(SettingsWindowChrome().frame(width: 0, height: 0))
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 850, idealWidth: 940, minHeight: 650, idealHeight: 740)
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
