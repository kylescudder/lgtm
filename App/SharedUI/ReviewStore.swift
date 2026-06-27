import Foundation

/// Disk-persisted record of which files the user has marked "reviewed", per pull
/// request (or commit). Each reviewed file is stored as a `path@objectId`
/// signature, so a mark is tied to the exact file *content* that was reviewed:
/// when a later commit changes that file its `objectId` changes, the signature no
/// longer matches, and the file shows up as unreviewed again — while files left
/// untouched stay reviewed. Mirrors `CacheStore`'s actor + JSON-file approach.
actor ReviewStore {
    private var entries: [String: Set<String>]
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.fileURL = dir.appendingPathComponent("lgtm-reviewed-files.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Set<String>].self, from: data) {
            self.entries = decoded
        } else {
            self.entries = [:]
        }
    }

    /// The reviewed-file signatures recorded for a key (PR or commit).
    func signatures(for key: String) -> Set<String> {
        entries[key] ?? []
    }

    /// Replaces (and persists) the reviewed-file signatures for a key.
    func set(_ signatures: Set<String>, for key: String) {
        if signatures.isEmpty { entries[key] = nil } else { entries[key] = signatures }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
