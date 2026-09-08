import SwiftUI
import AVKit
import AVFoundation
import UniformTypeIdentifiers

private enum NewProjectSource: String, CaseIterable, Identifiable {
    case videoFile
    case youtube

    var id: Self { self }
    var title: String { self == .videoFile ? "Video File" : "YouTube Video" }
    var icon: String { self == .videoFile ? "film" : "play.rectangle" }
}

private struct NewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var studio: StudioModel
    @State private var source = NewProjectSource.videoFile
    @State private var videoURL: URL?
    @State private var youtubeURL = ""

    private var trimmedYouTubeURL: String {
        youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        source == .videoFile ? videoURL != nil : !trimmedYouTubeURL.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Project")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)
            Form {
            Section {
                Picker("Project type", selection: $source) {
                    ForEach(NewProjectSource.allCases) { option in
                        Label(option.title, systemImage: option.icon).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
                .accessibilityHint("Choose a video file from this Mac or enter a YouTube video link.")
            } header: {
                Text("Choose a project source")
            }

            Section {
                if source == .videoFile {
                    LabeledContent("Video file") {
                        Button(videoURL == nil ? "Choose Video…" : "Choose Different Video…", systemImage: "folder") {
                            chooseVideo()
                        }
                    }
                    Text(videoURL?.path ?? "No video selected")
                        .font(.caption)
                        .foregroundStyle(videoURL == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                        .accessibilityLabel(videoURL.map { "Selected video: \($0.lastPathComponent)" } ?? "No video selected")
                } else {
                    TextField("YouTube video URL", text: $youtubeURL, prompt: Text("https://www.youtube.com/watch?v=…"))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("YouTube video URL")
                }
            } header: {
                Text(source.title)
            } footer: {
                Text(source == .videoFile
                     ? "VidiStudio copies the selected video into a new local project folder."
                     : "VidiStudio stores the project locally. Playback and analysis require an internet connection.")
            }

            Section {
                HStack {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Create Project", systemImage: "plus") { createProject() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canCreate)
                }
            }
            }
            .formStyle(.grouped)
        }
        .frame(width: 560, height: 410)
    }

    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Video"
        panel.message = "Choose the video file for this VidiStudio project."
        if panel.runModal() == .OK {
            videoURL = panel.url
        }
    }

    private func createProject() {
        switch source {
        case .videoFile:
            guard let videoURL else { return }
            studio.importVideo(at: videoURL)
        case .youtube:
            guard !trimmedYouTubeURL.isEmpty else { return }
            studio.execute("import-youtube", extra: ["--url", trimmedYouTubeURL, "--library", studio.settings.libraryPath])
        }
        dismiss()
    }
}

