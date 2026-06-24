import Foundation
import LGTMKit

/// Per-organization, disk-persisted cache of the data the PR list needs to
/// render before any network call returns: the org's projects and the resolved
/// Azure DevOps user id. Backed by a single JSON file under `.cachesDirectory`.
///
/// An `actor` so reads/writes are serialized off the main actor; callers `await`
/// the small accessors. The on-disk payload is keyed by `Account.accountName`.
actor CacheStore {
    /// One org's cached scan inputs.
    struct OrgCache: Codable, Sendable {
        var projects: [Project]
        var userId: String
    }

    private var entries: [String: OrgCache]
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.fileURL = dir.appendingPathComponent("lgtm-org-cache.json")
        // Load synchronously at init so the first `get` is already warm.
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: OrgCache].self, from: data) {
            self.entries = decoded
        } else {
            self.entries = [:]
        }
    }

    /// The cached projects + user id for an org, if present.
    func get(org: String) -> OrgCache? {
        entries[org]
    }

    /// Stores (and persists) the projects + user id for an org.
    func set(org: String, projects: [Project], userId: String) {
        entries[org] = OrgCache(projects: projects, userId: userId)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
