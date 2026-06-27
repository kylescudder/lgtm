import SwiftUI
import LGTMKit

// MARK: - Card container

/// A rounded, subtly-filled content card used to group sections natively.
struct Card<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
    }
}

/// A small section title with an optional trailing count chip.
struct SectionLabel: View {
    let title: String
    var systemImage: String? = nil
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).foregroundStyle(.secondary) }
            Text(title).font(.headline)
            if let count {
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.1)))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Avatar

/// A circular avatar that loads the identity image (authenticated + cached via
/// `AvatarLoader`), falling back to coloured initials while loading or on failure.
struct Avatar: View {
    let url: URL?
    let name: String?
    var size: CGFloat = 26

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color.accentColor.opacity(0.25))
                    .overlay(Text(initials).font(.system(size: size * 0.42, weight: .semibold)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: url) {
            image = await AvatarLoader.shared.image(for: url)
        }
    }

    private var initials: String {
        let parts = (name ?? "?").split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }
}

/// An authenticated, cached remote image (e.g. a PR description attachment).
/// Reuses `AvatarLoader` (which sends the ADO bearer token and caches), so the
/// image downloads at most once. Falls back to a labelled placeholder.
struct RemoteImage: View {
    let url: URL?
    var alt: String = ""
    @State private var image: CGImage?
    @State private var failed = false
    @State private var showFull = false

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .contentShape(Rectangle())
                    .onTapGesture { showFull = true }
                    .help("Click to view full size")
            } else if failed {
                Label(alt.isEmpty ? "image" : alt, systemImage: "photo")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: url) {
            guard let url else { failed = true; return }
            if let loaded = await AvatarLoader.shared.image(for: url) { image = loaded }
            else { failed = true }
        }
        .sheet(isPresented: $showFull) {
            if let image { ImagePreview(image: image, alt: alt) }
        }
    }
}

/// A zoomable, dismissible full-size image preview presented as a sheet.
/// Pinch (or trackpad) to zoom, double-tap to reset, Done/Esc to close.
private struct ImagePreview: View {
    let image: CGImage
    var alt: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(alt.isEmpty ? "Image" : alt)
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)

            Divider()

            GeometryReader { geo in
                // Fit the image to the viewport at rest so a wide image can't
                // overflow horizontally; the scroll content only grows past the
                // viewport once zoomed in (scaleEffect alone doesn't resize the
                // layout, so the ScrollView couldn't otherwise pan a zoomed image).
                let zoom = scale * pinch
                let fitWidth = max(geo.size.width - 32, 1)
                let fitHeight = max(geo.size.height - 32, 1)
                ScrollView([.horizontal, .vertical]) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: fitWidth, height: fitHeight)
                        .scaleEffect(zoom)
                        .frame(width: fitWidth * zoom, height: fitHeight * zoom)
                        .padding(16)
                        .gesture(
                            MagnificationGesture()
                                .updating($pinch) { value, state, _ in state = value }
                                .onEnded { value in scale = min(max(scale * value, 1), 6) }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) { scale = scale > 1 ? 1 : 2.5 }
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.92))
            }
        }
        .frame(minWidth: 680, minHeight: 520)
    }
}

// MARK: - Badges

/// A coloured pill for a reviewer's vote.
struct VoteBadge: View {
    let vote: Vote

    var body: some View {
        Label(vote.label, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch vote {
        case .approved, .approvedWithSuggestions: return .green
        case .waitingForAuthor: return .orange
        case .rejected: return .red
        case .noVote: return .secondary
        }
    }
    private var symbol: String {
        switch vote {
        case .approved: return "checkmark.circle.fill"
        case .approvedWithSuggestions: return "checkmark.circle"
        case .waitingForAuthor: return "clock.fill"
        case .rejected: return "xmark.circle.fill"
        case .noVote: return "circle.dashed"
        }
    }
}

/// A generic status pill (PR status, merge state, draft, etc.).
struct StatusPill: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.16)))
        .foregroundStyle(color)
    }
}