struct ContentView: View {
    @Bindable var studio: StudioModel
    @State private var showInspector = true
    @State private var showProjects = true
    @State private var search = ""
    @State private var rename = ""
    @State private var renaming = false
    @AppStorage("projectBrowserGrid") private var projectGrid = false
    var body: some View {
        GeometryReader { geometry in
        let inspectorVisible = showInspector && studio.selected != nil
        HStack(spacing: 0) {
        if showProjects {
          VStack(spacing: 0) {
            TextField("Search projects", text: $search).textFieldStyle(.roundedBorder).padding(12)
            if projectGrid {
                ProjectGridView(projects: studio.projects.filter { search.isEmpty || $0.name.localizedStandardContains(search) }, selection: $studio.selectedID, busy: studio.busy, rename: { p in
                    studio.selectedID = p.id; rename = p.name; renaming = true
                }, delete: { studio.trashProject($0) }, process: { p in studio.selectedID = p.id; studio.execute("analyze", project: p) }, clear: { studio.clearGeneratedContent($0) })
            } else {
            List(selection: $studio.selectedID) {
                Section("Local Projects") {
                    ForEach(studio.projects.filter { search.isEmpty || $0.name.localizedStandardContains(search) }) { p in
                        HStack(alignment: .top, spacing: 8) {
                            MaterialIcon(glyph: "\u{e02c}").accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(p.name).lineLimit(nil).fixedSize(horizontal: false, vertical: true).frame(width: 178, alignment: .leading)
                                Text("\(timecode(p.duration)) · \(p.cues.count) descriptions").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }.tag(p.id)
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") { studio.selectedID = p.id; rename = p.name; renaming = true }
                            Button("Open in Project Folder", systemImage: "folder") { if let folder = p.folder { NSWorkspace.shared.open(folder) } }
                            Button(p.canReprocess ? "Reprocess Video" : "Process Video", systemImage: "sparkles") {
                                studio.selectedID = p.id
                                studio.execute("analyze", project: p)
                            }.disabled(studio.busy)
                            Divider()
                            Button("Delete Generated Content…", systemImage: "eraser", role: .destructive) { studio.clearGeneratedContent(p) }.disabled(studio.busy || !p.hasGeneratedContent)
                            Button("Delete Project", systemImage: "trash", role: .destructive) { studio.trashProject(p) }.help("Move this project to the Mac Trash").disabled(studio.busy)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            }
            Spacer(minLength: 0)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    SettingsLink { Image(systemName: "gearshape") }
                        .help("Settings")
                        .accessibilityLabel("Settings")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
            }
          }.frame(width: projectGrid ? min(440, geometry.size.width * 0.48) : 252).frame(maxHeight: .infinity).background(.bar)
          Divider()
        }
        Group {
            if let p = studio.selected {
                ProjectEditor(shortcutsBlocked: renaming || studio.isCreatingProject || studio.error != nil, studio: studio, project: p).id(p.id)
            } else {
                ContentUnavailableView {
                    Label("Make every video accessible", systemImage: "video.badge.waveform")
                } description: {
                    Text("Create a project from a video file on this Mac or a YouTube video.")
                } actions: {
                    Button("New Project…", systemImage: "plus") { studio.isCreatingProject = true }.buttonStyle(.glassProminent)
                    Button("Open Project Folder…", systemImage: "folder") { studio.openProject() }
                }
            }
        }.frame(width: max(0, geometry.size.width - (showProjects ? (projectGrid ? min(440, geometry.size.width * 0.48) : 252) + 1 : 0) - (inspectorVisible ? 273 : 0)), height: geometry.size.height).clipped()
        if inspectorVisible {
            Divider()
            ProcessingInspector(studio: studio).frame(width: 272, height: geometry.size.height).background(.bar)
        }
        }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
        }
        .background(WindowFitter().frame(width: 0, height: 0))
        .focusedSceneValue(\.projectBrowser, ProjectBrowserActions(showProjects: $showProjects, showInspector: $showInspector, grid: $projectGrid, hasProject: studio.selected != nil))
        .preferredColorScheme(studio.settings.theme == "dark" ? .dark : studio.settings.theme == "light" ? .light : nil)
        .sheet(isPresented: $renaming) {
            VStack(spacing: 20) {
                TextField("Project name", text: $rename)
                HStack { Button("Cancel", role: .cancel) { renaming = false }; Button("Rename", systemImage: "pencil") { studio.execute("rename-project", extra: ["--name", rename]); renaming = false }.keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 420)
        }
        .sheet(isPresented: $studio.isCreatingProject) {
            NewProjectView(studio: studio)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) { Button(showProjects ? "Hide Project List" : "Show Project List", systemImage: "sidebar.left") { showProjects.toggle() } }
            ToolbarItem(placement: .navigation) {
                Picker("Project layout", selection: $projectGrid) {
                    Label("List View", systemImage: "list.bullet").tag(false)
                    Label("Grid View", systemImage: "square.grid.2x2").tag(true)
                }.pickerStyle(.segmented).onChange(of: projectGrid) { _, _ in showProjects = true }
            }
            ToolbarItem(placement: .primaryAction) { Button("New Project", systemImage: "plus") { studio.isCreatingProject = true }.disabled(studio.busy) }
            ToolbarItem(placement: .primaryAction) { Button("Open Project", systemImage: "folder") { studio.openProject() }.disabled(studio.busy) }
            if studio.selected != nil {
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) { Button(showInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right") { showInspector.toggle() } }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if studio.busy {
                HStack(spacing: 12) {
                    Text(studio.message).lineLimit(2).font(.caption)
                    Spacer()
                    Button("Cancel Processing", systemImage: "stop.circle") { studio.process?.terminate() }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
        }
        .alert("VidiStudio needs attention", isPresented: Binding(get: { studio.error != nil }, set: { if !$0 { studio.error = nil } })) {
            Button("OK", role: .cancel) { studio.error = nil }
        } message: { Text(studio.error ?? "") }
    }
}

struct ProcessingInspector: View {
    @Bindable var studio: StudioModel
    private let stages: [(String,String,String)] = [
        ("probe-video","Read Metadata","info.circle"), ("generate-thumbnails","Generate Thumbnails","photo.on.rectangle"),
        ("extract-audio","Extract Audio","waveform"), ("transcribe","Transcribe Video","text.bubble"),
        ("generate-summary","Generate Summary","text.alignleft"), ("generate-ad-cues","Generate Descriptions","sparkles"),
        ("synthesize-tts","Synthesize Narration","speaker.wave.2"), ("export-final-video","Export Final Video","square.and.arrow.up")]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Project Inspector").font(.headline)
                if let p = studio.selected {
                    LabeledContent("Duration", value: timecode(p.duration))
                    LabeledContent("Resolution", value: "\(p.width) × \(p.height)")
                    LabeledContent("Status", value: p.status)
                    Divider()
                    Text("PROCESSING").font(.caption).foregroundStyle(.secondary)
                    Button("Run All Analysis", systemImage: "sparkles") { studio.execute("analyze") }.disabled(studio.busy)
                    ForEach(stages, id: \.0) { stage in
                        Button { studio.execute(stage.0) } label: { HStack { MaterialIcon(glyph: stage.0 == "transcribe" ? "\u{e8af}" : stage.0 == "synthesize-tts" ? "\u{e050}" : "\u{e037}"); Text(stage.1) }.frame(maxWidth: .infinity, alignment: .leading) }
                            .disabled(studio.busy || (p.source.isEmpty && ["probe-video", "generate-thumbnails", "extract-audio"].contains(stage.0))).controlSize(.large)
                    }
                    Menu("Export Text", systemImage: "square.and.arrow.up") {
                        ForEach(["transcript", "descriptions", "combined"], id: \.self) { content in
                            Menu(content.capitalized, systemImage: "doc.text") {
                                ForEach(["srt", "vtt", "txt", "json"], id: \.self) { format in
                                    Button(format.uppercased(), systemImage: "doc") { studio.execute("export-subtitles", extra: ["--content", content, "--format", format]) }
                                }
                            }
                        }
                    }.disabled(studio.busy)
                    Button("Export Narration Audio", systemImage: "square.and.arrow.up") { studio.execute("export-audio") }.disabled(studio.busy)
                    Button("Synthesize Changed Segments", systemImage: "waveform") { studio.execute("synthesize-tts", extra: ["--changed"]) }.disabled(studio.busy)
                    HStack { Button("Undo Segment Edit", systemImage: "arrow.uturn.backward") { studio.execute("undo-cues") }; Button("Redo", systemImage: "arrow.uturn.forward") { studio.execute("redo-cues") } }.disabled(studio.busy)
                    if p.sourceType == "youtube" { Button("Attach Local Video Copy…", systemImage: "paperclip") { studio.attachVideo() }.disabled(studio.busy) }
                    Text("Run analysis stages in order. Review and edit descriptions before synthesizing narration.").font(.caption).foregroundStyle(.secondary)
                    Button("Show Project in Finder", systemImage: "folder") { if let folder = p.folder { NSWorkspace.shared.open(folder) } }
                    if !p.exports.isEmpty {
                        Divider(); Text("Exports").font(.headline)
                        ForEach(p.exports, id: \.self) { path in
                            Button(URL(fileURLWithPath: path).lastPathComponent, systemImage: "play.rectangle") { if let url = p.url(path) { NSWorkspace.shared.open(url) } }
                        }
                    }
                } else { Text("Select a project to see its media and processing tools.").foregroundStyle(.secondary) }
            }.padding(20)
        }
    }
}

struct ProjectEditor: View {
    var shortcutsBlocked = false
    @Bindable var studio: StudioModel
    let project: StudioProject
    @State private var playback = PlaybackModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab = "descriptions"
    @State private var requestedTitle = ""
    @State private var previewHidden = false
    @State private var cueToEdit: Segment?
    @State private var audioPreview: AVAudioPlayer?
    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                Group {
                    if let url = project.youtubeURL, project.source.isEmpty { YouTubePlayer(url: url, playback: playback) }
                    else { NativeVideoPlayer(player: playback.player, playback: playback) }
                }.frame(minWidth: 0, idealWidth: 700, maxWidth: .infinity, minHeight: previewHidden ? 0 : 120, idealHeight: previewHidden ? 0 : 340, maxHeight: previewHidden ? 0 : .infinity).background(.black)
                TimelineView(project: project, playback: playback).frame(height: previewHidden ? 0 : nil).clipped()
            }.frame(minHeight: previewHidden ? 0 : 220, maxHeight: previewHidden ? 0 : .infinity).clipped().accessibilityHidden(previewHidden).allowsHitTesting(!previewHidden)
            VStack(spacing: 0) {
                ScrollView(.horizontal) { HStack {
                    Picker("Editor section", selection: $tab) {
                        Text("Descriptions").tag("descriptions"); Text("Transcript").tag("transcript"); Text("Summary").tag("summary"); Text("AD Transcript").tag("ad-transcript"); Text("AD Overview").tag("ad-overview")
                    }.pickerStyle(.menu).labelsHidden().frame(maxWidth: 200)
                    Spacer()
                    Button(previewHidden ? "Show Preview" : "Hide Preview", systemImage: previewHidden ? "video" : "video.slash") {
                        playback.exitVideoFullScreen(); previewHidden.toggle()
                    }.labelStyle(.iconOnly).help(previewHidden ? "Show video preview" : "Hide video preview to focus on editing")
                    Button("Full-Screen Video", systemImage: "arrow.up.left.and.arrow.down.right") {
                        previewHidden = false
                        DispatchQueue.main.async { playback.toggleVideoFullScreen() }
                    }.labelStyle(.iconOnly).help("View video full screen; press Escape to return")
                    Button("Read Frame Text", systemImage: "text.viewfinder") { studio.execute("capture-frame", extra: ["--timestamp", String(playback.time)]) }.labelStyle(.iconOnly).help("Extract text from the current video frame").disabled(studio.busy)
                    Toggle("Narration", isOn: $playback.narrationEnabled).toggleStyle(.button).help("Play generated descriptions in sync with video")
                    Toggle("Follow", isOn: $studio.settings.followTranscript).toggleStyle(.button).help("Follow the active transcript or description")
                    if tab == "descriptions" {
                        Button("Add Segment", systemImage: "plus") {
                            let start = max(0, min(playback.time, project.duration - 0.1))
                            cueToEdit = Segment(id: UUID().uuidString, start: start, end: min(start+3,project.duration), text: "")
                        }.disabled(studio.busy)
                    }
                }.controlSize(.small).padding(12) }.fixedSize(horizontal: false, vertical: true)
                if let error = playback.speechError { Text(error).foregroundStyle(.red).padding(8) }
                Divider()
                if studio.busy {
                    VStack {
                        Spacer(minLength: 24)
                        ProgressView()
                            .controlSize(.large)
                            .scaleEffect(2)
                            .frame(width: 88, height: 88)
                            .accessibilityLabel("Processing")
                            .accessibilityValue(studio.message)
                            .accessibilityHint("VidiStudio is working. This indicator continues spinning until processing finishes.")
                        Spacer(minLength: 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tab == "ad-overview" {
                    ADOverviewView(studio: studio, project: project)
                } else if tab == "summary" {
                    MarkdownSummaryView(markdown: project.summary.isEmpty ? "Generate a summary after transcription to capture the story and visual context." : project.summary)
                } else {
                    let segments = (tab == "descriptions" || tab == "ad-transcript") ? project.cues : project.transcript
                    if segments.isEmpty {
                        ContentUnavailableView((tab == "descriptions" || tab == "ad-transcript") ? "Describe what matters" : "Your transcript appears here", systemImage: (tab == "descriptions" || tab == "ad-transcript") ? "text.below.photo" : "text.bubble", description: Text((tab == "descriptions" || tab == "ad-transcript") ? "Generate descriptions from the inspector or add a segment manually." : "Use Transcribe Video in the inspector to begin."))
                    } else {
                        ScrollViewReader { reader in
                        List(segments) { cue in
                            HStack(alignment: .top, spacing: 16) {
                                Button { playback.seek(cue.start) } label: {
                                    VStack { Text(timecode(cue.start)); Text(timecode(cue.end)).foregroundStyle(.secondary) }.monospacedDigit().font(.caption)
                                }.buttonStyle(.plain).help("Seek to \(timecode(cue.start))")
                                Text(cue.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                if tab == "descriptions" {
                                    if cue.audio != nil && cue.audioText == cue.text && cue.audioSettings == studio.settings.narrationSignature { Image(systemName: "waveform.circle.fill").foregroundStyle(.green).accessibilityLabel("Narration ready") }
                                    Button("Edit", systemImage: "pencil") { cueToEdit = cue }.labelStyle(.iconOnly).disabled(studio.busy)
                                    Menu {
                                        if let audio = cue.audio, let url = project.url(audio) { Button("Preview Narration", systemImage: "play.circle") { audioPreview = try? AVAudioPlayer(contentsOf: url); audioPreview?.play() } }
                                        Button("Rewrite to Fit", systemImage: "wand.and.stars") { studio.execute("rewrite-cue", extra: ["--segment", cue.id]) }
                                        Button("Synthesize This Segment", systemImage: "waveform") { studio.execute("synthesize-tts", extra: ["--segment", cue.id]) }
                                        Button("Delete Segment", systemImage: "trash", role: .destructive) { studio.saveCues(project.cues.filter { $0.id != cue.id }) }
                                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().disabled(studio.busy).accessibilityLabel("Segment actions")
                                }
                            }.padding(.vertical, 8)
                                .id(cue.id)
                                .listRowBackground(playback.time >= cue.start && playback.time < cue.end ? Color.accentColor.opacity(0.15) : Color.clear)
                        }.listStyle(.inset)
                        .onChange(of: segments.first(where: { playback.time >= $0.start && playback.time < $0.end })?.id) { _, id in
                            if studio.settings.followTranscript, let id { if reduceMotion { reader.scrollTo(id, anchor: .center) } else { withAnimation { reader.scrollTo(id, anchor: .center) } } }
                        }
                        }
                    }
                }
            }.frame(minHeight: 180)
        }
        .focusedSceneValue(\.editorShortcuts, shortcutsBlocked || studio.busy || cueToEdit != nil || studio.screenText != nil ? nil : EditorShortcutActions(run: { action in
            switch action {
            case "preview": playback.exitVideoFullScreen(); previewHidden.toggle()
            case "fullscreen":
                previewHidden = false
                DispatchQueue.main.async { playback.toggleVideoFullScreen() }
            case "play": playback.togglePlayback()
            case "back": playback.seek(max(0, playback.time - 5))
            case "forward": playback.seek(min(project.duration, playback.time + 5))
            case "narration": playback.narrationEnabled.toggle()
            case "follow": studio.settings.followTranscript.toggle()
            case "descriptions", "transcript", "summary", "ad-transcript", "ad-overview": tab = action
            case "add":
                let start = max(0, min(playback.time, project.duration - 0.1))
                cueToEdit = Segment(id: UUID().uuidString, start: start, end: min(start + 3, project.duration), text: "")
            case "undo": studio.execute("undo-cues")
            case "redo": studio.execute("redo-cues")
            default: break
            }
        }))
        .navigationTitle(project.name)
        .onChange(of: studio.busy) { _, busy in
            if !busy, !playback.videoTitle.isEmpty, requestedTitle != playback.videoTitle, project.name == "YouTube video" || project.name == "YouTube Project" || project.name == "YouTube " + (project.youtubeURL?.components(separatedBy: "v=").last ?? "") {
                requestedTitle = playback.videoTitle
                studio.execute("update-metadata", extra: ["--name", playback.videoTitle])
            }
        }
        .onChange(of: playback.videoTitle) { _, title in
            if !studio.busy, !title.isEmpty, requestedTitle != title, project.name == "YouTube video" || project.name == "YouTube Project" || project.name == "YouTube " + (project.youtubeURL?.components(separatedBy: "v=").last ?? "") {
                requestedTitle = title
                studio.execute("update-metadata", extra: ["--name", title])
            }
        }
        .onChange(of: playback.duration) { _, duration in
            if !studio.busy, duration > 0, abs(duration - project.duration) > 0.5 { studio.execute("update-metadata", extra: ["--duration", String(duration)]) }
        }
        .onChange(of: playback.time) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: playback.playing) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: studio.settings.narrationPlayback) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: studio.settings.systemVoice) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: studio.settings.systemSpeechRate) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: studio.settings.systemSpeechPitch) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: studio.settings.systemSpeechVolume) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onChange(of: playback.narrationEnabled) { _, _ in playback.syncNarration(project, settings: studio.settings) }
        .onAppear { playback.observe(); if !project.source.isEmpty, let url = project.url(project.source) { playback.player.replaceCurrentItem(with: AVPlayerItem(url: url)) } }
        .onDisappear { playback.stop(); audioPreview?.stop() }
        .sheet(isPresented: Binding(get: { studio.screenText != nil }, set: { if !$0 { studio.screenText = nil } })) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Screen Text").font(.title2)
                ScrollView { Text(studio.screenText?.isEmpty == false ? studio.screenText! : "No readable text in this frame.").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 200)
                HStack {
                    Button("Close") { studio.screenText = nil }
                    Spacer()
                    Button("Add as Description", systemImage: "text.badge.plus") {
                        cueToEdit = Segment(id: UUID().uuidString, start: studio.screenTimestamp, end: min(project.duration, studio.screenTimestamp + 3), text: studio.screenText ?? "")
                        studio.screenText = nil
                    }.disabled(studio.screenText?.isEmpty != false)
                }
            }.padding(24).frame(width: 540)
        }
        .sheet(item: $cueToEdit) { cue in
            CueEditor(cue: cue, duration: project.duration) { updated in
                var cues = project.cues.filter { $0.id != updated.id }; cues.append(updated); studio.saveCues(cues)
            }
        }
    }
}

