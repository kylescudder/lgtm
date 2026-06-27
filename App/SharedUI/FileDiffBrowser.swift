import SwiftUI
import LGTMKit

// MARK: - File-tree model

/// A node in the changed-file tree: a folder (with children) or a leaf file.
private enum DiffFileNode: Identifiable {
    case folder(path: String, name: String, children: [DiffFileNode])
    case file(change: ChangeEntry, path: String, name: String)

    var id: String {
        switch self {
        case .folder(let path, _, _): return "D:\(path)"
        case .file(_, let path, _): return "F:\(path)"
        }
    }
}

private enum FileTree {
    /// Builds a folder/file tree from a flat list of changes by splitting each
    /// `item.path` into directory components — like the Azure DevOps file tree.
    /// Single-child folder chains are compacted (`a/b/c`) to match how ADO and
    /// most IDEs present deep paths.
    static func build(_ changes: [ChangeEntry]) -> [DiffFileNode] {
        let entries: [(components: [String], change: ChangeEntry)] = changes.compactMap { change in
            guard let path = change.item?.path, !path.isEmpty else { return nil }
            let comps = path.split(separator: "/").map(String.init)
            guard !comps.isEmpty else { return nil }
            return (comps, change)
        }
        return build(entries, prefix: "")
    }

    private static func build(_ entries: [(components: [String], change: ChangeEntry)], prefix: String) -> [DiffFileNode] {
        var folderOrder: [String] = []
        var folderGroups: [String: [(components: [String], change: ChangeEntry)]] = [:]
        var files: [DiffFileNode] = []

        for entry in entries {
            if entry.components.count == 1 {
                let name = entry.components[0]
                let path = entry.change.item?.path ?? (prefix + "/" + name)
                files.append(.file(change: entry.change, path: path, name: name))
            } else {
                let head = entry.components[0]
                if folderGroups[head] == nil { folderGroups[head] = []; folderOrder.append(head) }
                folderGroups[head]!.append((Array(entry.components.dropFirst()), entry.change))
            }
        }

        // Folders first (Finder/ADO style), then files, preserving discovery order.
        var nodes: [DiffFileNode] = []
        for name in folderOrder {
            let folderPath = prefix + "/" + name
            var children = build(folderGroups[name]!, prefix: folderPath)
            var displayName = name
            var nodePath = folderPath
            // Compact `a/ → b/ → …` chains into a single `a/b` row.
            while children.count == 1, case .folder(let cPath, let cName, let cChildren) = children[0] {
                displayName += "/" + cName
                nodePath = cPath
                children = cChildren
            }
            nodes.append(.folder(path: nodePath, name: displayName, children: children))
        }
        nodes.append(contentsOf: files)
        return nodes
    }

    /// A signature identifying *which version* of a file was reviewed: its path
    /// plus the blob object id. When a commit changes the file, the object id
    /// changes, so the signature no longer matches and the mark clears.
    /// (Used instead of bare paths so review marks invalidate on content change.)
    static func signature(_ change: ChangeEntry) -> String {
        "\(change.item?.path ?? "")@\(change.item?.objectId ?? "")"
    }

    /// The review signatures of every file beneath a node (or the node itself).
    static func fileSignatures(_ node: DiffFileNode) -> [String] {
        switch node {
        case .file(let change, _, _): return [signature(change)]
        case .folder(_, _, let children): return children.flatMap(fileSignatures)
        }
    }
}

// MARK: - File presentation helpers (shared by the tree rows)

private func diffFileName(_ path: String?) -> String {
    guard let path, !path.isEmpty else { return "Diff" }
    return (path as NSString).lastPathComponent
}
private func diffFileIcon(_ type: String?) -> String {
    switch type?.lowercased() {
    case let t? where t.contains("add"): return "plus.circle.fill"
    case let t? where t.contains("delete"): return "minus.circle.fill"
    case let t? where t.contains("rename"): return "arrow.left.arrow.right.circle.fill"
    default: return "pencil.circle.fill"
    }
}
private func diffFileColor(_ type: String?) -> Color {
    switch type?.lowercased() {
    case let t? where t.contains("add"): return .green
    case let t? where t.contains("delete"): return .red
    default: return .orange
    }
}

// MARK: - Browser

/// A reusable master-detail file browser: changed files in a directory tree down
/// the left, the selected file's diff on the right. Shared by the commit detail
/// screen and the pull request "Changed files" tab so both look and behave
/// identically. Files (and whole folders) can be ticked off as reviewed; the
/// `reviewedPaths` binding is owned by the caller so the marks survive tab switches.
///
/// `makeDiffModel` builds the diff for a tapped file — the caller decides the two
/// sides (PR target↔source, or a commit↔its parent). `sidebarHeader` renders above
/// the file tree (e.g. a commit summary, or a "Changed files" label).
struct FileDiffBrowser<SidebarHeader: View>: View {
    let files: [ChangeEntry]
    var isLoading: Bool
    let makeDiffModel: (ChangeEntry) -> DiffViewModel
    @Binding var reviewedSignatures: Set<String>
    @ViewBuilder var sidebarHeader: () -> SidebarHeader

