import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A canned HTTP response.
struct StubResponse {
    var status: Int
    var headers: [String: String]
    var body: Data

    init(status: Int = 200, headers: [String: String] = [:], json: String = "{}") {
        self.status = status
        self.headers = headers
        self.body = Data(json.utf8)
    }
}

/// A captured request together with its (stream-decoded) body.
struct CapturedRequest {
    let request: URLRequest
    let body: Data
}

/// Thread-safe state shared between a test and `StubURLProtocol`.
final class StubResponder: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [StubResponse] = []
    private var captured: [CapturedRequest] = []

    func enqueue(_ responses: StubResponse...) {
        lock.lock(); defer { lock.unlock() }
        queue.append(contentsOf: responses)
    }

    /// Records the request and returns the next queued response. Once a single
    /// response remains it is "sticky" (returned for all further calls) so retry
    /// tests can keep hitting the same status.
    func handle(_ request: URLRequest) -> StubResponse {
        lock.lock(); defer { lock.unlock() }
        captured.append(CapturedRequest(request: request, body: Self.bodyData(from: request)))
        if queue.count > 1 { return queue.removeFirst() }
        return queue.first ?? StubResponse(status: 500)
    }

    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return captured.count }
    var last: CapturedRequest? { lock.lock(); defer { lock.unlock() }; return captured.last }

    /// `URLSession` turns `httpBody` into an `httpBodyStream` before the request
    /// reaches a `URLProtocol`, so we drain the stream to recover the bytes.
    static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// A `URLProtocol` that serves responses from the active `StubResponder`.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: StubResponder?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let stub = responder.handle(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// Builds a `URLSession` wired to this protocol and points it at `responder`.
    static func makeSession(_ responder: StubResponder) -> URLSession {
        Self.responder = responder
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}
