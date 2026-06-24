import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A typed, async client for the Azure DevOps REST API (v1 scope: pull requests).
///
/// Authentication is delegated to a `TokenProvider`; the client fetches a fresh
/// bearer token before every request so silent refresh is transparent. Throttled
/// (429) and transient (5xx) responses are retried with `Retry-After`-aware
/// exponential backoff.
public struct ADOClient: Sendable {
    public let configuration: ADOClientConfiguration
    private let tokenProvider: any TokenProvider
    private let session: URLSession

    public init(
        configuration: ADOClientConfiguration,
        tokenProvider: any TokenProvider,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.tokenProvider = tokenProvider
        self.session = session
    }

    // MARK: - Account / org discovery (org-agnostic, vssps host)

    /// The signed-in user's Azure DevOps profile. Its `id` is the `memberId`
    /// passed to `accounts(memberId:)`.
    public func profile() async throws -> Profile {
        try await get(path: "/_apis/profile/profiles/me", base: configuration.accountsBaseURL)
    }

    /// The organizations (accounts) the given member can access. The same Entra
    /// token works across all of them — no re-auth is needed to switch org.
    public func accounts(memberId: String) async throws -> [Account] {
        let list: ADOList<Account> = try await get(
            path: "/_apis/accounts",
            query: [URLQueryItem(name: "memberId", value: memberId)],
            base: configuration.accountsBaseURL
        )
        return list.value
    }

    /// The signed-in user's Azure DevOps identity in the configured organization.
    /// Use `authenticatedUser.id` as the `creatorId` / `reviewerId` for PR searches —
    /// it is the org-local identity GUID, not the Entra object id.
    public func connectionData() async throws -> ConnectionData {
        // connectionData is a preview resource; it rejects the plain "7.1" version.
        try await get(path: "/\(configuration.organization)/_apis/connectionData", apiVersion: "7.1-preview")
    }

    /// The team projects within the configured organization.
    public func projects() async throws -> [Project] {
        let list: ADOList<Project> = try await get(
            path: "/\(configuration.organization)/_apis/projects"
        )
        return list.value
    }

    // MARK: - Pull request reads

    /// Active pull requests where `reviewerId` is a reviewer (i.e. awaiting their review).
    public func pullRequestsAwaitingReview(
        project: String,
        reviewerId: String,
        top: Int = 50
    ) async throws -> [PullRequest] {
        try await listPullRequests(project: project, reviewerId: reviewerId, top: top)
    }

    /// Active pull requests created by `creatorId`.
    public func pullRequestsCreated(
        project: String,
        creatorId: String,
        top: Int = 50
    ) async throws -> [PullRequest] {
        try await listPullRequests(project: project, creatorId: creatorId, top: top)
    }

