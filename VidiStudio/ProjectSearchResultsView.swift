import SwiftUI

enum ProjectSearchHighlight {
    static let defaultColor = "#FFD60A"

    static func text(_ text: String, query: ProjectSearchQuery, enabled: Bool, color: String) -> AttributedString {
        var content = AttributedString(text)
        guard enabled else { return content }
        let rgb = SummaryHighlightColor.rgb(from: color) ?? (red: 1, green: 214 / 255, blue: 10 / 255)
        func linear(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
        let background = Color(red: Double(rgb.red), green: Double(rgb.green), blue: Double(rgb.blue))
        for range in query.matchingRanges(in: text) {
            guard let lower = AttributedString.Index(range.lowerBound, within: content),
                  let upper = AttributedString.Index(range.upperBound, within: content) else { continue }
            content[lower..<upper].backgroundColor = background
            content[lower..<upper].foregroundColor = luminance > 0.179 ? .black : .white
        }
        return content
    }
}

struct ProjectSearchResultsView: View {
    @Bindable var search: ProjectSearchState
    let settings: StudioSettings
    let section: String
    let canOpen: Bool
    let open: (ProjectSearchHit) -> Void

    private var groups: [ProjectSearchGroup] { search.groups[section] ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(groups.reduce(0) { $0 + $1.hits.count }) matches")
                .font(.caption).foregroundStyle(.secondary).padding(12)
                .accessibilityIdentifier("project-search-count")
            if groups.isEmpty {
                ContentUnavailableView("No matches", systemImage: "magnifyingglass")
            } else {
                List(selection: $search.selectedHitID) {
                    ForEach(groups) { group in
                        Section(group.title) {
                            ForEach(group.hits) { hit in
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        if let start = hit.start, let end = hit.end {
                                            Text("\(hit.importedCombined ? "AD Transcript" : hit.isDescription ? "AD" : "Transcript") · \(timecode(start))–\(timecode(end))")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Text(ProjectSearchHighlight.text(hit.text, query: search.query,
                                            enabled: settings.searchHighlightEnabled, color: settings.searchHighlightColor))
                                            .textSelection(.enabled)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Button(group.result.state == "draft" ? "Review Draft…" : "Open Result", systemImage: group.result.state == "draft" ? "doc.text.magnifyingglass" : "arrow.up.right.square") {
                                        search.selectedHitID = hit.id
                                        open(hit)
                                    }.disabled(!canOpen)
                                }
                                .tag(hit.id)
                                .contextMenu {
                                    Button(group.result.state == "draft" ? "Review Draft…" : "Open Result") { search.selectedHitID = hit.id; open(hit) }.disabled(!canOpen)
                                }
                            }
                        }
                    }
                }.accessibilityLabel("Project search results")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Project search results")
        .accessibilityIdentifier("project-search-results")
    }
}
