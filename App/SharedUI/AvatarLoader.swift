import Foundation
import CoreGraphics
import ImageIO
import CryptoKit
import LGTMKit

/// Loads and caches identity avatar images from Azure DevOps.
///
/// ADO avatar URLs require an `Authorization: Bearer <token>` header, so a plain
/// `AsyncImage` request (which sends no auth) fails. This loader fetches the
/// image bytes with the ADO bearer token, decodes them with ImageIO (which is
/// cross-platform, unlike `UIImage`/`NSImage`), and caches the decoded
/// `CGImage` both in memory (`NSCache`) and on disk (the caches directory) so a
/// given avatar is downloaded at most once.
///
/// Configure the shared instance with the app's `TokenProvider` at startup
/// (see `AppServices.init`); requests use `LGTMKit.azureDevOpsDefaultScope`.
final class AvatarLoader: @unchecked Sendable {
    /// The process-wide loader used by `Avatar`.
    static let shared = AvatarLoader()

    private let memory = NSCache<NSString, CGImageBox>()
    private let session: URLSession
    private let diskDirectory: URL
    private let lock = NSLock()
    private var tokenProvider: TokenProvider?

    /// Coalesces concurrent requests for the same URL into one in-flight task.
    private var inFlight: [String: Task<CGImage?, Never>] = [:]

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        diskDirectory = caches.appendingPathComponent("Avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
        session = URLSession(configuration: .default)
    }

    /// Wires the loader to the app's token provider. Call once at startup.
    func configure(tokenProvider: TokenProvider) {
        lock.lock()
        self.tokenProvider = tokenProvider
        lock.unlock()
    }

    /// Returns a decoded avatar image for `url`, fetching and caching it if
    /// needed. Returns `nil` on any failure (bad URL, no token, network error,
    /// 404/redirect, undecodable data) — callers should fall back to initials.
    func image(for url: URL?) async -> CGImage? {
        guard let url else { return nil }
        let key = url.absoluteString

        // 1. Memory cache.
        if let box = memory.object(forKey: key as NSString) { return box.image }

        // 2. Disk cache.
        if let disk = loadFromDisk(key: key) {
            memory.setObject(CGImageBox(disk), forKey: key as NSString)
            return disk
        }

        // 3. Coalesce concurrent fetches, then download.
        let task: Task<CGImage?, Never> = {
            lock.lock()
            defer { lock.unlock() }
            if let existing = inFlight[key] { return existing }
            let new = Task<CGImage?, Never> { [weak self] in
                await self?.download(url: url, key: key) ?? nil
            }
            inFlight[key] = new
            return new
        }()

        let result = await task.value
        lock.lock(); inFlight[key] = nil; lock.unlock()
        return result
    }

    // MARK: - Download

    private func download(url: URL, key: String) async -> CGImage? {
        lock.lock(); let provider = tokenProvider; lock.unlock()
        guard let provider else { return nil }

        do {
            let token = try await provider.token(for: azureDevOpsDefaultScope)
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard let image = Self.decode(data) else { return nil }
            memory.setObject(CGImageBox(image), forKey: key as NSString)
            writeToDisk(data: data, key: key)
            return image
        } catch {
            return nil
        }
    }

    // MARK: - Decoding

    /// Decodes image bytes to a `CGImage` using ImageIO (cross-platform).
    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - Disk cache

    private func diskURL(key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return diskDirectory.appendingPathComponent(name)
    }

    private func loadFromDisk(key: String) -> CGImage? {
        let file = diskURL(key: key)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return Self.decode(data)
    }

    private func writeToDisk(data: Data, key: String) {
        try? data.write(to: diskURL(key: key), options: .atomic)
    }
}

/// Reference wrapper so a `CGImage` (a CF type) can live in `NSCache`.
private final class CGImageBox {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
