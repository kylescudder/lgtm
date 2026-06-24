import Foundation

/// Response of the org-scoped `_apis/connectionData` endpoint. `authenticatedUser.id`
/// is the Azure DevOps **identity GUID** for the signed-in user in this organization
/// — the value PR `creatorId` / `reviewerId` filters expect. It is *not* the Entra
/// object id, so it must be resolved per org rather than assumed from the token.
public struct ConnectionData: Codable, Sendable {
    public let authenticatedUser: IdentityRef?
    public let authorizedUser: IdentityRef?
}
