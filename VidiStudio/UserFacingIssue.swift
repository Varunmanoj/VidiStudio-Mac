import Foundation
import OSLog

struct UserFacingIssue: Equatable {
    let title: String
    let message: String

    static let settingsSave = UserFacingIssue(
        title: "Settings Couldn’t Be Saved",
        message: "Your changes could not be saved. Check that VidiStudio can write to its settings folder, then try again."
    )
    static let projectOpen = UserFacingIssue(
        title: "Project Couldn’t Be Opened",
        message: "Choose a VidiStudio project folder that is available on this Mac and try again."
    )
    static let projectRead = UserFacingIssue(
        title: "Project Couldn’t Be Read",
        message: "VidiStudio could not read the latest project information. Close and reopen the project, then try again."
    )
    static let projectSave = UserFacingIssue(
        title: "Changes Couldn’t Be Saved",
        message: "Your changes were not saved. Make sure the project folder is available and has enough free space, then try again."
    )
    static let projectDelete = UserFacingIssue(
        title: "Project Couldn’t Be Moved to the Bin",
        message: "The project is still in its original location. Make sure its folder is available, then try again."
    )
    static let youtubePreview = UserFacingIssue(
        title: "Video Details Couldn’t Be Loaded",
        message: "Check the YouTube link and your internet connection, then try again."
    )
    static let narrationPlayback = UserFacingIssue(
        title: "Narration Couldn’t Be Played",
        message: "This narration audio is not available right now. Generate it again, then try playing it."
    )
    static let speech = UserFacingIssue(
        title: "Speech Isn’t Available",
        message: "Choose an installed Apple or Piper voice in Settings → Narration, then try again."
    )
    static let voicePreview = UserFacingIssue(
        title: "Voice Sample Couldn’t Be Created",
        message: "Check your Gemini settings and internet connection, then try the sample again."
    )
    static let engineCheck = UserFacingIssue(
        title: "VidiStudio Isn’t Ready Yet",
        message: "The media tools could not be checked. Use the included tools, or choose available tools in Settings → Storage, then try again."
    )
    static let exportPreparation = UserFacingIssue(
        title: "Export Couldn’t Be Prepared",
        message: "VidiStudio could not read the latest project information. Reopen the project and try exporting again."
    )
    static let exportMetadata = UserFacingIssue(
        title: "Export Needs Attention",
        message: "The video was created, but its accessibility information could not be finished. Keep the original export and try creating it again."
    )
    static let general = UserFacingIssue(
        title: "VidiStudio Couldn’t Finish",
        message: "Your completed work is safe. Try the action again, or reopen the project if the problem continues."
    )

