import Foundation
import LGTMKit

/// Composition root: wires the token provider into the Azure DevOps client and
/// the push service. The Azure DevOps organization is chosen at runtime — the
/// signed-in user may belong to several, and one Entra token works across all.
@MainActor
final class AppServices: ObservableObject {
    let tokenProvider: MSALTokenProvider
    let push: PushService
    /// Disk-persisted per-org cache of projects + resolved user id, so the PR
    /// list can render instantly from cache while a background refresh runs.
    let cache = CacheStore()

    /// The currently selected organization, and a client bound to it.
    @Published private(set) var currentOrg: Account?
    @Published private(set) var ado: ADOClient?

    init(tokenProvider: MSALTokenProvider) {
        self.tokenProvider = tokenProvider
        self.push = PushService(
            configuration: .init(
                baseURL: AppConfiguration.backendBaseURL,
                backendScope: AppConfiguration.backendScope
            ),
            tokenProvider: tokenProvider
        )
        // Authenticated avatar fetches (ADO image URLs need a bearer token).
        AvatarLoader.shared.configure(tokenProvider: tokenProvider)
    }

    /// The organizations the signed-in user can access.
    func availableOrgs() async throws -> [Account] {
        // Org-agnostic client (no org needed for the vssps profile/accounts calls).
        let client = makeClient(org: "")
        let profile = try await client.profile()
        return try await client.accounts(memberId: profile.id)
    }

    /// Binds the client to an organization. PR queries then target this org.
    func selectOrg(_ account: Account) {
        currentOrg = account
        ado = makeClient(org: account.accountName)
    }

    /// Returns to the org picker.
    func clearOrg() {
        currentOrg = nil
        ado = nil
    }

    private func makeClient(org: String) -> ADOClient {
        ADOClient(
            configuration: ADOClientConfiguration(organization: org),
            tokenProvider: tokenProvider
        )
    }

    /// Registers this device's APNs token with the backend so it can receive
    /// "a PR needs your approval" pushes.
    func registerForPush(apnsToken: String, platform: DevicePlatform) async {
        do { try await push.registerDevice(apnsToken: apnsToken, platform: platform) }
        catch { print("Push registration failed: \(error)") }
    }
}
