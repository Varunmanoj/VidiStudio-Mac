import AppKit
import SwiftUI

@MainActor @Observable final class YouTubeBrowserActions {
    var layout = "list"
    var selected = false
    var selectedCanOpen = false
    var openTitle = "Open in Editor"
    var ready = false
    var moreVideos = false
    var morePlaylists = false
    var handler: ((String) -> Void)?
    func canRun(_ id: String) -> Bool {
        switch id {
        case "youtube-accounts", "youtube-list", "youtube-table": return true
        case "youtube-open-editor", "youtube-open-direct": return selectedCanOpen && ready
        case "youtube-open-browser", "youtube-open-studio": return selected
        case "youtube-load-videos": return ready && moreVideos
        case "youtube-load-playlists": return ready && morePlaylists
        default: return ready
        }
    }
    func run(_ id: String) { if canRun(id) { handler?(id) } }
}
private struct YouTubeBrowserFocusKey: FocusedValueKey { typealias Value = YouTubeBrowserActions }
extension FocusedValues {
    var youtubeBrowser: YouTubeBrowserActions? {
        get { self[YouTubeBrowserFocusKey.self] }
        set { self[YouTubeBrowserFocusKey.self] = newValue }
    }
}

struct VideoBrowserRowCheckbox: View {
    let title: String
    let id: String
    @Binding var selection: String?

    var body: some View {
        Toggle("Select " + title, isOn: Binding(
            get: { selection == id },
            set: { checked in
                if checked { selection = id }
                else if selection == id { selection = nil }
            }
        ))
        .toggleStyle(.checkbox)
        .labelsHidden()
        .accessibilityLabel("Select " + title)
    }
}

struct VideoBrowserLoadingIndicator: View {
    let message: String
    var body: some View {
        VStack(spacing: 8) {
            ProgressView().progressViewStyle(.circular).accessibilityHidden(true)
            Text(message).multilineTextAlignment(.center)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

@MainActor struct YouTubeAccountsView: View {
    @Environment(\.dismiss) private var dismiss
    var showsDone = false
    @State private var service = YouTubeService.shared
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var disconnecting: YouTubeConnection?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("YouTube Accounts").font(.title2).accessibilityAddTraits(.isHeader).accessibilityHeading(.h1); Spacer(); if showsDone { Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) } }
            ForEach(service.connections) { connection in
                HStack {
                    AsyncImage(url: URL(string: connection.photo)) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "person.circle") }.frame(width: 40, height: 40).accessibilityLabel("Google profile photo")
                    VStack(alignment: .leading) {
                        Text(connection.name); Text(connection.email).foregroundStyle(.secondary)
                        Text("YouTube channel: \(connection.channelName)")
                    }
                    Spacer()
                    Button(service.selectedID == connection.id ? "Selected" : "Switch Account") { service.selectedID = connection.id }.disabled(service.selectedID == connection.id || service.signingIn)
                    Button("Disconnect YouTube Account…", systemImage: "person.crop.circle.badge.minus") { disconnecting = connection }.disabled(service.signingIn)
                }
                .contextMenu {
                    Button("Switch Account", systemImage: "person.crop.circle.badge.checkmark") { service.selectedID = connection.id }.disabled(service.selectedID == connection.id || service.signingIn)
                    Button("Disconnect YouTube Account…", systemImage: "person.crop.circle.badge.minus") { disconnecting = connection }.disabled(service.signingIn)
                }
            }
            HStack {
                Button("Add Account", systemImage: "person.crop.circle.badge.plus") { task = Task { do { try await service.signIn() } catch is CancellationError {} catch { self.error = error.localizedDescription } } }.disabled(service.signingIn)
                if service.signingIn { ProgressView("Waiting for Google sign-in"); Button("Cancel Sign-in", systemImage: "xmark.circle") { task?.cancel() } }
            }
            .contextMenu {
                Button("Add Account", systemImage: "person.crop.circle.badge.plus") { task = Task { do { try await service.signIn() } catch is CancellationError {} catch { self.error = error.localizedDescription } } }.disabled(service.signingIn)
                Button("Cancel Sign-in", systemImage: "xmark.circle") { task?.cancel() }.disabled(!service.signingIn)
            }
            if let error { Text(error).foregroundStyle(.red).accessibilityAddTraits(.isStaticText) }
            Link("Manage Google account access", destination: URL(string: "https://myaccount.google.com/connections")!)
                .contextMenu { Button("Manage Google account access", systemImage: "arrow.up.right.square") { NSWorkspace.shared.open(URL(string: "https://myaccount.google.com/connections")!) } }
            Link("YouTube Terms of Service", destination: URL(string: "https://www.youtube.com/t/terms")!)
                .contextMenu { Button("YouTube Terms of Service", systemImage: "doc.text") { NSWorkspace.shared.open(URL(string: "https://www.youtube.com/t/terms")!) } }
        }
        .padding()
        .confirmationDialog("Disconnect this YouTube account?", isPresented: Binding(get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }), titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                guard let value = disconnecting else { return }; disconnecting = nil
                do { try service.disconnect(value) } catch { self.error = error.localizedDescription }
            }
        } message: { Text("This removes the YouTube account from this Mac. Your Google Cloud connection and projects stay available.") }
        .onDisappear { task?.cancel() }
    }
}