    static func forEngine(command: String, technicalDetails: String?) -> UserFacingIssue {
        let detail = technicalDetails?.lowercased() ?? ""
        if command.hasPrefix("export-youtube-") {
            if detail.contains("duration") || detail.contains("timing") {
                return UserFacingIssue(
                    title: "YouTube Audio Timing Needs Attention",
                    message: "The soundtrack no longer matches this project's timing. Refresh the transcript and descriptions, or import the matching original video, then try again."
                )
            }
            if detail.contains("narration") || detail.contains("synthesize") || detail.contains("ad segment") {
                return UserFacingIssue(
                    title: "Narration Needs Attention",
                    message: "Generate narration for every current description and check that it fits its time slot, then export again."
                )
            }
            return UserFacingIssue(
                title: "YouTube Audio Export Couldn’t Finish",
                message: "Check your connection and that the video is public, then try again. If YouTube blocks the download, import your original video as a local project and export its described audio. Your completed work is safe."
            )
        }
        if detail.contains("api key") || detail.contains("unauthenticated") || detail.contains("unauthorized")
            || detail.contains("401") || detail.contains("403") {
            return UserFacingIssue(
                title: "Gemini Access Needs Attention",
                message: "Check your Gemini API key in Settings, then try again."
            )
        }
        if detail.contains("quota") || detail.contains("rate limit") || detail.contains("429") {
            return UserFacingIssue(
                title: "Gemini Is Temporarily Unavailable",
                message: "Your Gemini usage limit may have been reached. Wait a little while, then try again."
            )
        }
        if detail.contains("timed out") || detail.contains("timeout") || detail.contains("network")
            || detail.contains("internet") || detail.contains("connection") {
            return UserFacingIssue(
                title: "Connection Interrupted",
                message: "Check your internet connection, then try again. Your completed work is safe."
            )
        }
        if detail.contains("no space") || detail.contains("disk full") || detail.contains("not enough space") {
            return UserFacingIssue(
                title: "More Storage Is Needed",
                message: "Free some space on the drive that contains this project, then try again."
            )
        }
        if detail.contains("permission denied") || detail.contains("not permitted") {
            return UserFacingIssue(
                title: "Folder Access Is Needed",
                message: "Make sure the project folder is available and VidiStudio has permission to use it, then try again."
            )
        }
        if let regex = try? NSRegularExpression(pattern: #"^ad segment ([0-9]+) takes ([0-9]+(?:\.[0-9]+)?)s but has ([0-9]+(?:\.[0-9]+)?)s"#),
           let match = regex.firstMatch(in: detail, range: NSRange(detail.startIndex..., in: detail)) {
            let text = detail as NSString
            let segment = text.substring(with: match.range(at: 1))
            let needed = text.substring(with: match.range(at: 2))
            let available = text.substring(with: match.range(at: 3))
            return UserFacingIssue(
                title: "Narration Doesn’t Fit",
                message: "Audio Description \(segment) takes about \(needed) seconds to speak but has \(available) seconds. In Descriptions, use Rewrite to Fit or edit its text and timing, then generate narration again."
            )
        }
        if detail.contains("narration") && (detail.contains("fit") || detail.contains("too long") || detail.contains("slot")) {
            return UserFacingIssue(
                title: "Narration Doesn’t Fit",
                message: "One or more descriptions are too long for their time slots. In Descriptions, use Rewrite to Fit or edit the text and timing, then generate narration again."
            )
        }
        if detail.contains("overlap") || detail.contains("start time") || detail.contains("end time") {
            return UserFacingIssue(
                title: "Timing Needs Attention",
                message: "Adjust the highlighted segment times so they stay inside the video and do not overlap, then save again."
            )
        }
        if detail.contains("api_key_invalid") || detail.contains("api key not valid") || detail.contains("api key is not valid") || detail.contains("invalid api key") {
            return UserFacingIssue(
                title: "Invalid Gemini API Key",
                message: "Your Gemini API key could not be verified by Google AI Studio. Check and update your API key in Settings → Gemini API."
            )
        }

        switch command {
        case "import-video":
            return UserFacingIssue(
                title: "Video Couldn’t Be Added",
                message: "Make sure the video is available on this Mac and the project folder has enough free space, then try again."
            )
        case "import-youtube", "prepare-youtube":
            return UserFacingIssue(
                title: "YouTube Video Couldn’t Be Added",
                message: "Use a YouTube video with visibility set to Public or Unlisted. Private and other restricted visibility settings cannot be analyzed by Gemini. Check the link, your Gemini API settings, and your internet connection, then try again."
            )
        case "prepare-video", "probe-video", "generate-thumbnails":
            return UserFacingIssue(
                title: "Video Details Couldn’t Be Prepared",
                message: "The original video was not changed. Make sure it is available, then try again."
            )
        case "transcribe":
            return UserFacingIssue(
                title: "Transcript Couldn’t Be Created",
                message: "Check your Gemini settings and internet connection, then try generating the transcript again."
            )
        case "generate-summary":
            return UserFacingIssue(
                title: "Summary Couldn’t Be Created",
                message: "Your transcript is safe. Check your Gemini settings and try generating the summary again."
            )
        case "generate-ad-cues":
            return UserFacingIssue(
                title: "Audio Descriptions Couldn’t Be Created",
                message: "Your transcript and summary are safe. Check your Gemini settings, then try again."
            )
        case "analyze", "regenerate-all":
            return UserFacingIssue(
                title: "Video Analysis Couldn’t Be Completed",
                message: "Your completed work is safe. Check your Gemini settings and internet connection, then try again."
            )
        case "synthesize-tts", "synthesize-changed", "preview-tts":
            return command == "preview-tts" ? .voicePreview : UserFacingIssue(
                title: "Narration Couldn’t Be Created",
                message: "Check your selected voice and speech settings, then try generating narration again."
            )
        case "export-final-video", "export-selectable-video", "export-closed-audio-description-video",
             "export-open-audio-description-video", "export-closed-caption-video",
             "export-dual-closed-caption-video", "export-open-caption-video", "export-original-audio",
             "export-described-audio", "export-audio", "export-subtitles", "export-hls":
            return UserFacingIssue(
                title: "Export Couldn’t Be Created",
                message: "Your source video and existing exports are unchanged. Check that the project drive has enough free space, then try again."
            )
        case "save-cues", "save-segments", "rename-project", "update-metadata":
            return .projectSave
        case "doctor", "validate-config":
            return .engineCheck
        case "list-models", "check-api-key":
            return UserFacingIssue(
                title: "Gemini API Key or Models Couldn’t Be Verified",
                message: "Check your Gemini API key and internet connection, then try again."
            )
        case "reanalyze-transcript-segment":
            return UserFacingIssue(title: "This Transcript Range Couldn’t Be Generated", message: "Existing transcript, Audio Descriptions and narration have been kept. Check the selected range, video availability and Gemini settings. If newly detected dialogue overlaps an Audio Description, review and adjust that description before retrying; speech timing is never changed to fit narration.")
        case "undo-transcript", "redo-transcript":
            return UserFacingIssue(title: "Transcript History Couldn’t Be Restored", message: "The current transcript and Audio Descriptions have been kept. There may be no edit history, or newer descriptions may overlap the transcript you are trying to restore.")
        case "reanalyze-segment":
            return UserFacingIssue(title: "This Section Couldn’t Be Re-Analyzed", message: "Existing descriptions have been kept. Try a wider time range and check your video availability and Gemini settings.")
        case "prepare-analysis-video", "check-video-availability":
            return UserFacingIssue(title: "Video Availability Couldn’t Be Confirmed", message: "Check your internet connection and Gemini settings, then refresh the video status in the inspector.")
        case "capture-frame":
            return UserFacingIssue(
                title: "Frame Text Couldn’t Be Read",
                message: "Move to a clear frame with visible text, then try again."
            )
        default:
            return .general
        }
    }
}

enum UserFacingIssueReporter {
    private static let logger = Logger(subsystem: "Varunmanojkumar.VidiStudio", category: "Internal errors")

