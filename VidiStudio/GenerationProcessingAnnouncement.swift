/// A generation stage is spoken once per operation, regardless of status updates or view reloads.
struct GenerationProcessingAnnouncement {
    private var announcedStages: Set<String> = []

    mutating func take(stage: String?) -> String? {
        guard let stage else { return nil }
        let title: String
        switch stage {
        case "transcript": title = "Generating transcript"
        case "summary": title = "Generating summary"
        case "descriptions": title = "Generating descriptions"
        default: return nil
        }
        guard announcedStages.insert(stage).inserted else { return nil }
        return "Processing. \(title)."
    }
}