@MainActor struct YouTubeBrowserView: View {
    @Bindable var studio: StudioModel
    var onChooseVideo: ((YouTubeProjectPreview) -> Void)? = nil
    var onOpenProject: ((StudioProject) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    private var chooseMode: Bool { onChooseVideo != nil }
    private var openTitle: String { chooseMode ? "Choose Video" : "Open in Editor" }
    private var openIcon: String { chooseMode ? "checkmark.circle" : "square.and.arrow.down" }
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var service = YouTubeService.shared
    @State private var videos: [YouTubeVideo] = []
    @State private var playlists: [YouTubePlaylist] = []
    @State private var playlist = ""
    @State private var nextVideoPage = ""
    @State private var nextPlaylistPage = ""
    @State private var search = ""
    @State private var visibility = "all"
    @State private var sort = "newest"
    @State private var loading = false
    @State private var loadingKind = "videos"
    private var loadingMessage: String {
        switch loadingKind {
        case "more-videos": return "Loading more videos…"
        case "playlists": return "Loading playlists…"
        case "more-playlists": return "Loading more playlists…"
        case "opening": return "Fetching video details…"
        default: return "Loading videos…"
        }
    }
    @State private var error: String?
    @State private var showingAccounts = false
    @State private var chooseCaptions = false
    @State private var request: Task<Void, Never>?
    @State private var generation = UUID()
    @AppStorage("youtubeVideoLayout") private var layout = "list"
    @State private var selectedVideoID: String?
    @State private var selectingVideos = false
    @State private var actions = YouTubeBrowserActions()
    private var filtered: [YouTubeVideo] {
        videos.filter { (visibility == "all" || $0.visibility == visibility) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }.sorted {
            switch sort { case "title": return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            case "duration": return $0.duration < $1.duration
            case "views": return (UInt64($0.viewCount ?? "") ?? 0) > (UInt64($1.viewCount ?? "") ?? 0)
            case "oldest": return $0.publishedAt < $1.publishedAt
            default: return $0.publishedAt > $1.publishedAt }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My YouTube Videos").font(.title2.bold()).accessibilityAddTraits(.isHeader).accessibilityHeading(.h1)
            HStack {
                Picker("Google account and channel", selection: $service.selectedID) {
                    Text("Choose an account").tag("")
                    ForEach(service.connections) { Text($0.label).tag($0.id) }
                }
                Button("YouTube Accounts…") { showingAccounts = true }
                Button("Refresh") { reload() }.disabled(service.selected == nil || loading)
                Button(chooseMode ? "Cancel" : "Done") {
                    if chooseMode { dismiss() }
                    else { dismissWindow(id: "youtube-browser") }
                }.keyboardShortcut(.cancelAction)
            }
            if let connection = service.selected {
                Text("\(connection.email) · YouTube channel: \(connection.channelName)").foregroundStyle(.secondary)
                HStack {
                    Picker("Playlist", selection: $playlist) {
                        Text("All uploads").tag("")
                        ForEach(playlists) { Text("\($0.title) · \($0.visibility) · \($0.count.map(String.init) ?? "Unknown") videos").tag($0.id) }
                    }
                    if !nextPlaylistPage.isEmpty {
                        Button("Load More Playlists") { loadPlaylists() }.disabled(loading)
                    }
                }
                if let selected = playlists.first(where: { $0.id == playlist }) {
                    Text(selected.description); Text("Published: \(selected.publishedAt)").foregroundStyle(.secondary)
                }
                HStack {
                    TextField("Search loaded video titles", text: $search)
                    Picker("Visibility", selection: $visibility) { Text("All").tag("all"); Text("Public").tag("public"); Text("Unlisted").tag("unlisted"); Text("Private").tag("private") }
                    Picker("Sort", selection: $sort) { Text("Newest").tag("newest"); Text("Oldest").tag("oldest"); Text("Title").tag("title"); Text("Duration").tag("duration"); Text("Views").tag("views") }
                }
                Picker("Video layout", selection: $layout) {
                    Text("List View").tag("list")
                    Text("Table View").tag("table")
                }.pickerStyle(.segmented).fixedSize()
                Text("Search, filters, and sorting apply to loaded videos. Load more to include additional results.").font(.caption)
                Group {
                    if layout == "table" { youtubeTable }
                    else {
                List(filtered, selection: $selectedVideoID) { video in
                    HStack {
                        if selectingVideos {
                            VideoBrowserRowCheckbox(title: video.title, id: video.id, selection: $selectedVideoID)
                        }
                        AsyncImage(url: URL(string: video.thumbnailURL)) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "film") }.frame(width: 100, height: 60).accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(video.title).font(.headline); Text(video.detail).accessibilityLabel(video.spokenDetail)
                            Text("Published: \(video.publishedAt) · Views: \(video.viewCount ?? "Unavailable") · Likes: \(video.likeCount ?? "Unavailable") · Comments: \(video.commentCount ?? "Unavailable")").font(.caption)
                            Text(video.captionsAvailable ? "Captions available" : "Caption availability not reported").font(.caption)
                        }
                        Spacer()
                        Button(openTitle, systemImage: openIcon) { openInEditor(video, choose: chooseMode) }.disabled(!canRunOpeningAction(video))
                        Button("Open in YouTube", systemImage: "arrow.up.right.square") { openInBrowser(video) }
                    }.tag(video.id)
                    .contextMenu { videoActions(for: video) }
                }
                    }
                }
                .overlay(alignment: .center) {
                    if loading { VideoBrowserLoadingIndicator(message: loadingMessage) }
                }
                HStack {
                    Menu("Actions", systemImage: "ellipsis.circle") {
                        videoActions(for: filtered.first { $0.id == selectedVideoID })
                    }
                    Button(openTitle, systemImage: openIcon) { actions.run("youtube-open-editor") }.disabled(!actions.canRun("youtube-open-editor"))
                    Button("Open in YouTube", systemImage: "arrow.up.right.square") { actions.run("youtube-open-browser") }.disabled(!actions.canRun("youtube-open-browser"))
                    Button("Open in YouTube Studio", systemImage: "pencil") { actions.run("youtube-open-studio") }.disabled(!actions.canRun("youtube-open-studio"))
                }
                if !chooseMode {
                    Toggle("Choose YouTube captions after opening", isOn: $chooseCaptions)
                        .contextMenu {
                            Toggle(isOn: $chooseCaptions) {
                                Label("Choose YouTube captions after opening", systemImage: "captions.bubble")
                            }
                        }
                }
                if !nextVideoPage.isEmpty {
                    Button("Load More Videos") { loadVideos(reset: false) }.disabled(loading)
                }
                if videos.isEmpty && !loading { Text("No uploaded videos were returned for this channel or playlist.") }
            } else { Text("Add a Google account to browse its uploaded videos and playlists.") }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .padding().frame(minWidth: 850, minHeight: 580)
        .alert("Private Video Cannot Be Opened", isPresented: Binding(get: { error?.hasPrefix("Private Video Cannot Be Opened") == true }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }

        .sheet(isPresented: $showingAccounts) { YouTubeAccountsView(showsDone: true).frame(minWidth: 760, minHeight: 300) }
        .onChange(of: service.selectedID) { _, _ in reload() }
        .onChange(of: playlist) { _, _ in loadVideos(reset: true) }
        .focusedSceneValue(\.youtubeBrowser, actions)
        .onAppear {
            actions.handler = { id in
                switch id {
                case "youtube-list": layout = "list"
                case "youtube-table": layout = "table"
                case "youtube-accounts": showingAccounts = true
                case "youtube-refresh-list": reload()
                case "youtube-load-videos": loadVideos(reset: false)
                case "youtube-load-playlists": loadPlaylists()
                case "youtube-open-editor": if let video = filtered.first(where: { $0.id == selectedVideoID }) { openInEditor(video, choose: chooseMode) }
                case "youtube-open-direct": if let video = filtered.first(where: { $0.id == selectedVideoID }) { openInEditor(video, choose: false) }
                case "youtube-open-browser": if let video = filtered.first(where: { $0.id == selectedVideoID }) { openInBrowser(video) }
                case "youtube-open-studio": if let video = filtered.first(where: { $0.id == selectedVideoID }) { openInYouTubeStudio(video) }
                default: break
                }
            }
            reload(); updateActions()
        }
        .onChange(of: layout) { _, _ in updateActions() }
        .onChange(of: selectedVideoID) { _, _ in updateActions() }
        .onChange(of: loading) { _, _ in updateActions() }
        .onChange(of: studio.busy) { _, _ in updateActions() }
        .onChange(of: studio.settings.vertexConnected) { _, _ in updateActions() }
        .onChange(of: studio.settings.vertexProject) { _, _ in updateActions() }
        .onChange(of: service.googleConnectionRevision) { _, _ in updateActions() }
        .onChange(of: service.connections.map(\.id)) { _, _ in updateActions() }
        .onChange(of: nextVideoPage) { _, _ in updateActions() }
        .onChange(of: nextPlaylistPage) { _, _ in updateActions() }
        .onChange(of: search) { _, _ in selectedVideoID = nil; updateActions() }
        .onChange(of: visibility) { _, _ in selectedVideoID = nil; updateActions() }

        .onDisappear { request?.cancel(); generation = UUID() }
    }
    private var youtubeTable: some View {
        Table(filtered, selection: $selectedVideoID) {
            TableColumnForEach(selectingVideos ? [0] : [], id: \.self) { _ in
                TableColumn("Select") { video in
                    VideoBrowserRowCheckbox(title: video.title, id: video.id, selection: $selectedVideoID)
                }.width(55)
            }
            TableColumn("Thumbnail") { video in
                AsyncImage(url: URL(string: video.thumbnailURL)) { image in image.resizable().scaledToFit() }
                    placeholder: { Image(systemName: "film").foregroundStyle(.secondary) }
                    .frame(width: 80, height: 45).accessibilityHidden(true)
            }.width(90)
            TableColumn("Title", value: \.title).width(min: 180, ideal: 260)
            TableColumn("Channel", value: \.channelTitle).width(min: 100, ideal: 150)
            TableColumn("Visibility") { Text($0.visibility.capitalized) }.width(85)
            TableColumn("Duration") { Text($0.durationLabel).monospacedDigit().accessibilityLabel("Duration: \($0.spokenDuration)") }.width(120)
            TableColumn("Published") { Text($0.publishedLabel) }.width(min: 100, ideal: 140)
            Group {
                TableColumn("Views") { (video: YouTubeVideo) in Text(video.viewCount ?? "Unavailable") }.width(85)
                TableColumn("Likes") { (video: YouTubeVideo) in Text(video.likeCount ?? "Unavailable") }.width(85)
                TableColumn("Comments") { (video: YouTubeVideo) in Text(video.commentCount ?? "Unavailable") }.width(90)
                TableColumn("Captions") { (video: YouTubeVideo) in Text(video.captionsAvailable ? "Available" : "Not reported") }.width(105)
            }
            TableColumn("Actions") { video in
                Menu("Actions", systemImage: "ellipsis.circle") { videoActions(for: video) }
                    .accessibilityLabel("Actions for " + video.title)
            }.width(106)
        }.accessibilityLabel("YouTube videos table")
        .contextMenu(forSelectionType: String.self) { selection in
            videoActions(for: filtered.first { selection.contains($0.id) })
        }
    }

