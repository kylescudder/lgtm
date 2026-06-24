import Foundation

/// The fixed Azure DevOps resource GUID used to scope Entra ID tokens.
public let azureDevOpsResourceID = "499b84ac-1321-427f-aa17-267ca6975798"

/// The default scope for Azure DevOps REST calls via Entra ID OAuth.
public let azureDevOpsDefaultScope = "\(azureDevOpsResourceID)/.default"

/// Configuration for `ADOClient`.
public struct ADOClientConfiguration: Sendable {
    /// The Azure DevOps organization name (the `{org}` in `dev.azure.com/{org}`).
    public var organization: String
    /// The Entra scope to request for Azure DevOps calls.
    public var adoScope: String
    /// The org-scoped service root. Defaults to `https://dev.azure.com`.
    public var baseURL: URL
    /// The account/profile service root (org-agnostic). Defaults to
    /// `https://app.vssps.visualstudio.com` — used to list the orgs a user can access.
    public var accountsBaseURL: URL
    /// The REST API version sent on every request.
    public var apiVersion: String
    /// Maximum retry attempts for throttled (429) or transient (5xx) responses.
    public var maxRetries: Int
    /// Base delay (seconds) for exponential backoff when the server gives no `Retry-After`.
    public var retryBaseDelay: TimeInterval

    public init(
        organization: String,
        adoScope: String = azureDevOpsDefaultScope,
        baseURL: URL = URL(string: "https://dev.azure.com")!,
        accountsBaseURL: URL = URL(string: "https://app.vssps.visualstudio.com")!,
        apiVersion: String = "7.1",
        maxRetries: Int = 3,
        retryBaseDelay: TimeInterval = 0.5
    ) {
        self.organization = organization
        self.adoScope = adoScope
        self.baseURL = baseURL
        self.accountsBaseURL = accountsBaseURL
        self.apiVersion = apiVersion
        self.maxRetries = maxRetries
        self.retryBaseDelay = retryBaseDelay
    }
}

/// HTTP methods used by the client.
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case put = "PUT"
    case delete = "DELETE"
}
