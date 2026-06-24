import SwiftUI
import LGTMKit

/// A native, card-based pull request detail screen with the approval action bar.
struct PRDetailView: View {
    @StateObject private var model: PRDetailViewModel
    @State private var commentText = ""

    init(model: PRDetailViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                actionCard
                if let desc = model.pullRequest.description, !desc.isEmpty {
                    Card { SectionLabel(title: "Description", systemImage: "text.alignleft"); MarkdownText(text: desc) }
                }
                reviewersCard
                if !model.changedFiles.isEmpty { changedFilesCard }
                discussionCard
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .navigationTitle(Text(verbatim: "PR #\(model.pullRequest.pullRequestId)"))
        .task { await model.load() }
        .overlay { if model.isBusy { busyOverlay } }
        .alert("Something went wrong", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    // MARK: - Header

    private var headerCard: some View {
        Card(spacing: 12) {
            Text(model.pullRequest.title ?? "Untitled")
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                branchPill(model.pullRequest.sourceBranch ?? "?", icon: "arrow.triangle.branch")
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                branchPill(model.pullRequest.targetBranch ?? "?", icon: nil)
            }

            HStack(spacing: 8) { statusPills }

            HStack(spacing: 8) {
                Avatar(url: model.pullRequest.createdBy?.imageUrl, name: model.pullRequest.createdBy?.displayName)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.pullRequest.createdBy?.displayName ?? "Unknown")
                        .font(.subheadline.weight(.medium))
                    if let date = model.pullRequest.creationDate {
                        Text("opened \(date.formatted(.relative(presentation: .numeric)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var statusPills: some View {
        if model.pullRequest.isDraft == true {
            StatusPill(text: "Draft", systemImage: "pencil.line", color: .orange)
        }
        switch model.pullRequest.status {
        case .active: StatusPill(text: "Active", systemImage: "dot.radiowaves.left.and.right", color: .green)
        case .completed: StatusPill(text: "Completed", systemImage: "checkmark.seal", color: .blue)
        case .abandoned: StatusPill(text: "Abandoned", systemImage: "trash", color: .secondary)
        default: EmptyView()
        }
        switch model.pullRequest.mergeStatus {
        case .conflicts: StatusPill(text: "Conflicts", systemImage: "exclamationmark.triangle", color: .red)
        case .succeeded: StatusPill(text: "No conflicts", systemImage: "checkmark", color: .green)
        default: EmptyView()
        }
    }

    private func branchPill(_ name: String, icon: String?) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(name).lineLimit(1).truncationMode(.middle)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    // MARK: - Actions

    private var actionCard: some View {
        Card(spacing: 12) {
            HStack(spacing: 8) {
                Button { vote(.approved) } label: { Label("Approve", systemImage: "checkmark.circle.fill") }
                    .buttonStyle(.borderedProminent).tint(.green)
                Button { vote(.approvedWithSuggestions) } label: { Label("Suggestions", systemImage: "checkmark.circle") }
                    .buttonStyle(.bordered)
                Button { vote(.waitingForAuthor) } label: { Label("Wait", systemImage: "clock") }
                    .buttonStyle(.bordered).tint(.orange)
                Button { vote(.rejected) } label: { Label("Reject", systemImage: "xmark.circle") }
                    .buttonStyle(.bordered).tint(.red)
                Spacer(minLength: 0)
                Menu {
                    Button("Reset vote") { vote(.noVote) }
                    Divider()
                    Button("Abandon pull request", role: .destructive) { Task { await model.abandon() } }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            .controlSize(.large)

            HStack(spacing: 8) {
                TextField("Add a comment…", text: $commentText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                Button {
                    let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    commentText = ""
                    Task { await model.comment(text) }
                } label: { Image(systemName: "paperplane.fill") }
                    .buttonStyle(.borderedProminent)
                    .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func vote(_ vote: Vote) { Task { await model.vote(vote) } }

    // MARK: - Reviewers

    private var reviewersCard: some View {
        Card {
            SectionLabel(title: "Reviewers", systemImage: "person.2", count: model.pullRequest.reviewers?.count ?? 0)
            ForEach(model.pullRequest.reviewers ?? []) { reviewer in
                HStack(spacing: 10) {
                    Avatar(url: reviewer.imageUrl, name: reviewer.displayName)
                    Text(reviewer.displayName ?? reviewer.uniqueName ?? reviewer.id)
                        .font(.subheadline).lineLimit(1)
                    if reviewer.isRequired == true {
                        Text("Required").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    VoteBadge(vote: reviewer.vote)
                }
            }
        }
    }

    // MARK: - Changed files

    private var changedFilesCard: some View {
        Card {
            SectionLabel(title: "Changed files", systemImage: "doc.on.doc", count: model.changedFiles.count)
            ForEach(Array(model.changedFiles.enumerated()), id: \.offset) { _, change in
                NavigationLink {
                    DiffView(
                        model: model.makeDiffModel(for: change),
                        title: fileName(change.item?.path)
                    )
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: fileIcon(change.changeType))
                            .foregroundStyle(fileColor(change.changeType)).font(.caption)
                        Text(change.item?.path ?? "—")
                            .font(.system(.callout, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func fileName(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return "Diff" }
        return (path as NSString).lastPathComponent
    }

    private func fileIcon(_ type: String?) -> String {
        switch type?.lowercased() {
        case let t? where t.contains("add"): return "plus.circle.fill"
        case let t? where t.contains("delete"): return "minus.circle.fill"
        case let t? where t.contains("rename"): return "arrow.left.arrow.right.circle.fill"
        default: return "pencil.circle.fill"
        }
    }
    private func fileColor(_ type: String?) -> Color {
        switch type?.lowercased() {
        case let t? where t.contains("add"): return .green
        case let t? where t.contains("delete"): return .red
        default: return .orange
        }
    }

    // MARK: - Discussion

    private var discussionCard: some View {
        Card {
            SectionLabel(title: "Discussion", systemImage: "bubble.left.and.bubble.right")
            if model.threads.allSatisfy({ ($0.comments ?? []).isEmpty }) {
                Text("No comments yet.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(model.threads.enumerated()), id: \.offset) { index, thread in
                ForEach(thread.comments ?? []) { comment in
                    commentRow(comment)
                }
                if index < model.threads.count - 1 { Divider().opacity(0.5) }
            }
        }
    }

    @ViewBuilder private func commentRow(_ comment: Comment) -> some View {
        if (comment.commentType ?? "text") == "system" {
            Text((comment.content ?? "").humanizedSystemComment)
                .font(.caption).foregroundStyle(.secondary)
                .padding(.leading, 36)
        } else {
            HStack(alignment: .top, spacing: 10) {
                Avatar(url: comment.author?.imageUrl, name: comment.author?.displayName)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(comment.author?.displayName ?? "—").font(.subheadline.weight(.medium))
                        if let date = comment.publishedDate {
                            Text(date.formatted(.relative(presentation: .numeric)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    MarkdownText(text: comment.content ?? "")
                }
            }
        }
    }

    private var busyOverlay: some View {
        ProgressView()
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
