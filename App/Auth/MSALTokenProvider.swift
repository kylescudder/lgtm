import Foundation
import LGTMKit
import MSAL   // Add via SPM: https://github.com/AzureAD/microsoft-authentication-library-for-objc

#if canImport(UIKit)
import UIKit
typealias PresentationAnchor = UIViewController
#elseif canImport(AppKit)
import AppKit
typealias PresentationAnchor = NSViewController
#endif

/// MSAL-backed `TokenProvider`.
///
/// Tries silent acquisition first (cached/refresh token), falling back to an
/// interactive sign-in. Main-actor isolated because the interactive flow must
/// present UI on the main thread; lives in the app layer so `LGTMKit`
/// stays free of the MSAL binary.
@MainActor
final class MSALTokenProvider: TokenProvider {
    private let application: MSALPublicClientApplication
    private let anchorProvider: @MainActor () -> PresentationAnchor?
    private var account: MSALAccount?

    init(anchorProvider: @escaping @MainActor () -> PresentationAnchor?) throws {
        let authority = try MSALAADAuthority(url: URL(string: AppConfiguration.authority)!)
        let config = MSALPublicClientApplicationConfig(
            clientId: AppConfiguration.clientID,
            redirectUri: AppConfiguration.redirectURI,
            authority: authority
        )
        // MSAL's token cache lives in the keychain. On macOS this needs a keychain
        // access group (data-protection keychain) declared in the entitlements,
        // and a stable code signature — i.e. a Development Team must be selected.
        // Without this, the cache write fails (MSAL error -50000) and every call
        // re-prompts for sign-in.
        config.cacheConfig.keychainSharingGroup = AppConfiguration.keychainGroup
        self.application = try MSALPublicClientApplication(configuration: config)
        self.anchorProvider = anchorProvider
        self.account = try? application.allAccounts().first
    }

    /// The signed-in user's Entra object id (`oid`), which doubles as their
    /// Azure DevOps reviewer id in an Entra-backed organization.
    var currentUserObjectId: String? {
        account?.accountClaims?["oid"] as? String
    }

    func token(for scope: String) async throws -> String {
        let scopes = [scope]
        if let account, let token = try? await acquireSilent(scopes: scopes, account: account) {
            return token
        }
        return try await acquireInteractive(scopes: scopes)
    }

    func signOut() throws {
        if let account { try application.remove(account) }
        account = nil
    }

    // MARK: - MSAL bridging

    private func acquireSilent(scopes: [String], account: MSALAccount) async throws -> String {
        let params = MSALSilentTokenParameters(scopes: scopes, account: account)
        let result: MSALResult = try await withCheckedThrowingContinuation { continuation in
            application.acquireTokenSilent(with: params) { result, error in
                if let result { continuation.resume(returning: result) }
                else { continuation.resume(throwing: error ?? ADOError.unauthorized) }
            }
        }
        self.account = result.account
        return result.accessToken
    }

    private func acquireInteractive(scopes: [String]) async throws -> String {
        guard let anchor = anchorProvider() else { throw ADOError.unauthorized }
        let webParams = MSALWebviewParameters(authPresentationViewController: anchor)
        let params = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webParams)
        let result: MSALResult = try await withCheckedThrowingContinuation { continuation in
            application.acquireToken(with: params) { result, error in
                if let result { continuation.resume(returning: result) }
                else { continuation.resume(throwing: error ?? ADOError.unauthorized) }
            }
        }
        self.account = result.account
        return result.accessToken
    }
}
