import SwiftUI
import LGTMKit

/// A single rendered line of a unified diff.
private struct DiffLine: Identifiable {
    enum Kind: Equatable { case added, removed, unchanged, collapsed }
    let id: Int
    let kind: Kind
    let text: String
}

/// Fetches the two versions of a file (PR target vs. PR source) and computes a
/// line-based unified diff for display.
@MainActor
final class DiffViewModel: ObservableObject {
    fileprivate enum State {
        case loading
        case ready([DiffLine])
        case unsupported       // binary, too large, or otherwise undiffable
        case failed(String)
    }

    @Published fileprivate private(set) var state: State = .loading

    private let services: AppServices
    private let project: String
    private let repositoryId: String
    private let path: String
    private let changeType: String?
    private let oldVersion: String?
    private let oldVersionType: GitVersionType
    private let newVersion: String?
    private let newVersionType: GitVersionType

    /// Files larger than these limits are treated as undiffable.
    private let maxBytes = 200 * 1024
    private let maxLines = 3000

    init(
        services: AppServices,
        project: String,
        repositoryId: String,
        path: String,
        changeType: String?,
        oldVersion: String?,
        oldVersionType: GitVersionType,
        newVersion: String?,
        newVersionType: GitVersionType
    ) {
        self.services = services
        self.project = project
        self.repositoryId = repositoryId
        self.path = path
        self.changeType = changeType
        self.oldVersion = oldVersion
        self.oldVersionType = oldVersionType
        self.newVersion = newVersion
        self.newVersionType = newVersionType
    }

    func load() async {
        guard let ado = services.ado, !repositoryId.isEmpty else {
            state = .failed("This pull request is missing repository information.")
            return
        }
        state = .loading

        let isAdd = changeType?.lowercased().contains("add") == true
        let isDelete = changeType?.lowercased().contains("delete") == true

        // Added files have no old side; deleted files have no new side. Otherwise
        // fetch both; any fetch failure is treated as empty content so the diff
        // still renders gracefully.
        async let oldTask: String = (isAdd || oldVersion == nil)
            ? ""
            : fetch(ado, version: oldVersion!, type: oldVersionType)
        async let newTask: String = (isDelete || newVersion == nil)
            ? ""
            : fetch(ado, version: newVersion!, type: newVersionType)

        let oldText = await oldTask
        let newText = await newTask

        if oldText.utf8.count > maxBytes || newText.utf8.count > maxBytes {
            state = .unsupported
            return
        }
        if looksBinary(oldText) || looksBinary(newText) {
            state = .unsupported
            return
        }

        let oldLines = oldText.isEmpty ? [] : oldText.components(separatedBy: "\n")
        let newLines = newText.isEmpty ? [] : newText.components(separatedBy: "\n")
        if oldLines.count > maxLines || newLines.count > maxLines {
            state = .unsupported
            return
        }

        state = .ready(Self.collapse(Self.unifiedDiff(old: oldLines, new: newLines)))
    }

    /// A best-effort fetch: any error becomes empty content (deleted on one side,
    /// inaccessible, etc.) so the diff still renders.
    private func fetch(_ ado: ADOClient, version: String, type: GitVersionType) async -> String {
        do {
            return try await ado.itemContent(
                project: project,
                repositoryId: repositoryId,
                path: path,
                version: version,
                versionType: type
            )
        } catch {
            return ""
        }
    }

    private func looksBinary(_ text: String) -> Bool {
        // A NUL byte is a strong binary signal.
        text.unicodeScalars.prefix(8000).contains("\u{0}")
    }

    // MARK: - Diff algorithm