    @ViewBuilder private func videoActions(for target: YouTubeVideo?) -> some View {
        Toggle(isOn: $selectingVideos) { Label("Select", systemImage: "checklist") }
            .disabled(loading || filtered.isEmpty)
        if let target {
            if chooseMode {
                Button("Choose Video", systemImage: "checkmark.circle") { openInEditor(target, choose: true) }
                    .disabled(!canRunOpeningAction(target))
            }
            Button("Open in Editor", systemImage: "square.and.arrow.down") { openInEditor(target, choose: false) }
                .disabled(!canRunOpeningAction(target))
            Button("Open in YouTube", systemImage: "arrow.up.right.square") { openInBrowser(target) }
            Button("Open in YouTube Studio", systemImage: "pencil") { openInYouTubeStudio(target) }
        }
    }

    private func updateActions() {
        actions.layout = layout
        actions.openTitle = openTitle
        let selected = filtered.first { $0.id == selectedVideoID }
        actions.selected = selected != nil
        actions.selectedCanOpen = selected.map(canOpen) == true
        actions.ready = service.selected != nil && !loading && !studio.busy
        actions.moreVideos = !nextVideoPage.isEmpty; actions.morePlaylists = !nextPlaylistPage.isEmpty
    }
    private func openInBrowser(_ video: YouTubeVideo) {
        selectedVideoID = video.id
        if let url = URL(string: video.url) { NSWorkspace.shared.open(url) }
    }
    private func openInYouTubeStudio(_ video: YouTubeVideo) {
        guard filtered.contains(where: { $0.id == video.id }),
              let id = StudioModel.youtubeVideoID(from: video.url),
              let url = URL(string: "https://studio.youtube.com/video/\(id)/edit") else { return }
        selectedVideoID = video.id
        NSWorkspace.shared.open(url)
    }
    private func canOpen(_ video: YouTubeVideo) -> Bool {
        let owner = service.privateConnection(video.channelID, settings: studio.settings)
        let ownsPrivate = owner != nil && owner?.id == service.selected?.id
        return (try? video.requireAvailable(allowPrivate: ownsPrivate)) != nil
    }

