import SwiftUI

/// Native Markdown reading view shared by the Summary reading page and the
/// editor's live preview. Tables and task lists are rendered explicitly because
/// Foundation's attributed Markdown does not provide block layout for them.
struct MarkdownSummaryView: View {
    let markdown: String

    private enum Kind: Equatable {
        case heading(Int)
        case paragraph
        case bullet(Int)
        case numbered(Int)
        case task(Bool)
        case quote
        case code
        case table
        case rule
    }

    private struct Block: Identifiable {
        let id: Int
        var text: AttributedString
        var kind: Kind
        var table: [[String]]? = nil
    }

    private var blocks: [Block] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result: [Block] = []
        var index = 0
        var nextID = 0
        func append(_ text: String, _ kind: Kind, _ table: [[String]]? = nil) {
            result.append(Block(id: nextID, text: inline(text), kind: kind, table: table))
            nextID += 1
        }
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                index += 1
                var code: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                index += 1
                append(code.joined(separator: "\n"), .code)
                continue
            }
            if isTableStart(lines, index) {
                var table: [[String]] = [cells(line)]
                index += 2
                while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    table.append(cells(lines[index]))
                    index += 1
                }
                append("", .table, table)
                continue
            }
            if line.range(of: #"^\s*([-*_]\s*){3,}$"#, options: .regularExpression) != nil {
                append("", .rule)
                index += 1
                continue
            }
            if let match = heading(line) {
                append(match.text, .heading(match.level))
                index += 1
                continue
            }
            if let task = taskItem(line) {
                append((task.checked ? "\u{2611} " : "\u{2610} ") + task.text, .task(task.checked))
                index += 1
                continue
            }
            if let bullet = bulletItem(line) {
                append(bullet.text, .bullet(bullet.depth))
                index += 1
                continue
            }
            if let numbered = numberedItem(line) {
                append("\(numbered.number). \(numbered.text)", .numbered(numbered.depth))
                index += 1
                continue
            }
            if line.hasPrefix("> ") || line == ">" {
                append(String(line.dropFirst(line == ">" ? 1 : 2)), .quote)
                index += 1
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }
            var paragraph = [line]
            index += 1
            while index < lines.count,
                  !lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                  heading(lines[index]) == nil,
                  taskItem(lines[index]) == nil,
                  bulletItem(lines[index]) == nil,
                  numberedItem(lines[index]) == nil,
                  !lines[index].hasPrefix("> "),
                  !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```"),
                  !isTableStart(lines, index),
                  lines[index].range(of: #"^\s*([-*_]\s*){3,}$"#, options: .regularExpression) == nil {
                paragraph.append(lines[index])
                index += 1
            }
            append(paragraph.joined(separator: " "), .paragraph)
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(blocks) { block in
                    blockView(block)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(block.text)
                .font(level == 1 ? .largeTitle.bold() : level == 2 ? .title2.bold() : level == 3 ? .title3.bold() : .headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 6)
        case .paragraph:
            Text(block.text).font(.body).lineSpacing(4)
        case .bullet(let depth):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").accessibilityHidden(true)
                Text(block.text)
            }
            .padding(.leading, CGFloat(max(0, depth)) * 18)
        case .numbered(let depth):
            Text(block.text)
                .padding(.leading, CGFloat(max(0, depth)) * 18)
        case .task(let checked):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checked ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                Text(block.text)
            }
        case .quote:
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(.secondary.opacity(0.5)).frame(width: 3)
                Text(block.text).foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        case .code:
            Text(block.text)
                .font(.system(.body, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        case .table:
            if let table = block.table { tableView(table) }
        case .rule:
            Divider().padding(.vertical, 4)
        }
    }

    private func tableView(_ rows: [[String]]) -> some View {
        let columns = rows.map(\.count).max() ?? 0
        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(0..<max(columns, 1), id: \.self) { column in
                            Text(inline(column < row.count ? row[column] : ""))
                                .font(rowIndex == 0 ? .callout.weight(.semibold) : .callout)
                                .frame(minWidth: 110, maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(rowIndex == 0 ? Color.secondary.opacity(0.12) : Color.clear)
                            Divider()
                        }
                    }
                    Divider()
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .accessibilityLabel("Markdown table")
    }

    private func inline(_ value: String) -> AttributedString {
        (try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value)
    }

    private func isTableStart(_ lines: [String], _ index: Int) -> Bool {
        guard index + 1 < lines.count, lines[index].contains("|") else { return false }
        return lines[index + 1].range(of: #"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$"#, options: .regularExpression) != nil
    }

    private func cells(_ line: String) -> [String] {
        line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func heading(_ line: String) -> (level: Int, text: String)? {
        guard let match = line.range(of: #"^(#{1,6})\s+(.*)$"#, options: .regularExpression) else { return nil }
        let value = String(line[match])
        let hashes = value.prefix { $0 == "#" }.count
        let text = value.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
        return (hashes, text)
    }

    private func taskItem(_ line: String) -> (checked: Bool, text: String)? {
        guard let match = line.range(of: #"^\s*-\s*\[([ xX])\]\s+(.*)$"#, options: .regularExpression) else { return nil }
        let value = String(line[match])
        let checked = value.range(of: #"\[[xX]\]"#, options: .regularExpression) != nil
        let text = value.replacingOccurrences(of: #"^\s*-\s*\[[ xX]\]\s+"#, with: "", options: .regularExpression)
        return (checked, text)
    }

    private func bulletItem(_ line: String) -> (depth: Int, text: String)? {
        guard let match = line.range(of: #"^(\s*)[-*+]\s+(.*)$"#, options: .regularExpression) else { return nil }
        let value = String(line[match])
        let depth = (value.prefix { $0 == " " }.count / 2)
        let text = value.replacingOccurrences(of: #"^\s*[-*+]\s+"#, with: "", options: .regularExpression)
        return (depth, text)
    }

    private func numberedItem(_ line: String) -> (number: Int, depth: Int, text: String)? {
        guard let match = line.range(of: #"^(\s*)(\d+)\.\s+(.*)$"#, options: .regularExpression) else { return nil }
        let value = String(line[match])
        let depth = value.prefix { $0 == " " }.count / 2
        let pieces = value.trimmingCharacters(in: .whitespaces).split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let number = Int(pieces.first ?? "") ?? 1
        let text = pieces.count > 1 ? pieces[1].trimmingCharacters(in: .whitespaces) : value
        return (number, depth, text)
    }
}
