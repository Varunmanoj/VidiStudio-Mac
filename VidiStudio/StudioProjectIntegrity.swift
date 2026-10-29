import Foundation

enum StudioProjectIntegrity {
    /// Audits the files referenced by a loaded project.
    static func inspect(_ project: StudioProject) -> ProjectIntegrityReport {
        ProjectIntegrityAuditor.audit(project.integrityManifest)
    }

    /// True when project.json exists, is non-empty, and decodes into the model.
    /// Used to notice a live project file that was damaged after it was loaded
    /// and to upgrade a placeholder when its manifest is restored.
    static func isProjectManifestDecodable(at folder: URL) -> Bool {
        let url = folder.appendingPathComponent("project.json")
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return false }
        return (try? JSONDecoder().decode(StudioProject.self, from: data)) != nil
    }

    /// Builds a displayable, in-memory project for a folder that still has
    /// project artifacts but whose project.json is gone or cannot be decoded.
    static func damagedPlaceholder(folder: URL) -> StudioProject {
        let fileManager = FileManager.default
        let manifestURL = folder.appendingPathComponent("project.json")
        let object = (try? Data(contentsOf: manifestURL)).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        } ?? [:]

        let fallbackName = displayName(for: folder)
        let name = nonEmptyString(object["name"]) ?? fallbackName
        let id = nonEmptyString(object["id"]) ?? "damaged-\(stableIdentifier(for: folder))"
        let source = nonEmptyString(object["source"]) ?? ""
        let sourceType = nonEmptyString(object["sourceType"])
        let youtubeURL = nonEmptyString(object["youtubeURL"])
        let thumbnails = (object["thumbnails"] as? [String]) ?? []
        let exports = (object["exports"] as? [String]) ?? []
        let summary = (object["summary"] as? String) ?? ""

        let modified = (try? fileManager.attributesOfItem(atPath: folder.path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? Date().timeIntervalSince1970
        let createdAt = (object["createdAt"] as? Double) ?? modified
        let updatedAt = (object["updatedAt"] as? Double) ?? modified

        return StudioProject(
            schemaVersion: 2,
            id: id,
            name: name,
            source: source,
            duration: (object["duration"] as? Double) ?? 0,
            width: (object["width"] as? Int) ?? 0,
            height: (object["height"] as? Int) ?? 0,
            hasAudio: (object["hasAudio"] as? Bool) ?? false,
            createdAt: createdAt,
            updatedAt: updatedAt,
            thumbnails: thumbnails,
            transcript: [],
            summary: summary,
            cues: [],
            exports: exports,
            exportMediaInfo: nil,
            status: "Damaged",
            error: "project.json is missing or unreadable.",
            geminiVideo: nil,
            sourceType: sourceType,
            youtubeURL: youtubeURL,
            transcriptGenerated: nil,
            summaryGenerated: nil,
            descriptionsGenerated: nil,
            narrationEngine: nil,
            narrationVoice: nil,
            undoStack: nil,
            redoStack: nil,
            transcriptUndoStack: nil,
            transcriptRedoStack: nil,
            folder: folder,
            hasProcessed: nil,
            integrityPlaceholder: true
        )
    }

    static func displayName(for folder: URL) -> String {
        let name = folder.lastPathComponent
        guard name.count > 9 else { return name }
        let suffix = name.suffix(9)
        guard suffix.first == "-", suffix.dropFirst().allSatisfy({ $0.isHexDigit }) else {
            return name
        }
        return String(name.dropLast(9))
    }

    private static func stableIdentifier(for folder: URL) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in folder.standardizedFileURL.path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }
}

extension StudioProject {
    var integrityManifest: ProjectIntegrityManifest {
        let narrationReferences = cues.enumerated().compactMap { index, cue -> ProjectNarrationReference? in
            guard let path = cue.audio?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
                return nil
            }
            return ProjectNarrationReference(
                path: path,
                segmentNumber: index + 1,
                timeRange: "\(timecode(cue.start))–\(timecode(cue.end))"
            )
        }
        let importedPaths = [importedAudioDescription?.path, importedADTranscript?.path]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let manifestDecodable = folder.map { StudioProjectIntegrity.isProjectManifestDecodable(at: $0) } ?? false
        return ProjectIntegrityManifest(
            folder: folder,
            projectName: name,
            isYouTubeProject: isYouTubeURLProject,
            sourceRelativePath: source.isEmpty ? nil : source,
            thumbnailPaths: thumbnails,
            narrationReferences: narrationReferences,
            importedPaths: importedPaths,
            exportPaths: exports,
            knownManifestUnreadable: integrityPlaceholder == true && !manifestDecodable
        )
    }
}
