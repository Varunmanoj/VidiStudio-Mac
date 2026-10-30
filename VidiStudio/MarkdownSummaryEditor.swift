import SwiftUI
import AppKit
import Combine

// MARK: - Pure Markdown transformations

enum MarkdownCommand: String, CaseIterable {
    case bold, italic, strikethrough, inlineCode, codeBlock
    case paragraph, heading1, heading2, heading3, heading4, heading5, heading6
    case blockquote, bulletedList, numberedList, taskList
    case link, image, table, horizontalRule, clearFormatting

    var title: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .strikethrough: return "Strikethrough"
        case .inlineCode: return "Inline Code"
        case .codeBlock: return "Code Block"
        case .paragraph: return "Paragraph"
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return "Heading \(rawValue.last!)"
        case .blockquote: return "Blockquote"
        case .bulletedList: return "Bulleted List"
        case .numberedList: return "Numbered List"
        case .taskList: return "Task List"
        case .link: return "Link"
        case .image: return "Image"
        case .table: return "Table"
        case .horizontalRule: return "Horizontal Rule"
        case .clearFormatting: return "Clear Formatting"
        }
    }
    var icon: String {
        switch self {
        case .bold: return "bold"
        case .italic: return "italic"
        case .strikethrough: return "strikethrough"
        case .inlineCode: return "chevron.left.forwardslash.chevron.right"
        case .codeBlock: return "curlybraces.square"
        case .paragraph: return "text.alignleft"
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6: return "textformat.size"
        case .blockquote: return "quote.opening"
        case .bulletedList: return "list.bullet"
        case .numberedList: return "list.number"
        case .taskList: return "checklist"
        case .link: return "link"
        case .image: return "photo"
        case .table: return "tablecells"
        case .horizontalRule: return "minus"
        case .clearFormatting: return "eraser"
        }
    }
    var shortcut: String {
        switch self {
        case .bold: return "Command-B"
        case .italic: return "Command-I"
        case .strikethrough: return "Command-Shift-X"
        case .inlineCode: return "Command-Option-`"
        case .codeBlock: return "Command-Option-Shift-C"
        case .link: return "Command-K"
        case .image: return "Command-Shift-I"
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return "Command-Option-\(rawValue.last!)"
        case .paragraph: return "Command-Option-0"
        case .bulletedList: return "Command-Shift-8"
        case .numberedList: return "Command-Shift-7"
        case .taskList: return "Command-Shift-9"
        case .blockquote: return "Command-Option-Shift-Q"
        case .table: return "Command-Option-T"
        case .horizontalRule: return "Command-Option--"
        case .clearFormatting: return "Command-Option-Shift-K"
        }
    }
    var headingLevel: Int? {
        switch self {
        case .heading1: return 1
        case .heading2: return 2
        case .heading3: return 3
        case .heading4: return 4
        case .heading5: return 5
        case .heading6: return 6
        default: return nil
        }
    }
}

struct MarkdownEdit: Equatable {
    var text: String
    var selection: NSRange
}

enum MarkdownTransformer {
    static func apply(_ command: MarkdownCommand, to text: String, selection: NSRange) -> MarkdownEdit {
        let source = text as NSString
        let safe = clamped(selection, in: source.length)
        switch command {
        case .bold: return toggleWrap("**", text: text, selection: safe)
        case .italic: return toggleWrap("*", text: text, selection: safe)
        case .strikethrough: return toggleWrap("~~", text: text, selection: safe)
        case .inlineCode: return toggleWrap("`", text: text, selection: safe)
        case .codeBlock:
            return wrapBlock("```", text: text, selection: safe)
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return setHeading(command.headingLevel ?? 1, text: text, selection: safe)
        case .paragraph: return setHeading(nil, text: text, selection: safe)
        case .blockquote: return prefixLines("> ", text: text, selection: safe)
        case .bulletedList: return toggleLinePrefix("- ", text: text, selection: safe)
        case .numberedList: return toggleNumberedList(text: text, selection: safe)
        case .taskList: return toggleLinePrefix("- [ ] ", text: text, selection: safe)
        case .link: return insertLink(image: false, text: text, selection: safe)
        case .image: return insertLink(image: true, text: text, selection: safe)
        case .table:
            let template = "| Column 1 | Column 2 |\n| --- | --- |\n| Cell | Cell |\n"
            return insertBlock(template, text: text, selection: safe)
        case .horizontalRule:
            return insertBlock("---\n", text: text, selection: safe)
        case .clearFormatting:
            return clearFormatting(text: text, selection: safe)
        }
    }