struct TimelineView: View {
    let project: StudioProject
    let playback: PlaybackModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Label("Timeline", systemImage: "film").font(.caption); Spacer(); Text(timecode(project.duration)).font(.caption).monospacedDigit() }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(project.thumbnails, id: \.self) { path in
                            if let url = project.url(path), let image = NSImage(contentsOf: url) {
                                Image(nsImage: image).resizable().scaledToFill().frame(width: max(1,(geometry.size.width-14)/8), height: 42).clipped().accessibilityHidden(true)
                            }
                        }
                    }
                }
            }.frame(height: 42).clipShape(.rect(cornerRadius: 5))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                    ForEach(project.cues) { cue in
                        Button { playback.seek(cue.start) } label: {
                            RoundedRectangle(cornerRadius: 3).fill(.tint).overlay { Text(cue.text).font(.caption2).lineLimit(1).foregroundStyle(.white).padding(.horizontal,4) }
                        }.buttonStyle(.plain)
                            .frame(width: max(4,geometry.size.width*(cue.end-cue.start)/max(1,project.duration)))
                            .offset(x: geometry.size.width*cue.start/max(1,project.duration))
                            .accessibilityLabel("Description at \(timecode(cue.start)): \(cue.text)")
                    }
                }
            }.frame(height: 26)
        }.padding(12)
    }
}

