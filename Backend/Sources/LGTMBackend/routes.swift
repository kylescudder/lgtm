import Vapor
import VaporAPNS
import APNSCore
import LGTMKit

struct DeviceStoreKey: StorageKey { typealias Value = any DeviceStore }

func routes(_ app: Application) throws {
    app.storage[DeviceStoreKey.self] = InMemoryDeviceStore()

    app.get("health") { _ in "ok" }

    // MARK: Device registration (called by the app, authenticated with the
    // backend's own Entra scope). EntraAuthMiddleware validates the bearer token
    // and attaches the caller's `oid`.
    app.grouped(EntraAuthMiddleware())
        .post("devices") { req async throws -> HTTPStatus in
            let body = try req.content.decode(RegisterDeviceRequest.self)
            let oid = try req.requireEntraOID()
            let store = req.application.storage[DeviceStoreKey.self]!
            await store.register(oid: oid, apnsToken: body.apnsToken, platform: body.platform)
            return .ok
        }

    // MARK: Azure DevOps service-hook receiver.
    app.post("webhooks", "azuredevops") { req async throws -> HTTPStatus in
        // Verify the shared secret the service hook was configured with.
        let expected = req.application.storage[WebhookSecretKey.self]
        guard expected == nil || req.headers.first(name: "X-Webhook-Secret") == expected else {
            throw Abort(.unauthorized)
        }

        let event = try req.content.decode(PullRequestEvent.self)
        let reviewerIDs = PushLogic.reviewerIdsToNotify(for: event)
        guard !reviewerIDs.isEmpty else { return .ok }

        let store = req.application.storage[DeviceStoreKey.self]!
        let title = event.resource?.title ?? "Pull request"
        for oid in reviewerIDs {
            let tokens = await store.tokens(for: oid)
            for token in tokens {
                let alert = APNSAlertNotification(
                    alert: .init(title: .raw("Review requested"), body: .raw(title)),
                    expiration: .immediately,
                    priority: .immediately,
                    topic: Environment.get("APNS_TOPIC") ?? "co.uk.kylescudder.lgtm",
                    payload: PRPushPayload(pullRequestId: event.resource?.pullRequestId ?? 0)
                )
                try? await req.application.apns.client.sendAlertNotification(alert, deviceToken: token)
            }
        }
        return .ok
    }
}

struct RegisterDeviceRequest: Content {
    let apnsToken: String
    let platform: String
}

struct PRPushPayload: Codable {
    let pullRequestId: Int
}
