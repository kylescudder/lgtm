import Foundation
import LGTMKit

/// Loads the pull requests awaiting the signed-in user's review across every
/// project in the selected organization, plus the user's own open PRs.
@MainActor
final class PRListViewModel: ObservableObject {
    @Published var awaitingMe: [PullRequest] = []
    @Published var mine: [PullRequest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Progress for the per-project scan, surfaced as a determinate spinner.
    @Published var scannedProjects = 0
    @Published var totalProjects = 0

    private let services: AppServices
    /// The Azure DevOps identity id for the current org (resolved once, then cached).
    private var resolvedUserId: String?
    /// Guards against two background refreshes racing to update the cache.
    private var backgroundRefresh: Task<Void, Never>?

    init(services: AppServices) {
        self.services = services
    }

    func refresh() async {
        guard let ado = services.ado, let org = services.currentOrg?.accountName else { return }

        // Warm path: cached projects + user id let us scan immediately, so PRs
        // appear without waiting on projects() (can be 259 projects) or
        // connectionData(). A background task then refreshes both and updates
        // the cache for next launch.
        if let cached = await services.cache.get(org: org) {
            resolvedUserId = cached.userId
            await scan(ado, projects: cached.projects, userId: cached.userId)
            startBackgroundRefresh(ado, org: org, knownProjectIDs: Set(cached.projects.map(\.id)))
            return
        }

        // Cold path: no cache yet. Behave as before — resolve, fetch, then scan
        // with progress — and seed the cache for next time.
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let me = try await resolveUserId(ado)
            print("LGTM ▶ resolved ADO user id = \(me)  (oid = \(services.tokenProvider.currentUserObjectId ?? "nil"))")
            let projects = try await ado.projects()
            print("LGTM ▶ \(projects.count) projects: \(projects.map(\.name))")
            await services.cache.set(org: org, projects: projects, userId: me)
            await scan(ado, projects: projects, userId: me)
        } catch {
            print("LGTM ▶ refresh error: \(error)")
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Fans the per-project PR search out concurrently and publishes the result,
    /// driving the determinate progress counters as projects complete.
    private func scan(_ ado: ADOClient, projects: [Project], userId me: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        totalProjects = projects.count
        scannedProjects = 0
        var awaiting: [PullRequest] = []
        var owned: [PullRequest] = []
        do {
            // PR search is per-project; fan out across all projects concurrently
            // rather than serially, so latency is the slowest project, not the sum.
            try await withThrowingTaskGroup(of: (name: String, awaiting: [PullRequest], mine: [PullRequest]).self) { group in
                for project in projects {
                    let name = project.name
                    group.addTask {
                        async let a = ado.pullRequestsAwaitingReview(project: name, reviewerId: me)
                        async let m = ado.pullRequestsCreated(project: name, creatorId: me)
                        return (name: name, awaiting: try await a, mine: try await m)
                    }
                }
                for try await result in group {
                    scannedProjects += 1
                    if !result.awaiting.isEmpty || !result.mine.isEmpty {
                        print("LGTM ▶ project '\(result.name)': awaiting=\(result.awaiting.count) mine=\(result.mine.count)")
                    }
                    awaiting += result.awaiting
                    owned += result.mine
                }
            }
            print("LGTM ▶ TOTAL awaiting=\(awaiting.count) mine=\(owned.count)")
            awaitingMe = awaiting
            mine = owned
        } catch {
            print("LGTM ▶ scan error: \(error)")
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Re-resolves the user id and project list off the critical path. If the
    /// project set changed since the cached scan, re-scans with the fresh set so
    /// newly-added projects show without waiting for a manual refresh.
    private func startBackgroundRefresh(_ ado: ADOClient, org: String, knownProjectIDs: Set<String>) {
        backgroundRefresh?.cancel()
        backgroundRefresh = Task { [weak self] in
            guard let self else { return }
            do {
                let me = try await self.refreshUserId(ado)
                let projects = try await ado.projects()
                if Task.isCancelled { return }
                await self.services.cache.set(org: org, projects: projects, userId: me)
                if Set(projects.map(\.id)) != knownProjectIDs {
                    print("LGTM ▶ project set changed (\(knownProjectIDs.count) → \(projects.count)); re-scanning")
                    await self.scan(ado, projects: projects, userId: me)
                }
            } catch {
                // Background refresh is best-effort; the cached scan already showed.
                print("LGTM ▶ background refresh failed: \(error)")
            }
        }
    }

    /// Azure DevOps filters PRs by its own identity GUID, not the Entra `oid`.
    /// Resolve it via `connectionData`, falling back to the `oid` if unavailable.
    private func resolveUserId(_ ado: ADOClient) async throws -> String {
        if let resolvedUserId { return resolvedUserId }
        return try await refreshUserId(ado)
    }

    /// Resolves the ADO identity id unconditionally (used by the background
    /// refresh, which must re-check rather than trust the cached value).
    private func refreshUserId(_ ado: ADOClient) async throws -> String {
        do {
            let data = try await ado.connectionData()
            print("LGTM ▶ connectionData authenticatedUser: id=\(data.authenticatedUser?.id ?? "nil") name=\(data.authenticatedUser?.displayName ?? "nil") unique=\(data.authenticatedUser?.uniqueName ?? "nil")")
            if let id = data.authenticatedUser?.id {
                resolvedUserId = id
                return id
            }
        } catch {
            print("LGTM ▶ connectionData failed: \(error)")
        }
        guard let id = services.tokenProvider.currentUserObjectId else { throw ADOError.unauthorized }
        resolvedUserId = id
        return id
    }

    var awaitingCount: Int { awaitingMe.count }
}
