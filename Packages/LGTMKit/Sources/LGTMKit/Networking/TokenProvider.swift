import Foundation

/// Supplies OAuth bearer tokens for a given scope.
///
/// The production implementation wraps MSAL (`acquireTokenSilent` with an
/// interactive fallback) and lives in the app layer so that this package stays
/// free of the MSAL binary dependency and remains unit-testable. Tests inject a
/// simple stub.
public protocol TokenProvider: Sendable {
    /// Returns a valid bearer token for the requested scope, acquiring or
    /// refreshing one as needed.
    func token(for scope: String) async throws -> String
}

/// A trivial provider that always returns the same token. Useful for tests and
/// previews; not for production.
public struct StaticTokenProvider: TokenProvider {
    public let value: String
    public init(_ value: String) { self.value = value }
    public func token(for scope: String) async throws -> String { value }
}
