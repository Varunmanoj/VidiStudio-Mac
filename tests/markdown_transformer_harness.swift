import Foundation

@main
struct MarkdownTransformerHarness {
    static func edit(_ command: MarkdownCommand, _ text: String, _ location: Int, _ length: Int) -> MarkdownEdit {
        MarkdownTransformer.apply(command, to: text, selection: NSRange(location: location, length: length))
    }

    static func main() {
        var result = edit(.bold, "hello", 0, 5)
        precondition(result.text == "**hello**", result.text)
        precondition((result.text as NSString).substring(with: result.selection) == "hello")
        let toggled = MarkdownTransformer.apply(.bold, to: result.text, selection: result.selection)
        precondition(toggled.text == "hello", toggled.text)

        result = edit(.bold, "", 0, 0)
        precondition(result.text == "****" && result.selection.location == 2)

        result = edit(.italic, "word", 0, 4)
        precondition(result.text == "*word*")

        result = edit(.strikethrough, "gone", 0, 4)
        precondition(result.text == "~~gone~~")

        result = edit(.inlineCode, "x", 0, 1)
        precondition(result.text == "`x`")

        result = edit(.heading2, "Title", 0, 0)
        precondition(result.text == "## Title", result.text)
        result = MarkdownTransformer.apply(.paragraph, to: result.text, selection: NSRange(location: 3, length: 0))
        precondition(result.text == "Title", result.text)

        result = edit(.bulletedList, "a\nb", 0, 3)
        precondition(result.text == "- a\n- b", result.text)
        result = MarkdownTransformer.apply(.bulletedList, to: result.text, selection: NSRange(location: 0, length: 7))
        precondition(result.text == "a\nb", result.text)

        result = edit(.numberedList, "a\nb", 0, 3)
        precondition(result.text == "1. a\n2. b", result.text)

        result = edit(.taskList, "a", 0, 1)
        precondition(result.text == "- [ ] a", result.text)

        result = edit(.blockquote, "a\nb", 0, 3)
        precondition(result.text == "> a\n> b", result.text)

        result = edit(.link, "text", 0, 4)
        precondition(result.text == "[text](url)", result.text)
        precondition((result.text as NSString).substring(with: result.selection) == "url")

        result = edit(.image, "alt", 0, 3)
        precondition(result.text == "![alt](url)", result.text)

        result = edit(.table, "", 0, 0)
        precondition(result.text.contains("| Column 1 | Column 2 |"), result.text)
        precondition(result.text.contains("| --- | --- |"), result.text)

        result = edit(.horizontalRule, "", 0, 0)
        precondition(result.text == "---\n", result.text)

        let formatted = "## **Bold** and `code`"
        result = edit(.clearFormatting, formatted, 0, (formatted as NSString).length)
        precondition(!result.text.contains("**") && !result.text.contains("#") && !result.text.contains("`"), result.text)
        precondition(result.text.contains("Bold") && result.text.contains("code"))

        result = edit(.codeBlock, "line", 0, 4)
        precondition(result.text == "```\nline\n```", result.text)

        precondition(MarkdownTransformer.listContinuation(for: "- item") == "- ")
        precondition(MarkdownTransformer.listContinuation(for: "1. item") == "2. ")
        precondition(MarkdownTransformer.listContinuation(for: "- [ ] item") == "- [ ] ")
        precondition(MarkdownTransformer.listContinuation(for: "> quote") == "> ")
        precondition(MarkdownTransformer.listContinuation(for: "plain") == nil)

        // Text outside the selection is preserved.
        result = edit(.bold, "keep this change", 5, 4)
        precondition(result.text == "keep **this** change", result.text)
        print("PASS: Markdown transformations, toggles, lists, links, and continuation")
    }
}