    private static func clamped(_ range: NSRange, in length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        let maximum = max(0, length - location)
        return NSRange(location: location, length: min(max(0, range.length), maximum))
    }

    private static func toggleWrap(_ marker: String, text: String, selection: NSRange) -> MarkdownEdit {
        let source = text as NSString
        if selection.length == 0 {
            let insertion = marker + marker
            let value = source.replacingCharacters(in: selection, with: insertion)
            return MarkdownEdit(text: value, selection: NSRange(location: selection.location + marker.utf16.count, length: 0))
        }
        let selected = source.substring(with: selection)
        let before = NSRange(location: max(0, selection.location - marker.utf16.count), length: marker.utf16.count)
        let after = NSRange(location: selection.location + selection.length, length: marker.utf16.count)
        let wrapped = selection.location >= marker.utf16.count
            && after.location + after.length <= source.length
            && source.substring(with: before) == marker
            && source.substring(with: after) == marker
        if wrapped {
            let value = source.replacingCharacters(in: NSRange(location: before.location, length: before.length + selection.length + after.length), with: selected)
            return MarkdownEdit(text: value, selection: NSRange(location: before.location, length: selection.length))
        }
        let value = source.replacingCharacters(in: selection, with: marker + selected + marker)
        return MarkdownEdit(text: value, selection: NSRange(location: selection.location + marker.utf16.count, length: selection.length))
    }

    private static func wrapBlock(_ fence: String, text: String, selection: NSRange) -> MarkdownEdit {
        let source = text as NSString
        let selected = source.substring(with: selection)
        let replacement = fence + "\n" + selected + "\n" + fence
        let value = source.replacingCharacters(in: selection, with: replacement)
        return MarkdownEdit(text: value, selection: NSRange(location: selection.location + fence.utf16.count + 1, length: selection.length))
    }

    private static func insertBlock(_ block: String, text: String, selection: NSRange) -> MarkdownEdit {
        let source = text as NSString
        let value = source.replacingCharacters(in: selection, with: block)
        return MarkdownEdit(text: value, selection: NSRange(location: selection.location + block.utf16.count, length: 0))
    }

    private static func lineRange(for selection: NSRange, in source: NSString) -> NSRange {
        if selection.length == 0 { return source.lineRange(for: selection) }
        return source.lineRange(for: NSRange(location: selection.location, length: max(0, selection.length)))
    }

