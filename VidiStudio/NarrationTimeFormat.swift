import Foundation

/// Explicit, millisecond-precision time labels for the narration issues table.
enum NarrationTimeFormat {
    private static func milliseconds(_ seconds: Double) -> Int {
        guard seconds.isFinite else { return 0 }
        return Int((max(0, seconds) * 1_000).rounded())
    }

    static func timestamp(_ seconds: Double) -> String {
        let total = milliseconds(seconds)
        return String(format: "%02d:%02d:%02d.%03d",
                      total / 3_600_000, total / 60_000 % 60,
                      total / 1_000 % 60, total % 1_000)
    }

    static func duration(_ seconds: Double) -> String {
        let total = milliseconds(seconds)
        return String(format: "%d.%03d s", total / 1_000, total % 1_000)
    }

    private static func unit(_ value: Int, _ name: String) -> String {
        "\(value) \(name)\(value == 1 ? "" : "s")"
    }

    static func spokenTime(_ seconds: Double) -> String {
        let total = milliseconds(seconds)
        return [unit(total / 3_600_000, "hour"), unit(total / 60_000 % 60, "minute"),
                unit(total / 1_000 % 60, "second"), unit(total % 1_000, "millisecond")]
            .joined(separator: ", ")
    }

    static func spokenDuration(_ seconds: Double) -> String {
        let total = milliseconds(seconds)
        return "\(unit(total / 1_000, "second")), \(unit(total % 1_000, "millisecond"))"
    }
}
