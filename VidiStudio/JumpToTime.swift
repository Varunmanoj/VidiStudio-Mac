import Foundation
import SwiftUI

enum JumpTime {
    /// Seconds, minutes:seconds, or hours:minutes:seconds; only seconds may be fractional.
    static func parse(_ text: String, duration: Double) -> Double? {
        guard duration.isFinite, duration > 0 else { return nil }
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (index, part) in parts.enumerated() {
            let last = index == parts.count - 1
            let pattern = last ? "^[0-9]+(?:\\.[0-9]+)?$" : "^[0-9]+$"
            guard String(part).range(of: pattern, options: .regularExpression) != nil,
                  let value = Double(part), value.isFinite,
                  index == 0 || value < 60 else { return nil }
            total = total * 60 + value
        }
        return total.isFinite && total <= duration ? total : nil
    }

    static func format(_ seconds: Double) -> String {
        let milliseconds = Int((max(0, seconds) * 1000).rounded(.down))
        return String(format: "%02d:%02d:%02d.%03d", milliseconds / 3600000,
                      milliseconds / 60000 % 60, milliseconds / 1000 % 60, milliseconds % 1000)
    }
}

struct JumpToTimeView: View {
    let duration: Double
    let jump: (Double) -> Void
    @State private var time: String
    @FocusState private var timeFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(position: Double, duration: Double, jump: @escaping (Double) -> Void) {
        self.duration = duration
        self.jump = jump
        _time = State(initialValue: JumpTime.format(position.isFinite ? min(max(0, position), duration) : 0))
    }

    private var target: Double? { JumpTime.parse(time, duration: duration) }
    private func submit() {
        guard let target else { return }
        jump(target)
        dismiss()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Jump to Time").font(.title2.bold()).accessibilityAddTraits(.isHeader).accessibilityHeading(.h1)
            TextField("Time", text: $time, prompt: Text("hh:mm:ss.sss"))
                .monospacedDigit()
                .focused($timeFocused)
                .accessibilityLabel("Time")
                .accessibilityIdentifier("jump-time-input")
                .onSubmit(submit)
            if target == nil {
                Text("Enter a time from 0 to \(JumpTime.format(duration)).")
                    .foregroundStyle(.red).font(.caption)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Jump", action: submit).keyboardShortcut(.defaultAction)
                    .disabled(target == nil).accessibilityIdentifier("jump-time-submit")
            }
        }
        .padding(24).frame(width: 380)
        .contextMenu {
            Button("Jump", action: submit).disabled(target == nil)
            Button("Cancel") { dismiss() }
        }
        .onAppear { timeFocused = true }
    }
}
