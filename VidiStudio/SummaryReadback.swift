import SwiftUI
import AppKit
import AVFoundation

// MARK: - Highlight colors

enum SummaryHighlightColor {
    static let defaultSentenceHex = "#0A84FF"
    static let defaultWordHex = "#FFD60A"

    static func rgb(from hex: String) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        return (
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255
        )
    }

    static func color(from hex: String) -> Color {
        guard let rgb = rgb(from: hex) else { return Color.yellow }
        return Color(red: Double(rgb.red), green: Double(rgb.green), blue: Double(rgb.blue))
    }

    static func nsColor(from hex: String, alpha: CGFloat = 1) -> NSColor {
        guard let rgb = rgb(from: hex) else { return .systemYellow }
        return NSColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
    }

    static func hex(from color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        nsColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X",
            locale: Locale(identifier: "en_US_POSIX"),
            Int((min(max(red, 0), 1) * 255).rounded()),
            Int((min(max(green, 0), 1) * 255).rounded()),
            Int((min(max(blue, 0), 1) * 255).rounded())
        )
    }

    /// Contrasting text color for a solid word-highlight background.
    static func textColor(forWordHex hex: String) -> Color {
        guard let rgb = rgb(from: hex) else { return .black }
        let luminance = 0.299 * Double(rgb.red) + 0.587 * Double(rgb.green) + 0.114 * Double(rgb.blue)
        return luminance > 0.55 ? .black : .white
    }

    static func nsTextColor(forWordHex hex: String) -> NSColor {
        guard let rgb = rgb(from: hex) else { return .black }
        let luminance = 0.299 * Double(rgb.red) + 0.587 * Double(rgb.green) + 0.114 * Double(rgb.blue)
        return luminance > 0.55 ? .black : .white
    }
}

// MARK: - Sentences

struct SummarySentence: Identifiable, Hashable {
    let id: Int
    let blockID: Int
    let isFirstInBlock: Bool
    let text: String
    let heading: Int?
    let marker: String?
    let depth: Int
    let isQuote: Bool
    let isCode: Bool
}

enum SummarySpeechParser {
    static func sentences(from markdown: String) -> [SummarySentence] {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let blocks = markdownBlocks(from: markdown)
        var result: [SummarySentence] = []
        var sentenceID = 0
        for block in blocks {
            let plain = String(block.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !plain.isEmpty else { continue }
            let nsPlain = plain as NSString
            var ranges: [NSRange] = []
            nsPlain.enumerateSubstrings(
                in: NSRange(location: 0, length: nsPlain.length),
                options: [.bySentences, .localized]
            ) { _, range, _, _ in
                let fragment = nsPlain.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !fragment.isEmpty { ranges.append(range) }
            }
            if ranges.isEmpty {
                ranges = [NSRange(location: 0, length: nsPlain.length)]
            }
            for (offset, range) in ranges.enumerated() {
                let fragment = nsPlain.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !fragment.isEmpty else { continue }
                result.append(SummarySentence(
                    id: sentenceID,
                    blockID: block.id,
                    isFirstInBlock: offset == 0,
                    text: fragment,
                    heading: block.heading,
                    marker: block.marker,
                    depth: block.depth,
                    isQuote: block.isQuote,
                    isCode: block.isCode
                ))
                sentenceID += 1
            }
        }
        return result
    }

    private struct MarkdownBlock {
        let id: Int
        var text: AttributedString
        let heading: Int?
        let marker: String?
        let depth: Int
        let isQuote: Bool
        let isCode: Bool
    }

    private static func markdownBlocks(from markdown: String) -> [MarkdownBlock] {
        guard let parsed = try? AttributedString(markdown: markdown) else {
            return [MarkdownBlock(
                id: 0, text: AttributedString(markdown),
                heading: nil, marker: nil, depth: 0, isQuote: false, isCode: false
            )]
        }
        var result: [MarkdownBlock] = []
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let identity = components.first?.identity ?? 0
            var fragment = AttributedString(parsed[run.range])
            fragment.presentationIntent = nil
            if result.last?.id == identity {
                result[result.count - 1].text.append(fragment)
                continue
            }
            var heading: Int?
            var ordinal: Int?
            var ordered = false
            var depth = 0
            var quote = false
            var code = false
            for component in components {
                switch component.kind {
                case .header(let level): heading = level
                case .listItem(let number): if ordinal == nil { ordinal = number }
                case .orderedList:
                    if depth == 0 { ordered = true }
                    depth += 1
                case .unorderedList: depth += 1
                case .blockQuote: quote = true
                case .codeBlock: code = true
                default: break
                }
            }
            let marker = ordinal.map { ordered ? "\($0)." : "•" }
            result.append(MarkdownBlock(
                id: identity, text: fragment,
                heading: heading, marker: marker, depth: depth, isQuote: quote, isCode: code
            ))
        }
        return result
    }
}

