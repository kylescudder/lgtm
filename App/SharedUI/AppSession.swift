import Foundation
import LGTMKit

/// Holds the signed-in session. Created empty at launch; `signIn()` builds the
/// `AppServices` (and triggers the MSAL interactive flow) on demand, so the app
/// launches cleanly even before Phase 0 configuration exists.
@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var services: AppServices?
    @Published var lastError: String?
    @Published private(set) var isSigningIn = false

    private let factory: () throws -> AppServices

    init(factory: @escaping () throws -> AppServices) {
        self.factory = factory
    }

    func signIn() async {
        guard services == nil, !isSigningIn else { return }
        isSigningIn = true
        lastError = nil
        defer { isSigningIn = false }
        do {
            let services = try factory()
            // Force token acquisition now so the Microsoft sign-in UI appears
            // before we show the list.
            _ = try await services.tokenProvider.token(for: AppConfiguration.adoScopes.first ?? azureDevOpsDefaultScope)
            self.services = services
        } catch {
            // Surface the full error (incl. MSAL sub-codes) to the console for diagnosis.
            let ns = error as NSError
            print("Sign-in failed: domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            let detail = ns.userInfo["MSALErrorDescriptionKey"] as? String
            lastError = detail ?? (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func signOut() {
        try? services?.tokenProvider.signOut()
        services = nil
    }
}
