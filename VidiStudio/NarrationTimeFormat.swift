import Foundation

/// Explicit, millisecond-precision time labels for the narration issues table.
enum NarrationTimeFormat {
    private static func milliseconds(_ seconds: Double) -> Int {
        guard seconds.isFinite else { return 0 }
        return Int((max(0, seconds) * 1_000).rounded())
    }

    static func timestamp(_ seconds: Double) -> String {
        let total = milliseconds(seconds)
        let clock = String(format: "%02d:%02d:%02d.%03d",
                           total / 3_600_000 % 24, total / 60_000 % 60,
                           total / 1_000 % 60, total % 1_000)
        return total >= 86_400_000 ? "\(total / 86_400_000)d \(clock)" : clock
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
        let parts = [(total / 86_400_000, "day"), (total / 3_600_000 % 24, "hour"), (total / 60_000 % 60, "minute"),
                     (total / 1_000 % 60, "second"), (total % 1_000, "millisecond")]
            .filter { $0.0 > 0 }.map { unit($0.0, $0.1) }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: ", ")
    }

    static func spokenDuration(_ seconds: Double) -> String { spokenTime(seconds) }

    static func mediaDuration(_ seconds: Double) -> String {
        let total = milliseconds(seconds)
        let parts = [(total / 86_400_000, "d"), (total / 3_600_000 % 24, "h"),
                     (total / 60_000 % 60, "m"), (total / 1_000 % 60, "s"), (total % 1_000, "ms")]
            .filter { $0.0 > 0 }.map { "\($0.0)\($0.1)" }
        return parts.isEmpty ? "0s" : parts.joined(separator: " ")
    }

    static func projectDuration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "Unavailable" }
        return mediaDuration(seconds)
    }

    static func spokenProjectDuration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "unavailable" }
        return spokenDuration(seconds)
    }
}
