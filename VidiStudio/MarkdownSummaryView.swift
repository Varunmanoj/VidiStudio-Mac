import SwiftUI

/// Foundation parses Markdown; native views supply its block layout and heading semantics.
struct MarkdownSummaryView: View {
    let markdown: String

    private struct Block: Identifiable {
        let id: Int
        var text: AttributedString
        let heading: Int?
        let marker: String?
        let depth: Int
        let isQuote: Bool
        let isCode: Bool
    }

    private var blocks: [Block] {
        guard let parsed = try? AttributedString(markdown: markdown) else {
            return [Block(id: 0, text: AttributedString(markdown), heading: nil, marker: nil, depth: 0, isQuote: false, isCode: false)]
        }
        var result: [Block] = []
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
            result.append(Block(id: identity, text: fragment, heading: heading, marker: marker, depth: depth, isQuote: quote, isCode: code))
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(blocks) { block in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        if let marker = block.marker {
                            Text(marker).monospacedDigit().frame(minWidth: 18, alignment: .trailing)
                                .accessibilityHidden(true)
                        }
                        if let level = block.heading {
                            Text(block.text)
                                .font(level == 1 ? .largeTitle.bold() : level == 2 ? .title2.bold() : .title3.bold())
                                .accessibilityAddTraits(.isHeader)
                        } else {
                            Text(block.text)
                                .font(block.isCode ? .system(.body, design: .monospaced) : .body)
                                .foregroundStyle(block.isQuote ? .secondary : .primary)
                                .lineSpacing(4)
                        }
                    }
                    .padding(.leading, CGFloat(max(0, block.depth - 1)) * 24)
                    .padding(.top, block.heading == nil ? 0 : 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }
}
