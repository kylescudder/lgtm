import Foundation

/// One iteration (pushed update) of a pull request.
public struct Iteration: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let description: String?
    public let createdDate: Date?
    public let sourceRefCommit: GitCommitRef?
    public let targetRefCommit: GitCommitRef?
}

/// The item (file/folder) affected by a change.
public struct ChangeItem: Codable, Sendable, Hashable {
    public let path: String?
    public let isFolder: Bool?
    /// `"blob"` for a file, `"tree"` for a folder. Present on commit changes;
    /// used to filter folders out of a commit's changed-file list.
    public let gitObjectType: String?
    /// The Git blob object id of this item's content. It changes whenever the
    /// file's content changes, so it identifies *which version* of a file was
    /// reviewed — letting a "reviewed" mark auto-clear when a later commit
    /// touches that file while leaving untouched files marked.
    public let objectId: String?
}

/// A single file change within a pull request iteration.
public struct ChangeEntry: Codable, Sendable, Hashable {
    public let changeType: String?
    public let item: ChangeItem?
}

/// The set of file changes in a pull request iteration.
public struct IterationChanges: Codable, Sendable {
    public let changeEntries: [ChangeEntry]?
}

/// A single item (file) returned by the Git items API, including its text content.
public struct GitItem: Codable, Sendable {
    public let content: String?
}

/// How a `versionDescriptor.version` should be interpreted by the Git items API.
public enum GitVersionType: String, Sendable {
    case commit
    case branch
}