    static func record(_ technicalDetails: String, context: String) {
        logger.error("\(context, privacy: .public): \(technicalDetails, privacy: .private)")
    }

    static func message(for error: Error, issue: UserFacingIssue, context: String) -> String {
        record(error.localizedDescription, context: context)
        return issue.message
    }

    /// Piper failures already explain what to download or choose, so they are shown as written.
    static func speechMessage(for error: Error, issue: UserFacingIssue, context: String) -> String {
        if let piper = error as? PiperSpeechError, case .message(let text) = piper {
            record(text, context: context)
            return text
        }
        return message(for: error, issue: issue, context: context)
    }
}

enum UserFacingProgress {
    static func message(for command: String) -> String {
        switch command {
        case "import-video": return "Adding the video to your project…"
        case "import-youtube": return "Adding the YouTube video…"
        case "prepare-video", "probe-video": return "Reading video details…"
        case "generate-thumbnails": return "Creating timeline pictures…"
        case "analyze", "regenerate-all": return "Analyzing the video…"
        case "transcribe": return "Creating the transcript…"
        case "generate-summary": return "Creating the summary…"
        case "generate-ad-cues": return "Creating Audio Descriptions…"
        case "synthesize-tts", "synthesize-changed": return "Creating narration…"
        case "reanalyze-transcript-segment": return "Analyzing dialogue in the selected time range…"
        case "undo-transcript", "redo-transcript": return "Restoring transcript segments…"
        case "reanalyze-segment": return "Taking a closer look and adjusting descriptions…"
        case "prepare-analysis-video": return "Preparing video for analysis…"
        case "check-video-availability": return "Checking video availability…"
        case "capture-frame": return "Reading text from the selected frame…"
        case "save-cues", "save-segments", "save-summary": return "Saving your changes…"
        case "delete-export", "delete-generated", "delete-segment-audio": return "Updating the project…"
        case "doctor", "validate-config": return "Checking VidiStudio…"
        case "list-models", "check-api-key": return "Checking Gemini API key and models…"
        case let value where value.hasPrefix("export-"): return "Creating your export…"
        default: return "Working on your project…"
        }
    }
}
