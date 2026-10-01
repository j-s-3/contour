import Foundation
import Testing

@testable import Contour

struct WatchedPullRequestsParseTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func candidate(
        _ number: Int, author: String = "mwright", isBot: Bool = false, createdAt: TimeInterval? = nil
    ) -> WatchedPullRequests.Candidate {
        WatchedPullRequests.Candidate(
            pullRequest: WatchedPullRequest(
                url: "https://github.com/acme/api/pull/\(number)", number: number, title: "t\(number)",
                author: author, isDraft: false,
                createdAt: Date(timeIntervalSince1970: createdAt ?? TimeInterval(number))),
            isBot: isBot)
    }

    private let moment = Date(timeIntervalSince1970: 1_000_000)

    @Test func theGHFixtureParsesEveryRowAndFlagsItsBots() throws {
        let candidates = try #require(WatchedPullRequests.parseGH(try fixture("gh-pr-list")))
        #expect(!candidates.isEmpty)
        #expect(candidates.count <= WatchedPullRequests.fetchLimit)
        #expect(candidates.contains { $0.isBot })
        #expect(candidates.allSatisfy { $0.pullRequest.url.hasPrefix("https://github.com/") })
        #expect(candidates.allSatisfy { $0.pullRequest.createdAt != nil })
    }

    @Test func theRESTFixtureParsesEveryRowAndFlagsItsBots() throws {
        let candidates = try #require(WatchedPullRequests.parseREST(try fixture("rest-pulls")))
        #expect(!candidates.isEmpty)
        #expect(candidates.count <= WatchedPullRequests.fetchLimit)
        #expect(candidates.contains { $0.isBot })
        #expect(candidates.allSatisfy { $0.pullRequest.url.hasPrefix("https://github.com/") })
        #expect(candidates.allSatisfy { $0.pullRequest.createdAt != nil })
    }

    @Test func aListBuiltFromEitherFixtureHasNoBotsAndIsNewestFirst() throws {
        let sets = [
            try #require(WatchedPullRequests.parseGH(try fixture("gh-pr-list"))),
            try #require(WatchedPullRequests.parseREST(try fixture("rest-pulls"))),
        ]
        for candidates in sets {
            let list = WatchedPullRequests.list(from: candidates, fetchedAt: moment)
            let bots = Set(candidates.filter(\.isBot).map(\.pullRequest.url))
            #expect(list.pullRequests.count <= WatchedPullRequests.listLimit)
            #expect(list.pullRequests.allSatisfy { !bots.contains($0.url) })
            let dates = list.pullRequests.compactMap(\.createdAt)
            #expect(dates == dates.sorted(by: >))
            #expect(list.fetchedAt == moment)
        }
    }

    @Test func ghRowsCarryAuthorDraftAndDate() throws {
        let json = """
            [{"number":7,"title":"Seven","url":"https://github.com/acme/api/pull/7",
              "author":{"login":"mwright","is_bot":false},"isDraft":true,"createdAt":"2026-09-25T10:00:00Z"}]
            """
        let candidates = try #require(WatchedPullRequests.parseGH(Data(json.utf8)))
        #expect(
            candidates == [
                WatchedPullRequests.Candidate(
                    pullRequest: WatchedPullRequest(
                        url: "https://github.com/acme/api/pull/7", number: 7, title: "Seven", author: "mwright",
                        isDraft: true, createdAt: ISO8601DateFormatter().date(from: "2026-09-25T10:00:00Z")),
                    isBot: false)
            ])
    }

    @Test func restRowsCarryAuthorDraftAndDate() throws {
        let json = """
            [{"number":7,"title":"Seven","html_url":"https://github.com/acme/api/pull/7",
              "user":{"login":"mwright","type":"User"},"draft":true,"created_at":"2026-09-25T10:00:00Z"}]
            """
        let candidates = try #require(WatchedPullRequests.parseREST(Data(json.utf8)))
        #expect(
            candidates == [
                WatchedPullRequests.Candidate(
                    pullRequest: WatchedPullRequest(
                        url: "https://github.com/acme/api/pull/7", number: 7, title: "Seven", author: "mwright",
                        isDraft: true, createdAt: ISO8601DateFormatter().date(from: "2026-09-25T10:00:00Z")),
                    isBot: false)
            ])
    }

    @Test func rowsMissingOptionalFieldsStillParse() throws {
        let gh = #"[{"number":1,"title":"t","url":"https://github.com/acme/api/pull/1"}]"#
        let rest = #"[{"number":1,"title":"t","html_url":"https://github.com/acme/api/pull/1"}]"#
        for candidates in [
            try #require(WatchedPullRequests.parseGH(Data(gh.utf8))),
            try #require(WatchedPullRequests.parseREST(Data(rest.utf8))),
        ] {
            #expect(candidates.count == 1)
            #expect(candidates[0].pullRequest.author == "unknown")
            #expect(candidates[0].pullRequest.isDraft == false)
            #expect(candidates[0].pullRequest.createdAt == nil)
            #expect(candidates[0].isBot == false)
        }
    }

    @Test func rowsMissingRequiredFieldsAreDropped() throws {
        let gh = #"[{"title":"no number","url":"u"},{"number":2,"url":"u"},{"number":3,"title":"no url"}]"#
        let rest = #"[{"title":"no number","html_url":"u"},{"number":2,"html_url":"u"},{"number":3,"title":"x"}]"#
        #expect(try #require(WatchedPullRequests.parseGH(Data(gh.utf8))).isEmpty)
        #expect(try #require(WatchedPullRequests.parseREST(Data(rest.utf8))).isEmpty)
    }

    @Test func anEmptyArrayIsAnEmptyListNotAFailure() throws {
        #expect(try #require(WatchedPullRequests.parseGH(Data("[]".utf8))).isEmpty)
        #expect(try #require(WatchedPullRequests.parseREST(Data("[]".utf8))).isEmpty)
    }

    @Test(arguments: ["", "not json", "{}", #"{"message":"Not Found"}"#, "[1,2]"])
    func inputThatIsNotAListOfObjectsCannotBeRead(input: String) {
        #expect(WatchedPullRequests.parseGH(Data(input.utf8)) == nil)
        #expect(WatchedPullRequests.parseREST(Data(input.utf8)) == nil)
    }

    @Test func botsAreRecognisedByFlagByAppPrefixAndByBotSuffix() {
        #expect(WatchedPullRequests.isBot(login: "someone", flagged: true))
        #expect(WatchedPullRequests.isBot(login: "app/dependabot", flagged: false))
        #expect(WatchedPullRequests.isBot(login: "renovate[bot]", flagged: false))
        #expect(!WatchedPullRequests.isBot(login: "mwright", flagged: false))
        #expect(!WatchedPullRequests.isBot(login: "application", flagged: false))
    }

    @Test func bothTransportsFlagABotFromItsLoginAlone() throws {
        let gh = #"[{"number":1,"title":"t","url":"u","author":{"login":"app/renovate"}}]"#
        let rest = #"[{"number":1,"title":"t","html_url":"u","user":{"login":"renovate[bot]"}}]"#
        #expect(try #require(WatchedPullRequests.parseGH(Data(gh.utf8)))[0].isBot)
        #expect(try #require(WatchedPullRequests.parseREST(Data(rest.utf8)))[0].isBot)
    }

    @Test func aListDropsBotsSortsNewestFirstAndKeepsTen() {
        let people = (1...12).map { candidate($0) }
        let bots = (13...15).map { candidate($0, author: "app/dependabot", isBot: true) }
        let list = WatchedPullRequests.list(from: (people + bots).shuffled(), fetchedAt: moment)
        #expect(list.pullRequests.map(\.number) == [12, 11, 10, 9, 8, 7, 6, 5, 4, 3])
        #expect(list.hasMore)
    }

    @Test func rowsWithoutADateSortLast() {
        var undated = candidate(99)
        undated.pullRequest.createdAt = nil
        let list = WatchedPullRequests.list(from: [undated, candidate(1), candidate(2)], fetchedAt: moment)
        #expect(list.pullRequests.map(\.number) == [2, 1, 99])
    }

    @Test func aShortListHasNoMore() {
        let list = WatchedPullRequests.list(from: (1...10).map { candidate($0) }, fetchedAt: moment)
        #expect(list.pullRequests.count == 10)
        #expect(!list.hasMore)
    }

    @Test func aFullPageMeansThereMayBeMoreEvenWithFewPeople() {
        let people = (1...4).map { candidate($0) }
        let bots = (5...30).map { candidate($0, author: "app/dependabot", isBot: true) }
        let list = WatchedPullRequests.list(from: people + bots, fetchedAt: moment)
        #expect(list.pullRequests.count == 4)
        #expect(list.hasMore)
    }

    @Test func aFullPageOfBotsLeavesAnEmptyListThatHasMore() {
        let bots = (1...30).map { candidate($0, author: "app/dependabot", isBot: true) }
        let list = WatchedPullRequests.list(from: bots, fetchedAt: moment)
        #expect(list.pullRequests.isEmpty)
        #expect(list.hasMore)
    }

    @Test func aPullRequestIsIdentifiedByItsURL() {
        #expect(candidate(7).pullRequest.id == "https://github.com/acme/api/pull/7")
    }
}
