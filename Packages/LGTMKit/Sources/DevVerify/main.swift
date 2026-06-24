import Foundation
import LGTMKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Tiny assertion harness

final class Checks: @unchecked Sendable {
    private let lock = NSLock()
    private var failures: [String] = []
    private var passed = 0

    func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
        lock.lock(); defer { lock.unlock() }
        if condition { passed += 1 } else { failures.append(message()) }
    }

    func finish() -> Never {
        lock.lock(); defer { lock.unlock() }
        if failures.isEmpty {
            print("✓ DevVerify: all \(passed) checks passed")
            exit(0)
        }
        print("✗ DevVerify: \(failures.count) failure(s), \(passed) passed")
        for f in failures { print("   • \(f)") }
        exit(1)
    }
}

// MARK: - URLProtocol stub (mirrors the test harness)

struct StubResponse {
    var status = 200
    var headers: [String: String] = [:]
    var json = "{}"
}

final class Responder: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [StubResponse] = []
    private(set) var requests: [(URLRequest, Data)] = []

    func enqueue(_ responses: StubResponse...) {
        lock.lock(); defer { lock.unlock() }
        queue.append(contentsOf: responses)
    }
    func handle(_ request: URLRequest) -> StubResponse {
        lock.lock(); defer { lock.unlock() }
        requests.append((request, Self.body(request)))
        if queue.count > 1 { return queue.removeFirst() }
        return queue.first ?? StubResponse(status: 500)
    }
    var last: (URLRequest, Data)? { lock.lock(); defer { lock.unlock() }; return requests.last }
    var count: Int { lock.lock(); defer { lock.unlock() }; return requests.count }

    static func body(_ request: URLRequest) -> Data {
        if let b = request.httpBody { return b }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }
}

final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: Responder?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let stub = Self.responder!.handle(request)
        let resp = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func makeSession(_ responder: Responder) -> URLSession {
    StubProtocol.responder = responder
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    return URLSession(configuration: config)
}

func makeClient(_ responder: Responder, maxRetries: Int = 3) -> ADOClient {
    ADOClient(
        configuration: ADOClientConfiguration(organization: "myorg", maxRetries: maxRetries, retryBaseDelay: 0),
        tokenProvider: StaticTokenProvider("test-token"),
        session: makeSession(responder)
    )
}

func bodyJSON(_ data: Data?) -> [String: Any] {
    guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return obj
}

// MARK: - Checks

let checks = Checks()

