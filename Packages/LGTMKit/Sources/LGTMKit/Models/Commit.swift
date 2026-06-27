import Foundation

/// Authored/committed name + email + timestamp on a Git commit.
public struct GitUserDate: Codable, Sendable, Hashable {
    public let name: String?
    public let email: String?
    public let date: Date?
}

/// A commit on a pull request.
public struct GitCommit: Codable, Sendable, Identifiable, Hashable {
    public let commitId: String
    public let comment: String?
    public let author: GitUserDate?
    public let committer: GitUserDate?
    /// Parent commit ids. Present on the single-commit "Get Commit" response, not
    /// on the PR commits list. The first parent is the base to diff this commit against.
    public let parents: [String]?
    /// The files changed by this commit. Present when fetched with a `changeCount`
    /// (see `ADOClient.commit`), otherwise `nil`.
    public let changes: [ChangeEntry]?

    public var id: String { commitId }
    /// The abbreviated SHA shown in the UI.
    public var shortId: String { String(commitId.prefix(8)) }
    /// The first line of the commit message.
    public var summary: String {
        (comment ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }
    /// The first parent — the commit to diff this one against. `nil` for a root commit.
    public var parentId: String? { parents?.first }
}
