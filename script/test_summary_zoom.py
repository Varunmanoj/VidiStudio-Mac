"""Exercise production zoom/display/anchor methods with native AppKit layout."""
from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'VidiStudio/SummaryReadback.swift').read_text()
parser = source[source.index('struct SummarySentence:'):source.index('// MARK: - Readback model')]
zoom = source[source.index('    var zoom: Double = 1'):source.index('    var sentences: [SummarySentence] = []')]
display = source[source.index('    private func displayPrefix'):source.index('    // MARK: Speech plumbing')]
anchors = source[source.index('        // Anchor the same character'):source.index('        weak var textView: SummaryTextView?')]
subclass = source[source.index('final class SummaryTextView:'):source.index('struct SummarySentenceTextView:')]
harness = r'''
import AppKit
import SwiftUI
// PARSER
@MainActor final class SummaryReadbackModel {
// ZOOM
    var sentences: [SummarySentence] = []
    var currentIndex: Int?
    var wordRange: NSRange?
    private var cachedLines: [(prefix: String, body: String)] = []
    private var cachedLineRanges: [NSRange] = []
    private var cachedPlain = ""
    init(_ markdown: String) {
        sentences = SummarySpeechParser.sentences(from: markdown)
        rebuildDisplayCache()
    }
// DISPLAY
}
// SUBCLASS
@MainActor final class AnchorProbe {
    weak var textView: SummaryTextView?
// ANCHORS
}
@MainActor func check(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
}
@main struct Run {
    @MainActor static func main() {
        let paragraph = String(repeating: "Andy helps Olivia with her inhaler, नमस्ते 世界 👩🏽‍🦯. ", count: 45)
        let model = SummaryReadbackModel("# Andy\n\n" + paragraph + "\n\n- A list item\n\n```\ncode\n```")
        let plain = model.plainText
        let ranges = model.sentences.indices.map { model.lineRange(forSentence: $0)! }
        model.currentIndex = 1
        model.wordRange = NSRange(location: ranges[1].location, length: 4)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 220))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        let view = SummaryTextView(frame: NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: 220))
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 20, height: 14)
        scroll.documentView = view
        let selection = NSRange(location: ranges[2].location + 2, length: 7)
        func render() -> NSAttributedString {
            let content = model.displayContent(sentenceBackground: .blue, wordBackground: .yellow, wordForeground: .black)
            view.textStorage!.setAttributedString(content)
            view.layoutManager!.ensureLayout(for: view.textContainer!)
            view.setSelectedRange(selection)
            check(content.string == plain, "Zoom changed displayed text")
            check(model.sentences.indices.map { model.lineRange(forSentence: $0)! } == ranges, "Zoom shifted UTF-16 speech ranges")
            check(content.attribute(.backgroundColor, at: model.wordRange!.location, effectiveRange: nil) as? NSColor == .yellow, "Zoom lost the word highlight")
            check(view.selectedRange() == selection, "Zoom lost selection")
            check(view.layoutManager!.usedRect(for: view.textContainer!).width <= view.textContainer!.size.width + 1, "Zoom caused horizontal overflow")
            return content
        }
        let activeRange = model.lineRange(forSentence: model.currentIndex!)!
        let word = model.wordRange!
        let sentenceProbe = (activeRange.location..<NSMaxRange(activeRange)).first { !NSLocationInRange($0, word) }!
        let baseline = model.displayContent(sentenceBackground: .blue, wordBackground: .yellow, wordForeground: .black, highlightSentence: false, highlightWord: false)
        for sentenceOn in [false, true] {
            for wordOn in [false, true] {
                let content = model.displayContent(sentenceBackground: .blue, wordBackground: .yellow, wordForeground: .black, highlightSentence: sentenceOn, highlightWord: wordOn)
                check(content.string == baseline.string, "Highlight choices changed the summary text")
                check((content.attribute(.backgroundColor, at: sentenceProbe, effectiveRange: nil) as? NSColor) == (sentenceOn ? .blue : nil), "Sentence toggle did not independently control its background")
                check((content.attribute(.backgroundColor, at: word.location, effectiveRange: nil) as? NSColor) == (wordOn ? .yellow : sentenceOn ? .blue : nil), "Word toggle did not independently control its background")
                let foreground = content.attribute(.foregroundColor, at: word.location, effectiveRange: nil) as? NSColor
                let expected = wordOn ? NSColor.black : baseline.attribute(.foregroundColor, at: word.location, effectiveRange: nil) as? NSColor
                check(foreground == expected, "Disabling the word highlight left its foreground styling behind")
                check(model.wordRange == word && model.lineRange(forSentence: model.currentIndex!) == activeRange, "Toggling highlights changed readback position")
            }
        }
        var previousHeight: CGFloat = 0
        for zoom in [0.5, 1.0, 2.0, 4.0] {
            model.setZoom(zoom)
            let content = render()
            check(abs((content.attribute(.font, at: 0, effectiveRange: nil) as! NSFont).pointSize - 24 * zoom) < 0.01, "Heading size did not scale")
            let height = view.layoutManager!.usedRect(for: view.textContainer!).height
            check(height > previousHeight, "Text did not reflow at higher zoom")
            previousHeight = height
        }
        model.setZoom(1); _ = render()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
        let probe = AnchorProbe(); probe.textView = view
        let anchor = probe.visibleAnchor()!
        model.setZoom(2); _ = render()
        probe.restoreVisibleAnchor(anchor)
        let after = probe.visibleAnchor()!
        check(abs(after.1 - anchor.1) < 1, "Reflow lost the viewport anchor offset")
        model.setZoom(10); check(model.zoomPercent == 400, "Upper limit")
        model.zoomIn(); check(model.zoomPercent == 400, "Zoom In exceeded upper limit")
        model.setZoom(-2); check(model.zoomPercent == 50, "Lower limit")
        model.zoomOut(); check(model.zoomPercent == 50, "Zoom Out exceeded lower limit")
        model.setZoom(.nan); check(model.zoomPercent == 50, "Nonfinite zoom")
        model.setZoom(1.56); model.zoomIn(); check(model.zoomPercent == 160, "Zoom In after pinch")
        model.setZoom(1.56); model.zoomOut(); check(model.zoomPercent == 150, "Zoom Out after pinch")
        model.setZoom(1); check(model.zoomPercent == 100, "100% reset")
        print("PASS: independent sentence/word highlight combinations; native 50/100/200/400% wrapping, fonts, multilingual UTF-16 speech/highlights, selection, viewport anchor, zoom steps/bounds/reset")
    }
}
'''
for marker, code in [('PARSER', parser), ('ZOOM', zoom), ('DISPLAY', display), ('SUBCLASS', subclass), ('ANCHORS', anchors)]:
    harness = harness.replace('// ' + marker, code)
build = ROOT / 'build/summary-zoom-test'
build.mkdir(exist_ok=True)
(build / 'main.swift').write_text(harness)
env = os.environ | {'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(build / 'modules'), str(build / 'main.swift'), '-o', str(build / 'test')], check=True, env=env)
subprocess.run([str(build / 'test')], check=True)
