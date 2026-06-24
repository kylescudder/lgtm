import Foundation

/// A reviewer's vote on a pull request. Raw values match the Azure DevOps REST API.
public enum Vote: Int, Codable, Sendable, CaseIterable {
    case approved = 10
    case approvedWithSuggestions = 5
    case noVote = 0
    case waitingForAuthor = -5
    case rejected = -10

    /// Human-readable label for UI.
    public var label: String {
        switch self {
        case .approved: return "Approved"
        case .approvedWithSuggestions: return "Approved with suggestions"
        case .noVote: return "No vote"
        case .waitingForAuthor: return "Waiting for author"
        case .rejected: return "Rejected"
        }
    }

    // Defensive decoding: unknown numeric values map to `.noVote` rather than failing the whole payload.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = Vote(rawValue: raw) ?? .noVote
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A reviewer assigned to a pull request, including their current vote.
public struct Reviewer: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let displayName: String?
    public let uniqueName: String?
    public let imageUrl: URL?
    public let vote: Vote
    public let isRequired: Bool?
    public let hasDeclined: Bool?

    enum CodingKeys: String, CodingKey {
        case id, displayName, uniqueName, imageUrl, vote
        case isRequired, hasDeclined
    }

    public init(id: String, displayName: String? = nil, uniqueName: String? = nil,
                imageUrl: URL? = nil, vote: Vote = .noVote,
                isRequired: Bool? = nil, hasDeclined: Bool? = nil) {
        self.id = id
        self.displayName = displayName
        self.uniqueName = uniqueName
        self.imageUrl = imageUrl
        self.vote = vote
        self.isRequired = isRequired
        self.hasDeclined = hasDeclined
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        uniqueName = try c.decodeIfPresent(String.self, forKey: .uniqueName)
        imageUrl = try c.decodeIfPresent(URL.self, forKey: .imageUrl)
        vote = try c.decodeIfPresent(Vote.self, forKey: .vote) ?? .noVote
        isRequired = try c.decodeIfPresent(Bool.self, forKey: .isRequired)
        hasDeclined = try c.decodeIfPresent(Bool.self, forKey: .hasDeclined)
    }
}