// MARK: - Readback model (Apple Text to Speech)

@MainActor @Observable
final class SummaryReadbackModel: NSObject, AVSpeechSynthesizerDelegate {
    var sentences: [SummarySentence] = []
    var currentIndex: Int?
    /// Word highlight in display-text (UTF-16) coordinates. See `cachedLineRanges`.
    var wordRange: NSRange?
    var isReading = false
    var isPaused = false
    var error: String?
    /// Current text selection in display-text coordinates, reported by the text view.
    var selectedRange: NSRange?
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var settings = StudioSettings()
    @ObservationIgnored private var speakingIndex: Int?
    @ObservationIgnored private var suppressAdvance = false
    @ObservationIgnored private var markdownSignature = ""
    @ObservationIgnored private var cachedLines: [(prefix: String, body: String)] = []
    @ObservationIgnored private var cachedLineRanges: [NSRange] = []
    @ObservationIgnored private var cachedPlain = ""
    /// UTF-16 offset within the speaking sentence where a partial utterance starts.
    @ObservationIgnored private var partialOffset = 0
    @ObservationIgnored private var oneShotActive = false
    /// The utterance most recently handed to the synthesizer. Delegate callbacks
    /// carrying any other utterance are stale (e.g. from speech stopped just
    /// before a new start) and must be ignored.
    @ObservationIgnored private var speakingUtterance: AVSpeechUtterance?
    /// Hook for the text view to collapse its visual selection when user-initiated
    /// speech starts, so sentence/word highlighting is visible. Wired by the view;
    /// chained sentence advances never clear, so selecting text mid-reading works.
    @ObservationIgnored var clearTextSelection: (@MainActor () -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var hasContent: Bool { !sentences.isEmpty }

    var progressLabel: String {
        guard !sentences.isEmpty else { return "No summary to read" }
        if isPaused { return "Paused" }
        return isReading ? "Reading summary" : "Ready to read"
    }

    /// A selection anchored inside a known sentence, usable as a read-from point.
    var hasReadableSelection: Bool {
        guard let location = selectedRange?.location, location != NSNotFound else { return false }
        return sentenceIndex(at: location) != nil
    }

    var hasNonEmptySelection: Bool {
        guard let selectedRange, selectedRange.location != NSNotFound else { return false }
        return selectedRange.length > 0
    }

    func configure(markdown: String, settings: StudioSettings) {
        self.settings = settings
        guard markdown != markdownSignature else { return }
        stop()
        markdownSignature = markdown
        sentences = SummarySpeechParser.sentences(from: markdown)
        rebuildDisplayCache()
        error = nil
    }

    func updateSettings(_ settings: StudioSettings) {
        self.settings = settings
    }

    // MARK: Transport

    func play() {
        error = nil
        guard !sentences.isEmpty else { return }
        if isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
            return
        }
        if isReading { return }
        speak(at: currentIndex ?? 0, userInitiated: true)
    }

