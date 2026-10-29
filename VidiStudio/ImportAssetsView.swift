import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Shared formatting

func importClock(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "00:00:00.000" }
    let milliseconds = Int((seconds * 1000).rounded())
    return String(format: "%02d:%02d:%02d.%03d",
                  milliseconds / 3_600_000, milliseconds / 60_000 % 60,
                  milliseconds / 1_000 % 60, milliseconds % 1_000)
}

func parseImportTime(_ raw: String) throws -> Double {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
    guard !text.isEmpty else { throw ImportTimeError.invalid }
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty }) else { throw ImportTimeError.invalid }
    var value = 0.0
    for (index, part) in parts.enumerated() {
        guard let number = Double(part), number.isFinite, number >= 0,
              index == 0 || number < 60 else { throw ImportTimeError.invalid }
        value = value * 60 + number
    }
    guard value.isFinite else { throw ImportTimeError.invalid }
    return value
}


/// Parses TXT lines, SRT cues, or VTT cues into editable timing rows. TXT
/// rows start without times and use the distribute action; subtitle rows keep
/// their existing times so they can be reviewed or corrected before import.
func importedTimingRows(from url: URL) -> [ImportTimingRow] {
    let text = ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    let lines = text.components(separatedBy: "\n")
    if url.pathExtension.lowercased() == "txt" {
        return lines.enumerated().compactMap { index, line in
            let value = line.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { return nil }
            return ImportTimingRow(sourceLine: index + 1, text: value, start: nil, end: nil, aiGenerated: nil)
        }
    }
    var rows: [ImportTimingRow] = []
    var index = 0
    while index < lines.count {
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty { index += 1 }
        guard index < lines.count else { break }
        let blockStart = index
        var block: [String] = []
        while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            block.append(lines[index]); index += 1
        }
        guard !block.isEmpty else { continue }
        let first = block[0].trimmingCharacters(in: .whitespaces).uppercased()
        if first.hasPrefix("WEBVTT") || first.hasPrefix("NOTE") || first.hasPrefix("STYLE") || first.hasPrefix("REGION") {
            continue
        }
        guard let timingIndex = block.firstIndex(where: { $0.contains("-->") }) else { continue }
        let components = block[timingIndex].components(separatedBy: "-->")
        guard components.count == 2,
              let start = subtitleTime(components[0]),
              let end = subtitleTime(components[1].split(separator: " ").first.map(String.init) ?? components[1]) else { continue }
        let body = block[(timingIndex + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { continue }
        rows.append(ImportTimingRow(sourceLine: blockStart + timingIndex + 2, text: body, start: start, end: end, aiGenerated: nil))
    }
    return rows
}

func subtitleTime(_ raw: String) -> Double? {
    let value = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 3 || parts.count == 2 else { return nil }
    var seconds = 0.0
    for (index, part) in parts.enumerated() {
        guard let number = Double(part), number.isFinite, number >= 0,
              index == 0 || number < 60 else { return nil }
        seconds = seconds * 60 + number
    }
    return seconds
}

enum ImportTimeError: LocalizedError {
    case invalid
    var errorDescription: String? { "Use a time such as 00:01:23.500." }
}

enum ImportFileKind {
    case transcript, summary, adTranscript, audio

    var title: String {
        switch self {
        case .transcript: return "Transcript"
        case .summary: return "Summary"
        case .adTranscript: return "AD transcript"
        case .audio: return "AD audio"
        }
    }
    var extensions: [String] {
        switch self {
        case .transcript, .adTranscript: return ["srt", "vtt", "txt"]
        case .summary: return ["md", "markdown", "txt"]
        case .audio: return ["wav", "mp3", "m4a", "aac", "flac"]
        }
    }
    var prompt: String {
        switch self {
        case .transcript: return "Choose a transcript (SRT, VTT, or TXT)"
        case .summary: return "Choose a summary (Markdown or TXT)"
        case .adTranscript: return "Choose an AD transcript (SRT, VTT, or TXT)"
        case .audio: return "Choose AD audio (WAV, MP3, M4A, AAC, or FLAC)"
        }
    }

    func choose() -> URL? {
        let panel = NSOpenPanel()
        let types = extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowedContentTypes = types.isEmpty ? [.plainText] : types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choose"
        panel.message = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - Existing assets sheet

enum ImportScope: String, Identifiable {
    case all, transcript, summary, descriptions
    var id: Self { self }
    var title: String {
        switch self {
        case .all: return "Import Existing Assets"
        case .transcript: return "Import Transcript"
        case .summary: return "Import Summary"
        case .descriptions: return "Import Descriptions"
        }
    }
    var detail: String {
        switch self {
        case .all: return "Bring a transcript, summary, AD transcript, or AD audio into the project."
        case .transcript: return "Choose an SRT, VTT, or TXT transcript. TXT timing is reviewed before saving."
        case .summary: return "Choose a Markdown or TXT summary. A transcript is not required."
        case .descriptions: return "Choose an AD transcript. AD-only text becomes editable descriptions and requires an existing transcript."
        }
    }
}

struct ImportExistingAssetsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var studio: StudioModel
    let project: StudioProject
    var scope: ImportScope = .all
    var title: String? = nil
    var primaryTitle: String? = nil
    var combineTitle: String
    var onFinished: ((StudioProject?) -> Void)? = nil

    @State private var selection: ImportAssetSelection
    @State private var timingRequest: ImportTimingRequest?
    @State private var pendingCombine = false
    @State private var confirmReplacements = false
    @State private var timingWarning: TimingWarningRequest?
    @State private var localError: String?

    init(
        studio: StudioModel,
        project: StudioProject,
        selection: ImportAssetSelection = ImportAssetSelection(),
        scope: ImportScope = .all,
        title: String? = nil,
        primaryTitle: String? = nil,
        combineTitle: String = "Import & Combine",
        onFinished: ((StudioProject?) -> Void)? = nil
    ) {
        self.studio = studio
        self.project = project
        self.scope = scope
        self.title = title
        self.primaryTitle = primaryTitle
        self.combineTitle = combineTitle
        self.onFinished = onFinished
        _selection = State(initialValue: selection)
    }

    private var canCombine: Bool {
        scope == .all && selection.adAudio != nil && !project.isYouTubeURLProject && project.hasFile(project.source)
    }
    private var replacementNames: [String] {
        var names: [String] = []
        if selection.transcript != nil, !project.transcript.isEmpty { names.append("Transcript") }
        if selection.summary != nil, !project.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { names.append("Summary") }
        if selection.adTranscript != nil, project.importedADTranscript != nil { names.append("AD transcript") }
        if selection.adAudio != nil, project.importedAudioDescription != nil { names.append("AD audio") }
        return names
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title ?? scope.title)
                .font(.title2.bold())
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 4)
            Text(scope == .all
                 ? "Bring a transcript, summary, AD transcript, or AD audio into “\(project.name)”. Files are copied into the project folder."
                 : "\(scope.detail) Files are copied into “\(project.name)”.")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.bottom, 10)
            Form {
                Section("Text assets") {
                    if scope == .all || scope == .transcript {
                        assetRow(.transcript, url: $selection.transcript, timing: selection.transcriptTiming)
                    }
                    if scope == .all || scope == .summary {
                        assetRow(.summary, url: $selection.summary, timing: nil)
                    }
                    if scope == .all || scope == .descriptions {
                        assetRow(.adTranscript, url: $selection.adTranscript, timing: selection.adTranscriptTiming)
                        if selection.adTranscript != nil {
                            Picker("AD transcript type", selection: $selection.adTranscriptMode) {
                                ForEach(ImportedADTranscriptMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            .help("Choose whether this AD transcript creates editable descriptions or one combined caption track.")
                            Text(selection.adTranscriptMode.detail).font(.caption).foregroundStyle(.secondary)
                            if selection.adTranscriptMode == .narration && project.transcript.isEmpty && selection.transcript == nil {
                                Label("A transcript is required before AD-only descriptions can be imported.", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
                if scope == .all {
                Section("AD audio") {
                    if project.isYouTubeURLProject {
                        Text("Audio combination is unavailable for YouTube projects because there is no local video source. Text imports are still available.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        assetRow(.audio, url: $selection.adAudio, timing: nil)
                        if selection.adAudio != nil {
                            Picker("Audio type", selection: $selection.adAudioMode) {
                                ForEach(ImportedADAudioMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            .help("Choose narration-only audio or a full AD mix.")
                            Text(selection.adAudioMode.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Create Project & Combine creates Original Audio and English - Audio Description tracks. Viewers can switch between them.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                }
                if let localError {
                    Section {
                        Label(localError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if canCombine {
                    Button(combineTitle, systemImage: "waveform.badge.plus") { startImport(combine: true) }
                        .disabled(studio.busy || !selection.hasAny)
                        .help("Import the selected assets and create a two-track described video")
                }
                Button(primaryTitle ?? (scope == .all ? "Import" : scope.title), systemImage: "square.and.arrow.down") { startImport(combine: false) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(studio.busy || !selection.hasAny)
                    .help("Copy the selected assets into this project")
            }
            .padding(20)
        }
        .frame(width: 680, height: 620)
        .sheet(item: $timingRequest) { request in
            TXTImportTimingView(
                fileURL: request.url,
                duration: project.duration,
                transcript: request.kind == .transcript ? [] : project.transcript,
                mode: request.mode,
                project: project,
                studio: studio
            ) { timingURL, _ in
                if request.kind == .transcript { selection.transcriptTiming = timingURL }
                else { selection.adTranscriptTiming = timingURL }
                timingRequest = nil
            }
        }
        .confirmationDialog("Replace existing assets?", isPresented: $confirmReplacements, titleVisibility: .visible) {
            Button("Replace and Import", role: .destructive) { performImport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace: \(replacementNames.joined(separator: ", ")). The previous files remain in the project until cleanup.")
        }
        .alert("Timing Warnings", isPresented: Binding(
            get: { timingWarning != nil },
            set: { if !$0 { timingWarning = nil } }
        )) {
            Button("Import Anyway", role: .destructive) {
                timingWarning = nil
                performImport()
            }
            .help("Proceed with the import. Flagged rows are reported and can be retimed afterward.")
            Button("Review Timing…") {
                if let warning = timingWarning {
                    timingRequest = ImportTimingRequest(url: warning.fileURL, kind: warning.kind, mode: warning.mode)
                }
                timingWarning = nil
            }
            .help("Open the timing editor for all rows before importing")
            Button("Cancel", role: .cancel) { timingWarning = nil }
        } message: {
            Text((timingWarning?.messages ?? []).joined(separator: "\n\n") + "\n\nYou can import anyway and edit transcript timings afterward.")
        }
        .alert("Import Couldn’t Be Completed", isPresented: Binding(get: { studio.error != nil }, set: { if !$0 { studio.dismissError() } })) {
            Button("OK", role: .cancel) { studio.dismissError() }
        } message: { Text(studio.error ?? "") }
        .onChange(of: selection.transcript) { _, url in
            selection.transcriptTiming = nil
            if let url, url.pathExtension.lowercased() == "txt" { requestTiming(kind: .transcript, url: url) }
        }
        .onChange(of: selection.adTranscript) { _, url in
            selection.adTranscriptTiming = nil
            if let url, url.pathExtension.lowercased() == "txt" { requestTiming(kind: .adTranscript, url: url) }
        }
    }

    @ViewBuilder
    private func assetRow(_ kind: ImportFileKind, url: Binding<URL?>, timing: URL?) -> some View {
        LabeledContent(kind.title) {
            HStack(spacing: 8) {
                Text(url.wrappedValue?.lastPathComponent ?? "None")
                    .foregroundStyle(url.wrappedValue == nil ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Button("Choose…") {
                    if let selected = kind.choose() { url.wrappedValue = selected }
                }
                .help("Choose a \(kind.title.lowercased()) file")
                if url.wrappedValue != nil {
                    Button("Remove", systemImage: "xmark.circle") { url.wrappedValue = nil }
                        .labelStyle(.iconOnly)
                        .help("Remove this selection")
                }
                if kind == .transcript || kind == .adTranscript {
                    Button(timing == nil ? "Review Timing…" : "Review Timing…") {
                        if let selected = url.wrappedValue { requestTiming(kind: kind, url: selected) }
                    }
                    .help("Review and validate start and end times for every row before importing")
                }
            }
        }
    }

    private func requestTiming(kind: ImportFileKind, url: URL) {
        timingRequest = ImportTimingRequest(url: url,
                                            kind: kind,
                                            mode: kind == .adTranscript ? selection.adTranscriptMode : .narration)
    }

    private func startImport(combine: Bool) {
        localError = nil
        if let url = selection.transcript, url.pathExtension.lowercased() == "txt", selection.transcriptTiming == nil {
            requestTiming(kind: .transcript, url: url)
            localError = "Review the TXT timing before importing."
            return
        }
        if let url = selection.adTranscript, url.pathExtension.lowercased() == "txt", selection.adTranscriptTiming == nil {
            requestTiming(kind: .adTranscript, url: url)
            localError = "Review the TXT timing before importing."
            return
        }
        var entries: [(URL, ImportFileKind, ImportedADTranscriptMode, [String])] = []
        if let url = selection.transcript, selection.transcriptTiming == nil {
            let warnings = timingWarnings(for: url, kind: .transcript, mode: .narration)
            if !warnings.isEmpty { entries.append((url, .transcript, .narration, warnings)) }
        }
        if let url = selection.adTranscript, selection.adTranscriptTiming == nil {
            let warnings = timingWarnings(for: url, kind: .adTranscript, mode: selection.adTranscriptMode)
            if !warnings.isEmpty { entries.append((url, .adTranscript, selection.adTranscriptMode, warnings)) }
        }
        if let first = entries.first {
            pendingCombine = combine
            timingWarning = TimingWarningRequest(
                fileURL: first.0, kind: first.1, mode: first.2,
                messages: entries.flatMap(\.3))
            return
        }
        pendingCombine = combine
        if replacementNames.isEmpty { performImport() }
        else { confirmReplacements = true }
    }

    /// Preflight validation for every text type. SRT/VTT keep their times and
    /// are checked here; TXT must pass through the timing editor first.
    private func timingWarnings(for url: URL, kind: ImportFileKind, mode: ImportedADTranscriptMode) -> [String] {
        let rows = importedTimingRows(from: url)
        guard !rows.isEmpty else { return ["No timed rows were found in this file."] }
        let duration = project.duration
        var messages: [String] = []
        var previousEnd: Double?
        for (index, row) in rows.enumerated() {
            let label = kind == .transcript ? "Transcript row \(index + 1)" : "AD row \(index + 1)"
            guard let start = row.start, let end = row.end else {
                messages.append("\(label) has no start or end time.")
                continue
            }
            if end <= start {
                messages.append("\(label) ends before it starts (\(importClock(start))).")
            } else if end > duration + 0.001 {
                messages.append("\(label) ends at \(importClock(end)), after the video ends at \(importClock(duration)). It will be omitted.")
            } else if start >= duration {
                messages.append("\(label) starts after the video ends and will be omitted.")
            }
            if let previousEnd, start < previousEnd - 0.001 {
                messages.append("\(label) overlaps another row in this file (\(importClock(start))–\(importClock(end))).")
            }
            if kind == .adTranscript {
                for transcript in project.transcript where start < transcript.end && end > transcript.start {
                    messages.append("\(label) overlaps transcript \(importClock(transcript.start))–\(importClock(transcript.end)) and will be flagged for retiming.")
                    break
                }
                for cue in project.cues where start < cue.end && end > cue.start {
                    messages.append("\(label) overlaps existing description \(importClock(cue.start))–\(importClock(cue.end)) and will be flagged for retiming.")
                    break
                }
            }
            previousEnd = max(previousEnd ?? 0, end)
            if messages.count >= 8 { break }
        }
        if messages.count > 8 { messages = Array(messages.prefix(8)) + ["And more timing issues…"] }
        var seen = Set<String>()
        return messages.filter { seen.insert($0).inserted }
    }

    private var timingIsReady: Bool {
        (selection.transcript?.pathExtension.lowercased() != "txt" || selection.transcriptTiming != nil)
            && (selection.adTranscript?.pathExtension.lowercased() != "txt" || selection.adTranscriptTiming != nil)
    }

    private func performImport() {
        let combine = pendingCombine
        studio.importAssets(selection, into: project, combine: combine, replaceExisting: !replacementNames.isEmpty) { result in
            if let result { onFinished?(result) }
        }
        dismiss()
    }
}

struct TimingWarningRequest: Identifiable {
    let id = UUID()
    var fileURL: URL
    var kind: ImportFileKind
    var mode: ImportedADTranscriptMode
    var messages: [String]
}

struct ImportTimingRequest: Identifiable {
    let id = UUID()
    let url: URL
    let kind: ImportFileKind
    let mode: ImportedADTranscriptMode
}

// MARK: - TXT timing editor

struct TXTImportTimingView: View {
    @Environment(\.dismiss) private var dismiss
    let fileURL: URL
    let duration: Double
    let transcript: [Segment]
    let mode: ImportedADTranscriptMode
    let project: StudioProject
    @Bindable var studio: StudioModel
    let onSave: (URL, Bool) -> Void

    @State private var rows: [ImportTimingRow] = []
    @State private var aiUsed = false
    @State private var alignmentError: String?

    private var validation: [Int: String] {
        var errors: [Int: String] = [:]
        var previousEnd: Double?
        for (index, row) in rows.enumerated() {
            do {
                let start = try parseImportTime(row.start.map { importClock(Double($0)) } ?? "")
                let end = try parseImportTime(row.end.map { importClock(Double($0)) } ?? "")
                if end <= start { errors[index] = "End must be after start." }
                else if end > duration + 0.001 { errors[index] = "Ends after the video." }
                else if let previousEnd, start < previousEnd - 0.001 { errors[index] = "Overlaps the previous line." }
                previousEnd = end
            } catch {
                errors[index] = "Enter a valid start and end time."
            }
        }
        return errors
    }
    private var canSave: Bool { !rows.isEmpty && validation.isEmpty && !studio.busy }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(fileURL.pathExtension.lowercased() == "txt" ? "Set TXT Timing" : "Review Timing")
                .font(.title2.bold()).padding(20)
            Text("Every row needs a start and end time inside \(importClock(duration)). SRT and VTT times are prefilled for review; use Distribute Evenly or Auto-time with Gemini when needed.")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.bottom, 10)
            HStack {
                Button("Distribute Evenly", systemImage: "arrow.left.and.right") { distribute() }
                    .help("Give every line an equal share of the video")
                Button("Auto-time with Gemini", systemImage: "sparkles") { align() }
                    .disabled(!studio.hasValidApiKey || studio.busy)
                    .help(studio.hasApiKey ? "Ask Gemini for proposed timing; review every row before saving" : "Enter your Gemini API key in Settings → Gemini API to auto-time text")
                Spacer()
                Text("\(rows.count) lines").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.bottom, 8)
            if let alignmentError {
                Label(alignmentError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red).padding(.horizontal, 20)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(row.sourceLine)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                            TextField("Start", text: Binding(
                                get: { row.start.map { importClock($0) } ?? "" },
                                set: { rows[index].start = try? parseImportTime($0) }
                            ))
                            .frame(width: 110)
                            .help("Start time for source line \(row.sourceLine)")
                            TextField("End", text: Binding(
                                get: { row.end.map { importClock($0) } ?? "" },
                                set: { rows[index].end = try? parseImportTime($0) }
                            ))
                            .frame(width: 110)
                            .help("End time for source line \(row.sourceLine)")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.text).lineLimit(2)
                                if let error = validation[index] {
                                    Text(error).font(.caption).foregroundStyle(.red)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 6)
                        Divider()
                    }
                }
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save Timing", systemImage: "checkmark") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                    .help(canSave ? "Save reviewed timing and return to the import sheet" : "Fix every timing error before saving")
            }
            .padding(20)
        }
        .frame(width: 760, height: 620)
        .onAppear { loadRows() }
    }

    private func loadRows() {
        guard rows.isEmpty else { return }
        rows = importedTimingRows(from: fileURL)
        if rows.contains(where: { $0.start == nil || $0.end == nil }) {
            distribute()
        }
    }

    private func distribute() {
        guard !rows.isEmpty, duration > 0 else { return }
        for index in rows.indices {
            rows[index].start = Double(index) * duration / Double(rows.count)
            rows[index].end = Double(index + 1) * duration / Double(rows.count)
        }
        aiUsed = false
    }

    private func align() {
        alignmentError = nil
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("vidistudio-align-input-\(UUID().uuidString).txt")
        do {
            try rows.map(\.text).joined(separator: "\n").write(to: temp, atomically: true, encoding: .utf8)
        } catch {
            alignmentError = error.localizedDescription
            return
        }
        studio.alignImportedText(file: temp, mode: mode, project: project) { result in
            try? FileManager.default.removeItem(at: temp)
            switch result {
            case .success(let proposal):
                var proposed = proposal.rows
                for index in proposed.indices {
                    if proposed[index].sourceLine <= 0 { proposed[index].sourceLine = index + 1 }
                }
                rows = proposed
                aiUsed = true
                alignmentError = "Gemini proposed timing for \(proposed.count) lines. Review every row before saving."
            case .failure(let error):
                alignmentError = error.localizedDescription
            }
        }
    }

    private func save() {
        guard canSave else { return }
        let payload: [String: Any] = [
            "aiGenerated": aiUsed,
            "reviewed": true,
            "rows": rows.map { row in
                [
                    "sourceLine": row.sourceLine,
                    "text": row.text,
                    "start": row.start ?? 0,
                    "end": row.end ?? 0,
                ]
            },
        ]
        do {
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("vidistudio-timing-\(UUID().uuidString).json")
            try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]).write(to: output, options: .atomic)
            onSave(output, aiUsed)
            dismiss()
        } catch {
            alignmentError = error.localizedDescription
        }
    }
}

// MARK: - Import report

struct ImportReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let reports: [ImportReport]
    var canEditTranscriptTimings: Bool = false
    var onEditTranscriptTimings: () -> Void = {}
    var onReviewDescriptions: () -> Void = {}
    var onReviewTranscript: () -> Void = {}
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Import Report")
                .font(.title2.bold()).padding(.horizontal, 20).padding(.top, 20)
            Text("Review what was imported, what needs retiming, and what was omitted.")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(reports) { report in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(report.kindTitle): \(report.sourceName)").font(.headline)
                                Spacer()
                                Text("\(report.rowsImported) imported")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                            if let duration = report.videoDuration {
                                Text("Video duration used for validation: \(importClock(duration))")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Video duration is unknown. Timing could not be verified against the video.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            HStack(spacing: 16) {
                                countLabel("Flagged for retiming", report.rowsFlagged, color: .orange)
                                countLabel("Ended after video", report.rowsOmittedAfterVideo, color: .red)
                                countLabel("Invalid or empty", report.rowsOmittedInvalid, color: .red)
                                if let overlaps = report.rowsOmittedTranscriptOverlap, overlaps > 0 {
                                    countLabel("Transcript overlaps", overlaps, color: .red)
                                }
                            }
                            ForEach(report.warnings ?? [], id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            ForEach(report.omitted ?? []) { row in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Source line \(row.sourceLine ?? 0): \(row.text)").font(.caption.weight(.semibold))
                                    Text(row.reason).font(.caption).foregroundStyle(.red)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                            }
                            ForEach(Array((report.flagged ?? []).enumerated()), id: \.offset) { _, flagged in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("AD segment \(flagged.row ?? 0): \(flagged.text ?? "")").font(.caption.weight(.semibold))
                                    ForEach(Array((flagged.conflicts ?? []).enumerated()), id: \.offset) { _, conflict in
                                        Text(conflictDescription(conflict)).font(.caption).foregroundStyle(.orange)
                                    }
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                            }
                            if let guidance = report.guidance {
                                Text(guidance).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 20)
            }
            HStack {
                if canEditTranscriptTimings {
                    Button("Edit Transcript Timings…", systemImage: "clock") {
                        onEditTranscriptTimings()
                        onClose()
                    }
                    .help("Review and correct the timing of every imported transcript row")
                }
                Button("Review Descriptions", systemImage: "text.below.photo") {
                    onReviewDescriptions()
                    onClose()
                }
                .help("Open Descriptions to fix timing issues")
                Button("Review Transcript", systemImage: "text.bubble") {
                    onReviewTranscript()
                    onClose()
                }
                .help("Open Transcript to review imported rows")
                Spacer()
                Button("Close", role: .cancel) { onClose() }
                    .keyboardShortcut(.defaultAction)
                    .help("Close the import report and return to the editor")
            }
            .padding(20)
        }
        .frame(width: 720, height: 640)
    }

    private func countLabel(_ title: String, _ value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.title3.bold()).foregroundStyle(value == 0 ? Color.secondary : color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func conflictDescription(_ conflict: ImportConflict) -> String {
        let kind = conflict.kind == "transcript" ? "Transcript" : conflict.kind == "description" ? "AD segment" : "Timing"
        let range = "\(importClock(conflict.start ?? 0)) to \(importClock(conflict.end ?? 0))"
        return "\(kind) \(conflict.row ?? 0) overlaps \(range): \(conflict.text ?? "")"
    }
}

// MARK: - Post-import transcript timing editor

struct TranscriptTimingEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var studio: StudioModel
    let project: StudioProject

    private struct Draft: Identifiable {
        var id: String
        var text: String
        var startText: String
        var endText: String
        var start: Double?
        var end: Double?
    }

    @State private var drafts: [Draft] = []
    @State private var errorMessage: String?

    private var validation: [Int: String] {
        var result: [Int: String] = [:]
        var previousEnd: Double?
        for (index, draft) in drafts.enumerated() {
            guard let start = draft.start, let end = draft.end else {
                result[index] = "Enter a valid start and end time."
                continue
            }
            if end <= start { result[index] = "End must be after start." }
            else if end > project.duration + 0.001 { result[index] = "Ends after the video." }
            else if let previousEnd, start < previousEnd - 0.001 { result[index] = "Overlaps the previous row." }
            previousEnd = end
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit Transcript Timings")
                .font(.title2.bold()).padding(.horizontal, 20).padding(.top, 20)
            Text("Review the start and end of every transcript row. Descriptions that overlap these rows are flagged for retiming; text exports remain available.")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.bottom, 10)
            HStack {
                Button("Distribute Evenly", systemImage: "arrow.left.and.right") { distribute() }
                    .help("Give every transcript row an equal share of the video")
                Spacer()
                Text("\(drafts.count) rows").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.bottom, 8)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red).padding(.horizontal, 20)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                        HStack(alignment: .top, spacing: 10) {
                            TextField("Start", text: Binding(
                                get: { drafts[index].startText },
                                set: { text in
                                    drafts[index].startText = text
                                    drafts[index].start = try? parseImportTime(text)
                                }
                            ))
                            .frame(width: 115)
                            .help("Start time for transcript row \(index + 1)")
                            TextField("End", text: Binding(
                                get: { drafts[index].endText },
                                set: { text in
                                    drafts[index].endText = text
                                    drafts[index].end = try? parseImportTime(text)
                                }
                            ))
                            .frame(width: 115)
                            .help("End time for transcript row \(index + 1)")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(drafts[index].text).lineLimit(2)
                                if let error = validation[index] {
                                    Text(error).font(.caption).foregroundStyle(.red)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 6)
                        Divider()
                    }
                }
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save Timings", systemImage: "checkmark") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!validation.isEmpty || drafts.isEmpty || studio.busy)
                    .help("Save the reviewed transcript timings and run overlap validation")
            }
            .padding(20)
        }
        .frame(width: 760, height: 640)
        .onAppear(perform: load)
    }

    private func load() {
        guard drafts.isEmpty else { return }
        drafts = project.transcript.map {
            Draft(id: $0.id, text: $0.text, startText: importClock($0.start), endText: importClock($0.end), start: $0.start, end: $0.end)
        }
    }

    private func distribute() {
        guard !drafts.isEmpty, project.duration > 0 else { return }
        for index in drafts.indices {
            let start = Double(index) * project.duration / Double(drafts.count)
            let end = Double(index + 1) * project.duration / Double(drafts.count)
            drafts[index].start = start
            drafts[index].end = end
            drafts[index].startText = importClock(start)
            drafts[index].endText = importClock(end)
        }
    }

    private func save() {
        guard validation.isEmpty else { return }
        var updated = project.transcript
        let byID = Dictionary(uniqueKeysWithValues: drafts.map { ($0.id, $0) })
        for index in updated.indices {
            guard let draft = byID[updated[index].id], let start = draft.start, let end = draft.end else { continue }
            updated[index].start = start
            updated[index].end = end
        }
        studio.saveSegments(updated, cues: project.cues)
        dismiss()
    }
}
