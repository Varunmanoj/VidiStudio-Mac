import Foundation
import Observation

/// One audition across narration, Summary, and voice-management windows.
@MainActor @Observable final class VoiceSampleSession {
    static let shared = VoiceSampleSession()
    private(set) var owner: UUID?
    var busy: Bool { owner != nil }
    func begin(_ id: UUID) -> Bool {
        guard owner == nil else { return false }
        owner = id
        return true
    }
    func end(_ id: UUID) { if owner == id { owner = nil } }
}