    func pause() {
        guard isReading, !isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    /// Single shared play/pause entry used by the button, menus, and shortcuts
    /// so every trigger behaves identically. Smart start: resumes when paused,
    /// reads from the text selection when one exists, otherwise reads from the
    /// beginning of the summary.
    func togglePlayPause() {
        if isReading, !isPaused {
            pause()
            return
        }
        if isPaused {
            play()
            return
        }
        if hasNonEmptySelection {
            playFromSelection()
            return
        }
        playFromStart()
    }

    func stop() {
        suppressAdvance = true
        synthesizer.stopSpeaking(at: .immediate)
        speakingUtterance = nil
        speakingIndex = nil
        currentIndex = nil
        wordRange = nil
        isReading = false
        isPaused = false
        partialOffset = 0
        oneShotActive = false
        suppressAdvance = false
    }

    func playFromStart() {
        guard !sentences.isEmpty else { return }
        error = nil
        restart(at: 0)
    }

    /// Start reading at an exact display-text location (e.g. a right-clicked word),
    /// snapping to the containing word, then continue through following sentences.
    func playFrom(location: Int) {
        guard !sentences.isEmpty else { return }
        guard let index = sentenceIndex(at: location) else {
            play()
            return
        }
        let prefixLength = (cachedLines[index].prefix as NSString).length
        let bodyStart = cachedLineRanges[index].location + prefixLength
        let bodyLength = (sentences[index].text as NSString).length
        var offset = max(0, min(location - bodyStart, bodyLength))
        offset = snappedWordOffset(sentence: index, utf16Offset: offset)
        error = nil
        if offset >= bodyLength {
            let next = index + 1
            if sentences.indices.contains(next) { restart(at: next) } else { stop() }
            return
        }
        speakPartial(sentence: index, utf16Offset: offset)
    }

    func playFromSelection() {
        guard let location = selectedRange?.location, location != NSNotFound else {
            play()
            return
        }
        playFrom(location: location)
    }

    /// Read exactly the selected text once, without continuing or disturbing sentence order.
    func readSelectedText() {
        guard let selection = selectedRange,
              selection.location != NSNotFound,
              selection.length > 0 else { return }
        let plain = cachedPlain as NSString
        guard NSMaxRange(selection) <= plain.length else { return }
        let text = plain.substring(with: selection).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        clearTextSelection?()
        do {
            let utterance = try SystemSpeechUtterance.make(text: text, settings: settings)
            suppressAdvance = true
            synthesizer.stopSpeaking(at: .immediate)
            suppressAdvance = false
            oneShotActive = true
            speakingIndex = nil
            partialOffset = 0
            currentIndex = sentenceIndex(at: selection.location)
            wordRange = nil
            isReading = true
            isPaused = false
            error = nil
            speakingUtterance = utterance
            synthesizer.speak(utterance)
        } catch {
            self.error = UserFacingIssueReporter.message(
                for: error,
                issue: .speech,
                context: "Read selected summary text"
            )
            oneShotActive = false
            isReading = false
            isPaused = false
        }
    }

    // MARK: Display cache

    private func displayPrefix(for sentence: SummarySentence) -> String {
        let indent = String(repeating: "    ", count: max(0, sentence.depth - 1))
        if sentence.isFirstInBlock, let marker = sentence.marker {
            return indent + marker + "  "
        }
        return indent
    }

    private func rebuildDisplayCache() {
        cachedLines = sentences.map { (prefix: displayPrefix(for: $0), body: $0.text) }
        cachedLineRanges = []
        cachedLineRanges.reserveCapacity(cachedLines.count)
        var plain = ""
        plain.reserveCapacity(sentences.reduce(0) { $0 + $1.text.count + 8 })
        var location = 0
        for line in cachedLines {
            let text = line.prefix + line.body
            let length = (text as NSString).length
            if !cachedLineRanges.isEmpty { plain += "\n" ; location += 1 }
            cachedLineRanges.append(NSRange(location: location, length: length))
            plain += text
            location += length
        }
        cachedPlain = plain
    }

    var plainText: String { cachedPlain }

    func lineRange(forSentence index: Int) -> NSRange? {
        guard cachedLineRanges.indices.contains(index) else { return nil }
        return cachedLineRanges[index]
    }

    func sentenceIndex(at location: Int) -> Int? {
        for (index, range) in cachedLineRanges.enumerated() {
            if NSLocationInRange(location, range) || location == NSMaxRange(range) {
                return index
            }
        }
        return nil
    }

    private func snappedWordOffset(sentence index: Int, utf16Offset: Int) -> Int {
        let text = sentences[index].text as NSString
        guard utf16Offset > 0, utf16Offset < text.length else { return utf16Offset }
        var snapped = utf16Offset
        text.enumerateSubstrings(
            in: NSRange(location: 0, length: text.length),
            options: .byWords
        ) { _, wordRange, _, stop in
            if NSLocationInRange(utf16Offset, wordRange) || utf16Offset == NSMaxRange(wordRange) {
                snapped = wordRange.location
                stop.pointee = true
            }
        }
        return snapped
    }

    private func displayFont(for sentence: SummarySentence) -> NSFont {
        if let level = sentence.heading {
            let size: CGFloat = level == 1 ? 24 : level == 2 ? 19 : 16
            return NSFont.systemFont(ofSize: size, weight: .bold)
        }
        if sentence.isCode {
            return NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        }
        return NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }

    /// Full attributed text with sentence and word background highlights.
    /// Word ranges are tracked in display-text coordinates so speech callbacks map exactly.
    func displayContent(
        sentenceBackground: NSColor,
        wordBackground: NSColor,
        wordForeground: NSColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        guard cachedLines.count == sentences.count,
              cachedLineRanges.count == sentences.count else {
            return NSAttributedString(string: cachedPlain)
        }
        for (index, line) in cachedLines.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }
            let sentence = sentences[index]
            let storage = NSMutableAttributedString(string: line.prefix + line.body)
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.addAttribute(.font, value: displayFont(for: sentence), range: fullRange)
            // Explicit semantic foreground so the text adapts to Dark Mode even if
            // the host view ever changes its default text color.
            storage.addAttribute(
                .foregroundColor,
                value: sentence.isQuote ? NSColor.secondaryLabelColor : NSColor.labelColor,
                range: fullRange
            )
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 10
            paragraph.lineSpacing = 3
            storage.addAttribute(.paragraphStyle, value: paragraph, range: fullRange)
            if currentIndex == sentence.id {
                storage.addAttribute(.backgroundColor, value: sentenceBackground, range: fullRange)
                if let wordRange, wordRange.length > 0, wordRange.location != NSNotFound {
                    let local = NSRange(
                        location: wordRange.location - cachedLineRanges[index].location,
                        length: wordRange.length
                    )
                    if local.location >= 0, NSMaxRange(local) <= storage.length {
                        storage.addAttribute(.backgroundColor, value: wordBackground, range: local)
                        storage.addAttribute(.foregroundColor, value: wordForeground, range: local)
                    }
                }
            }
            result.append(storage)
        }
        return result
    }

    // MARK: Speech plumbing

    private func isCurrentUtterance(_ identifier: ObjectIdentifier) -> Bool {
        guard let speakingUtterance else { return false }
        return ObjectIdentifier(speakingUtterance) == identifier
    }

    private func restart(at index: Int) {
        suppressAdvance = true
        synthesizer.stopSpeaking(at: .immediate)
        suppressAdvance = false
        speak(at: index, userInitiated: true)
    }

    /// - Parameter userInitiated: true for button/menu/shortcut starts (clears the
    ///   text selection so highlighting is visible); false for chained advances,
    ///   which must preserve a selection the user makes mid-reading.
    private func speak(at index: Int, userInitiated: Bool = false) {
        guard sentences.indices.contains(index) else {
            stop()
            return
        }
        if userInitiated { clearTextSelection?() }
        do {
            let utterance = try SystemSpeechUtterance.make(text: sentences[index].text, settings: settings)
            speakingIndex = index
            partialOffset = 0
            oneShotActive = false
            currentIndex = index
            wordRange = nil
            isReading = true
            isPaused = false
            error = nil
            speakingUtterance = utterance
            synthesizer.speak(utterance)
        } catch {
            self.error = UserFacingIssueReporter.message(
                for: error,
                issue: .speech,
                context: "Read summary"
            )
            isReading = false
            isPaused = false
            currentIndex = nil
            wordRange = nil
            speakingIndex = nil
        }
    }

    private func speakPartial(sentence index: Int, utf16Offset: Int) {
        let storage = sentences[index].text as NSString
        guard utf16Offset < storage.length else {
            let next = index + 1
            if sentences.indices.contains(next) { restart(at: next) } else { stop() }
            return
        }
        let partial = storage.substring(from: utf16Offset)
        guard !partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let next = index + 1
            if sentences.indices.contains(next) { restart(at: next) } else { stop() }
            return
        }
        clearTextSelection?()
        do {
            let utterance = try SystemSpeechUtterance.make(text: partial, settings: settings)
            suppressAdvance = true
            synthesizer.stopSpeaking(at: .immediate)
            suppressAdvance = false
            speakingIndex = index
            partialOffset = utf16Offset
            oneShotActive = false
            currentIndex = index
            wordRange = nil
            isReading = true
            isPaused = false
            error = nil
            speakingUtterance = utterance
            synthesizer.speak(utterance)
        } catch {
            self.error = UserFacingIssueReporter.message(
                for: error,
                issue: .speech,
                context: "Continue summary reading"
            )
            isReading = false
            isPaused = false
            currentIndex = nil
            wordRange = nil
            speakingIndex = nil
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.isCurrentUtterance(identifier) else { return }
            if self.oneShotActive { return }
            guard let speakingIndex = self.speakingIndex else { return }
            self.currentIndex = speakingIndex
            self.wordRange = nil
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.isCurrentUtterance(identifier) else { return }
            if self.oneShotActive { return }
            guard let speakingIndex = self.speakingIndex,
                  self.cachedLineRanges.indices.contains(speakingIndex) else { return }
            self.currentIndex = speakingIndex
            let prefixLength = (self.cachedLines[speakingIndex].prefix as NSString).length
            let displayLocation = self.cachedLineRanges[speakingIndex].location
                + prefixLength
                + self.partialOffset
                + characterRange.location
            self.wordRange = NSRange(location: displayLocation, length: characterRange.length)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.isCurrentUtterance(identifier) else { return }
            guard !self.suppressAdvance, self.isReading, !self.isPaused else { return }
            if self.oneShotActive {
                self.oneShotActive = false
                self.speakingUtterance = nil
                self.speakingIndex = nil
                self.currentIndex = nil
                self.wordRange = nil
                self.isReading = false
                self.isPaused = false
                return
            }
            guard let finished = self.speakingIndex else { return }
            let next = finished + 1
            if self.sentences.indices.contains(next) {
                self.speak(at: next)
            } else {
                self.speakingUtterance = nil
                self.speakingIndex = nil
                self.currentIndex = nil
                self.wordRange = nil
                self.isReading = false
                self.isPaused = false
                self.partialOffset = 0
            }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        // Intentional stops set suppressAdvance; natural cancellation needs no recovery
        // because the model state was already reset by stop() or replaced by restart().
    }
}

