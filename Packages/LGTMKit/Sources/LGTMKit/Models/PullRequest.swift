import Foundation

/// The lifecycle status of a pull request.
public enum PullRequestStatus: String, Codable, Sendable {
    case active
    case completed
    case abandoned
    case all
    case notSet

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PullRequestStatus(rawValue: raw) ?? .notSet
    }
}

/// The merge state of a pull request's source into its target.
public enum MergeStatus: String, Codable, Sendable {
    case queued
    case conflicts
    case succeeded
    case rejectedByPolicy
    case failure
    case notSet

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MergeStatus(rawValue: raw) ?? .notSet
    }
}

/// An Azure DevOps pull request.
public struct PullRequest: Codable, Sendable, Identifiable, Hashable {
    public let pullRequestId: Int
    public let title: String?
    public let description: String?
    public let status: PullRequestStatus?
    public let createdBy: IdentityRef?
    public let creationDate: Date?
    public let sourceRefName: String?
    public let targetRefName: String?
    public let mergeStatus: MergeStatus?
    public let isDraft: Bool?
    public let reviewers: [Reviewer]?
    public let repository: GitRepository?
    public let lastMergeSourceCommit: GitCommitRef?

    public var id: Int { pullRequestId }

    /// The source branch name without the `refs/heads/` prefix.
    public var sourceBranch: String? { sourceRefName?.replacingOccurrences(of: "refs/heads/", with: "") }
    /// The target branch name without the `refs/heads/` prefix.
    public var targetBranch: String? { targetRefName?.replacingOccurrences(of: "refs/heads/", with: "") }
}
