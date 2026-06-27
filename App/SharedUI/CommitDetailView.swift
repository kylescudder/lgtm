import SwiftUI
import LGTMKit

/// Loads the files changed by a single commit and diffs each one against the
/// commit's parent.
@MainActor
final class CommitDetailViewModel: ObservableObject {
    @Published var files: [ChangeEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// `path@objectId` signatures of files marked reviewed in this commit. A
    /// commit is immutable, so these are stable; persisted via `ReviewStore`.
    @Published private(set) var reviewedSignatures: Set<String> = []

    let commit: GitCommit
    private let services: AppServices
    private let project: String
    private let repositoryId: String
    /// Resolved from the Get Commit response; the old side of every file diff.
    private var parentId: String?
    /// Stable per-commit key for persisted review state.
    private var reviewKey: String {
        "commit/\(services.currentOrg?.accountName ?? "")/\(repositoryId)/\(commit.commitId)"
    }

    init(commit: GitCommit, services: AppServices, project: String, repositoryId: String) {
        self.commit = commit
        self.services = services
        self.project = project
        self.repositoryId = repositoryId
    }

    /// Records (and persists) the set of reviewed-file signatures.
    func setReviewed(_ signatures: Set<String>) {
        reviewedSignatures = signatures
        let key = reviewKey
        Task { await services.reviews.set(signatures, for: key) }
    }

    func load() async {
        guard let ado = services.ado, !repositoryId.isEmpty else {
            errorMessage = "This commit is missing repository information."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        reviewedSignatures = await services.reviews.signatures(for: reviewKey)
        do {
            let full = try await ado.commit(project: project, repositoryId: repositoryId, commitId: commit.commitId)
            parentId = full.parentId
            // Keep files only — commit changes can include folder ("tree") entries.
            files = (full.changes ?? []).filter { change in
                let item = change.item
                return item?.isFolder != true
                    && item?.gitObjectType != "tree"
                    && (item?.path?.isEmpty == false)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Diffs a file between this commit's parent (old) and this commit (new).
    /// A root commit (no parent) yields a `nil` old side, which `DiffViewModel`
    /// renders as an all-added file.
    func makeDiffModel(for change: ChangeEntry) -> DiffViewModel {
        DiffViewModel(
            services: services,
            project: project,
            repositoryId: repositoryId,
            path: change.item?.path ?? "",
            changeType: change.changeType,
            oldVersion: parentId,
            oldVersionType: .commit,
            newVersion: commit.commitId,
            newVersionType: .commit
        )
    }
}

/// A commit's changed files listed down the left; selecting one shows its diff
/// on the right. Uses the shared `FileDiffBrowser`, with the commit summary as
/// the sidebar header.
struct CommitDetailView: View {
    @StateObject private var model: CommitDetailViewModel

    init(model: CommitDetailViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        FileDiffBrowser(
            files: model.files,
            isLoading: model.isLoading,
            makeDiffModel: { model.makeDiffModel(for: $0) },
            reviewedSignatures: Binding(get: { model.reviewedSignatures }, set: { model.setReviewed($0) })
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.commit.summary.isEmpty ? "(no message)" : model.commit.summary)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.commit.shortId)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            Divider()
        }
        .navigationTitle(model.commit.shortId)
        .task { await model.load() }
        .alert("Something went wrong", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}
