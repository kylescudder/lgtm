import Vapor
import VaporAPNS
import APNSCore

/// Wires up APNs (token-based auth with the .p8 key) and routes.
func configure(_ app: Application) async throws {
    // APNs token-based auth — one key serves iOS and macOS.
    let apnsConfig = APNSClientConfiguration(
        authenticationMethod: .jwt(
            privateKey: try .loadFrom(string: Environment.get("APNS_P8") ?? ""),
            keyIdentifier: Environment.get("APNS_KEY_ID") ?? "",
            teamIdentifier: Environment.get("APNS_TEAM_ID") ?? ""
        ),
        environment: app.environment.isRelease ? .production : .development
    )
    app.apns.containers.use(
        apnsConfig,
        eventLoopGroupProvider: .shared(app.eventLoopGroup),
        responseDecoder: JSONDecoder(),
        requestEncoder: JSONEncoder(),
        as: .default
    )

    // Shared secret used to verify Azure DevOps webhook calls.
    app.storage[WebhookSecretKey.self] = Environment.get("WEBHOOK_SECRET")

    try routes(app)
}

struct WebhookSecretKey: StorageKey { typealias Value = String }
