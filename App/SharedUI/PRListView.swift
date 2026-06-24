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

/// A rich, card-style PR row: author avatar, title, a context caption, and
/// trailing status pills. Mirrors the native look of `PRDetailView`.
private struct PRRow: View {
    let pr: PullRequest

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(url: pr.createdBy?.imageUrl, name: pr.createdBy?.displayName, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(pr.title ?? "Untitled")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !pills.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(pills.enumerated()), id: \.offset) { _, pill in
                            StatusPill(text: pill.text, systemImage: pill.icon, color: pill.color)
                        }
                    }
                    .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    /// "<repo> · <sourceBranch> · opened <relative date>" (skipping unknown parts).
    private var caption: String {
        var parts: [String] = []
        if let repo = pr.repository?.name { parts.append(repo) }
        if let branch = pr.sourceBranch { parts.append(branch) }
        if let date = pr.creationDate {
            parts.append("opened \(date.formatted(.relative(presentation: .numeric)))")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private struct Pill { let text: String; let icon: String?; let color: Color }

    /// Trailing pills: a Draft marker plus a merge/status indicator.
    private var pills: [Pill] {
        var result: [Pill] = []
        if pr.isDraft == true {
            result.append(Pill(text: "Draft", icon: "pencil.line", color: .orange))
        }
        switch pr.mergeStatus {
        case .conflicts:
            result.append(Pill(text: "Conflicts", icon: "exclamationmark.triangle", color: .red))
        case .succeeded:
            result.append(Pill(text: "No conflicts", icon: "checkmark", color: .green))
        case .queued:
            result.append(Pill(text: "Queued", icon: "clock", color: .secondary))
        default:
            switch pr.status {
            case .active: result.append(Pill(text: "Active", icon: "dot.radiowaves.left.and.right", color: .green))
            case .completed: result.append(Pill(text: "Completed", icon: "checkmark.seal", color: .blue))
            case .abandoned: result.append(Pill(text: "Abandoned", icon: "trash", color: .secondary))
            default: break
            }
        }
        return result
    }
}
