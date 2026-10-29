import Foundation

/// Overall health of the files that make up a VidiStudio project.
///
/// A project can survive regenerable files (thumbnails, narration audio, and
/// exports) being removed, but the project manifest and the original source
/// video are required. A project is marked damaged when one of those required
/// files is unavailable or when most of its files disappear.
enum ProjectIntegrityLevel: Int, Comparable, Sendable {
    case healthy
    case warning
    case damaged

    static func < (lhs: ProjectIntegrityLevel, rhs: ProjectIntegrityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var isDamaged: Bool { self == .damaged }
}

enum ProjectFileCategory: String, CaseIterable, Sendable {
    case manifest
    case source
    case metadata
    case thumbnails
    case narration
    case importedAssets
    case exports
    case significantLoss

    var title: String {
        switch self {
        case .manifest: return "Project File"
        case .source: return "Original Video"
        case .metadata: return "Video Details"
        case .thumbnails: return "Timeline Pictures"
        case .narration: return "Narration Audio"
        case .importedAssets: return "Imported Assets"
        case .exports: return "Exports"
        case .significantLoss: return "Project Files"
        }
    }

    var iconName: String {
        switch self {
        case .manifest: return "doc.text"
        case .source: return "film"
        case .metadata: return "info.circle"
        case .thumbnails: return "photo.on.rectangle.angled"
        case .narration: return "waveform"
        case .importedAssets: return "square.and.arrow.down"
        case .exports: return "square.and.arrow.up"
        case .significantLoss: return "externaldrive.badge.exclamationmark"
        }
    }
}

/// One missing or unusable file, with a user-facing label that can include the
/// affected AD segment number and time range.
struct ProjectMissingFile: Identifiable, Hashable, Sendable {
    let path: String
    let displayName: String

    var id: String { "\(path)\u{1F}\(displayName)" }
}

struct ProjectFileProblem: Identifiable, Hashable, Sendable {
    let category: ProjectFileCategory
    let severity: ProjectIntegrityLevel
    let title: String
    let detail: String
    let impact: String
    let recovery: String?
    let missingFiles: [ProjectMissingFile]
    let expectedCount: Int

    var id: ProjectFileCategory { category }
    var missingCount: Int { missingFiles.count }
    var isCritical: Bool { severity == .damaged }
}

struct ProjectNarrationReference: Hashable, Sendable {
    let path: String
    let segmentNumber: Int
    let timeRange: String

    var displayName: String {
        let range = timeRange.isEmpty ? "" : " · \(timeRange)"
        return "\(path) (AD \(segmentNumber)\(range))"
    }
}

/// The project information needed to audit the files on disk. Keeping this
/// separate from `StudioProject` lets the audit logic be tested on its own.
struct ProjectIntegrityManifest: Sendable {
    var folder: URL?
    var projectName: String
    var isYouTubeProject: Bool
    var sourceRelativePath: String?
    var thumbnailPaths: [String]
    var narrationReferences: [ProjectNarrationReference]
    var importedPaths: [String]
    var exportPaths: [String]
    var knownManifestUnreadable: Bool

    init(
        folder: URL?,
        projectName: String,
        isYouTubeProject: Bool,
        sourceRelativePath: String?,
        thumbnailPaths: [String],
        narrationReferences: [ProjectNarrationReference],
        importedPaths: [String] = [],
        exportPaths: [String],
        knownManifestUnreadable: Bool = false
    ) {
        self.folder = folder
        self.projectName = projectName
        self.isYouTubeProject = isYouTubeProject
        self.sourceRelativePath = sourceRelativePath
        self.thumbnailPaths = thumbnailPaths
        self.narrationReferences = narrationReferences
        self.importedPaths = importedPaths
        self.exportPaths = exportPaths
        self.knownManifestUnreadable = knownManifestUnreadable
    }
}

struct ProjectIntegrityReport: Equatable, Sendable {
    let level: ProjectIntegrityLevel
    let problems: [ProjectFileProblem]
    let totalTrackedFiles: Int
    let missingTrackedFiles: Int
    let manifestUnreadable: Bool
    let folderMissing: Bool
    let projectName: String
    let folderPath: String?

    var isHealthy: Bool { level == .healthy }
    var isDamaged: Bool { level == .damaged }
    var hasWarnings: Bool { level == .warning }

    var canShowInFinder: Bool { !folderMissing && folderPath != nil }

    var canRegenerateNarration: Bool {
        !folderMissing && problems.contains { $0.category == .narration }
    }