// MARK: - Selectable text view with summary reading menu

/// NSTextView that serves its right-click menu through a closure, using direct
/// subclass dispatch instead of the delegate channel.
final class SummaryTextView: NSTextView {
    var contextMenuProvider: (@MainActor (NSEvent) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuProvider?(event) ?? super.menu(for: event)
    }

    /// The standard AppKit text menu for the provider to extend.
    func standardMenu(for event: NSEvent) -> NSMenu? {
        super.menu(for: event)
    }
}

struct SummarySentenceTextView: NSViewRepresentable {
    @Bindable var model: SummaryReadbackModel
    let settings: StudioSettings
    var hasSummary: Bool = true
    var follow: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        let textView = SummaryTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 20, height: 14)
        textView.backgroundColor = .textBackgroundColor
        // Fixed default text color renders black in Dark Mode; semantic colors
        // adapt so the summary stays readable in both appearances.
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        context.coordinator.textView = textView
        // Collapse the visual selection whenever user-initiated speech starts so
        // sentence/word highlighting is visible instead of hiding under blue.
        // Runs synchronously inside the triggering action, before speech state
        // changes render, and records the write so its echo is never adopted.
        context.coordinator.model.clearTextSelection = { [weak textView, weak coordinator = context.coordinator] in
            guard let textView, let coordinator else { return }
            let length = (textView.string as NSString).length
            let caret = min(max(0, textView.selectedRange().location), length)
            let collapsed = NSRange(location: caret, length: 0)
            coordinator.lastProgrammaticRange = collapsed
            coordinator.isRestoringSelection = true
            textView.setSelectedRange(collapsed)
            coordinator.isRestoringSelection = false
            coordinator.model.selectedRange = collapsed
        }
        textView.contextMenuProvider = { [weak coordinator = context.coordinator] event in
            guard let coordinator else { return nil }
            return coordinator.menu(for: event, in: textView)
        }
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.hasSummary = hasSummary
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Never fight an active mouse selection: defer highlight refreshes until release.
        let userSelecting = (NSEvent.pressedMouseButtons & 1) != 0
        let content = model.displayContent(
            sentenceBackground: SummaryHighlightColor.nsColor(
                from: settings.summarySentenceHighlight, alpha: 0.38),
            wordBackground: SummaryHighlightColor.nsColor(
                from: settings.summaryWordHighlight, alpha: 1),
            wordForeground: SummaryHighlightColor.nsTextColor(
                forWordHex: settings.summaryWordHighlight)
        )
        let signature = "\(content.string.hashValue):\(model.currentIndex ?? -1):" +
            "\(model.wordRange?.location ?? -1):\(model.wordRange?.length ?? 0):" +
            "\(settings.summarySentenceHighlight):\(settings.summaryWordHighlight)"
        if signature != coordinator.lastContentSignature, !userSelecting {
            coordinator.lastContentSignature = signature
            if let storage = textView.textStorage, !storage.isEqual(to: content) {
                let selection = textView.selectedRange()
                storage.setAttributedString(content)
                let length = (content.string as NSString).length
                var restored = selection
                restored.location = min(max(0, restored.location), length)
                restored.length = min(max(0, restored.length), max(0, length - restored.location))
                context.coordinator.restoreSelection(restored)
            }
        }
        if follow, hasSummary, !userSelecting,
           let index = model.currentIndex, index != coordinator.lastScrolledIndex,
           let range = model.lineRange(forSentence: index) {
            coordinator.lastScrolledIndex = index
            textView.scrollRangeToVisible(range)
        } else if model.currentIndex == nil {
            coordinator.lastScrolledIndex = nil
        } else if !follow {
            coordinator.lastScrolledIndex = model.currentIndex
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        let model: SummaryReadbackModel
        var hasSummary = true
        var lastContentSignature = ""
        var lastScrolledIndex: Int?
        weak var textView: SummaryTextView?
        /// Anchor resolved when the context menu opens (click, or selection when clicked inside it).
        private var menuAnchor = NSNotFound
        /// Set while restoring the selection around highlight refreshes so those
        /// programmatic resets are never mistaken for a user selection.
        var isRestoringSelection = false
        /// The range last written programmatically; its deferred echo posts are ignored.
        var lastProgrammaticRange: NSRange?
        private var selectionObserver: NSObjectProtocol?

        init(model: SummaryReadbackModel) {
            self.model = model
            super.init()
            // Selection is tracked through NotificationCenter, which posts
            // reliably, rather than the NSTextViewDelegate channel. The post is
            // treated only as a signal: the view's live range is re-read, so a
            // deferred post can never install a stale range.
            selectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard let self,
                      notification.object as? NSTextView != nil else { return }
                if Thread.isMainThread {
                    MainActor.assumeIsolated {
                        self.adoptLiveSelection()
                    }
                } else {
                    Task { @MainActor [weak self] in
                        self?.adoptLiveSelection()
                    }
                }
            }
        }

        deinit {
            if let selectionObserver {
                NotificationCenter.default.removeObserver(selectionObserver)
            }
        }

        /// Write the selection programmatically without it being adopted back.
        func restoreSelection(_ range: NSRange) {
            guard let textView else { return }
            lastProgrammaticRange = range
            isRestoringSelection = true
            textView.setSelectedRange(range)
            isRestoringSelection = false
        }

        private func adoptLiveSelection() {
            guard !isRestoringSelection, let liveRange = textView?.selectedRange() else { return }
            if liveRange == lastProgrammaticRange, model.selectedRange != liveRange {
                return
            }
            lastProgrammaticRange = nil
            if model.selectedRange != liveRange {
                model.selectedRange = liveRange
            }
        }

        /// Resolve the read-from anchor for a right-click, preferring the
        /// selection when the click falls inside it.
        func menu(for event: NSEvent, in view: SummaryTextView) -> NSMenu? {
            let point = view.convert(event.locationInWindow, from: nil)
            let clicked = view.characterIndexForInsertion(at: point)
            let plainLength = (model.plainText as NSString).length
            let clamped = min(max(0, clicked), plainLength)
            let selection = view.selectedRange()
            if selection.length > 0,
               selection.location != NSNotFound,
               clamped >= selection.location, clamped <= NSMaxRange(selection) {
                menuAnchor = selection.location
            } else {
                menuAnchor = clamped
            }
            return combinedMenu(proposed: view.standardMenu(for: event), selection: selection)
        }

        private func combinedMenu(proposed menu: NSMenu?, selection: NSRange) -> NSMenu? {
            guard hasSummary, !model.sentences.isEmpty else { return menu }
            let plainLength = (model.plainText as NSString).length
            let anchor = menuAnchor != NSNotFound ? menuAnchor : selection.location
            let combined = NSMenu()
            let sentenceAtAnchor = anchor != NSNotFound
                ? model.sentenceIndex(at: min(anchor, max(0, plainLength - 1)))
                : nil
            let fromHere = NSMenuItem(
                title: "Read Summary from Here",
                action: #selector(readFromHere(_:)),
                keyEquivalent: ""
            )
            fromHere.target = self
            fromHere.image = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: nil)
            fromHere.isEnabled = sentenceAtAnchor != nil
            combined.addItem(fromHere)
            let selected = NSMenuItem(
                title: "Read Selected Text",
                action: #selector(readSelectedText(_:)),
                keyEquivalent: ""
            )
            selected.target = self
            selected.image = NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: nil)
            selected.isEnabled = selection.length > 0
            combined.addItem(selected)
            combined.addItem(.separator())
            let pauseResume = NSMenuItem(
                title: model.isReading && !model.isPaused ? "Pause Summary Reading" : "Resume Summary Reading",
                action: #selector(pauseResume(_:)),
                keyEquivalent: ""
            )
            pauseResume.target = self
            pauseResume.image = NSImage(
                systemSymbolName: model.isReading && !model.isPaused ? "pause.fill" : "play.fill",
                accessibilityDescription: nil
            )
            pauseResume.isEnabled = model.isReading
            combined.addItem(pauseResume)
            let stop = NSMenuItem(
                title: "Stop Summary Reading",
                action: #selector(stopReading(_:)),
                keyEquivalent: ""
            )
            stop.target = self
            stop.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)
            stop.isEnabled = model.isReading
            combined.addItem(stop)
            combined.addItem(.separator())
            // Copy: the proposed menu may be a shared instance whose items
            // cannot be moved into another menu.
            for item in menu?.items ?? [] {
                if let copy = item.copy() as? NSMenuItem {
                    combined.addItem(copy)
                }
            }
            return combined
        }

        @objc private func readFromHere(_ sender: NSMenuItem) {
            guard menuAnchor != NSNotFound else { return }
            model.playFrom(location: menuAnchor)
        }

        @objc private func readSelectedText(_ sender: NSMenuItem) {
            model.readSelectedText()
        }

        @objc private func pauseResume(_ sender: NSMenuItem) {
            guard model.isReading else { return }
            model.togglePlayPause()
        }

        @objc private func stopReading(_ sender: NSMenuItem) {
            model.stop()
        }
    }
}

