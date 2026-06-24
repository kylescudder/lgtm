import Vapor
import JWT

/// Validates an Entra ID access token on incoming requests and stashes the
/// caller's object id (`oid`) for handlers to read.
///
/// Production hardening (left as TODOs): fetch and cache the tenant JWKS from
/// `https://login.microsoftonline.com/<tenant>/discovery/v2.0/keys`, verify the
/// signature with it, and check `aud` == the backend API's app ID URI and `iss`
/// == the tenant issuer.
struct EntraAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let bearer = request.headers.bearerAuthorization else {
            throw Abort(.unauthorized, reason: "Missing bearer token")
        }
        // TODO: verify signature against the tenant JWKS and validate aud/iss/exp.
        let payload = try request.jwt.parse(EntraClaims.self, from: bearer.token)
        request.storage[EntraOIDKey.self] = payload.oid.value
        return try await next.respond(to: request)
    }
}

struct EntraClaims: JWTPayload {
    let oid: SubjectClaim
    let exp: ExpirationClaim
    func verify(using algorithm: some JWTAlgorithm) throws {
        try exp.verifyNotExpired()
    }
}

struct EntraOIDKey: StorageKey { typealias Value = String }

extension Request {
    func requireEntraOID() throws -> String {
        guard let oid = storage[EntraOIDKey.self] else { throw Abort(.unauthorized) }
        return oid
    }
}