    /// Regenerating video details needs the original video, so it is only
    /// offered when the source is still available.
    var canRegenerateVideoArtifacts: Bool {
        !folderMissing
            && !problems.contains { $0.category == .source }
            && problems.contains { $0.category == .metadata || $0.category == .thumbnails }
    }

    var canReExport: Bool {
        !folderMissing && problems.contains { $0.category == .exports }
    }

    var headline: String {
        if isHealthy { return "Project Files Are Healthy" }
        if folderMissing { return "Project Folder Is Missing" }
        if manifestUnreadable { return "Project Is Marked as Damaged" }
        if problems.contains(where: { $0.category == .source }) { return "Original Video Is Missing" }
        if isDamaged { return "Project Is Marked as Damaged" }
        if problems.count == 1, let problem = problems.first {
            switch problem.category {
            case .narration: return "Narration Audio Is Missing"
            case .thumbnails: return "Timeline Pictures Are Missing"
            case .metadata: return "Video Details Are Missing"
            case .exports: return "Exports Are Missing"
            case .importedAssets: return "Imported Assets Are Missing"
            case .manifest: return "Project File Is Missing"
            case .source: return "Original Video Is Missing"
            case .significantLoss: return "Project Is Marked as Damaged"
            }
        }
        return "Project Files Are Missing"
    }

    var message: String {
        if isHealthy {
            return "All tracked project files are available."
        }
        if folderMissing {
            return "The project folder could not be found, so none of its files are available. Remove the project from VidiStudio or restore the folder from the Bin."
        }
        if manifestUnreadable {
            return "The project file (project.json) is missing, empty, or damaged. VidiStudio cannot load or save this project's transcript, summary, descriptions, or settings, so the project is marked as damaged. Restore it from a backup, or delete the project if no backup exists."
        }
        if problems.contains(where: { $0.category == .source }) {
            return "The original video stored in this project is missing. Playback, video analysis, and video exports are unavailable, and the original video cannot be regenerated. Delete the project if the source is no longer available."
        }
        if isDamaged {
            return "Most of this project's files are missing. VidiStudio marked the project as damaged because too little of the original project remains. Regenerate what is available or delete the project if it cannot be recovered."
        }
        if problems.count == 1, let problem = problems.first {
            switch problem.category {
            case .narration:
                return "Narration audio is missing for \(problem.missingCount) AD segment\(problem.missingCount == 1 ? "" : "s"). The description text and timing are safe, and the missing audio can be regenerated."
            case .thumbnails:
                return "Timeline pictures are missing. The project can still be edited, and the pictures can be regenerated from the original video."
            case .metadata:
                return "Video details are missing. Playback and editing still work, and the details can be regenerated from the original video."
            case .exports:
                return "\(problem.missingCount) exported file\(problem.missingCount == 1 ? "" : "s") listed in this project are missing. Export them again to recreate the files."
            case .importedAssets:
                return "\(problem.missingCount) imported file\(problem.missingCount == 1 ? "" : "s") are missing. Project text stays available; restore the file or import it again."
            case .manifest, .source, .significantLoss:
                break
            }
        }
        return "Some generated project files are missing. Your transcript, summary, descriptions, and project settings are stored in project.json and are still available. The missing files can be regenerated or re-exported."
    }

    var accessibilityLabel: String {
        "\(headline). \(message) \(missingTrackedFiles) of \(totalTrackedFiles) tracked files are missing."
    }

    var badgeAccessibilityLabel: String {
        isDamaged
            ? "Project damaged, \(missingTrackedFiles) files missing"
            : "Project files missing, \(missingTrackedFiles) files missing"
    }

    var shortDescription: String {
        "\(headline). \(missingTrackedFiles) of \(totalTrackedFiles) tracked files are missing."
    }

    static func healthy(projectName: String, folderPath: String?) -> ProjectIntegrityReport {
        ProjectIntegrityReport(
            level: .healthy,
            problems: [],
            totalTrackedFiles: 0,
            missingTrackedFiles: 0,
            manifestUnreadable: false,
            folderMissing: false,
            projectName: projectName,
            folderPath: folderPath
        )
    }
}

enum ProjectIntegrityAuditor {
    private enum FileState {
        case ok
        case missing
        case empty
        case unreadable
        case notRegularFile
        case invalidJSON
    }

