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
            DisclosureGroup(isExpanded: $expanded) {
                content.padding(.top, 6).frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text(title).font(.caption.weight(.semibold)).accessibilityAddTraits(.isHeader).accessibilityHeading(.h2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("inspector-section-\(title)")
        }
    }
}
