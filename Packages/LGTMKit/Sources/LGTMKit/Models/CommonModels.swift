import Foundation

/// A lightweight reference to an Azure DevOps identity (user or group).
public struct IdentityRef: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let displayName: String?
    public let uniqueName: String?
    public let imageUrl: URL?

    public init(id: String, displayName: String? = nil, uniqueName: String? = nil, imageUrl: URL? = nil) {
        self.id = id
        self.displayName = displayName
        self.uniqueName = uniqueName
        self.imageUrl = imageUrl
    }
}

/// A reference to a project that owns a repository.
public struct ProjectRef: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String?
}

/// A Git repository reference as returned on a pull request.
public struct GitRepository: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String?
    public let project: ProjectRef?
}

/// A reference to a Git commit.
public struct GitCommitRef: Codable, Sendable, Hashable {
    public let commitId: String?
    public let url: URL?

    public init(commitId: String?, url: URL? = nil) {
        self.commitId = commitId
        self.url = url
    }
}

/// The standard Azure DevOps list envelope: `{ "count": N, "value": [...] }`.
public struct ADOList<Element: Codable & Sendable>: Codable, Sendable {
    public let count: Int
    public let value: [Element]
}
