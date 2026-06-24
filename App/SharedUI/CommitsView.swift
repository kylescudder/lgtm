import SwiftUI
import LGTMKit

/// Loads the commits for a pull request.
@MainActor
final class CommitsViewModel: ObservableObject {
    @Published var commits: [GitCommit] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let services: AppServices
    private let project: String
    private let repositoryId: String
    private let pullRequestId: Int

    init(services: AppServices, project: String, repositoryId: String, pullRequestId: Int) {
        self.services = services
        self.project = project
        self.repositoryId = repositoryId
        self.pullRequestId = pullRequestId
    }

    func load() async {
        guard let ado = services.ado else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            commits = try await ado.pullRequestCommits(
                project: project, repositoryId: repositoryId, pullRequestId: pullRequestId
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// A dedicated screen listing a pull request's commits (pushed via navigation,
/// kept out of the main detail scroll).
struct CommitsView: View {
    @StateObject private var model: CommitsViewModel

    init(model: CommitsViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if model.commits.isEmpty && !model.isLoading {
                    Text("No commits.").foregroundStyle(.secondary)
                }
                ForEach(model.commits) { commit in
                    row(commit)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .navigationTitle("Commits")
        .overlay { if model.isLoading { ProgressView() } }
        .task { await model.load() }
        .alert("Something went wrong", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private func row(_ commit: GitCommit) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "smallcircle.filled.circle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(commit.summary.isEmpty ? "(no message)" : commit.summary)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text(commit.shortId)
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                        if let name = commit.author?.name {
                            Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if let date = commit.author?.date {
                            Text(date.formatted(.relative(presentation: .numeric)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