    @State private var selectedPath: String?
    @State private var collapsedFolders: Set<String> = []

    private var tree: [DiffFileNode] { FileTree.build(files) }
    private var reviewedCount: Int { files.filter { reviewedSignatures.contains(FileTree.signature($0)) }.count }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 300)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear(perform: selectFirstIfNeeded)
        .onChange(of: files) { _ in selectFirstIfNeeded() }
    }

    /// Select the first file once the list loads, and recover if the current
    /// selection vanishes (e.g. when the file set changes).
    private func selectFirstIfNeeded() {
        if selectedPath == nil || !files.contains(where: { $0.item?.path == selectedPath }) {
            selectedPath = files.first?.item?.path
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader()

            if !files.isEmpty {
                HStack(spacing: 8) {
                    Text("\(reviewedCount) of \(files.count) reviewed")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if reviewedCount > 0 {
                        Button("Reset") { reviewedSignatures.removeAll() }
                            .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                Divider()
            }

            if files.isEmpty && !isLoading {
                Text("No files changed.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        DiffFileTree(
                            nodes: tree,
                            depth: 0,
                            selectedPath: $selectedPath,
                            collapsed: $collapsedFolders,
                            reviewed: $reviewedSignatures
                        )
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
    }

    // MARK: Diff detail

    @ViewBuilder
    private var detail: some View {
        if let path = selectedPath,
           let change = files.first(where: { $0.item?.path == path }) {
            // `.id(path)` gives each file a fresh DiffViewModel so its `.task`
            // reloads when the selection changes.
            DiffView(model: makeDiffModel(change), title: diffFileName(path))
                .id(path)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "sidebar.left")
                    .font(.largeTitle).foregroundStyle(.secondary)
                Text("Select a file to view its changes.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Recursive tree rows

private struct DiffFileTree: View {
    let nodes: [DiffFileNode]
    let depth: Int
    @Binding var selectedPath: String?
    @Binding var collapsed: Set<String>
    @Binding var reviewed: Set<String>

    var body: some View {
        ForEach(nodes) { node in
            switch node {
            case .folder(let path, let name, let children):
                folderRow(path: path, name: name, children: children)
                if !collapsed.contains(path) {
                    DiffFileTree(
                        nodes: children,
                        depth: depth + 1,
                        selectedPath: $selectedPath,
                        collapsed: $collapsed,
                        reviewed: $reviewed
                    )
                }
            case .file(let change, let path, let name):
                fileRow(change: change, path: path, name: name)
            }
        }
    }

    private func folderRow(path: String, name: String, children: [DiffFileNode]) -> some View {
        let childSignatures = children.flatMap(FileTree.fileSignatures)
        let allReviewed = !childSignatures.isEmpty && childSignatures.allSatisfy(reviewed.contains)
        let isCollapsed = collapsed.contains(path)
        return HStack(spacing: 6) {
            Button {
                if isCollapsed { collapsed.remove(path) } else { collapsed.insert(path) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2).foregroundStyle(.secondary).frame(width: 10)
                    Image(systemName: "folder.fill").font(.caption).foregroundStyle(.secondary)
                    Text(name).font(.callout.weight(.medium))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            reviewToggle(isOn: allReviewed) {
                if allReviewed { childSignatures.forEach { reviewed.remove($0) } }
                else { childSignatures.forEach { reviewed.insert($0) } }
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, CGFloat(depth) * 14 + 8)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fileRow(change: ChangeEntry, path: String, name: String) -> some View {
        let signature = FileTree.signature(change)
        let isSelected = path == selectedPath
        let isReviewed = reviewed.contains(signature)
        return HStack(spacing: 6) {
            Button { selectedPath = path } label: {
                HStack(spacing: 6) {
                    Image(systemName: diffFileIcon(change.changeType))
                        .foregroundStyle(diffFileColor(change.changeType)).font(.caption)
                    Text(name)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .strikethrough(isReviewed, color: .secondary)
                        .foregroundStyle(isReviewed ? Color.secondary : Color.primary)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            reviewToggle(isOn: isReviewed) {
                if isReviewed { reviewed.remove(signature) } else { reviewed.insert(signature) }
            }
        }
        .padding(.vertical, 5)
        .padding(.leading, CGFloat(depth) * 14 + 8)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
    }

    private func reviewToggle(isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isOn ? Color.green : Color.secondary)
                .font(.body)
        }
        .buttonStyle(.plain)
        .help(isOn ? "Mark as not reviewed" : "Mark as reviewed")
    }
}
