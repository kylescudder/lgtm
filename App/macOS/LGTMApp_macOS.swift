#if os(macOS)
import SwiftUI
import AppKit
import LGTMKit

/// macOS entry point: a menu-bar item plus a full window, both hosting the
/// shared UI behind a sign-in gate.
@main
struct LGTMMacApp: App {
    @StateObject private var session: AppSession
    @StateObject private var menuBar: MenuBarModel

    init() {
        let session = AppSession {
            let provider = try MSALTokenProvider(anchorProvider: {
                (NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first)?.contentViewController
            })
            return AppServices(tokenProvider: provider)
        }
        _session = StateObject(wrappedValue: session)
        _menuBar = StateObject(wrappedValue: MenuBarModel(session: session))
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack { RootView(session: session) }
                .frame(minWidth: 720, minHeight: 480)
        }

        MenuBarExtra {
            NavigationStack { RootView(session: session) }
                .frame(width: 420, height: 520)
        } label: {
            // Live badge: a filled seal with the awaiting-review count when any
            // are pending, an empty seal otherwise.
            if menuBar.awaitingCount > 0 {
                Image(systemName: "checkmark.seal.fill")
                Text("\(menuBar.awaitingCount)")
            } else {
                Image(systemName: "checkmark.seal")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
#endif