private struct TimecodeInput: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    private func componentBinding(
        divisor: Double,
        modulus: Int? = nil,
        allowed: ClosedRange<Int>
    ) -> Binding<Int> {
        Binding {
            let whole = Int(max(0, value) / divisor)
            return modulus.map { whole % $0 } ?? whole
        } set: { newValue in
            let oldComponent = modulus.map { Int(max(0, value) / divisor) % $0 }
                ?? Int(max(0, value) / divisor)
            let clamped = min(max(newValue, allowed.lowerBound), allowed.upperBound)
            value = min(max(value + Double(clamped - oldComponent) * divisor, range.lowerBound), range.upperBound)
        }
    }

    private var milliseconds: Binding<Int> {
        Binding {
            Int((max(0, value) * 1000).rounded()) % 1000
        } set: { newValue in
            let old = Int((max(0, value) * 1000).rounded()) % 1000
            let clamped = min(max(newValue, 0), 999)
            value = min(max(value + Double(clamped - old) / 1000, range.lowerBound), range.upperBound)
        }
    }

    private var formattedValue: String {
        let totalMilliseconds = max(0, Int((value * 1000).rounded()))
        let hours = totalMilliseconds / 3_600_000
        let minutes = totalMilliseconds / 60_000 % 60
        let seconds = totalMilliseconds / 1_000 % 60
        let milliseconds = totalMilliseconds % 1_000
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.headline).accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                timePart("Hours", value: componentBinding(divisor: 3600, allowed: 0...99), width: 54, digits: 2)
                Text(":").accessibilityHidden(true)
                timePart("Minutes", value: componentBinding(divisor: 60, modulus: 60, allowed: 0...59), width: 48, digits: 2)
                Text(":").accessibilityHidden(true)
                timePart("Seconds", value: componentBinding(divisor: 1, modulus: 60, allowed: 0...59), width: 48, digits: 2)
                Text(".").accessibilityHidden(true)
                timePart("Milliseconds", value: milliseconds, width: 62, digits: 3)
            }
            Text("Timecode: \(formattedValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(label): \(formattedValue)")
        }
        .accessibilityElement(children: .contain)
    }

    private func timePart(_ name: String, value: Binding<Int>, width: CGFloat, digits: Int) -> some View {
        VStack(spacing: 4) {
            TextField(name, value: value, format: .number.precision(.integerLength(digits)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: width)
                .accessibilityLabel("\(label) \(name.lowercased())")
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct CueEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cue: Segment
    let duration: Double
    let save: (Segment) -> Void
    init(cue: Segment, duration: Double, save: @escaping (Segment) -> Void) {
        _cue = State(initialValue: cue); self.duration = duration; self.save = save
    }
    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 28) {
                    TimecodeInput(label: "Start time", value: $cue.start, range: 0...max(0, duration))
                    TimecodeInput(label: "End time", value: $cue.end, range: 0...max(0, duration))
                }
            } header: {
                Text("Timing")
            } footer: {
                Text("Enter hours, minutes, seconds, and milliseconds. End time must be after start time and within the video.")
            }
            Section {
                TextEditor(text: $cue.text)
                    .frame(height: 140)
                    .accessibilityLabel("Audio description text")
            } header: {
                Text("Description")
            } footer: {
                Text("Keep narration concise and inside a gap in dialogue. Available time: \(max(0,cue.end-cue.start), specifier: "%.3f") seconds.")
            }
            Section {
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Save Segment", systemImage: "checkmark") { save(cue); dismiss() }.keyboardShortcut(.defaultAction)
                    .disabled(cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cue.start < 0 || cue.end <= cue.start || cue.end > duration)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(cue.text.isEmpty ? "Add Audio Description Segment" : "Edit Audio Description Segment")
        .frame(width: 720, height: 520)
    }
}
