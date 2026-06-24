import Foundation

/// A single comment within a pull request thread.
public struct Comment: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let content: String?
    public let author: IdentityRef?
    public let commentType: String?
    public let publishedDate: Date?
}

/// The file/line a thread is anchored to, when it is not a general comment.
public struct ThreadContext: Codable, Sendable, Hashable {
    public let filePath: String?
}

/// A comment thread on a pull request.
public struct CommentThread: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let status: String?
    public let comments: [Comment]?
    public let publishedDate: Date?
    public let threadContext: ThreadContext?

    /// `true` when the thread is a general (non-file-anchored) discussion.
    public var isGeneral: Bool { threadContext?.filePath == nil }
}