    static func audit(_ manifest: ProjectIntegrityManifest) -> ProjectIntegrityReport {
        guard let folder = manifest.folder else {
            return folderMissingReport(manifest: manifest, folderPath: nil)
        }
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let folderExists = fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue
        guard folderExists else {
            return folderMissingReport(manifest: manifest, folderPath: folder.path)
        }

        var problems: [ProjectFileProblem] = []
        var trackedFiles = 0
        var missingFiles = 0
        var manifestUnreadable = false

        // project.json is the project's source of truth.
        trackedFiles += 1
        let manifestState = manifest.knownManifestUnreadable
            ? FileState.invalidJSON
            : manifestFileState(folder)
        if manifestState != .ok {
            manifestUnreadable = true
            missingFiles += 1
            problems.append(ProjectFileProblem(
                category: .manifest,
                severity: .damaged,
                title: "Project file is missing or damaged",
                detail: "project.json is \(describe(manifestState)).",
                impact: "VidiStudio cannot open, save, or recover the project's transcript, summary, descriptions, and settings.",
                recovery: "Restore project.json from a backup, or delete the project if no backup exists.",
                missingFiles: [ProjectMissingFile(path: "project.json", displayName: "project.json")],
                expectedCount: 1
            ))
        }

        // The original video cannot be recreated by VidiStudio. YouTube
        // projects use the remote URL from project.json instead of a local file.
        if !manifest.isYouTubeProject {
            trackedFiles += 1
            let source = manifest.sourceRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if source.isEmpty {
                missingFiles += 1
                problems.append(ProjectFileProblem(
                    category: .source,
                    severity: .damaged,
                    title: "Original video reference is missing",
                    detail: "The project does not contain a valid relative path to its original video.",
                    impact: "Playback, video analysis, and video exports are unavailable because VidiStudio cannot find the source video.",
                    recovery: "Restore the project's source folder from a backup, or delete the project and import the video again.",
                    missingFiles: [ProjectMissingFile(path: "source", displayName: "source/ (unknown video file)")],
                    expectedCount: 1
                ))
            } else if let url = resolve(source, in: folder) {
                let state = fileState(url, allowDirectory: false)
                if state != .ok {
                    missingFiles += 1
                    problems.append(ProjectFileProblem(
                        category: .source,
                        severity: .damaged,
                        title: "Original video is missing",
                        detail: "\(source) is \(describe(state)).",
                        impact: "Playback, video analysis, and video exports are unavailable, and the original video cannot be regenerated.",
                        recovery: "Restore the source video from the Bin or a backup. If it is gone, delete the project and import the video again.",
                        missingFiles: [ProjectMissingFile(path: source, displayName: source)],
                        expectedCount: 1
                    ))
                }
            } else {
                missingFiles += 1
                problems.append(ProjectFileProblem(
                    category: .source,
                    severity: .damaged,
                    title: "Original video path is invalid",
                    detail: "The saved video path is outside the project folder.",
                    impact: "Playback, video analysis, and video exports are unavailable.",
                    recovery: "Restore a valid source video inside the project's source folder, or delete the project.",
                    missingFiles: [ProjectMissingFile(path: source, displayName: source)],
                    expectedCount: 1
                ))
            }
        }

        // Video details are regenerated by Prepare Video.
        trackedFiles += 1
        let probePath = "metadata/probe.json"
        let probeState = fileState(folder.appendingPathComponent(probePath), allowDirectory: false)
        if probeState != .ok {
            missingFiles += 1
            problems.append(ProjectFileProblem(
                category: .metadata,
                severity: .warning,
                title: "Video details are missing",
                detail: "\(probePath) is \(describe(probeState)).",
                impact: "Project information and the timeline may be incomplete until the video details are regenerated.",
                recovery: "Use Analysis → Generate Video Details & Timeline Pictures to recreate this file.",
                missingFiles: [ProjectMissingFile(path: probePath, displayName: probePath)],
                expectedCount: 1
            ))
        }

        // Referenced timeline pictures.
        let thumbnailPaths = uniquePaths(manifest.thumbnailPaths)
        var missingThumbnails: [ProjectMissingFile] = []
        for path in thumbnailPaths {
            guard let url = resolve(path, in: folder), fileState(url, allowDirectory: false) == .ok else {
                missingThumbnails.append(ProjectMissingFile(path: path, displayName: path))
                continue
            }
        }
        trackedFiles += thumbnailPaths.count
        if !missingThumbnails.isEmpty {
            missingFiles += missingThumbnails.count
            problems.append(ProjectFileProblem(
                category: .thumbnails,
                severity: .warning,
                title: "Timeline pictures are missing",
                detail: "\(missingThumbnails.count) of \(thumbnailPaths.count) timeline picture\(thumbnailPaths.count == 1 ? "" : "s") \(missingThumbnails.count == 1 ? "is" : "are") missing or empty.",
                impact: "The project browser preview and timeline pictures may be incomplete.",
                recovery: "Use Analysis → Generate Video Details & Timeline Pictures to recreate them.",
                missingFiles: missingThumbnails,
                expectedCount: thumbnailPaths.count
            ))
        }

        // Referenced narration audio. Cues without an audio path have simply
        // not been narrated yet and are not damage.
        let narrationReferences = uniqueNarrationReferences(manifest.narrationReferences)
        var missingNarration: [ProjectMissingFile] = []
        for reference in narrationReferences {
            guard let url = resolve(reference.path, in: folder), fileState(url, allowDirectory: false) == .ok else {
                missingNarration.append(ProjectMissingFile(
                    path: reference.path,
                    displayName: reference.displayName
                ))
                continue
            }
        }
        trackedFiles += narrationReferences.count
        if !missingNarration.isEmpty {
            missingFiles += missingNarration.count
            problems.append(ProjectFileProblem(
                category: .narration,
                severity: .warning,
                title: "Narration audio is missing",
                detail: "\(missingNarration.count) of \(narrationReferences.count) narration audio file\(narrationReferences.count == 1 ? "" : "s") \(missingNarration.count == 1 ? "is" : "are") missing or empty.",
                impact: "Affected AD segments will play without narration, and exports that need narration may fail until the audio is regenerated.",
                recovery: "Use Generate Missing or Changed AD Audio to recreate the missing narration.",
                missingFiles: missingNarration,
                expectedCount: narrationReferences.count
            ))
        }

        // Imported assets are copied into the project and are never recreated by
        // analysis. Losing one is a warning: the project content stays, but the
        // original imported file must be restored or imported again.
        let importedPaths = uniquePaths(manifest.importedPaths)
        var missingImports: [ProjectMissingFile] = []
        for path in importedPaths {
            guard let url = resolve(path, in: folder), fileState(url, allowDirectory: false) == .ok else {
                missingImports.append(ProjectMissingFile(path: path, displayName: path))
                continue
            }
        }
        trackedFiles += importedPaths.count
        if !missingImports.isEmpty {
            missingFiles += missingImports.count
            problems.append(ProjectFileProblem(
                category: .importedAssets,
                severity: .warning,
                title: "Imported assets are missing",
                detail: "\(missingImports.count) of \(importedPaths.count) imported file\(importedPaths.count == 1 ? "" : "s") \(missingImports.count == 1 ? "is" : "are") missing or empty.",
                impact: "Existing text and descriptions remain in the project, but imported audio or a combined AD transcript cannot be used until it is restored.",
                recovery: "Restore the imported file from a backup, or use Project → Import Existing Assets… to import it again.",
                missingFiles: missingImports,
                expectedCount: importedPaths.count
            ))
        }

        // Referenced exports. HLS exports are folders, so directories count as
        // present when they contain at least one file.
        let exportPaths = uniquePaths(manifest.exportPaths)
        var missingExports: [ProjectMissingFile] = []
        for path in exportPaths {
            guard let url = resolve(path, in: folder), fileState(url, allowDirectory: true) == .ok else {
                missingExports.append(ProjectMissingFile(path: path, displayName: path))
                continue
            }
        }
        trackedFiles += exportPaths.count
        if !missingExports.isEmpty {
            missingFiles += missingExports.count
            problems.append(ProjectFileProblem(
                category: .exports,
                severity: .warning,
                title: "Exports are missing",
                detail: "\(missingExports.count) of \(exportPaths.count) exported file\(exportPaths.count == 1 ? "" : "s") \(missingExports.count == 1 ? "is" : "are") missing or empty.",
                impact: "The project still lists these exports, but they cannot be opened or shared until they are recreated.",
                recovery: "Use Export to recreate the missing files.",
                missingFiles: missingExports,
                expectedCount: exportPaths.count
            ))
        }

        // A project with most of its files gone is marked damaged even when
        // project.json and the source video still exist. A single regenerable
        // category (for example every narration file) stays a warning so the
        // user can recreate it without being told to delete the project.
        let affectedGeneratedCategories = Set(problems.filter {
            $0.severity == .warning && $0.category != .metadata && $0.category != .importedAssets
        }.map(\.category))
        if !problems.contains(where: { $0.severity == .damaged }),
           trackedFiles >= 4,
           missingFiles >= 3,
           affectedGeneratedCategories.count >= 2,
           Double(missingFiles) / Double(trackedFiles) >= 0.75 {
            problems.insert(ProjectFileProblem(
                category: .significantLoss,
                severity: .damaged,
                title: "Most project files are missing",
                detail: "\(missingFiles) of \(trackedFiles) tracked files are missing or empty.",
                impact: "The project is marked as damaged because a significant portion of its files are gone. Regenerate the missing files or delete the project.",
                recovery: "Regenerate available content where possible, or delete the project if the remaining files are not useful.",
                missingFiles: [],
                expectedCount: trackedFiles
            ), at: 0)
        }

        let level: ProjectIntegrityLevel
        if problems.contains(where: { $0.severity == .damaged }) {
            level = .damaged
        } else if problems.isEmpty {
            level = .healthy
        } else {
            level = .warning
        }

        return ProjectIntegrityReport(
            level: level,
            problems: problems,
            totalTrackedFiles: trackedFiles,
            missingTrackedFiles: missingFiles,
            manifestUnreadable: manifestUnreadable,
            folderMissing: false,
            projectName: manifest.projectName,
            folderPath: folder.path
        )
    }