// MARK: - Reader view

struct SummaryReaderView: View {
    let markdown: String
    @Bindable var model: SummaryReadbackModel
    let settings: StudioSettings
    var follow: Bool = true
    /// When true the text is an instructional placeholder, so reading controls stay disabled.
    var hasSummary: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            readbackControls
            Divider()
            if let error = model.error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .textSelection(.enabled)
                    .accessibilityLabel("Summary reading error: \(error)")
            }
            SummarySentenceTextView(
                model: model,
                settings: settings,
                hasSummary: hasSummary,
                follow: follow
            )
        }
        .onAppear { model.configure(markdown: markdown, settings: settings) }
        .onChange(of: markdown) { _, newValue in model.configure(markdown: newValue, settings: settings) }
        .onChange(of: settings.systemVoice) { _, _ in model.updateSettings(settings) }
        .onChange(of: settings.systemSpeechRate) { _, _ in model.updateSettings(settings) }
        .onChange(of: settings.systemSpeechPitch) { _, _ in model.updateSettings(settings) }
        .onChange(of: settings.systemSpeechVolume) { _, _ in model.updateSettings(settings) }
        // Closing the summary review mid-sentence must not leave speech running.
        .onDisappear { model.stop() }
    }

    // MARK: Controls

    private var readbackControls: some View {
        HStack(spacing: 10) {
            Button(model.isReading && !model.isPaused ? "Pause" : "Play", systemImage: model.isReading && !model.isPaused ? "pause.fill" : "play.fill") {
                model.togglePlayPause()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasSummary || model.sentences.isEmpty)
            .help(model.isReading && !model.isPaused
                ? "Pause summary reading (right-click for more options)"
                : "Read the summary aloud from the selected text, or from the start when nothing is selected (right-click for more options)")
            .accessibilityLabel(model.isReading && !model.isPaused ? "Pause summary reading" : "Play summary reading")
            .accessibilityHint("Reads the selected summary text aloud, or the whole summary from the start, with synchronized word highlighting. Right-click for read-from options.")
            .contextMenu { summaryOptionsMenu }

            Button("Stop", systemImage: "stop.fill") { model.stop() }
                .buttonStyle(.bordered)
                .disabled(!model.isReading && model.currentIndex == nil)
                .help("Stop summary reading and clear highlighting")
                .accessibilityLabel("Stop summary reading")

            Text(model.progressLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityLabel("Summary reading status: \(model.progressLabel)")

            Spacer(minLength: 8)

            Text("Apple Speech")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Summary reading uses the Apple on-device voice selected in Settings → Narration")
                .accessibilityLabel("Summary reading uses the Apple on-device voice")
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Summary playback controls")
    }

    /// The same read-from options as the text right-click menu and the menu bar,
    /// attached to the Play/Pause button.
    @ViewBuilder
    private var summaryOptionsMenu: some View {
        Button("Read from Start", systemImage: "forward.end") { model.playFromStart() }
            .disabled(!hasSummary || model.sentences.isEmpty)
        Button("Read from Selection", systemImage: "text.cursor") { model.playFromSelection() }
            .disabled(!hasSummary || !model.hasReadableSelection)
        Button("Read Selected Text Only", systemImage: "quote.bubble") { model.readSelectedText() }
            .disabled(!hasSummary || !model.hasNonEmptySelection)
        Divider()
        Button("Stop", systemImage: "stop.fill") { model.stop() }
            .disabled(!model.isReading)
    }
}
