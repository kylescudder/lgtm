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

    public var id: String { commitId }
    /// The abbreviated SHA shown in the UI.
    public var shortId: String { String(commitId.prefix(8)) }
    /// The first line of the commit message.
    public var summary: String {
        (comment ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }
}
