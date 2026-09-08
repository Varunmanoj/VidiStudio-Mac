import SwiftUI
import AVKit
import AVFoundation

struct ContentView: View {
    @Bindable var studio: StudioModel
    @State private var showInspector = true
    @State private var importYouTube = false
    @State private var youtubeURL = ""
    @State private var search = ""
    @State private var rename = ""
    @State private var renaming = false
    var body: some View {
        NavigationSplitView {
            List(selection: $studio.selectedID) {
                Section("Local Projects") {
                    ForEach(studio.projects.filter { search.isEmpty || $0.name.localizedStandardContains(search) }) { p in
                        Label {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(p.name).lineLimit(1)
                                Text("\(timecode(p.duration)) · \(p.cues.count) descriptions").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        } icon: { MaterialIcon(glyph: "\u{e02c}") }.tag(p.id)
                        .contextMenu {
                            Button("Rename") { studio.selectedID = p.id; rename = p.name; renaming = true }
                            Button("Move Project to Trash", role: .destructive) { studio.trashProject(p) }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search projects")
            .navigationTitle("VidiStudio")
            .navigationSplitViewColumnWidth(min: 210, ideal: 240)
            .safeAreaInset(edge: .bottom) {
                HStack { Label("On this Mac", systemImage: "internaldrive"); Spacer(); SettingsLink { Image(systemName: "gearshape") }.help("Settings").accessibilityLabel("Settings") }
                    .font(.caption).foregroundStyle(.secondary).padding()
            }
        } detail: {
            if let p = studio.selected {
                ProjectEditor(shortcutsBlocked: renaming || importYouTube || studio.error != nil, studio: studio, project: p).id(p.id)
            } else {
                ContentUnavailableView {
                    Label("Make every video accessible", systemImage: "video.badge.waveform")
                } description: {
                    Text("Import a video to create a local workspace for transcripts, audio descriptions, narration, and final exports.")
                } actions: {
                    Button("Import Video…", systemImage: "plus") { studio.importVideo() }.buttonStyle(.glassProminent)
                    Button("Open Project Folder…") { studio.openProject() }
                }
            }
        }
        .background(WindowFitter().frame(width: 0, height: 0))
        .preferredColorScheme(studio.settings.theme == "dark" ? .dark : studio.settings.theme == "light" ? .light : nil)
        .sheet(isPresented: $renaming) {
            VStack(spacing: 20) {
                TextField("Project name", text: $rename)
                HStack { Button("Cancel", role: .cancel) { renaming = false }; Button("Rename") { studio.execute("rename-project", extra: ["--name", rename]); renaming = false }.keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 420)
        }
        .sheet(isPresented: $importYouTube) {
            VStack(alignment: .leading, spacing: 20) {
                Text("New YouTube Project").font(.title2)
                TextField("YouTube video URL", text: $youtubeURL).textFieldStyle(.roundedBorder)
                Text("The project and generated results are stored locally. YouTube playback and analysis require an internet connection.").foregroundStyle(.secondary)
                HStack {
                    Button("Cancel", role: .cancel) { importYouTube = false }
                    Spacer()
                    Button("Create Project") {
                        studio.execute("import-youtube", extra: ["--url", youtubeURL, "--library", studio.settings.libraryPath])
                        importYouTube = false
                    }.disabled(youtubeURL.isEmpty).keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 520)
        }
        .inspector(isPresented: $showInspector) { ProcessingInspector(studio: studio).inspectorColumnWidth(min: 240, ideal: 270, max: 350) }
        .toolbar {
            ToolbarItem { Button("Import Video", systemImage: "plus") { studio.importVideo() }.disabled(studio.busy) }
            ToolbarItem { Button("YouTube Project", systemImage: "link") { importYouTube = true }.disabled(studio.busy) }
            ToolbarItem { Button("Open Project", systemImage: "folder") { studio.openProject() }.disabled(studio.busy) }
            ToolbarSpacer(.fixed)
            ToolbarItem { Button("Show Inspector", systemImage: "sidebar.right") { showInspector.toggle() } }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                if studio.busy { ProgressView().controlSize(.small) }
                Text(studio.message).lineLimit(2).font(.caption)
                Spacer()
                if studio.busy { Button("Cancel Processing") { studio.process?.terminate() } }
                if studio.busy { ProgressView(value: studio.progress).frame(width: 120).accessibilityLabel("Processing progress") }
                Label("Local workspace", systemImage: "externaldrive").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 18).padding(.vertical, 10)
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
                    Menu("Export Text") {
                        ForEach(["transcript", "descriptions", "combined"], id: \.self) { content in
                            Menu(content.capitalized) {
                                ForEach(["srt", "vtt", "txt", "json"], id: \.self) { format in
                                    Button(format.uppercased()) { studio.execute("export-subtitles", extra: ["--content", content, "--format", format]) }
                                }
                            }
                        }
                    }.disabled(studio.busy)
                    Button("Export Narration Audio") { studio.execute("export-audio") }.disabled(studio.busy)
                    Button("Synthesize Changed Cues") { studio.execute("synthesize-tts", extra: ["--changed"]) }.disabled(studio.busy)
                    HStack { Button("Undo Cue Edit") { studio.execute("undo-cues") }; Button("Redo") { studio.execute("redo-cues") } }.disabled(studio.busy)
                    if p.sourceType == "youtube" { Button("Attach Local Video Copy…") { studio.attachVideo() }.disabled(studio.busy) }
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
    @State private var cueToEdit: Segment?
    @State private var audioPreview: AVAudioPlayer?
    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                Group {
                    if let url = project.youtubeURL, project.source.isEmpty { YouTubePlayer(url: url, playback: playback) }
                    else { NativeVideoPlayer(player: playback.player) }
                }.frame(minWidth: 0, idealWidth: 700, maxWidth: .infinity, minHeight: 220, idealHeight: 340, maxHeight: .infinity).background(.black)
                TimelineView(project: project, playback: playback)
            }.frame(minHeight: 310)
            VStack(spacing: 0) {
                HStack {
                    Picker("Editor section", selection: $tab) {
                        Text("Descriptions").tag("descriptions"); Text("Transcript").tag("transcript"); Text("Summary").tag("summary")
                    }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 410)
                    Spacer()
                    Button("Read Frame Text", systemImage: "text.viewfinder") { studio.execute("capture-frame", extra: ["--timestamp", String(playback.time)]) }.labelStyle(.iconOnly).help("Extract text from the current video frame").disabled(studio.busy)
                    Toggle("Narration", isOn: $playback.narrationEnabled).toggleStyle(.button).help("Play generated descriptions in sync with video")
                    Toggle("Follow", isOn: $studio.settings.followTranscript).toggleStyle(.button).help("Follow the active transcript or description")
                    if tab == "descriptions" {
                        Button("Add Cue", systemImage: "plus") {
                            let start = max(0, min(playback.time, project.duration - 0.1))
                            cueToEdit = Segment(id: UUID().uuidString, start: start, end: min(start+3,project.duration), text: "")
                        }.disabled(studio.busy)
                    }
                }.padding(12)
                Divider()
                if tab == "summary" {
                    ScrollView { Text(project.summary.isEmpty ? "Generate a summary after transcription to capture the story and visual context." : project.summary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(20) }
                } else {
                    let segments = tab == "descriptions" ? project.cues : project.transcript
                    if segments.isEmpty {
                        ContentUnavailableView(tab == "descriptions" ? "Describe what matters" : "Your transcript appears here", systemImage: tab == "descriptions" ? "text.below.photo" : "text.bubble", description: Text(tab == "descriptions" ? "Generate descriptions from the inspector or add a cue manually." : "Use Transcribe Video in the inspector to begin."))
                    } else {
                        ScrollViewReader { reader in
                        List(segments) { cue in
                            HStack(alignment: .top, spacing: 16) {
                                Button { playback.seek(cue.start) } label: {
                                    VStack { Text(timecode(cue.start)); Text(timecode(cue.end)).foregroundStyle(.secondary) }.monospacedDigit().font(.caption)
                                }.buttonStyle(.plain).help("Seek to \(timecode(cue.start))")
                                Text(cue.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                if tab == "descriptions" {
                                    if cue.audio != nil && cue.audioText == cue.text { Image(systemName: "waveform.circle.fill").foregroundStyle(.green).accessibilityLabel("Narration ready") }
                                    Button("Edit", systemImage: "pencil") { cueToEdit = cue }.labelStyle(.iconOnly).disabled(studio.busy)
                                    Menu {
                                        if let audio = cue.audio, let url = project.url(audio) { Button("Preview Narration") { audioPreview = try? AVAudioPlayer(contentsOf: url); audioPreview?.play() } }
                                        Button("Rewrite to Fit") { studio.execute("rewrite-cue", extra: ["--segment", cue.id]) }
                                        Button("Synthesize This Cue") { studio.execute("synthesize-tts", extra: ["--segment", cue.id]) }
                                        Button("Delete Cue", role: .destructive) { studio.saveCues(project.cues.filter { $0.id != cue.id }) }
                                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().disabled(studio.busy).accessibilityLabel("Cue actions")
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
            }.frame(minHeight: 220)
        }
        .focusedSceneValue(\.editorShortcuts, shortcutsBlocked || studio.busy || cueToEdit != nil || studio.screenText != nil ? nil : EditorShortcutActions(run: { action in
            switch action {
            case "play": playback.togglePlayback()
            case "back": playback.seek(max(0, playback.time - 5))
            case "forward": playback.seek(min(project.duration, playback.time + 5))
            case "narration": playback.narrationEnabled.toggle()
            case "follow": studio.settings.followTranscript.toggle()
            case "descriptions", "transcript", "summary": tab = action
            case "add":
                let start = max(0, min(playback.time, project.duration - 0.1))
                cueToEdit = Segment(id: UUID().uuidString, start: start, end: min(start + 3, project.duration), text: "")
            case "undo": studio.execute("undo-cues")
            case "redo": studio.execute("redo-cues")
            default: break
            }
        }))
        .navigationTitle(project.name)
        .onChange(of: playback.duration) { _, duration in
            if !studio.busy, duration > 0, abs(duration - project.duration) > 0.5 { studio.execute("update-metadata", extra: ["--duration", String(duration)]) }
        }
        .onChange(of: playback.time) { _, _ in playback.syncNarration(project) }
        .onChange(of: playback.playing) { _, _ in playback.syncNarration(project) }
        .onChange(of: playback.narrationEnabled) { _, _ in playback.syncNarration(project) }
        .onAppear { playback.observe(); if !project.source.isEmpty, let url = project.url(project.source) { playback.player.replaceCurrentItem(with: AVPlayerItem(url: url)) } }
        .onDisappear { playback.stop(); audioPreview?.stop() }
        .sheet(isPresented: Binding(get: { studio.screenText != nil }, set: { if !$0 { studio.screenText = nil } })) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Screen Text").font(.title2)
                ScrollView { Text(studio.screenText?.isEmpty == false ? studio.screenText! : "No readable text in this frame.").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 200)
                HStack {
                    Button("Close") { studio.screenText = nil }
                    Spacer()
                    Button("Add as Description") {
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

struct CueEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cue: Segment
    let duration: Double
    let save: (Segment) -> Void
    init(cue: Segment, duration: Double, save: @escaping (Segment) -> Void) {
        _cue = State(initialValue: cue); self.duration = duration; self.save = save
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Audio Description").font(.title2.bold())
            HStack {
                TextField("Start (seconds)", value: $cue.start, format: .number)
                TextField("End (seconds)", value: $cue.end, format: .number)
            }
            TextEditor(text: $cue.text).frame(height: 140).border(.quaternary).accessibilityLabel("Description text")
            Text("Keep narration concise and inside a gap in dialogue. Available time: \(max(0,cue.end-cue.start), specifier: "%.1f") seconds.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer(); Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Cue") { save(cue); dismiss() }.keyboardShortcut(.defaultAction)
                    .disabled(cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cue.start < 0 || cue.end <= cue.start || cue.end > duration)
            }
        }.padding(24).frame(width: 520)
    }
}