    private func listPullRequests(
        project: String,
        reviewerId: String? = nil,
        creatorId: String? = nil,
        status: PullRequestStatus = .active,
        top: Int
    ) async throws -> [PullRequest] {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "searchCriteria.status", value: status.rawValue),
            URLQueryItem(name: "$top", value: String(top))
        ]
        if let reviewerId { query.append(URLQueryItem(name: "searchCriteria.reviewerId", value: reviewerId)) }
        if let creatorId { query.append(URLQueryItem(name: "searchCriteria.creatorId", value: creatorId)) }

        let list: ADOList<PullRequest> = try await get(
            path: "/\(configuration.organization)/\(project)/_apis/git/pullrequests",
            query: query
        )
        return list.value
    }

    /// Full detail for a single pull request.
    public func pullRequest(
        project: String,
        repositoryId: String,
        pullRequestId: Int
    ) async throws -> PullRequest {
        try await get(path: gitPRPath(project, repositoryId, pullRequestId))
    }

    /// The iterations (pushed updates) of a pull request.
    public func iterations(
        project: String,
        repositoryId: String,
        pullRequestId: Int
    ) async throws -> [Iteration] {
        let list: ADOList<Iteration> = try await get(
            path: gitPRPath(project, repositoryId, pullRequestId) + "/iterations"
        )
        return list.value
    }

    /// The file changes in a specific iteration of a pull request.
    public func changes(
        project: String,
        repositoryId: String,
        pullRequestId: Int,
        iterationId: Int
    ) async throws -> IterationChanges {
        try await get(
            path: gitPRPath(project, repositoryId, pullRequestId) + "/iterations/\(iterationId)/changes"
        )
    }

    /// The comment threads on a pull request.
    public func threads(
        project: String,
        repositoryId: String,
        pullRequestId: Int
    ) async throws -> [CommentThread] {
        let list: ADOList<CommentThread> = try await get(
            path: gitPRPath(project, repositoryId, pullRequestId) + "/threads"
        )
        return list.value
    }

    /// Fetches the text content of a file in a repository at a specific commit or
    /// branch. Returns the decoded `content` string from the Git items API.
    ///
    /// - Parameters:
    ///   - version: A commit id (for `.commit`) or branch name with `refs/heads/`
    ///     already stripped (for `.branch`).
    public func itemContent(
        project: String,
        repositoryId: String,
        path: String,
        version: String,
        versionType: GitVersionType
    ) async throws -> String {
        let item: GitItem = try await get(
            path: "/\(configuration.organization)/\(project)/_apis/git/repositories/\(repositoryId)/items",
            query: [
                URLQueryItem(name: "path", value: path),
                URLQueryItem(name: "includeContent", value: "true"),
                URLQueryItem(name: "$format", value: "json"),
                URLQueryItem(name: "versionDescriptor.version", value: version),
                URLQueryItem(name: "versionDescriptor.versionType", value: versionType.rawValue)
            ]
        )
        return item.content ?? ""
    }

    /// The commits on a pull request, most recent first.
    public func pullRequestCommits(
        project: String,
        repositoryId: String,
        pullRequestId: Int
    ) async throws -> [GitCommit] {
        let list: ADOList<GitCommit> = try await get(
            path: gitPRPath(project, repositoryId, pullRequestId) + "/commits"
        )
        return list.value
    }

    // MARK: - Pull request writes

    /// Casts (or updates) the signed-in user's vote on a pull request.
    @discardableResult
    public func vote(
        project: String,
        repositoryId: String,
        pullRequestId: Int,
        reviewerId: String,
        vote: Vote
    ) async throws -> Reviewer {
        let body = try JSONCoding.makeEncoder().encode(VoteBody(vote: vote.rawValue))
        return try await send(
            method: .put,
            path: gitPRPath(project, repositoryId, pullRequestId) + "/reviewers/\(reviewerId)",
            body: body
        )
    }

    /// Adds a general (non-file-anchored) comment thread to a pull request.
    @discardableResult
    public func addComment(
        project: String,
        repositoryId: String,
        pullRequestId: Int,
        content: String
    ) async throws -> CommentThread {
        let body = try JSONCoding.makeEncoder().encode(
            NewThreadBody(comments: [.init(content: content)], status: "active")
        )
        return try await send(
            method: .post,
            path: gitPRPath(project, repositoryId, pullRequestId) + "/threads",
            body: body
        )
    }

    /// Abandons a pull request.
    @discardableResult
    public func abandon(
        project: String,
        repositoryId: String,
        pullRequestId: Int
    ) async throws -> PullRequest {
        let body = try JSONCoding.makeEncoder().encode(UpdatePRBody(status: "abandoned"))
        return try await send(
            method: .patch,
            path: gitPRPath(project, repositoryId, pullRequestId),
            body: body
        )
    }

    /// Completes (merges) a pull request.
    @discardableResult
    public func complete(
        project: String,
        repositoryId: String,
        pullRequestId: Int,
        lastMergeSourceCommitId: String,
        options: CompletionOptions = CompletionOptions()
    ) async throws -> PullRequest {
        let body = try JSONCoding.makeEncoder().encode(
            UpdatePRBody(
                status: "completed",
                lastMergeSourceCommit: .init(commitId: lastMergeSourceCommitId),
                completionOptions: options
            )
        )
        return try await send(
            method: .patch,
            path: gitPRPath(project, repositoryId, pullRequestId),
            body: body
        )
    }

    /// Enables auto-complete on a pull request on behalf of `reviewerId`.
    @discardableResult
    public func setAutoComplete(
        project: String,
        repositoryId: String,
        pullRequestId: Int,
        reviewerId: String,
        options: CompletionOptions = CompletionOptions()
    ) async throws -> PullRequest {
        let body = try JSONCoding.makeEncoder().encode(
            UpdatePRBody(completionOptions: options, autoCompleteSetBy: .init(id: reviewerId))
        )
        return try await send(
            method: .patch,
            path: gitPRPath(project, repositoryId, pullRequestId),
            body: body
        )
    }

    // MARK: - Paths

    private func gitPRPath(_ project: String, _ repositoryId: String, _ pullRequestId: Int) -> String {
        "/\(configuration.organization)/\(project)/_apis/git/repositories/\(repositoryId)/pullrequests/\(pullRequestId)"
    }

    // MARK: - Request plumbing

    private func get<T: Decodable>(path: String, query: [URLQueryItem] = [], base: URL? = nil, apiVersion: String? = nil) async throws -> T {
        try await send(method: .get, path: path, query: query, body: nil, base: base, apiVersion: apiVersion)
    }

    private func send<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        base: URL? = nil,
        apiVersion: String? = nil
    ) async throws -> T {
        let data = try await perform { try await makeRequest(method: method, path: path, query: query, body: body, base: base, apiVersion: apiVersion) }
        do {
            return try JSONCoding.makeDecoder().decode(T.self, from: data)
        } catch {
            throw ADOError.decoding(String(describing: error))
        }
    }

    private func makeRequest(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem],
        body: Data?,
        base: URL?,
        apiVersion: String?
    ) async throws -> URLRequest {
        guard var components = URLComponents(url: base ?? configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw ADOError.invalidResponse
        }
        components.path = path
        components.queryItems = query + [URLQueryItem(name: "api-version", value: apiVersion ?? configuration.apiVersion)]
        guard let url = components.url else { throw ADOError.invalidResponse }

        let token = try await tokenProvider.token(for: configuration.adoScope)

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// Performs a request with retry/backoff, re-building it each attempt so the
    /// bearer token is refreshed if needed.
    private func perform(_ makeRequest: () async throws -> URLRequest) async throws -> Data {
        var attempt = 0
        while true {
            let request = try await makeRequest()
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ADOError.invalidResponse }

            switch http.statusCode {
            case 200...299:
                return data
            case 401:
                throw ADOError.unauthorized
            case 429, 500, 502, 503, 504:
                attempt += 1
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                if attempt > configuration.maxRetries {
                    if http.statusCode == 429 { throw ADOError.rateLimited(retryAfter: retryAfter) }
                    throw ADOError.httpError(status: http.statusCode, body: Self.bodyString(data))
                }
                let delay = retryAfter ?? configuration.retryBaseDelay * pow(2, Double(attempt - 1))
                if delay > 0 {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            default:
                throw ADOError.httpError(status: http.statusCode, body: Self.bodyString(data))
            }
        }
    }

    private static func bodyString(_ data: Data) -> String? {
        guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }
}

// MARK: - Request bodies

private struct VoteBody: Encodable {
    let vote: Int
}

/// Options governing how a pull request is completed.
public struct CompletionOptions: Encodable, Sendable {
    public var deleteSourceBranch: Bool?
    public var mergeStrategy: String?
    public var transitionWorkItems: Bool?

    public init(deleteSourceBranch: Bool? = nil, mergeStrategy: String? = nil, transitionWorkItems: Bool? = nil) {
        self.deleteSourceBranch = deleteSourceBranch
        self.mergeStrategy = mergeStrategy
        self.transitionWorkItems = transitionWorkItems
    }
}

private struct IdRefBody: Encodable {
    let id: String
}

private struct CommitRefBody: Encodable {
    let commitId: String
}

private struct UpdatePRBody: Encodable {
    var status: String?
    var lastMergeSourceCommit: CommitRefBody?
    var completionOptions: CompletionOptions?
    var autoCompleteSetBy: IdRefBody?
}

private struct NewThreadBody: Encodable {
    struct NewComment: Encodable {
        let content: String
        let commentType = "text"
    }
    let comments: [NewComment]
    let status: String
}
