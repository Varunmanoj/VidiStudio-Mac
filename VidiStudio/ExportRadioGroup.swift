import AppKit
import SwiftUI

/// SwiftUI owns selection; native radio buttons own per-option availability.
struct ExportRadioGroup<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, title: String, enabled: Bool)]
    @Binding var selection: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            ExportRadioButtons(title: title, options: options, selection: $selection)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ExportRadioButtons<Value: Hashable>: NSViewRepresentable {
    let title: String
    let options: [(value: Value, title: String, enabled: Bool)]
    @Binding var selection: Value

    func makeNSView(context: Context) -> ExportRadioGroupView {
        ExportRadioGroupView()
    }

    func updateNSView(_ view: ExportRadioGroupView, context: Context) {
        view.configure(
            title: title,
            titles: options.map(\.title),
            enabled: options.map(\.enabled),
            selectedIndex: options.firstIndex { $0.value == selection }
        ) { index in
            guard options.indices.contains(index), options[index].enabled else { return }
            selection = options[index].value
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ExportRadioGroupView, context: Context) -> CGSize? {
        nsView.fittingSize
    }
}

@MainActor
final class ExportRadioGroupView: NSStackView {
    private(set) var radioButtons: [NSButton] = []
    private var selectionChanged: ((Int) -> Void)?

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 3
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, titles: [String], enabled: [Bool], selectedIndex: Int?, onSelection: @escaping (Int) -> Void) {
        precondition(titles.count == enabled.count)
        selectionChanged = onSelection
        setAccessibilityLabel(title)
        if radioButtons.count != titles.count {
            for button in radioButtons {
                removeArrangedSubview(button)
                button.removeFromSuperview()
            }
            radioButtons = titles.indices.map { index in
                let button = NSButton(radioButtonWithTitle: titles[index], target: self, action: #selector(selectOption(_:)))
                button.tag = index
                button.setContentHuggingPriority(.required, for: .horizontal)
                addArrangedSubview(button)
                return button
            }
            setAccessibilityChildren(radioButtons)
        }
        for (index, button) in radioButtons.enumerated() {
            button.title = titles[index]
            button.isEnabled = enabled[index]
            button.state = selectedIndex == index ? .on : .off
        }
        invalidateIntrinsicContentSize()
    }

    @objc private func selectOption(_ sender: NSButton) {
        guard sender.isEnabled, radioButtons.indices.contains(sender.tag) else { return }
        selectionChanged?(sender.tag)
    }
}