    private func canRunOpeningAction(_ video: YouTubeVideo) -> Bool {
        !studio.busy && !loading && service.selected != nil && canOpen(video)
    }

    private func openInEditor(_ video: YouTubeVideo, choose: Bool) {
        guard canRunOpeningAction(video), filtered.contains(where: { $0.id == video.id }),
              let connection = service.selected else { return }
        selectedVideoID = video.id
        let stamp = generation
        loadingKind = "opening"
        loading = true
        error = nil
        request = Task {
            defer { if generation == stamp { loading = false } }
            do {
                var current = try await service.video(video.id, connectionID: connection.id)
                current.openedFromPlaylist = playlists.first { $0.id == playlist }
                guard !Task.isCancelled, generation == stamp, service.selectedID == connection.id else { return }
                try current.requireAvailable(allowPrivate: canOpen(current))
                if choose, let onChooseVideo {
                    let preview = await YouTubeProjectPreviewFetcher.selectedVideo(current)
                    guard !Task.isCancelled, generation == stamp, service.selectedID == connection.id else { return }
                    onChooseVideo(preview)
                    dismiss()
                    return
                }
                studio.openYouTubeVideo(current) { project in
                    guard let project else { return }
                    if let onOpenProject {
                        onOpenProject(project)
                        dismiss()
                        return
                    }
                    openWindow(id: "project-editor", value: project.id)
                    if chooseCaptions { studio.youtubeDetailAction = "youtube-captions"; openWindow(id: "youtube-details") }
                }
            } catch { if !Task.isCancelled, generation == stamp { self.error = error.localizedDescription } }
        }
    }
    private func reload() {
        request?.cancel(); generation = UUID(); selectedVideoID = nil; loading = false; videos = []; playlists = []; nextPlaylistPage = ""; nextVideoPage = ""; playlist = ""
        guard service.selected != nil else { return }
        loadPlaylists(andVideos: true)
    }
    private func loadPlaylists(andVideos: Bool = false) {
        guard let connection = service.selected else { return }
        let stamp = generation, page = nextPlaylistPage
        loadingKind = andVideos || page.isEmpty ? "playlists" : "more-playlists"
        loading = true; error = nil
        request = Task {
            do {
                let (items, next) = try await service.playlists(page: page, connectionID: connection.id)
                guard !Task.isCancelled, generation == stamp, service.selectedID == connection.id else { return }
                playlists += items; nextPlaylistPage = next; loading = false
                if andVideos { loadVideos(reset: true) }
            } catch { if generation == stamp { self.error = error.localizedDescription; loading = false } }
        }
    }
    private func loadVideos(reset: Bool) {
        guard let connection = service.selected else { return }
        request?.cancel(); generation = UUID(); let stamp = generation
        if reset { videos = []; nextVideoPage = "" }
        let page = nextVideoPage, list = playlist.isEmpty ? connection.uploads : playlist
        guard !list.isEmpty else { loading = false; return }
        loadingKind = reset ? "videos" : "more-videos"
        loading = true; error = nil
        request = Task {
            do {
                let (items, next) = try await service.videos(playlist: list, page: page, connectionID: connection.id)
                guard !Task.isCancelled, generation == stamp, service.selectedID == connection.id else { return }
                let existing = Set(videos.map(\.id)); videos += items.filter { !existing.contains($0.id) }; nextVideoPage = next
            } catch { if !Task.isCancelled && generation == stamp { self.error = error.localizedDescription } }
            if generation == stamp { loading = false }
        }
    }
}

