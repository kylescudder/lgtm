#if os(macOS)
import Foundation
import Combine
import LGTMKit

/// Drives the menu-bar badge: keeps a live count of PRs awaiting the signed-in
/// user's review, refreshing on a timer. It owns a private `PRListViewModel`
/// (used unchanged) and only runs while signed in and bound to an organization
/// (`AppServices.ado != nil`). Refreshes are cheap thanks to the on-disk cache.
@MainActor
final class MenuBarModel: ObservableObject {
    /// PRs awaiting the user's review. Zero when signed out or none pending.
    @Published private(set) var awaitingCount = 0

    /// How often to re-scan. Generous because each refresh hits the on-disk
    /// cache first, so the cost is small and the count stays roughly current.
    private let interval: TimeInterval = 180

    private let session: AppSession
    private var listModel: PRListViewModel?
    private var boundServices: AppServices?
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var countObservation: AnyCancellable?
    private var sessionObservation: AnyCancellable?

    init(session: AppSession) {
        self.session = session
        // React to sign-in / sign-out (and org selection) so the badge starts
        // counting once `services.ado` exists and stops when it goes away.
        sessionObservation = session.objectWillChange.sink { [weak self] _ in
            // objectWillChange fires *before* the value updates; defer the read.
            Task { @MainActor in self?.syncWithSession() }
        }
        syncWithSession()
    }

    deinit {
        timer?.invalidate()
        refreshTask?.cancel()
    }

    /// Reconciles our private list model with the current session state. Builds
    /// and starts the refresh loop when signed in + an org is selected; tears it
    /// down (zeroing the badge) when not.
    private func syncWithSession() {
        guard let services = session.services, services.ado != nil else {
            stop()
            return
        }
        // Already bound to this services instance: nothing to do.
        if boundServices === services { return }
        start(with: services)
    }

    private func start(with services: AppServices) {
        stop()
        boundServices = services
        let model = PRListViewModel(services: services)
        listModel = model
        // Mirror the list model's awaiting count onto our published property.
        countObservation = model.$awaitingMe
            .map(\.count)
            .removeDuplicates()
            .sink { [weak self] count in self?.awaitingCount = count }

        refreshNow()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        countObservation = nil
        listModel = nil
        boundServices = nil
        awaitingCount = 0
    }

    /// Kicks off a single refresh, coalescing with any already in flight.
    private func refreshNow() {
        guard let model = listModel else { return }
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await model.refresh()
            self?.refreshTask = nil
        }
    }
}
#endif
