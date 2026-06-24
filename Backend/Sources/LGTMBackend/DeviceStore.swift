import Foundation

/// Maps an Entra user object id (`oid`) to that user's registered APNs device
/// tokens. The reference implementation is in-memory; swap for Postgres/Fluent
/// for production (the protocol keeps the routes unchanged).
protocol DeviceStore: Sendable {
    func register(oid: String, apnsToken: String, platform: String) async
    func tokens(for oid: String) async -> [String]
}

actor InMemoryDeviceStore: DeviceStore {
    private var tokensByUser: [String: Set<String>] = [:]

    func register(oid: String, apnsToken: String, platform: String) async {
        tokensByUser[oid, default: []].insert(apnsToken)
    }

    func tokens(for oid: String) async -> [String] {
        Array(tokensByUser[oid] ?? [])
    }
}
