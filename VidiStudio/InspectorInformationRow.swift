import SwiftUI

/// Keeps short fields compact and gives long values their own wrapping line.
struct InspectorInformationRow: View {
    let label: String
    let value: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label).foregroundStyle(.secondary).fixedSize()
                Spacer(minLength: 8)
                Text(value).textSelection(.enabled).fixedSize()
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(label).foregroundStyle(.secondary)
                Text(value).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}
