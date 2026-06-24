#if os(iOS)
import SwiftUI
import UIKit
import UserNotifications
import LGTMKit

/// iOS entry point. Launches behind a sign-in gate and registers for APNs after
/// sign-in so the user gets "a PR needs your approval" notifications.
@main
struct LGTMiOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = AppSession {
        let provider = try MSALTokenProvider(anchorProvider: {
            UIApplication.shared.topMostViewController()
        })
        let services = AppServices(tokenProvider: provider)
        AppDelegate.services = services
        return services
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack { RootView(session: session) }
                .onChange(of: session.services != nil) { signedIn in
                    if signedIn { Task { await requestPushPermission() } }
                }
        }
    }

    private func requestPushPermission() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var services: AppServices?

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await Self.services?.registerForPush(apnsToken: token, platform: .iOS) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error)")
    }
}

extension UIApplication {
    /// Best-effort top-most view controller for presenting the MSAL web view.
    func topMostViewController() -> UIViewController? {
        let scene = connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
#endif
