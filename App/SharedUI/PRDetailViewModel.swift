import Foundation
import LGTMKit

/// Backs the PR detail screen: loads threads and changed files, and performs the
/// approval actions with optimistic UI.
@MainActor
final class PRDetailViewModel: ObservableObject {
    @Published var pullRequest: PullRequest
    @Published var threads: [CommentThread] = []
    @Published var changedFiles: [ChangeEntry] = []
    @Published var isBusy = false
    @Published var errorMessage: String?

    private let services: AppServices
    let project: String
    private var repositoryId: String { pullRequest.repository?.id ?? "" }
    private var prId: Int { pullRequest.pullRequestId }

    /// Builds a diff view model for a changed file, resolving the old side to the
    /// PR target branch and the new side to the PR source commit (falling back to
    /// the source branch when no merge commit is available).
    func makeDiffModel(for change: ChangeEntry) -> DiffViewModel {
        let oldVersion = pullRequest.targetBranch
        let oldType: GitVersionType = .branch

        let newVersion = pullRequest.lastMergeSourceCommit?.commitId ?? pullRequest.sourceBranch
        let newType: GitVersionType = pullRequest.lastMergeSourceCommit?.commitId != nil ? .commit : .branch

        return DiffViewModel(
            services: services,
            project: project,
            repositoryId: repositoryId,
            path: change.item?.path ?? "",
            changeType: change.changeType,
            oldVersion: oldVersion,
            oldVersionType: oldType,
            newVersion: newVersion,
            newVersionType: newType
        )
    }

    init(pullRequest: PullRequest, project: String, services: AppServices) {
        self.pullRequest = pullRequest
        self.project = project
        self.services = services
    }

    func load() async {
        guard let ado = services.ado else { return }
        isBusy = true; defer { isBusy = false }
        do {
            // The list response carries an abbreviated description; fetch the full
            // PR by id so the description, reviewers and status are complete.
            async let fullTask = ado.pullRequest(project: project, repositoryId: repositoryId, pullRequestId: prId)
            async let threadsTask = ado.threads(project: project, repositoryId: repositoryId, pullRequestId: prId)
            let iterations = try await ado.iterations(project: project, repositoryId: repositoryId, pullRequestId: prId)
            if let latest = iterations.last {
                let changes = try await ado.changes(project: project, repositoryId: repositoryId, pullRequestId: prId, iterationId: latest.id)
                changedFiles = changes.changeEntries ?? []
            }
            if let full = try? await fullTask { pullRequest = full }
            threads = try await threadsTask
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func vote(_ vote: Vote) async {
        guard let ado = services.ado, let me = services.tokenProvider.currentUserObjectId else { return }
        await run {
            _ = try await ado.vote(project: self.project, repositoryId: self.repositoryId, pullRequestId: self.prId, reviewerId: me, vote: vote)
        }
    }

    func comment(_ text: String) async {
        guard let ado = services.ado else { return }
        await run {
            _ = try await ado.addComment(project: self.project, repositoryId: self.repositoryId, pullRequestId: self.prId, content: text)
            await self.load()
        }
    }

    func abandon() async {
        guard let ado = services.ado else { return }
        await run {
            self.pullRequest = try await ado.abandon(project: self.project, repositoryId: self.repositoryId, pullRequestId: self.prId)
        }
    }

    private func run(_ action: () async throws -> Void) async {
        isBusy = true; errorMessage = nil; defer { isBusy = false }
        do { try await action() }
        catch { errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
}
