import Foundation

/// Uses source-result numbering and stable row identities, never filtered row positions.
struct SegmentRangeFilter: Equatable {
    enum Mode: String, CaseIterable, Identifiable {
        case all, selection, numberRanges, timeRanges
        var id: Self { self }
        var title: String {
            switch self {
            case .all: return "All segments"
            case .selection: return "Select segment numbers"
            case .numberRanges: return "Segment number ranges"
            case .timeRanges: return "Time ranges"
            }
        }
    }
    enum TimeMatch: String, CaseIterable, Identifiable {
        case overlaps, contained
        var id: Self { self }
        var title: String { self == .overlaps ? "Overlaps a time range" : "Fully inside a time range" }
    }
    struct NumberRange: Equatable, Identifiable {
        let id = UUID()
        var isDescription = false
        var start = "1"
        var end = "1"
    }
    struct TimeRange: Equatable, Identifiable {
        let id = UUID()
        var start: Double = 0
        var end: Double = 1
    }
    var mode: Mode = .all
    var selectedIDs: Set<String> = []
    var numberRanges: [NumberRange] = []
    var timeRanges: [TimeRange] = []
    var timeMatch: TimeMatch = .overlaps
    var isActive: Bool { mode != .all }

    func error(transcriptCount: Int, descriptionCount: Int, duration: Double, availableIDs: Set<String>) -> String? {
        switch mode {
        case .all: return nil
        case .selection:
            return !selectedIDs.isEmpty && selectedIDs.isSubset(of: availableIDs) ? nil : "Select at least one available segment."
        case .numberRanges:
            guard !numberRanges.isEmpty else { return "Add a segment number range." }
            for range in numberRanges {
                let count = range.isDescription ? descriptionCount : transcriptCount
                guard count > 0 else { return "No \(range.isDescription ? "description" : "transcript") segments are available." }
                guard let start = Int(range.start), let end = Int(range.end), start >= 1, end <= count, start <= end else {
                    return "Enter whole segment numbers from 1 to \(count), with End at or after Start."
                }
            }
        case .timeRanges:
            guard !timeRanges.isEmpty else { return "Add a time range." }
            for range in timeRanges {
                guard range.start.isFinite, range.end.isFinite, range.start >= 0, range.end > range.start else {
                    return "Each End time must be after its Start time."
                }
                guard !duration.isFinite || duration <= 0 || range.end <= duration else { return "Time ranges must stay within the video duration." }
            }
        }
        return nil
    }
    func matches(id: String, number: Int, isDescription: Bool, start: Double, end: Double) -> Bool {
        switch mode {
        case .all: return true
        case .selection: return selectedIDs.contains(id)
        case .numberRanges:
            return numberRanges.contains { range in
                guard range.isDescription == isDescription, let first = Int(range.start), let last = Int(range.end) else { return false }
                return first <= number && number <= last
            }
        case .timeRanges:
            guard start.isFinite, end.isFinite, end > start else { return false }
            return timeRanges.contains { range in
                timeMatch == .contained ? start >= range.start && end <= range.end : start < range.end && end > range.start
            }
        }
    }
}
