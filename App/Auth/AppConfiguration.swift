import Foundation
import LGTMKit

/// Static configuration for the app. Fill these in after completing the Phase 0
/// registrations (see the project README).
///
/// Multi-tenant public-client values; nothing here is secret (public client,
/// no client secret), so it is safe to commit.
enum AppConfiguration {
    /// Entra application (client) ID of the native app registration.
    /// The app's own identity — the same for every install, and not secret.
    static let clientID = "882f43d1-27fb-46d7-9c49-f614101b2475"

    /// Multi-tenant authority: users from ANY Entra organization can sign in.
    /// (The app registration must be configured as multi-tenant.) Azure DevOps
    /// does not support personal Microsoft accounts, so use `/organizations`
    /// rather than `/common`.
    static let authority = "https://login.microsoftonline.com/organizations"

    /// Redirect URI — must match the platform redirect registered in Entra.
    /// Format: `msauth.<bundle-id>://auth`.
    static let redirectURI = "msauth.\(Bundle.main.bundleIdentifier ?? "co.uk.kylescudder.lgtm")://auth"

    // The Azure DevOps organization is chosen at runtime (the user may belong to
    // several); there is no hardcoded org.

    /// Scopes requested for Azure DevOps REST calls.
    static let adoScopes = [azureDevOpsDefaultScope]

    /// Scope exposed by the push backend's own Entra API registration.
    static let backendScope = "api://<BACKEND_APP_ID>/access_as_user"

    /// Push backend root URL.
    static let backendBaseURL = URL(string: "https://lgtm-push.kylescudder.dev")!

    /// Keychain access group for MSAL token cache / SSO across the suite.
    /// iOS: `com.microsoft.adalcache`; macOS: `com.microsoft.identity.universalstorage`.
    #if os(macOS)
    static let keychainGroup = "com.microsoft.identity.universalstorage"
    #else
    static let keychainGroup = "com.microsoft.adalcache"
    #endif

    /// `true` once the Phase 0 client ID has been filled in. Until then the app
    /// launches into a "configuration needed" state instead of attempting (and
    /// crashing on) an invalid sign-in.
    static var isConfigured: Bool {
        !clientID.contains("<")
    }
}
