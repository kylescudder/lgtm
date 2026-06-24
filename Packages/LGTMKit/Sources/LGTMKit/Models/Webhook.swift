import Foundation

/// An Azure DevOps service-hook event for a pull request
/// (`git.pullrequest.created` / `git.pullrequest.updated`).
///
/// The push backend receives these, decides who is newly blocking the PR, and
/// pushes to their devices. The `resource` reuses `PullRequest`, which already
/// carries `reviewers`, `createdBy`, and `repository`.
public struct PullRequestEvent: Codable, Sendable {
    public let eventType: String?
    public let resource: PullRequest?

    public init(eventType: String?, resource: PullRequest?) {
        self.eventType = eventType
        self.resource = resource
    }
}

/// Pure domain logic shared by the app and the push backend.
public enum PushLogic {
    /// The reviewer identity ids that should be notified that a pull request
    /// needs their attention.
    ///
    /// A reviewer is notified when the PR is active and they are a non-author
    /// reviewer who has not yet voted and has not declined.
    public static func reviewerIdsToNotify(for event: PullRequestEvent) -> [String] {
        guard let pr = event.resource, pr.status == .active else { return [] }
        let authorId = pr.createdBy?.id
        return (pr.reviewers ?? [])
            .filter { reviewer in
                reviewer.id != authorId
                    && reviewer.vote == .noVote
                    && reviewer.hasDeclined != true
            }
            .map(\.id)
    }
}
