import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The Apple platform a device token belongs to.
public enum DevicePlatform: String, Codable, Sendable {
    case iOS
    case macOS
}

/// Registers this device's APNs token with our push backend so the backend can
/// deliver "a PR needs your approval" notifications.
///
/// Calls are authenticated with a bearer token for the backend's own Entra scope
/// (distinct from the Azure DevOps scope) so the backend can trust the caller's
/// identity (`oid`) without ever seeing the Azure DevOps token.
public struct PushService: Sendable {
    public struct Configuration: Sendable {
        /// Root URL of the push backend, e.g. `https://lgtm-push.kylescudder.dev`.
        public var baseURL: URL
        /// The Entra scope exposed by the backend API registration.
        public var backendScope: String

        public init(baseURL: URL, backendScope: String) {
            self.baseURL = baseURL
            self.backendScope = backendScope
        }
    }

    private let configuration: Configuration
    private let tokenProvider: any TokenProvider
    private let session: URLSession

    public init(
        configuration: Configuration,
        tokenProvider: any TokenProvider,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.tokenProvider = tokenProvider
        self.session = session
    }

    /// Registers (or refreshes) this device's APNs token.
    public func registerDevice(apnsToken: String, platform: DevicePlatform) async throws {
        let body = try JSONCoding.makeEncoder().encode(
            RegisterDeviceBody(apnsToken: apnsToken, platform: platform)
        )
        let token = try await tokenProvider.token(for: configuration.backendScope)

        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("devices"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ADOError.invalidResponse }
        switch http.statusCode {
        case 200...299: return
        case 401: throw ADOError.unauthorized
        default:
            let bodyString = data.isEmpty ? nil : String(data: data, encoding: .utf8)
            throw ADOError.httpError(status: http.statusCode, body: bodyString)
        }
    }
}

private struct RegisterDeviceBody: Encodable {
    let apnsToken: String
    let platform: DevicePlatform
}
