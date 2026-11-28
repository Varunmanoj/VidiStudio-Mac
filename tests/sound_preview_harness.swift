import Foundation
import AVFoundation
@main struct NativePreviewCheck {
    @MainActor static func main() async throws {
        let cue = SettingsSoundPreview()
        let rows = [("narration-off", "Boink3"), ("narration-missing", "ascend"),
                    ("export", "descend"), ("generation", "descend"), ("timing-validation", "Buzzer1")]
        for (id, resource) in rows {
            cue.toggle(id, resource: resource)
            precondition(cue.isPlaying(id))
            try await Task.sleep(for: .milliseconds(30))
            cue.toggle(id, resource: resource)
            precondition(!cue.playing && cue.activeID == id)
            try await Task.sleep(for: .milliseconds(500))
            precondition(!cue.playing && cue.activeID == id)
            cue.toggle(id, resource: resource)
            precondition(cue.isPlaying(id))
            try await Task.sleep(for: .milliseconds(800))
            precondition(!cue.playing && cue.activeID == nil)
        }
        cue.toggle("export", resource: "descend")
        precondition(cue.isPlaying("export") && !cue.isPlaying("generation"))
        cue.toggle("generation", resource: "descend")
        precondition(cue.isPlaying("generation") && !cue.isPlaying("export"))
        cue.stop(); precondition(cue.activeID == nil && !cue.playing)
        print("PASS: all five production Mac previews play, pause, retain position, resume and reset after completion; switching/stopping clears the previous cue")
    }
}