    private static func setHeading(_ level: Int?, text: String, selection: NSRange) -> MarkdownEdit {
        let source = text as NSString
        let range = lineRange(for: selection, in: source)
        let original = source.substring(with: range)
        let lines = original.components(separatedBy: "\n")
        let output = lines.map { line -> String in
            let stripped = line.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression)
            guard let level else { return stripped }
            return String(repeating: "#", count: level) + " " + stripped
        }.joined(separator: "\n")
        let value = source.replacingCharacters(in: range, with: output)
        return MarkdownEdit(text: value, selection: NSRange(location: range.location, length: output.utf16.count))
    }

    private static func prefixLines(_ prefix: String, text: String, selection: NSRange) -> MarkdownEdit {
        let source = text as NSString
        let range = lineRange(for: selection, in: source)
        let original = source.substring(with: range)
        let lines = original.components(separatedBy: "\n")
        let output = lines.map { prefix + $0 }.joined(separator: "\n")
        let value = source.replacingCharacters(in: range, with: output)
        return MarkdownEdit(text: value, selection: NSRange(location: range.location, length: output.utf16.count))
    }

    private static func toggleLinePrefix(_ prefix: String, text: String, selection: NSRange) -> MarkdownEdit {
        let source = text as NSString
        let range = lineRange(for: selection, in: source)
        let original = source.substring(with: range)
        let lines = original.components(separatedBy: "\n").filter { !$0.isEmpty }
        let hasPrefix = !lines.isEmpty && lines.allSatisfy { $0.hasPrefix(prefix) }
        let output = lines.map { $0.hasPrefix(prefix) && hasPrefix ? String($0.dropFirst(prefix.count)) : (hasPrefix ? $0 : prefix + $0) }
            .joined(separator: "\n")
        let value = source.replacingCharacters(in: range, with: output)
        return MarkdownEdit(text: value, selection: NSRange(location: range.location, length: output.utf16.count))
    }

    private static func toggleNumberedList(text: String, selection: NSRange) -> MarkdownEdit {
        let source = text as NSString
        let range = lineRange(for: selection, in: source)
        let original = source.substring(with: range)
        let lines = original.components(separatedBy: "\n").filter { !$0.isEmpty }
        let pattern = #"^\d+\.\s+"#
        let hasPrefix = !lines.isEmpty && lines.allSatisfy { $0.range(of: pattern, options: .regularExpression) != nil }
        let output = lines.enumerated().map { index, line in
            let stripped = line.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            return hasPrefix ? stripped : "\(index + 1). " + stripped
        }.joined(separator: "\n")
        let value = source.replacingCharacters(in: range, with: output)
        return MarkdownEdit(text: value, selection: NSRange(location: range.location, length: output.utf16.count))
    }

    private static func insertLink(image: Bool, text: String, selection: NSRange) -> MarkdownEdit {
        let source = text as NSString
        let selected = source.substring(with: selection)
        let label = selected.isEmpty ? "text" : selected
        let prefix = image ? "![" : "["
        let replacement = prefix + label + "](url)"
        let value = source.replacingCharacters(in: selection, with: replacement)
        let labelStart = selection.location + prefix.utf16.count
        let urlStart = labelStart + label.utf16.count + 2
        return MarkdownEdit(text: value, selection: NSRange(location: urlStart, length: 3))
    }

    private static func clearFormatting(text: String, selection: NSRange) -> MarkdownEdit {
        let source = text as NSString
        let selected = selection.length == 0 ? source.substring(with: lineRange(for: selection, in: source)) : source.substring(with: selection)
        let plain = selected
            .replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^>\s?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^(?:-\s\[[ xX]\]\s|-\s|\*\s|\d+\.\s)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "~~", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "")
        let value = source.replacingCharacters(in: selection, with: plain)
        return MarkdownEdit(text: value, selection: NSRange(location: selection.location, length: plain.utf16.count))
    }

    /// Returns the list prefix that Enter should repeat, or nil for ordinary text.
    static func listContinuation(for line: String) -> String? {
        if line.range(of: #"^\s*-\s\[[ xX]\]\s+"#, options: .regularExpression) != nil { return "- [ ] " }
        if line.range(of: #"^\s*[-*+]\s+"#, options: .regularExpression) != nil { return "- " }
        if let match = line.range(of: #"^(\s*)(\d+)\.\s+"#, options: .regularExpression) {
            let prefix = line[match]
            let number = prefix.trimmingCharacters(in: .whitespaces).split(separator: ".").first.flatMap { Int($0) } ?? 1
            return "\(number + 1). "
        }
        if line.hasPrefix("> ") { return "> " }
        return nil
    }
}

// MARK: - Native editor

@MainActor
final class MarkdownEditorController: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    weak var textView: NSTextView?

    func apply(_ command: MarkdownCommand) {
        guard let textView, let storage = textView.textStorage else { return }
        let edit = MarkdownTransformer.apply(command, to: storage.string, selection: textView.selectedRange())
        guard edit.text != storage.string || edit.selection != textView.selectedRange() else { return }
        textView.undoManager?.beginUndoGrouping()
        textView.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: edit.text)
        textView.setSelectedRange(edit.selection)
        textView.didChangeText()
        textView.undoManager?.endUndoGrouping()
        textView.window?.makeFirstResponder(textView)
    }

    func undo() {
        textView?.undoManager?.undo()
    }
    func redo() {
        textView?.undoManager?.redo()
    }
    func focus() {
        textView?.window?.makeFirstResponder(textView)
    }
}

struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    @ObservedObject var controller: MarkdownEditorController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 18, height: 14)
        textView.string = text
        controller.textView = textView
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        controller.textView = textView
        if textView.string != text, !context.coordinator.isEditing {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextEditor
        weak var textView: NSTextView?
        var isEditing = false

        init(_ parent: MarkdownTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isEditing = true
            parent.text = textView.string
            isEditing = false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let source = textView.string as NSString
            let lineRange = source.lineRange(for: textView.selectedRange())
            let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
            guard let prefix = MarkdownTransformer.listContinuation(for: line) else { return false }
            if line.trimmingCharacters(in: .whitespaces) == prefix.trimmingCharacters(in: .whitespaces) {
                textView.replaceCharacters(in: lineRange, with: "")
                return true
            }
            textView.insertText("\n" + prefix, replacementRange: textView.selectedRange())
            return true
        }
    }
}

// MARK: - Summary editor

struct SummaryMarkdownEditorView: View {
    @Binding var text: String
    @Binding var origin: SummaryOrigin
    let onCancel: () -> Void

    @StateObject private var controller = MarkdownEditorController()
    @State private var showPreview = false
    @State private var showingHelp = false

    private var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Edit Summary", systemImage: "pencil").font(.headline)
                Text("\(wordCount) words · \(text.count) characters")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Picker("Provenance", selection: $origin) {
                    ForEach(SummaryOrigin.editableCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 190)
                .help("Choose the whole-summary provenance. Unknown is replaced when you choose one of these labels.")
                Button("Revert", systemImage: "arrow.uturn.backward") { onCancel() }
                    .help("Discard uncommitted edits and restore the saved summary")
            }
            .controlSize(.small)
            .padding(.horizontal, 16).padding(.vertical, 8)
            toolbar
            Divider()
            HStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Type or paste your summary. Use the toolbar or Markdown shortcuts to format headings, lists, quotes, code, links, and tables.")
                            .font(.body).foregroundStyle(.tertiary)
                            .padding(.horizontal, 24).padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                    MarkdownTextEditor(text: $text, controller: controller)
                        .accessibilityLabel("Summary Markdown editor")
                }
                if showPreview {
                    Divider()
                    MarkdownSummaryView(markdown: text.isEmpty ? "Nothing to preview yet." : text)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .sheet(isPresented: $showingHelp) { MarkdownHelpView() }
        .onAppear { controller.focus() }
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                group {
                    toolbarButton(.bold)
                    toolbarButton(.italic)
                    toolbarButton(.strikethrough)
                    toolbarButton(.inlineCode)
                }
                Divider().frame(height: 18)
                group {
                    toolbarButton(.paragraph)
                    ForEach([1, 2, 3, 4, 5, 6], id: \.self) { level in
                        toolbarButton(level == 1 ? .heading1 : level == 2 ? .heading2 : level == 3 ? .heading3 : level == 4 ? .heading4 : level == 5 ? .heading5 : .heading6)
                    }
                }
                Divider().frame(height: 18)
                group {
                    toolbarButton(.blockquote)
                    toolbarButton(.codeBlock)
                    toolbarButton(.bulletedList)
                    toolbarButton(.numberedList)
                    toolbarButton(.taskList)
                }
                Divider().frame(height: 18)
                group {
                    toolbarButton(.link)
                    toolbarButton(.image)
                    toolbarButton(.table)
                    toolbarButton(.horizontalRule)
                }
                Divider().frame(height: 18)
                group {
                    toolbarButton(.clearFormatting)
                    Button(showPreview ? "Hide Preview" : "Preview", systemImage: "eye") { showPreview.toggle() }
                        .keyboardShortcut("p", modifiers: [.command, .option, .shift])
                        .help("Toggle preview (Command-Option-Shift-P)")
                    Button("Markdown Help", systemImage: "questionmark.circle") { showingHelp = true }
                        .keyboardShortcut("m", modifiers: [.command, .option, .shift])
                        .help("Open the Markdown cheat sheet (Command-Option-Shift-M)")
                }
                Divider().frame(height: 18)
                group {
                    Button("Undo", systemImage: "arrow.uturn.backward") { controller.undo() }
                        .help("Undo (Command-Z)")
                        .accessibilityLabel("Undo summary edit")
                    Button("Redo", systemImage: "arrow.uturn.forward") { controller.redo() }
                        .help("Redo (Command-Shift-Z)")
                        .accessibilityLabel("Redo summary edit")
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 2) { content() }
    }

    private func toolbarButton(_ command: MarkdownCommand) -> some View {
        let shortcut = markdownShortcut(command)
        return Button(command.title, systemImage: command.icon) { controller.apply(command) }
            .labelStyle(.iconOnly)
            .keyboardShortcut(shortcut.0, modifiers: shortcut.1)
            .help("\(command.title) (\(command.shortcut))")
            .accessibilityLabel(command.title)
    }

    private func markdownShortcut(_ command: MarkdownCommand) -> (KeyEquivalent, EventModifiers) {
        switch command {
        case .bold: return ("b", .command)
        case .italic: return ("i", .command)
        case .strikethrough: return ("x", [.command, .shift])
        case .inlineCode: return ("`", [.command, .option])
        case .codeBlock: return ("c", [.command, .option, .shift])
        case .heading1: return ("1", [.command, .option])
        case .heading2: return ("2", [.command, .option])
        case .heading3: return ("3", [.command, .option])
        case .heading4: return ("4", [.command, .option])
        case .heading5: return ("5", [.command, .option])
        case .heading6: return ("6", [.command, .option])
        case .paragraph: return ("0", [.command, .option])
        case .bulletedList: return ("8", [.command, .shift])
        case .numberedList: return ("7", [.command, .shift])
        case .taskList: return ("9", [.command, .shift])
        case .blockquote: return ("q", [.command, .option, .shift])
        case .table: return ("t", [.command, .option])
        case .horizontalRule: return ("-", [.command, .option])
        case .clearFormatting: return ("k", [.command, .option, .shift])
        case .link: return ("k", .command)
        case .image: return ("i", [.command, .shift])
        }
    }
}

