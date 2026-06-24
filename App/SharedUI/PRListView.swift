import SwiftUI
import LGTMKit

/// The main list: PRs awaiting my review, and my own open PRs. Shared by both
/// the macOS window and the iOS app.
struct PRListView: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var model: PRListViewModel

    init(services: AppServices) {
        _model = StateObject(wrappedValue: PRListViewModel(services: services))
    }

    var body: some View {
        List {
            Section("Awaiting my review (\(model.awaitingMe.count))") {
                ForEach(model.awaitingMe) { pr in
                    NavigationLink(value: pr) { PRRow(pr: pr) }
                }
                if model.awaitingMe.isEmpty && !model.isLoading {
                    Text("Nothing waiting on you. 🎉").foregroundStyle(.secondary)
                }
            }
            Section("My pull requests") {
                ForEach(model.mine) { pr in
                    NavigationLink(value: pr) { PRRow(pr: pr) }
                }
            }
        }
        .navigationTitle(services.currentOrg?.accountName ?? "Pull Requests")
        .toolbar {
            ToolbarItem {
                Button { services.clearOrg() } label: {
                    Label("Switch organization", systemImage: "building.2")
                }
            }
        }
        .overlay {
            if model.isLoading {
                VStack(spacing: 12) {
                    if model.totalProjects > 0 {
                        ProgressView(value: Double(model.scannedProjects), total: Double(model.totalProjects))
                            .frame(width: 220)
                        Text("Scanning \(model.scannedProjects) of \(model.totalProjects) projects…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                        Text("Loading pull requests…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .refreshable { await model.refresh() }
        .task { await model.refresh() }
        .navigationDestination(for: PullRequest.self) { pr in
            // Project is needed for repo-scoped calls; carry it from the PR's repository.
            PRDetailView(
                model: PRDetailViewModel(
                    pullRequest: pr,
                    project: pr.repository?.project?.name ?? "",
                    services: services
                )
            )
        }
        .alert("Error", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

private struct PRRow: View {
    let pr: PullRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if pr.isDraft == true {
                    Text("DRAFT").font(.caption2).bold().foregroundStyle(.secondary)
                }
                Text(pr.title ?? "Untitled").lineLimit(1).bold()
            }
            HStack(spacing: 8) {
                Text(pr.repository?.name ?? "—")
                if let by = pr.createdBy?.displayName { Text("· \(by)") }
                if let branch = pr.sourceBranch { Text("· \(branch)") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