    /// Computes a simple line-based unified diff via an LCS over the two line
    /// arrays. Lines present only in `new` are added, only in `old` are removed,
    /// and shared lines are unchanged.
    fileprivate static func unifiedDiff(old: [String], new: [String]) -> [DiffLine] {
        let n = old.count, m = new.count

        // LCS length table.
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    if old[i] == new[j] {
                        lcs[i][j] = lcs[i + 1][j + 1] + 1
                    } else {
                        lcs[i][j] = max(lcs[i + 1][j], lcs[i][j + 1])
                    }
                }
            }
        }

        var lines: [DiffLine] = []
        var id = 0
        func append(_ kind: DiffLine.Kind, _ text: String) {
            lines.append(DiffLine(id: id, kind: kind, text: text)); id += 1
        }

        var i = 0, j = 0
        while i < n && j < m {
            if old[i] == new[j] {
                append(.unchanged, old[i]); i += 1; j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                append(.removed, old[i]); i += 1
            } else {
                append(.added, new[j]); j += 1
            }
        }
        while i < n { append(.removed, old[i]); i += 1 }
        while j < m { append(.added, new[j]); j += 1 }
        return lines
    }

    /// Collapses runs of unchanged lines that are far from any change into a
    /// single "N unchanged lines" marker, keeping `context` lines of surrounding
    /// context — so a one-line change in a huge file (e.g. a lockfile) doesn't
    /// render the entire file. Returns `[]` when there are no changes at all.
    fileprivate static func collapse(_ lines: [DiffLine], context: Int = 3) -> [DiffLine] {
        let changed = lines.indices.filter { lines[$0].kind != .unchanged }
        guard !changed.isEmpty else { return [] }

        // Mark every line within `context` of a change as one to keep.
        var keep = [Bool](repeating: false, count: lines.count)
        for i in changed {
            for j in max(0, i - context)...min(lines.count - 1, i + context) { keep[j] = true }
        }

        var result: [DiffLine] = []
        var id = 0
        var i = 0
        while i < lines.count {
            if keep[i] {
                result.append(DiffLine(id: id, kind: lines[i].kind, text: lines[i].text)); id += 1
                i += 1
            } else {
                var n = 0
                while i < lines.count && !keep[i] { n += 1; i += 1 }
                result.append(DiffLine(id: id, kind: .collapsed, text: "\(n) unchanged line\(n == 1 ? "" : "s")")); id += 1
            }
        }
        return result
    }
}

/// A monospaced unified diff for one changed file, with a loading and error state.
struct DiffView: View {
    @StateObject private var model: DiffViewModel
    private let title: String

    init(model: DiffViewModel, title: String) {
        _model = StateObject(wrappedValue: model)
        self.title = title
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading diff…").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let lines):
                diffScroll(lines)
            case .unsupported:
                message("doc.questionmark", "This file is binary or too large to diff.")
            case .failed(let reason):
                message("exclamationmark.triangle", reason)
            }
        }
        .navigationTitle(Text(verbatim: title))
        .task { await model.load() }
    }

    private func diffScroll(_ lines: [DiffLine]) -> some View {
        GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    if lines.isEmpty {
                        Text("No differences.").font(.callout).foregroundStyle(.secondary).padding()
                    }
                    ForEach(lines) { line in
                        row(line)
                    }
                }
                .padding(.vertical, 8)
                // Fill at least the viewport, pinned top-left, so a short diff sits
                // at the top rather than floating centred (a two-axis ScrollView
                // centres content smaller than its viewport by default).
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private func row(_ line: DiffLine) -> some View {
        if case .collapsed = line.kind {
            HStack(spacing: 6) {
                Image(systemName: "ellipsis")
                Text(line.text)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04))
        } else {
            HStack(alignment: .top, spacing: 8) {
                Text(prefix(line.kind))
                    .frame(width: 12, alignment: .leading)
                Text(line.text.isEmpty ? " " : line.text)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(color(line.kind))
            .padding(.horizontal, 12)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background(line.kind))
        }
    }

    private func message(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func prefix(_ kind: DiffLine.Kind) -> String {
        switch kind {
        case .added: return "+"
        case .removed: return "-"
        case .unchanged: return " "
        case .collapsed: return ""
        }
    }
    private func color(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return .green
        case .removed: return .red
        case .unchanged: return .secondary
        case .collapsed: return .secondary
        }
    }
    private func background(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return Color.green.opacity(0.10)
        case .removed: return Color.red.opacity(0.10)
        case .unchanged: return .clear
        case .collapsed: return .clear
        }
    }
}
