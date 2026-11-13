import SwiftUI

struct InspectorSection<Content: View>: View {
    private let title: String
    private let content: Content
    @AppStorage private var expanded: Bool

    init(_ title: String, id: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        _expanded = AppStorage(wrappedValue: true, "inspectorSection.\(id ?? title).expanded")
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    // Keep the native disclosure role separate from the heading role.
                    DisclosureGroup(isExpanded: $expanded) { EmptyView() } label: { EmptyView() }
                        .fixedSize()
                        .accessibilityLabel(title)
                        .accessibilityHint(expanded ? "Collapse \(title)" : "Expand \(title)")
                        .accessibilityIdentifier("inspector-section-\(title)")
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityHeading(.h2)
                    Spacer(minLength: 0)
                }
                if expanded {
                    content.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