// MARK: - Markdown

/// A lightweight Markdown renderer for PR descriptions and comments: handles
/// headings, bullet/numbered lists, task checkboxes, and inline emphasis/links.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                row(for: block)
            }
        }
    }

    @ViewBuilder
    private func row(for block: Block) -> some View {
        switch block {
        case .heading(let level, let s):
            inline(s).font(level <= 1 ? .title3.bold() : (level == 2 ? .headline : .subheadline.bold()))
                .padding(.top, 4)
        case .bullet(let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                inline(s)
            }
        case .task(let done, let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .foregroundStyle(done ? Color.green : .secondary)
                inline(s)
            }
        case .paragraph(let s):
            inline(s)
        case .image(let alt, let urlString):
            RemoteImage(url: URL(string: urlString), alt: alt)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                .padding(.vertical, 2)
        case .blank:
            Color.clear.frame(height: 3)
        }
    }

    private func inline(_ s: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(s)
    }

    private enum Block {
        case heading(Int, String), bullet(String), task(Bool, String), paragraph(String), image(String, String), blank
    }

    private var blocks: [Block] {
        text.components(separatedBy: "\n").map { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return .blank }
            if line.hasPrefix("### ") { return .heading(3, String(line.dropFirst(4))) }
            if line.hasPrefix("## ") { return .heading(2, String(line.dropFirst(3))) }
            if line.hasPrefix("# ") { return .heading(1, String(line.dropFirst(2))) }
            if line.hasPrefix("- [ ] ") { return .task(false, String(line.dropFirst(6))) }
            if line.lowercased().hasPrefix("- [x] ") { return .task(true, String(line.dropFirst(6))) }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { return .bullet(String(line.dropFirst(2))) }
            // A line that is just a Markdown image: ![alt](url)
            if line.hasPrefix("!["), let sep = line.range(of: "]("), line.hasSuffix(")") {
                let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<sep.lowerBound])
                let url = String(line[sep.upperBound..<line.index(before: line.endIndex)])
                return .image(alt, url)
            }
            return .paragraph(line)
        }
    }
}

// MARK: - System comment humanizer

extension String {
    /// Rewrites Azure DevOps system-event comment text into human-friendly phrasing.
    ///
    /// Examples:
    /// - "James Barea voted 10"          -> "James Barea approved"
    /// - "James Barea voted -5"          -> "James Barea is waiting for the author"
    /// - "Policy status has been updated" -> "Policy status updated"
    ///
    /// Non-system phrasings pass through unchanged.
    var humanizedSystemComment: String {
        var result = self

        // "voted <signed-int>" -> friendly phrase (keeps the preceding name).
        if let regex = try? NSRegularExpression(pattern: "voted (-?\\d+)") {
            let range = NSRange(result.startIndex..., in: result)
            // Replace from last match to first so earlier ranges stay valid.
            for match in regex.matches(in: result, range: range).reversed() {
                guard let full = Range(match.range, in: result),
                      let captured = Range(match.range(at: 1), in: result),
                      let raw = Int(result[captured]),
                      let phrase = Self.votePhrase(for: raw) else { continue }
                result.replaceSubrange(full, with: phrase)
            }
        }

        result = result.replacingOccurrences(of: "Policy status has been updated",
                                             with: "Policy status updated")
        return result
    }

    /// Maps a raw ADO vote value to the friendly verb phrase used in the discussion.
    private static func votePhrase(for raw: Int) -> String? {
        switch Vote(rawValue: raw) {
        case .approved: return "approved"
        case .approvedWithSuggestions: return "approved with suggestions"
        case .waitingForAuthor: return "is waiting for the author"
        case .rejected: return "rejected"
        case .noVote: return "reset their vote"
        case nil: return nil
        }
    }
}
