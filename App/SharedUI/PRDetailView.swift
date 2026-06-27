import SwiftUI
import LGTMKit

/// A native, card-based pull request detail screen with the approval action bar.
struct PRDetailView: View {
    @StateObject private var model: PRDetailViewModel
    @State private var commentText = ""
    @State private var tab: Tab = .details

    /// The tabs shown beneath the pinned header.
    private enum Tab: Hashable { case details, files, commits }

    init(model: PRDetailViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned: title + status and the vote/comment bar stay visible across tabs.
            pinnedHeader
            actionCard
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            Picker("View", selection: $tab) {
                Text("Details").tag(Tab.details)
                Text("Changed files").tag(Tab.files)
                Text("Commits").tag(Tab.commits)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(Text(verbatim: "PR #\(model.pullRequest.pullRequestId)"))
        .task { await model.load() }
        .overlay { if model.isBusy { busyOverlay } }
        .alert("Something went wrong", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    // MARK: - Tab content

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .details:
            detailsTab
        case .files:
            FileDiffBrowser(
                files: model.changedFiles,
                isLoading: model.isBusy,
                makeDiffModel: { model.makeDiffModel(for: $0) },
                reviewedSignatures: Binding(get: { model.reviewedSignatures }, set: { model.setReviewed($0) })
            ) {
                Text("Changed files")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                Divider()
            }
        case .commits:
            CommitsView(model: model.makeCommitsModel())
        }
    }

    private var detailsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                infoCard
                if let desc = model.pullRequest.description, !desc.isEmpty {
                    Card { SectionLabel(title: "Description", systemImage: "text.alignleft"); MarkdownText(text: desc) }
                }
                reviewersCard
                discussionCard
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
    }

    // MARK: - Header

    /// Compact, always-visible header above the tabs: title + status.
    private var pinnedHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.pullRequest.title ?? "Untitled")
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) { statusPills }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    /// Branch flow + author — shown on the Details tab.
    private var infoCard: some View {
        Card(spacing: 12) {
            HStack(spacing: 6) {
                branchPill(model.pullRequest.sourceBranch ?? "?", icon: "arrow.triangle.branch")
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                branchPill(model.pullRequest.targetBranch ?? "?", icon: nil)
            }

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
                    .keyboardShortcut(.return, modifiers: .command)
                Button { vote(.approvedWithSuggestions) } label: { Label("Suggestions", systemImage: "checkmark.circle") }
                    .voteEmphasis(model.myVote == .approvedWithSuggestions)
                Button { vote(.waitingForAuthor) } label: { Label("Wait", systemImage: "clock") }
                    .voteEmphasis(model.myVote == .waitingForAuthor, tint: .orange)
                    .keyboardShortcut("l", modifiers: .command)
                Button { vote(.rejected) } label: { Label("Reject", systemImage: "xmark.circle") }
                    .voteEmphasis(model.myVote == .rejected, tint: .red)
                    .keyboardShortcut(.delete, modifiers: .command)
                Spacer(minLength: 0)
                Menu {
                    Button("Reset vote") { vote(.noVote) }
                    Divider()
                    Button("Abandon pull request", role: .destructive) { Task { await model.abandon() } }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            .controlSize(.large)

            if let myVote = model.myVote {
                HStack(spacing: 6) {
                    Text("Your vote:").font(.caption).foregroundStyle(.secondary)
                    VoteBadge(vote: myVote)
                }
            }

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

private extension View {
    /// Renders an action button filled (prominent) when it matches the user's
    /// current vote, and bordered otherwise, so the active choice stands out.
    @ViewBuilder func voteEmphasis(_ active: Bool, tint: Color? = nil) -> some View {
        if active {
            self.buttonStyle(.borderedProminent).tint(tint ?? .accentColor)
        } else {
            self.buttonStyle(.bordered).tint(tint ?? .accentColor)
        }
    }
}