struct MarkdownHelpView: View {
    @Environment(\.dismiss) private var dismiss
    private let shortcuts: [(String, String)] = [
        ("Bold", "Command-B"), ("Italic", "Command-I"), ("Strikethrough", "Command-Shift-X"),
        ("Inline code", "Command-Option-`"), ("Code block", "Command-Option-Shift-C"),
        ("Link", "Command-K"), ("Image", "Command-Shift-I"), ("Headings 1–6", "Command-Option-1–6"),
        ("Paragraph", "Command-Option-0"), ("Bulleted list", "Command-Shift-8"),
        ("Numbered list", "Command-Shift-7"), ("Task list", "Command-Shift-9"),
        ("Blockquote", "Command-Option-Shift-Q"), ("Table", "Command-Option-T"),
        ("Horizontal rule", "Command-Option--"), ("Clear formatting", "Command-Option-Shift-K"),
        ("Preview", "Command-Option-Shift-P"), ("Markdown Help", "Command-Option-Shift-M"),
        ("Undo / Redo", "Command-Z / Command-Shift-Z"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Markdown Help").font(.title2.bold())
            Text("Supported: headings, paragraphs, bold, italic, strikethrough, bulleted/numbered/task lists, blockquotes, inline and fenced code, links, tables, and horizontal rules. Images insert Markdown and render as alt text and a link; remote images, math, Mermaid, and footnotes are not included.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, item in
                        HStack { Text(item.0); Spacer(); Text(item.1).monospaced().foregroundStyle(.secondary) }
                    }
                }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).help("Close the Markdown cheat sheet") }
        }
        .padding(20)
        .frame(width: 520, height: 560)
    }
}
