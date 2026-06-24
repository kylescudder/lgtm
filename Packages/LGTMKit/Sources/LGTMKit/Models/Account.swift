import Foundation

/// The signed-in user's Azure DevOps profile (from the vssps profile API).
/// Its `id` is the `memberId` used to look up accessible organizations.
public struct Profile: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let displayName: String?
    public let emailAddress: String?
}

/// An Azure DevOps organization (account) the user can access.
/// `accountName` is the `{org}` segment in `dev.azure.com/{org}`.
public struct Account: Codable, Sendable, Identifiable, Hashable {
    public let accountId: String
    public let accountName: String
    public let accountUri: String?

    public var id: String { accountId }
}

/// A team project within an organization.
public struct Project: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let state: String?
}