@MainActor struct YouTubeDetailsView: View {
    @Bindable var studio: StudioModel
    let project: StudioProject
    var startWithCaptions = false
    @State private var video: YouTubeVideo?
    @State private var captions: [YouTubeCaption] = []
    @State private var error: String?
    @State private var loading = false
    @State private var account = YouTubeService.shared.selectedID
    @State private var deletingData = false
    @State private var replacing: YouTubeCaption?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YouTube Details").font(.title2).accessibilityAddTraits(.isHeader).accessibilityHeading(.h1)
            if let v = video {
                Text(v.title).font(.headline); Text(v.detail).accessibilityLabel(v.spokenDetail); Text(v.description)
                Text("Published: \(v.publishedAt)\nViews: \(v.viewCount ?? "Unavailable") · Likes: \(v.likeCount ?? "Unavailable") · Comments: \(v.commentCount ?? "Unavailable")\nLanguage: \(v.language ?? "Unavailable") · Audio language: \(v.audioLanguage ?? "Unavailable")\nCategory: \(v.categoryID ?? "Unavailable") · Embedding: \(v.embeddable.map { $0 ? "Allowed" : "Not allowed" } ?? "Unavailable")\nProcessing: \(v.uploadStatus ?? "Unavailable") · Live status: \(v.liveStatus ?? "Unavailable")\nTags: \(v.tags.joined(separator: ", "))").textSelection(.enabled)
            }
            Picker("Caption account", selection: $account) { Text("Choose an account").tag(""); ForEach(YouTubeService.shared.connections) { Text($0.label).tag($0.id) } }
            HStack {
                Button("Refresh Details") { Task { await refresh() } }.disabled(loading)
                Button("Import YouTube Captions…") { Task { await listCaptions() } }.disabled(loading || account.isEmpty || studio.busy)
            }
            ForEach(captions) { caption in
                Button(caption.label) {
                    if project.hasGeneratedTranscript { replacing = caption } else { Task { await download(caption, replace: false) } }
                }.disabled(loading || studio.busy || caption.status != "serving")
            }
            if loading { VideoBrowserLoadingIndicator(message: "Loading YouTube information…").frame(maxWidth: .infinity) }
            if let error { Text(error).foregroundStyle(.red) }
            Button("Delete Stored YouTube Data…", role: .destructive) { deletingData = true }.disabled(studio.busy)
            Text("Caption downloads require permission to edit this video. Imports change the local VidiStudio transcript only.").font(.caption)
        }.padding().frame(minWidth: 650)
        .confirmationDialog("Delete stored YouTube data for this project?", isPresented: $deletingData, titleVisibility: .visible) {
            Button("Delete Stored YouTube Data", role: .destructive) { studio.execute("clear-youtube-data", project: project); video = nil; captions = [] }
        } message: { Text("Removes fetched details, downloaded caption copies, imported YouTube caption rows (including edits to those rows), and transcript history. Other manually created transcript rows remain. Nothing is deleted on YouTube.") }
        .task { await refresh(); if startWithCaptions && !account.isEmpty { await listCaptions() } }
        .onChange(of: account) { _, _ in captions = [] }
        .confirmationDialog("Replace this project's transcript?", isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } }), titleVisibility: .visible) {
            Button("Replace Transcript", role: .destructive) { guard let caption = replacing else { return }; replacing = nil; Task { await download(caption, replace: true) } }
        } message: { Text("Your current transcript will be replaced by the selected YouTube caption track. Review description timing afterward.") }
    }
    private func refresh() async {
        guard let url = project.youtubeURL, let id = StudioModel.youtubeVideoID(from: url) else { return }
        loading = true; error = nil; defer { loading = false }
        do {
            let value = try await YouTubeService.shared.projectVideo(id, privateChannelID: project.privateYouTubeChannel, settings: studio.settings)
            try value.requireAvailable(allowPrivate: project.privateYouTubeChannel != nil)
            video = value
            studio.saveYouTubeMetadata(value, project: project)
        }
        catch { self.error = error.localizedDescription }
    }
    private func listCaptions() async {
        guard let id = project.youtubeURL.flatMap(StudioModel.youtubeVideoID) else { return }
        let selected = account; loading = true; error = nil; defer { loading = false }
        do { let value = try await YouTubeService.shared.captions(videoID: id, connectionID: selected); if account == selected { captions = value; if value.isEmpty { error = "No caption tracks were returned for this video." } } }
        catch { self.error = error.localizedDescription }
    }
    private func download(_ caption: YouTubeCaption, replace: Bool) async {
        let selected = account; loading = true; error = nil; defer { loading = false }
        do {
            let data = try await YouTubeService.shared.download(caption, connectionID: selected)
            guard account == selected else { return }
            studio.importYouTubeCaption(data, caption: caption, project: project, replace: replace)
        } catch { self.error = error.localizedDescription }
    }
}

