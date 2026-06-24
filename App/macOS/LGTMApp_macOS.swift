#if os(macOS)
import SwiftUI
import AppKit
import LGTMKit

/// macOS entry point: a menu-bar item plus a full window, both hosting the
/// shared UI behind a sign-in gate.
@main
struct LGTMMacApp: App {
    @StateObject private var session = AppSession {
        let provider = try MSALTokenProvider(anchorProvider: {
            (NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first)?.contentViewController
        })
        return AppServices(tokenProvider: provider)
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack { RootView(session: session) }
                .frame(minWidth: 720, minHeight: 480)
        }

        MenuBarExtra("lgtm", systemImage: "checkmark.seal") {
            NavigationStack { RootView(session: session) }
                .frame(width: 420, height: 520)
        }
        .menuBarExtraStyle(.window)
    }
}
#endif
