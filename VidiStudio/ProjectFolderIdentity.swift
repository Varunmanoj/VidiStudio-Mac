import Foundation

/// The same project folder can be reached through a library path, a recent path, or a directory link.
enum ProjectFolderIdentity {
    static func normalize(_ folder: URL) -> URL {
        folder.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }
}
