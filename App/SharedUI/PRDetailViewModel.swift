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
    /// The signed-in user's current vote on this PR, if they are a reviewer.
    @Published var myVote: Vote?
    /// `path@objectId` signatures of files the user has marked reviewed. Loaded
    /// from / persisted to `ReviewStore`; tied to file content so a mark clears
    /// when a later commit changes that file.
    @Published private(set) var reviewedSignatures: Set<String> = []

    private let services: AppServices
    let project: String
    private var repositoryId: String { pullRequest.repository?.id ?? "" }
    private var prId: Int { pullRequest.pullRequestId }
    /// Stable per-PR key for persisted review state.
    private var reviewKey: String {
        "pr/\(services.currentOrg?.accountName ?? "")/\(project)/\(repositoryId)/\(prId)"
    }
    /// The Azure DevOps identity id for the signed-in user (resolved once).
    private var resolvedUserId: String?

    /// Builds a diff view model for a changed file, resolving the old side to the
    /// PR target branch and the new side to the PR source commit (falling back to
    /// the source branch when no merge commit is available).
    /// Builds the view model for the (separate) commits screen.
    func makeCommitsModel() -> CommitsViewModel {
        CommitsViewModel(services: services, project: project, repositoryId: repositoryId, pullRequestId: prId)
    }

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

    /// Records (and persists) the set of reviewed-file signatures.
    func setReviewed(_ signatures: Set<String>) {
        reviewedSignatures = signatures
        let key = reviewKey
        Task { await services.reviews.set(signatures, for: key) }
    }

    func load() async {
        guard let ado = services.ado else { return }
        isBusy = true; defer { isBusy = false }
        reviewedSignatures = await services.reviews.signatures(for: reviewKey)
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
            await refreshMyVote(ado)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Resolves the signed-in user's ADO identity id and matches it against the
    /// PR reviewers to surface their current vote.
    private func refreshMyVote(_ ado: ADOClient) async {
        guard let me = await resolvedUserId(ado) else { return }
        myVote = pullRequest.reviewers?.first { $0.id == me }?.vote
    }

    /// Azure DevOps filters by its own identity GUID, not the Entra `oid`.
    /// Resolve it via `connectionData`, falling back to the `oid`. Cached after
    /// the first successful resolution.
    private func resolvedUserId(_ ado: ADOClient) async -> String? {
        if let resolvedUserId { return resolvedUserId }
        if let id = try? await ado.connectionData().authenticatedUser?.id {
            resolvedUserId = id
            return id
        }
        resolvedUserId = services.tokenProvider.currentUserObjectId
        return resolvedUserId
    }

    func vote(_ vote: Vote) async {
        guard let ado = services.ado, let me = await resolvedUserId(ado) else { return }
        await run {
            _ = try await ado.vote(project: self.project, repositoryId: self.repositoryId, pullRequestId: self.prId, reviewerId: me, vote: vote)
            self.myVote = vote == .noVote ? nil : vote
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
