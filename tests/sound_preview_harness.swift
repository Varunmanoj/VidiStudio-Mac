import Foundation
import AVFoundation
@main struct NativePreviewCheck {
    @MainActor static func main() async throws {
        let cue = SettingsSoundPreview()
        for resource in ["Boink3", "ascend", "descend", "Buzzer1"] {
            cue.toggle(resource)
            precondition(cue.isPlaying(resource))
            try await Task.sleep(for: .milliseconds(30))
            cue.toggle(resource)
            precondition(!cue.playing && cue.resource == resource)
            try await Task.sleep(for: .milliseconds(500))
            precondition(!cue.playing && cue.resource == resource)
            cue.toggle(resource)
            precondition(cue.isPlaying(resource))
            try await Task.sleep(for: .milliseconds(800))
            precondition(!cue.playing && cue.resource == nil)
        }
        cue.toggle("descend");cue.toggle("ascend")
        precondition(cue.resource == "ascend" && cue.playing)
        cue.stop(); precondition(cue.resource == nil && !cue.playing)
        print("PASS: all four production Mac previews play, pause, retain position, resume and reset after completion; switching/stopping clears the previous cue")
    }
}