    static func folderLooksLikeProject(_ folder: URL) -> Bool {
        let markers = [
            "project.json",
            "source",
            "metadata",
            "thumbnails",
            "audio-description",
            "exports",
            ".engine.lock"
        ]
        let fileManager = FileManager.default
        if markers.contains(where: { marker in
            fileManager.fileExists(atPath: folder.appendingPathComponent(marker).path)
        }) {
            return true
        }
        // VidiStudio creates project folders as "<project name>-<8 hex chars>".
        // An otherwise empty folder with that shape is still worth surfacing as
        // a damaged project so the user can remove it.
        let name = folder.lastPathComponent
        guard name.count > 9 else { return false }
        let suffix = name.suffix(9)
        return suffix.first == "-" && suffix.dropFirst().allSatisfy { $0.isHexDigit }
    }

    static func resolve(_ relative: String, in folder: URL) -> URL? {
        let trimmed = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/") else { return nil }
        let root = folder.standardizedFileURL.resolvingSymlinksInPath()
        let url = root.appendingPathComponent(trimmed).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/") else { return nil }
        return url
    }

    private static func folderMissingReport(manifest: ProjectIntegrityManifest, folderPath: String?) -> ProjectIntegrityReport {
        let problem = ProjectFileProblem(
            category: .manifest,
            severity: .damaged,
            title: "Project folder is missing",
            detail: folderPath.map { "The folder \($0) could not be found." } ?? "The project folder could not be found.",
            impact: "No project files are available, so the project cannot be opened, edited, or exported.",
            recovery: "Restore the folder from the Bin, or remove the project from VidiStudio.",
            missingFiles: folderPath.map { [ProjectMissingFile(path: $0, displayName: $0)] } ?? [],
            expectedCount: 1
        )
        return ProjectIntegrityReport(
            level: .damaged,
            problems: [problem],
            totalTrackedFiles: 1,
            missingTrackedFiles: 1,
            manifestUnreadable: true,
            folderMissing: true,
            projectName: manifest.projectName,
            folderPath: folderPath
        )
    }

