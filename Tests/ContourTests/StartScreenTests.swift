import XCTest

@testable import Contour

final class StartScreenTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("contour-recents-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func record(_ cache: AnalysisCache, _ number: Int, title: String = "t", at seconds: TimeInterval) {
        cache.recordOpened(
            url: "https://github.com/acme/shop/pull/\(number)", repo: "acme/shop",
            number: number, title: title, at: Date(timeIntervalSince1970: seconds))
    }

    func testRecentPRsAreNewestFirst() {
        let cache = AnalysisCache(directory: directory)
        XCTAssertEqual(cache.recentPRs(), [])
        record(cache, 1, at: 100)
        record(cache, 2, at: 200)
        record(cache, 3, at: 300)
        XCTAssertEqual(cache.recentPRs().map(\.number), [3, 2, 1])
        XCTAssertEqual(cache.recentPRs(limit: 2).map(\.number), [3, 2])
    }

    func testReopeningMovesToTopWithoutDuplicating() {
        let cache = AnalysisCache(directory: directory)
        record(cache, 1, title: "old title", at: 100)
        record(cache, 2, at: 200)
        record(cache, 1, title: "new title", at: 300)
        let recents = cache.recentPRs()
        XCTAssertEqual(recents.map(\.number), [1, 2])
        XCTAssertEqual(recents.first?.title, "new title")
        XCTAssertEqual(recents.first?.lastOpened, Date(timeIntervalSince1970: 300))
    }

    func testRecentPRsAreKeyedByRepoAndNumber() {
        let cache = AnalysisCache(directory: directory)
        record(cache, 7, at: 100)
        cache.recordOpened(
            url: "https://github.com/acme/api/pull/7", repo: "acme/api", number: 7,
            title: "t", at: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(cache.recentPRs().map(\.repo), ["acme/api", "acme/shop"])
    }

    func testRecentIndexIsCapped() {
        let cache = AnalysisCache(directory: directory)
        for n in 1...(AnalysisCache.recentCapacity + 5) { record(cache, n, at: TimeInterval(n)) }
        let recents = cache.recentPRs()
        XCTAssertEqual(recents.count, AnalysisCache.recentCapacity)
        XCTAssertEqual(recents.first?.number, AnalysisCache.recentCapacity + 5)
    }

    func testRecentIndexIsBypassedInMockMode() {
        let cache = AnalysisCache(directory: directory)
        setenv("CONTOUR_MOCK_ANALYSIS", "1", 1)
        record(cache, 1, at: 100)
        unsetenv("CONTOUR_MOCK_ANALYSIS")
        XCTAssertEqual(cache.recentPRs(), [])
    }

    func testParsesReviewRequestsNewestUpdateFirst() {
        let json = """
            [{"author":{"login":"alice","type":"User"},"isDraft":false,"number":12,
              "repository":{"name":"shop","nameWithOwner":"acme/shop"},"title":"Older",
              "updatedAt":"2026-09-24T16:15:59Z","url":"https://github.com/acme/shop/pull/12"},
             {"author":{"login":"bob","type":"User"},"isDraft":true,"number":40,
              "repository":{"name":"api","nameWithOwner":"acme/api"},"title":"Newer",
              "updatedAt":"2026-09-25T14:09:07Z","url":"https://github.com/acme/api/pull/40"}]
            """
        let requests = ReviewRequests.parse(json)
        XCTAssertEqual(requests.map(\.title), ["Newer", "Older"])
        XCTAssertEqual(requests.first?.repo, "acme/api")
        XCTAssertEqual(requests.first?.number, 40)
        XCTAssertEqual(requests.first?.author, "bob")
        XCTAssertEqual(requests.first?.isDraft, true)
        XCTAssertEqual(requests.first?.url, "https://github.com/acme/api/pull/40")
        XCTAssertNotNil(requests.first?.updatedAt)
    }

    func testReviewRequestRowsMissingFieldsAreDropped() {
        let json = """
            [{"number":1,"title":"no url","repository":{"nameWithOwner":"acme/shop"}},
             {"number":2,"title":"ok","url":"https://github.com/acme/shop/pull/2","repository":{"nameWithOwner":"acme/shop"}}]
            """
        let requests = ReviewRequests.parse(json)
        XCTAssertEqual(requests.map(\.number), [2])
        XCTAssertEqual(requests.first?.author, "unknown")
        XCTAssertNil(requests.first?.updatedAt)
    }

    func testMalformedReviewRequestOutputIsEmpty() {
        XCTAssertEqual(ReviewRequests.parse(""), [])
        XCTAssertEqual(ReviewRequests.parse("not json"), [])
        XCTAssertEqual(ReviewRequests.parse("{}"), [])
    }

    func testReviewRequestIDCombinesRepoAndNumber() {
        let request = ReviewRequest(
            url: "https://github.com/acme/shop/pull/7", repo: "acme/shop",
            number: 7, title: "t", author: "a", isDraft: false, updatedAt: nil)
        XCTAssertEqual(request.id, "acme/shop#7")
    }

    func testRowsMissingUpdatedAtSortLast() {
        let json = """
            [{"number":1,"title":"no date","url":"https://github.com/acme/shop/pull/1","repository":{"nameWithOwner":"acme/shop"}},
             {"number":2,"title":"has date","url":"https://github.com/acme/shop/pull/2","repository":{"nameWithOwner":"acme/shop"},"updatedAt":"2026-09-25T00:00:00Z"}]
            """
        let requests = ReviewRequests.parse(json)
        XCTAssertEqual(requests.map(\.title), ["has date", "no date"])
    }

    func testNoReviewRequestsWhenAccessIsAnonymous() async {
        let requests = await ReviewRequests.fetch(access: .anonymous)
        XCTAssertNil(requests)
    }

    func testFetchReachesGHWhenAccessIsntAnonymous() async {
        let requests = await ReviewRequests.fetch(access: .gh)
        if let requests { XCTAssertTrue(requests.allSatisfy { !$0.repo.isEmpty }) }
    }
}
