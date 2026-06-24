import Testing
import Foundation
@testable import LGTMKit

struct ModelDecodingTests {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONCoding.makeDecoder().decode(T.self, from: Data(json.utf8))
    }

    @Test func pullRequestDecodesWithReviewersAndDates() throws {
        let json = """
        {
          "pullRequestId": 42,
          "title": "Add feature",
          "status": "active",
          "isDraft": false,
          "mergeStatus": "succeeded",
          "creationDate": "2026-06-20T09:15:00.123Z",
          "sourceRefName": "refs/heads/feature/x",
          "targetRefName": "refs/heads/main",
          "createdBy": { "id": "author-guid", "displayName": "Ada" },
          "repository": {
            "id": "repo-guid", "name": "core",
            "project": { "id": "proj-guid", "name": "MyProject" }
          },
          "reviewers": [
            { "id": "rev-1", "displayName": "Bob", "vote": 10, "isRequired": true },
            { "id": "rev-2", "displayName": "Cleo", "vote": -10 }
          ]
        }
        """
        let pr = try decode(PullRequest.self, json)
        #expect(pr.pullRequestId == 42)
        #expect(pr.status == .active)
        #expect(pr.mergeStatus == .succeeded)
        #expect(pr.isDraft == false)
        #expect(pr.sourceBranch == "feature/x")
        #expect(pr.targetBranch == "main")
        #expect(pr.creationDate != nil)
        #expect(pr.reviewers?.count == 2)
        #expect(pr.reviewers?[0].vote == .approved)
        #expect(pr.reviewers?[1].vote == .rejected)
        #expect(pr.repository?.project?.name == "MyProject")
    }

    @Test func plainAndFractionalDatesBothParse() {
        #expect(JSONCoding.parseDate("2026-06-20T09:15:00Z") != nil)
        #expect(JSONCoding.parseDate("2026-06-20T09:15:00.123Z") != nil)
        #expect(JSONCoding.parseDate("not-a-date") == nil)
    }

    @Test func unknownEnumValuesDecodeDefensively() throws {
        // An unknown vote, merge status, and PR status must not fail the payload.
        let json = """
        { "pullRequestId": 1, "status": "supernova", "mergeStatus": "rejectedByUser",
          "reviewers": [ { "id": "r", "vote": 7 } ] }
        """
        let pr = try decode(PullRequest.self, json)
        #expect(pr.status == .notSet)
        #expect(pr.mergeStatus == .notSet)
        #expect(pr.reviewers?.first?.vote == .noVote)
    }

    @Test func webhookSelectsOnlyBlockingReviewers() throws {
        let json = """
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
        """
        let event = try decode(PullRequestEvent.self, json)
        #expect(PushLogic.reviewerIdsToNotify(for: event) == ["needs-review"])
    }

    @Test func webhookOnNonActivePRNotifiesNobody() throws {
        let json = #"{ "eventType": "git.pullrequest.updated", "resource": { "pullRequestId": 8, "status": "abandoned", "reviewers": [ { "id": "x", "vote": 0 } ] } }"#
        let event = try decode(PullRequestEvent.self, json)
        #expect(PushLogic.reviewerIdsToNotify(for: event).isEmpty)
    }

    @Test func listEnvelopeDecodes() throws {
        let json = """
        { "count": 2, "value": [ { "pullRequestId": 1 }, { "pullRequestId": 2 } ] }
        """
        let list = try decode(ADOList<PullRequest>.self, json)
        #expect(list.count == 2)
        #expect(list.value.map(\.pullRequestId) == [1, 2])
    }
}
