import SwiftUI

struct SegmentFilterOption: Identifiable {
    let id: String
    let number: Int
    let isDescription: Bool
    let start: Double
    let end: Double
    let text: String
    var title: String { "\(isDescription ? "Audio description" : "Transcript") #\(number) · \(Self.time(start))–\(Self.time(end)) · \(text)" }
    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let ms = Int((seconds * 1000).rounded())
        return String(format: "%02d:%02d:%02d.%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }
}

struct SegmentRangeFilterControls: View {
    let options: [SegmentFilterOption]
    let showsTranscript: Bool
    let showsDescriptions: Bool
    let duration: Double
    @Binding var ranges: SegmentRangeFilter

    private func selection(_ option: SegmentFilterOption) -> Binding<Bool> {
        Binding(get: { ranges.selectedIDs.contains(option.id) }, set: { selected in
            if selected { ranges.selectedIDs.insert(option.id) } else { ranges.selectedIDs.remove(option.id) }
        })
    }
    private func changeMode(_ mode: SegmentRangeFilter.Mode) {
        ranges.mode = mode
        if mode == .numberRanges && ranges.numberRanges.isEmpty { addNumberRange() }
        if mode == .timeRanges && ranges.timeRanges.isEmpty { addTimeRange() }
    }
    private func addNumberRange() {
        ranges.numberRanges.append(.init(isDescription: !showsTranscript, start: "1", end: "1"))
    }
    private func addTimeRange() {
        ranges.timeRanges.append(.init(start: 0, end: max(0.001, duration.isFinite && duration > 0 ? duration : 1)))
    }
    private var numberRanges: some View {
        Section("Segment number ranges") {
            ForEach($ranges.numberRanges) { $range in
                VStack(alignment: .leading, spacing: 10) {
                    if showsTranscript && showsDescriptions {
                        Picker("Segment type", selection: $range.isDescription) {
                            Text("Transcript").tag(false)
                            Text("Audio description").tag(true)
                        }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        numberInput("Start segment", value: $range.start, description: range.isDescription)
                        numberInput("End segment", value: $range.end, description: range.isDescription)
                        Button("Remove Range", systemImage: "minus.circle") { ranges.numberRanges.removeAll { $0.id == range.id } }
                            .labelStyle(.iconOnly)
                            .contextMenu { Button("Remove Range") { ranges.numberRanges.removeAll { $0.id == range.id } } }
                    }
                }
            }
            Button("Add Segment Range", systemImage: "plus") { addNumberRange() }
                .contextMenu { Button("Add Segment Range") { addNumberRange() } }
        }
    }
    private func numberInput(_ label: String, value: Binding<String>, description: Bool) -> some View {
        let count = options.filter { $0.isDescription == description }.count
        return VStack(alignment: .leading) {
            TextField(label, text: value)
                .accessibilityLabel(label)
                .accessibilityIdentifier(label == "Start segment" ? "filter-start-segment" : "filter-end-segment")
            Stepper(value: Binding(get: { Int(value.wrappedValue) ?? 1 }, set: { value.wrappedValue = String($0) }), in: 1...max(1, count)) {
                Text("1–\(count)").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityLabel("\(label), 1 to \(count)")
            .disabled(count == 0)
        }
    }
    private var timeRanges: some View {
        Section("Time ranges") {
            ForEach($ranges.timeRanges) { $range in
                VStack(alignment: .leading, spacing: 12) {
                    TimecodeInput(label: "Start time", value: $range.start)
                    TimecodeInput(label: "End time", value: $range.end)
                    Button("Remove Range", systemImage: "minus.circle") { ranges.timeRanges.removeAll { $0.id == range.id } }
                        .contextMenu { Button("Remove Range") { ranges.timeRanges.removeAll { $0.id == range.id } } }
                }
            }
            Button("Add Time Range", systemImage: "plus") { addTimeRange() }
                .contextMenu { Button("Add Time Range") { addTimeRange() } }
            Picker("Time matching", selection: $ranges.timeMatch) {
                ForEach(SegmentRangeFilter.TimeMatch.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.radioGroup)
            .contextMenu {
                ForEach(SegmentRangeFilter.TimeMatch.allCases) { mode in
                    Toggle(mode.title, isOn: Binding(get: { ranges.timeMatch == mode }, set: { if $0 { ranges.timeMatch = mode } }))
                }
            }
        }
    }
    var body: some View {
        Group {
            Section("Filter by") {
                Picker("Filter type", selection: Binding(get: { ranges.mode }, set: changeMode)) {
                    ForEach(SegmentRangeFilter.Mode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("segment-filter-type")
                .contextMenu {
                    ForEach(SegmentRangeFilter.Mode.allCases) { mode in
                        Toggle(mode.title, isOn: Binding(get: { ranges.mode == mode }, set: { if $0 { changeMode(mode) } }))
                            .accessibilityIdentifier("filter-mode-\(mode.rawValue)")
                    }
                }
            }
            if ranges.mode == .selection {
                Section("Select segments") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(options) { option in
                                Toggle(option.title, isOn: selection(option))
                                    .toggleStyle(.checkbox).tint(.accentColor).lineLimit(2)
                                    .padding(8)
                                    .background(ranges.selectedIDs.contains(option.id) ? Color.accentColor.opacity(0.18) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 6))
                                    .accessibilityIdentifier("filter-segment-\(option.id)")
                                    .contextMenu {
                                        Toggle(option.title, isOn: selection(option))
                                            .accessibilityIdentifier("filter-segment-number-menu")
                                    }
                            }
                        }
                    }
                    .frame(height: 240)
                }
            }
            if ranges.mode == .numberRanges { numberRanges }
            if ranges.mode == .timeRanges { timeRanges }
        }
    }
}