    private static func manifestFileState(_ folder: URL) -> FileState {
        let url = folder.appendingPathComponent("project.json")
        let state = fileState(url, allowDirectory: false)
        guard state == .ok else { return state }
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return .invalidJSON
        }
        return .ok
    }

    private static func fileState(_ url: URL, allowDirectory: Bool) -> FileState {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .missing
        }
        if isDirectory.boolValue {
            guard allowDirectory else { return .notRegularFile }
            let contents = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            return contents.isEmpty ? .empty : .ok
        }
        guard fileManager.isReadableFile(atPath: url.path) else { return .unreadable }
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              size > 0 else {
            return .empty
        }
        return .ok
    }

    private static func describe(_ state: FileState) -> String {
        switch state {
        case .ok: return "available"
        case .missing: return "missing"
        case .empty: return "empty"
        case .unreadable: return "unreadable"
        case .notRegularFile: return "not a regular file"
        case .invalidJSON: return "damaged or not valid JSON"
        }
    }

    private static func uniquePaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.compactMap { path in
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    private static func uniqueNarrationReferences(_ references: [ProjectNarrationReference]) -> [ProjectNarrationReference] {
        var seen = Set<String>()
        return references.compactMap { reference in
            let path = reference.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            return ProjectNarrationReference(path: path, segmentNumber: reference.segmentNumber, timeRange: reference.timeRange)
        }
    }
}