extension StudioProject {
    var youtubeWatchURL: URL? {
        guard let id = youtubeURL.flatMap(StudioModel.youtubeVideoID) else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(id)")
    }
}
extension StudioModel {
    func openYouTubeInBrowser(_ project: StudioProject) {
        guard let url = project.youtubeWatchURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openYouTubeVideo(_ video: YouTubeVideo, name: String? = nil, completion: @escaping (StudioProject?) -> Void) {
        do {
            try video.requireAvailable(allowPrivate: YouTubeService.shared.privateConnection(video.channelID, settings: settings) != nil)
            if let existing = existingProject(forYouTubeURL: video.url) { selectedID = existing.id; completion(existing); return }
            let metadata = try temporaryYouTubeFile(try JSONEncoder().encode(video), extension: "json")
            let nameArgument = name.map { ["--name", $0] } ?? []
            execute("import-youtube", extra: ["--url", video.url, "--library", settings.libraryPath, "--youtube-metadata", metadata.path] + nameArgument,
                    cleanupURL: metadata, completion: completion)
        } catch { self.error = error.localizedDescription; completion(nil) }
    }
    func temporaryYouTubeFile(_ data: Data, extension suffix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-youtube-\(UUID().uuidString).\(suffix)")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }
    func saveYouTubeMetadata(_ video: YouTubeVideo, project: StudioProject) {
        guard !busy else { return }
        do {
            let file = try temporaryYouTubeFile(try JSONEncoder().encode(video), extension: "json")
            execute("update-youtube-metadata", extra: ["--youtube-metadata", file.path], project: project, cleanupURL: file)
        } catch { self.error = error.localizedDescription }
    }
    func importYouTubeCaption(_ data: Data, caption: YouTubeCaption, project: StudioProject, replace: Bool) {
        guard !busy else { return }
        do {
            let file = try temporaryYouTubeFile(data, extension: "srt")
            let provenance: [String: String] = ["videoID": project.youtubeURL.flatMap(Self.youtubeVideoID) ?? "", "trackID": caption.id, "language": caption.language, "name": caption.name, "trackKind": caption.kind]
            let info = try temporaryYouTubeFile(JSONSerialization.data(withJSONObject: provenance), extension: "json")
            execute("import-transcript", extra: ["--input", file.path, "--caption-provenance", info.path] + (replace ? ["--replace-existing"] : []), project: project, cleanupURL: file) { _ in try? FileManager.default.removeItem(at: info) }
        } catch { self.error = error.localizedDescription }
    }
    func runYouTube(_ command: String) {
        switch command {
        case "youtube-browser": showingYouTubeBrowser = true
        case "youtube-details", "youtube-refresh", "youtube-captions": showingYouTubeDetails = true
        default: break
        }
    }
}
