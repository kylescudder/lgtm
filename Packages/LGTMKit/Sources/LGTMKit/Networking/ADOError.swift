import Foundation

/// Errors surfaced by `ADOClient`.
public enum ADOError: Error, Sendable, Equatable {
    /// The token was rejected (HTTP 401).
    case unauthorized
    /// Throttled (HTTP 429). `retryAfter` is the server-advised wait, if present.
    case rateLimited(retryAfter: TimeInterval?)
    /// A non-success HTTP status not otherwise handled.
    case httpError(status: Int, body: String?)
    /// The response was missing or not an HTTP response.
    case invalidResponse
    /// The response body could not be decoded into the expected type.
    case decoding(String)
}

extension ADOError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .rateLimited(let retryAfter):
            if let retryAfter { return "Azure DevOps is rate limiting requests. Retry in \(Int(retryAfter))s." }
            return "Azure DevOps is rate limiting requests."
        case .httpError(let status, let body):
            return "Azure DevOps returned an error (HTTP \(status)).\(body.map { " \($0)" } ?? "")"
        case .invalidResponse:
            return "Received an invalid response from Azure DevOps."
        case .decoding(let detail):
            return "Could not read the Azure DevOps response: \(detail)"
        }
    }
}