// Model decoding (with fractional date + defensive enum fallback).
do {
    let json = #"""
    { "pullRequestId": 42, "status": "active", "mergeStatus": "succeeded",
      "creationDate": "2026-06-20T09:15:00.123Z", "sourceRefName": "refs/heads/feature/x",
      "reviewers": [ { "id": "r1", "vote": 10 }, { "id": "r2", "vote": 99 } ] }
    """#
    let pr = try JSONDecoder.adoDecoderForVerify().decode(PullRequest.self, from: Data(json.utf8))
    checks.expect(pr.pullRequestId == 42, "pr id decodes")
    checks.expect(pr.status == .active, "pr status decodes")
    checks.expect(pr.sourceBranch == "feature/x", "source branch strips refs/heads/")
    checks.expect(pr.creationDate != nil, "fractional ISO date parses")
    checks.expect(pr.reviewers?[0].vote == .approved, "vote 10 -> approved")
    checks.expect(pr.reviewers?[1].vote == .noVote, "unknown vote 99 -> noVote (defensive)")
}

// Awaiting-review request building.
do {
    let responder = Responder()
    responder.enqueue(StubResponse(json: #"{ "count": 1, "value": [ { "pullRequestId": 42, "status": "active" } ] }"#))
    let client = makeClient(responder)
    let prs = try await client.pullRequestsAwaitingReview(project: "MyProject", reviewerId: "me-guid")
    checks.expect(prs.count == 1, "awaiting-review returns 1 PR")
    let url = responder.last?.0.url?.absoluteString ?? ""
    checks.expect(url.contains("/myorg/MyProject/_apis/git/pullrequests"), "correct path")
    checks.expect(url.contains("searchCriteria.reviewerId=me-guid"), "reviewerId query")
    checks.expect(url.contains("api-version=7.1"), "api-version query")
    checks.expect(responder.last?.0.value(forHTTPHeaderField: "Authorization") == "Bearer test-token", "bearer header")
}

// Vote PUT with body.
do {
    let responder = Responder()
    responder.enqueue(StubResponse(json: #"{ "id": "rev-guid", "vote": 10 }"#))
    let client = makeClient(responder)
    let reviewer = try await client.vote(project: "MyProject", repositoryId: "repo", pullRequestId: 42, reviewerId: "rev-guid", vote: .approved)
    checks.expect(reviewer.vote == .approved, "vote response decodes")
    checks.expect(responder.last?.0.httpMethod == "PUT", "vote uses PUT")
    checks.expect((bodyJSON(responder.last?.1)["vote"] as? Int) == 10, "vote body is 10")
}

// 429 then success (retry/backoff).
do {
    let responder = Responder()
    responder.enqueue(
        StubResponse(status: 429, headers: ["Retry-After": "0"]),
        StubResponse(json: #"{ "count": 0, "value": [] }"#)
    )
    let client = makeClient(responder)
    let prs = try await client.pullRequestsAwaitingReview(project: "MyProject", reviewerId: "me")
    checks.expect(prs.isEmpty, "retry recovers to empty list")
    checks.expect(responder.count == 2, "retried exactly once (2 requests)")
}

// 401 -> unauthorized.
do {
    let responder = Responder()
    responder.enqueue(StubResponse(status: 401))
    let client = makeClient(responder)
    do {
        _ = try await client.pullRequestsAwaitingReview(project: "MyProject", reviewerId: "me")
        checks.expect(false, "401 should throw")
    } catch let error as ADOError {
        checks.expect(error == .unauthorized, "401 -> ADOError.unauthorized")
    }
}

// Webhook reviewer-selection (backend domain logic).
do {
    let json = #"""
    { "eventType": "git.pullrequest.updated",
      "resource": {
        "pullRequestId": 7, "status": "active",
        "createdBy": { "id": "author" },
        "reviewers": [
          { "id": "needs-review", "vote": 0 },
          { "id": "already-approved", "vote": 10 },
          { "id": "author", "vote": 0 },
          { "id": "declined", "vote": 0, "hasDeclined": true }
        ]
      } }
    """#
    let event = try JSONDecoder.adoDecoderForVerify().decode(PullRequestEvent.self, from: Data(json.utf8))
    let ids = PushLogic.reviewerIdsToNotify(for: event)
    checks.expect(ids == ["needs-review"], "only the un-voted non-author, non-declined reviewer is notified (got \(ids))")
}

// Abandoned/completed PRs notify nobody.
do {
    let json = #"{ "eventType": "git.pullrequest.updated", "resource": { "pullRequestId": 8, "status": "abandoned", "reviewers": [ { "id": "x", "vote": 0 } ] } }"#
    let event = try JSONDecoder.adoDecoderForVerify().decode(PullRequestEvent.self, from: Data(json.utf8))
    checks.expect(PushLogic.reviewerIdsToNotify(for: event).isEmpty, "non-active PR notifies nobody")
}

// Account discovery hits the org-agnostic vssps host.
do {
    let responder = Responder()
    responder.enqueue(StubResponse(json: #"{ "count": 1, "value": [ { "accountId": "a1", "accountName": "myorg" } ] }"#))
    let client = makeClient(responder)
    let accounts = try await client.accounts(memberId: "member-1")
    checks.expect(accounts.first?.accountName == "myorg", "accounts decode")
    let url = responder.last?.0.url?.absoluteString ?? ""
    checks.expect(url.contains("app.vssps.visualstudio.com/_apis/accounts"), "accounts use vssps host (got \(url))")
    checks.expect(url.contains("memberId=member-1"), "memberId query present")
}

// Projects are org-scoped on dev.azure.com.
do {
    let responder = Responder()
    responder.enqueue(StubResponse(json: #"{ "count": 2, "value": [ { "id": "p1", "name": "Alpha" }, { "id": "p2", "name": "Beta" } ] }"#))
    let client = makeClient(responder)
    let projects = try await client.projects()
    checks.expect(projects.map(\.name) == ["Alpha", "Beta"], "projects decode")
    checks.expect((responder.last?.0.url?.absoluteString ?? "").contains("/myorg/_apis/projects"), "projects org-scoped path")
}

// connectionData resolves the org-local identity id (not the Entra oid).
do {
    let responder = Responder()
    responder.enqueue(StubResponse(json: #"{ "authenticatedUser": { "id": "ado-identity-guid", "providerDisplayName": "Kyle Scudder" } }"#))
    let client = makeClient(responder)
    let data = try await client.connectionData()
    checks.expect(data.authenticatedUser?.id == "ado-identity-guid", "connectionData authenticatedUser.id decodes")
    let cdURL = responder.last?.0.url?.absoluteString ?? ""
    checks.expect(cdURL.contains("/myorg/_apis/connectionData"), "connectionData org-scoped path")
    checks.expect(cdURL.contains("api-version=7.1-preview"), "connectionData uses preview api-version (got \(cdURL))")
}

// Git item content fetch builds the items URL with version descriptor + content flags.
do {
    let responder = Responder()
    responder.enqueue(StubResponse(json: #"{ "content": "line one\nline two\n" }"#))
    let client = makeClient(responder)
    let content = try await client.itemContent(
        project: "MyProject",
        repositoryId: "repo-guid",
        path: "/src/App.swift",
        version: "abc123",
        versionType: .commit
    )
    checks.expect(content == "line one\nline two\n", "itemContent decodes content field")
    let url = responder.last?.0.url?.absoluteString ?? ""
    checks.expect(url.contains("/myorg/MyProject/_apis/git/repositories/repo-guid/items"), "items path (got \(url))")
    checks.expect(url.contains("includeContent=true"), "includeContent flag present")
    checks.expect(url.contains("versionDescriptor.version=abc123"), "version descriptor version present")
    checks.expect(url.contains("versionDescriptor.versionType=commit"), "version descriptor type present")
    checks.expect(url.contains("path=/src/App.swift") || url.contains("path=/src/App.swift".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""), "path query present (got \(url))")
}

checks.finish()

// Local decoder mirroring LGTMKit's internal JSONCoding (which is not public).
extension JSONDecoder {
    static func adoDecoderForVerify() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
            if let date = f1.date(from: s) ?? f2.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: try d.singleValueContainer(), debugDescription: "bad date \(s)")
        }
        return decoder
    }
}
