import SwiftUI

/// Downloads a staged transcript; the containing import dialog owns validation and writes.
struct YouTubeCaptionDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    let project: StudioProject
    let selected: (Data, YouTubeCaption) -> Void
    @State private var service = YouTubeService.shared
    @State private var account = YouTubeService.shared.selectedID
    @State private var tracks: [YouTubeCaption] = []
    @State private var loading = false
    @State private var progressMessage = "Loading caption tracks…"
    @State private var issue: String?
    @State private var request: Task<Void, Never>?
    @State private var showingAccounts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Download YouTube Captions").font(.title2).accessibilityAddTraits(.isHeader).accessibilityHeading(.h1)
            Picker("Caption account", selection: $account) {
                Text("Choose an account").tag("")
                ForEach(service.connections) { Text($0.label).tag($0.id) }
            }.disabled(loading)
            Button("YouTube Accounts…") { showingAccounts = true }.disabled(loading)
            Button("Load Caption Tracks") { request = Task { await load() } }.disabled(loading || account.isEmpty)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(tracks) { track in
                        Button(track.label) { request = Task { await download(track) } }
                            .disabled(loading || track.status != "serving")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 100)
            if loading { ProgressView(progressMessage) }
            if let issue { Text(issue).foregroundStyle(.red).textSelection(.enabled) }
            Text("Caption downloads require video-edit permission. Caption availability does not guarantee download access.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel", role: .cancel) { request?.cancel(); dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(20).frame(width: 600, height: 470)
        .sheet(isPresented: $showingAccounts) { YouTubeAccountsView(showsDone: true) }
        .onChange(of: account) { _, _ in tracks = []; issue = nil }
        .onChange(of: service.selectedID) { _, id in account = id }
        .onDisappear { request?.cancel() }
    }
    private func load() async {
        guard let id = project.youtubeURL.flatMap(StudioModel.youtubeVideoID) else { return }
        let connection = account
        progressMessage = "Loading YouTube caption tracks…"
        loading = true; issue = nil; defer { loading = false }
        do {
            let result = try await service.captions(videoID: id, connectionID: connection)
            try Task.checkCancellation()
            guard connection == account else { return }
            tracks = result
            if result.isEmpty { issue = "No caption tracks were returned for this video." }
        } catch is CancellationError {} catch { issue = error.localizedDescription }
    }
    private func download(_ track: YouTubeCaption) async {
        let connection = account
        progressMessage = "Downloading YouTube captions…"
        loading = true; issue = nil; defer { loading = false }
        do {
            let data = try await service.download(track, connectionID: connection)
            try Task.checkCancellation()
            guard connection == account else { return }
            selected(data, track); dismiss()
        } catch is CancellationError {} catch { issue = error.localizedDescription }
    }
}
