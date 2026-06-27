import Testing
import Foundation
@testable import LGTMKit

/// All tests here share `StubURLProtocol.responder` (a process-global), so the
/// suite is `.serialized` to prevent parallel tests from clobbering each other.
@Suite(.serialized)
struct NetworkClientTests {

    private func makeClient(
        _ responder: StubResponder,
        maxRetries: Int = 3,
        retryBaseDelay: TimeInterval = 0
    ) -> ADOClient {
        let config = ADOClientConfiguration(
            organization: "myorg",
            maxRetries: maxRetries,
            retryBaseDelay: retryBaseDelay
        )
        return ADOClient(
            configuration: config,
            tokenProvider: StaticTokenProvider("test-token"),
            session: StubURLProtocol.makeSession(responder)
        )
    }

    private func jsonBody(_ captured: CapturedRequest?) throws -> [String: Any] {
        let data = try #require(captured?.body)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func awaitingReviewBuildsRequest() async throws {
        let responder = StubResponder()
        responder.enqueue(StubResponse(json: #"{ "count": 1, "value": [ { "pullRequestId": 42, "title": "Add feature", "status": "active" } ] }"#))
        let client = makeClient(responder)

        let prs = try await client.pullRequestsAwaitingReview(project: "MyProject", reviewerId: "me-guid")

        #expect(prs.count == 1)
        #expect(prs.first?.pullRequestId == 42)

        let req = try #require(responder.last?.request)
        #expect(req.httpMethod == "GET")
        let url = try #require(req.url?.absoluteString)
        #expect(url.contains("/myorg/MyProject/_apis/git/pullrequests"))
        #expect(url.contains("searchCriteria.reviewerId=me-guid"))
        #expect(url.contains("searchCriteria.status=active"))
        #expect(url.contains("api-version=7.1"))
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    }

    @Test func voteSendsPutWithVoteBody() async throws {
        let responder = StubResponder()
        responder.enqueue(StubResponse(json: #"{ "id": "rev-guid", "displayName": "Bob", "vote": 10 }"#))
        let client = makeClient(responder)

        let reviewer = try await client.vote(
            project: "MyProject", repositoryId: "repo-guid",
            pullRequestId: 42, reviewerId: "rev-guid", vote: .approved
        )

        #expect(reviewer.vote == .approved)
        let req = try #require(responder.last?.request)
        #expect(req.httpMethod == "PUT")
        #expect(try #require(req.url?.absoluteString).contains("/pullrequests/42/reviewers/rev-guid"))
        #expect(try jsonBody(responder.last)["vote"] as? Int == 10)
    }

    @Test func addCommentPostsThread() async throws {
        let responder = StubResponder()
        responder.enqueue(StubResponse(json: #"{ "id": 100, "status": "active", "comments": [ { "id": 1, "content": "LGTM", "commentType": "text" } ] }"#))
        let client = makeClient(responder)

        let thread = try await client.addComment(
            project: "MyProject", repositoryId: "repo-guid",
            pullRequestId: 42, content: "LGTM"
        )

        #expect(thread.id == 100)
        let req = try #require(responder.last?.request)
        #expect(req.httpMethod == "POST")
        #expect(try #require(req.url?.absoluteString).contains("/pullrequests/42/threads"))
        let body = try jsonBody(responder.last)
        let comments = try #require(body["comments"] as? [[String: Any]])
        #expect(comments.first?["content"] as? String == "LGTM")
        #expect(comments.first?["commentType"] as? String == "text")
        #expect(body["status"] as? String == "active")
    }

    @Test func abandonPatchesStatus() async throws {
        let responder = StubResponder()
        responder.enqueue(StubResponse(json: #"{ "pullRequestId": 42, "status": "abandoned" }"#))
        let client = makeClient(responder)

        let pr = try await client.abandon(project: "MyProject", repositoryId: "repo-guid", pullRequestId: 42)

        #expect(pr.status == .abandoned)
        let req = try #require(responder.last?.request)
        #expect(req.httpMethod == "PATCH")
        #expect(try jsonBody(responder.last)["status"] as? String == "abandoned")
    }

    @Test func unauthorizedThrows() async throws {
        let responder = StubResponder()
        responder.enqueue(StubResponse(status: 401))
        let client = makeClient(responder)

        await #expect(throws: ADOError.unauthorized) {
            _ = try await client.pullRequestsAwaitingReview(project: "MyProject", reviewerId: "me")
        }
    }

    @Test func retriesOn429ThenSucceeds() async throws {
        let responder = StubResponder()
        responder.enqueue(
            StubResponse(status: 429, headers: ["Retry-After": "0"]),
            StubResponse(json: #"{ "count": 0, "value": [] }"#)
        )
        let client = makeClient(responder, maxRetries: 3, retryBaseDelay: 0)

        let prs = try await client.pullRequestsAwaitingReview(project: "MyProject", reviewerId: "me")

        #expect(prs.isEmpty)
        #expect(responder.requestCount == 2)
    }

    @Test func rateLimitedAfterMaxRetries() async throws {
        let responder = StubResponder()
        responder.enqueue(
            StubResponse(status: 429, headers: ["Retry-After": "0"]),
            StubResponse(status: 429, headers: ["Retry-After": "0"])
        )
        let client = makeClient(responder, maxRetries: 1, retryBaseDelay: 0)

        await #expect(throws: ADOError.rateLimited(retryAfter: 0)) {
            _ = try await client.pullRequestsAwaitingReview(project: "MyProject", reviewerId: "me")
        }
        #expect(responder.requestCount == 2)
    }

    @Test func commitFetchesChangesWithChangeCount() async throws {
        let responder = StubResponder()
        responder.enqueue(StubResponse(json: #"{ "commitId": "feabc1234567890", "comment": "Tweak\nbody", "parents": ["parent000aaa"], "changes": [ { "changeType": "edit", "item": { "path": "/src/App.swift", "gitObjectType": "blob" } } ] }"#))
        let client = makeClient(responder)

        let commit = try await client.commit(project: "MyProject", repositoryId: "repo-guid", commitId: "feabc1234567890")

        #expect(commit.parentId == "parent000aaa")
        #expect(commit.changes?.first?.item?.path == "/src/App.swift")
        let req = try #require(responder.last?.request)
        #expect(req.httpMethod == "GET")
        let url = try #require(req.url?.absoluteString)
        #expect(url.contains("/myorg/MyProject/_apis/git/repositories/repo-guid/commits/feabc1234567890"))
        #expect(url.contains("changeCount="))
    }

    @Test func accountsUseVsspsHost() async throws {
        let responder = StubResponder()
        responder.enqueue(StubResponse(json: #"{ "count": 1, "value": [ { "accountId": "a1", "accountName": "myorg" } ] }"#))
        let client = makeClient(responder)

        let accounts = try await client.accounts(memberId: "member-1")

        #expect(accounts.first?.accountName == "myorg")
        let url = try #require(responder.last?.request.url?.absoluteString)
        #expect(url.contains("app.vssps.visualstudio.com/_apis/accounts"))
        #expect(url.contains("memberId=member-1"))
    }

    @Test func projectsAreOrgScoped() async throws {
        let responder = StubResponder()
        responder.enqueue(StubResponse(json: #"{ "count": 2, "value": [ { "id": "p1", "name": "Alpha" }, { "id": "p2", "name": "Beta" } ] }"#))
        let client = makeClient(responder)

        let projects = try await client.projects()

        #expect(projects.map(\.name) == ["Alpha", "Beta"])
        #expect(try #require(responder.last?.request.url?.absoluteString).contains("/myorg/_apis/projects"))
    }

    // MARK: - PushService

    @Test func registerDevicePostsToBackend() async throws {
        let responder = StubResponder()
        responder.enqueue(StubResponse(status: 200))
        let service = PushService(
            configuration: .init(
                baseURL: URL(string: "https://push.example.com")!,
                backendScope: "api://backend/access_as_user"
            ),
            tokenProvider: StaticTokenProvider("backend-token"),
            session: StubURLProtocol.makeSession(responder)
        )

        try await service.registerDevice(apnsToken: "abc123", platform: .iOS)

        let captured = try #require(responder.last)
        #expect(captured.request.httpMethod == "POST")
        #expect(try #require(captured.request.url?.absoluteString).hasSuffix("/devices"))
        #expect(captured.request.value(forHTTPHeaderField: "Authorization") == "Bearer backend-token")
        let body = try #require(JSONSerialization.jsonObject(with: captured.body) as? [String: Any])
        #expect(body["apnsToken"] as? String == "abc123")
        #expect(body["platform"] as? String == "iOS")
    }

    @Test func registerDeviceThrowsOnServerError() async throws {
        let responder = StubResponder()
        responder.enqueue(StubResponse(status: 500, json: #"{"error":"boom"}"#))
        let service = PushService(
            configuration: .init(baseURL: URL(string: "https://push.example.com")!, backendScope: "scope"),
            tokenProvider: StaticTokenProvider("t"),
            session: StubURLProtocol.makeSession(responder)
        )

        let thrown = await #expect(throws: ADOError.self) {
            try await service.registerDevice(apnsToken: "abc", platform: .macOS)
        }
        guard case .httpError(let status, _) = thrown else {
            Issue.record("Expected httpError, got \(String(describing: thrown))")
            return
        }
        #expect(status == 500)
    }
}
