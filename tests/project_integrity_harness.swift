import Foundation

@main
struct ProjectIntegrityHarness {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("vidistudio-integrity-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        func write(_ relative: String, _ text: String = "x") throws {
            let url = root.appendingPathComponent(relative)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }

        func manifest(
            source: String? = "source/video.mp4",
            youtube: Bool = false,
            thumbs: [String] = ["thumbnails/frame-00.jpg"],
            narration: [ProjectNarrationReference] = [ProjectNarrationReference(path: "audio-description/one.mp3", segmentNumber: 1, timeRange: "00:01–00:03")],
            imports: [String] = ["imports/ad.wav"],
            exports: [String] = ["exports/out.wav"]
        ) -> ProjectIntegrityManifest {
            ProjectIntegrityManifest(
                folder: root,
                projectName: "Test",
                isYouTubeProject: youtube,
                sourceRelativePath: source,
                thumbnailPaths: thumbs,
                narrationReferences: narration,
                importedPaths: imports,
                exportPaths: exports
            )
        }

        try write("project.json", "{}")
        try write("source/video.mp4")
        try write("metadata/probe.json")
        try write("thumbnails/frame-00.jpg")
        try write("audio-description/one.mp3")
        try write("imports/ad.wav")
        try write("exports/out.wav")

        let healthy = ProjectIntegrityAuditor.audit(manifest())
        precondition(healthy.level == .healthy, "healthy project should be healthy")
        precondition(healthy.isHealthy, "healthy project should report healthy")

        try fileManager.removeItem(at: root.appendingPathComponent("audio-description/one.mp3"))
        let missingNarration = ProjectIntegrityAuditor.audit(manifest())
        precondition(missingNarration.level == .warning, "missing narration should be a warning")
        precondition(missingNarration.canRegenerateNarration, "missing narration should offer regeneration")
        precondition(!missingNarration.isDamaged, "missing narration must not mark the project damaged")

        try write("audio-description/one.mp3")
        try fileManager.removeItem(at: root.appendingPathComponent("imports/ad.wav"))
        let missingImport = ProjectIntegrityAuditor.audit(manifest())
        precondition(missingImport.level == .warning, "missing imported asset should be a warning")
        precondition(missingImport.headline.contains("Imported Assets"), "import headline should name the assets")
        precondition(!missingImport.isDamaged, "missing imported assets must not mark the project damaged")
        try write("imports/ad.wav")
        try fileManager.removeItem(at: root.appendingPathComponent("source/video.mp4"))
        let missingSource = ProjectIntegrityAuditor.audit(manifest())
        precondition(missingSource.level == .damaged, "missing source should mark the project damaged")
        precondition(missingSource.headline.contains("Original Video"), "source headline should name the video")

        try write("source/video.mp4")
        try fileManager.removeItem(at: root.appendingPathComponent("project.json"))
        let missingManifest = ProjectIntegrityAuditor.audit(manifest())
        precondition(missingManifest.level == .damaged, "missing manifest should mark the project damaged")
        precondition(missingManifest.manifestUnreadable, "missing manifest should be flagged unreadable")

        try write("project.json", "not json")
        let invalidManifest = ProjectIntegrityAuditor.audit(manifest())
        precondition(invalidManifest.level == .damaged, "invalid manifest should mark the project damaged")
        precondition(invalidManifest.manifestUnreadable, "invalid manifest should be flagged unreadable")

        try write("project.json", "{}")
        let manyThumbs = (0..<6).map { "thumbnails/frame-\($0).jpg" }
        let manyNarrationPaths = (0..<6).map { "audio-description/narration-\($0).mp3" }
        let manyNarration = manyNarrationPaths.enumerated().map {
            ProjectNarrationReference(path: $0.element, segmentNumber: $0.offset + 1, timeRange: "00:0\($0.offset)–00:0\($0.offset + 2)")
        }
        let manyExports = (0..<6).map { "exports/out-\($0).wav" }
        for path in manyThumbs + manyNarrationPaths + manyExports { try write(path) }
        let mixed = manifest(thumbs: manyThumbs, narration: manyNarration, exports: manyExports)
        for path in manyThumbs + manyNarrationPaths + manyExports {
            try fileManager.removeItem(at: root.appendingPathComponent(path))
        }
        let significant = ProjectIntegrityAuditor.audit(mixed)
        precondition(significant.level == .damaged, "most missing files should mark the project damaged")
        precondition(significant.problems.contains { $0.category == .significantLoss }, "significant loss problem should be present")
        precondition(significant.problems.contains { $0.category == .narration }, "narration detail should still be present")

        for path in manyThumbs + manyNarrationPaths + manyExports { try write(path) }
        let healthyAgain = ProjectIntegrityAuditor.audit(mixed)
        precondition(healthyAgain.level == .healthy, "restored files should clear the warning")

        // A single regenerable category must stay a warning even when every
        // file in that category is gone.
        let audioRoot = root.appendingPathComponent("audio-only")
        try fileManager.createDirectory(at: audioRoot, withIntermediateDirectories: true)
        func writeAudioFixture(_ relative: String, _ text: String = "x") throws {
            let url = audioRoot.appendingPathComponent(relative)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        try writeAudioFixture("project.json", "{}")
        try writeAudioFixture("source/video.mp4")
        try writeAudioFixture("metadata/probe.json")
        try writeAudioFixture("thumbnails/frame-00.jpg")
        try writeAudioFixture("exports/out.wav")
        let audioPaths = (0..<20).map { "audio-description/voice-\($0).mp3" }
        for path in audioPaths { try writeAudioFixture(path) }
        let audioReferences = audioPaths.enumerated().map {
            ProjectNarrationReference(path: $0.element, segmentNumber: $0.offset + 1, timeRange: "00:00–00:01")
        }
        let audioHeavy = ProjectIntegrityManifest(
            folder: audioRoot,
            projectName: "Audio Only",
            isYouTubeProject: false,
            sourceRelativePath: "source/video.mp4",
            thumbnailPaths: ["thumbnails/frame-00.jpg"],
            narrationReferences: audioReferences,
            exportPaths: ["exports/out.wav"]
        )
        for path in audioPaths { try fileManager.removeItem(at: audioRoot.appendingPathComponent(path)) }
        let allAudioMissing = ProjectIntegrityAuditor.audit(audioHeavy)
        precondition(allAudioMissing.level == .warning, "all narration audio missing must remain a recoverable warning")
        precondition(allAudioMissing.canRegenerateNarration, "all narration audio missing should offer regeneration")

        let youtube = manifest(source: nil, youtube: true, thumbs: [], narration: [], exports: [])
        precondition(ProjectIntegrityAuditor.audit(youtube).level == .healthy, "YouTube project without a local source should be healthy")

        let gone = ProjectIntegrityAuditor.audit(ProjectIntegrityManifest(
            folder: root.appendingPathComponent("gone"),
            projectName: "Gone",
            isYouTubeProject: false,
            sourceRelativePath: nil,
            thumbnailPaths: [],
            narrationReferences: [],
            exportPaths: []
        ))
        precondition(gone.level == .damaged && gone.folderMissing, "missing folder should be damaged")
        precondition(ProjectIntegrityAuditor.resolve("../outside.txt", in: root) == nil, "path traversal must be rejected")

        print("PASS: project integrity harness")
    }
}
