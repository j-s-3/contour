import XCTest
@testable import Contour

final class PRLinkTests: XCTestCase {
    private let canonical = "https://github.com/sharkdp/bat/pull/3877"

    func testExtractsABareURL() {
        XCTAssertEqual(PRLink.extract(from: canonical), canonical)
        XCTAssertEqual(PRLink.extract(from: "  \(canonical)\n"), canonical)
    }

    /// Links arrive inside a sentence, on a sub-page, or with an anchor.
    func testExtractsFromSurroundingTextAndDropsTheTail() {
        XCTAssertEqual(PRLink.extract(from: "can you look at \(canonical) today?"), canonical)
        XCTAssertEqual(PRLink.extract(from: "<\(canonical)|sharkdp/bat#3877>"), canonical)
        XCTAssertEqual(PRLink.extract(from: "\(canonical)/files"), canonical)
        XCTAssertEqual(PRLink.extract(from: "\(canonical)#discussion_r123"), canonical)
        XCTAssertEqual(PRLink.extract(from: "\(canonical)?w=1"), canonical)
    }

    func testCanonicalizesSchemeAndHost() {
        XCTAssertEqual(PRLink.extract(from: "github.com/sharkdp/bat/pull/3877"), canonical)
        XCTAssertEqual(PRLink.extract(from: "http://www.github.com/sharkdp/bat/pull/3877"), canonical)
        XCTAssertEqual(PRLink.extract(from: "https://github.com/acme/my.repo_name-2/pull/1"),
                       "https://github.com/acme/my.repo_name-2/pull/1")
    }

    func testTakesTheFirstOfSeveral() {
        XCTAssertEqual(PRLink.extract(from: "\(canonical) and https://github.com/cli/cli/pull/1"), canonical)
    }

    func testRejectsWhatIsNotAPullRequest() {
        XCTAssertNil(PRLink.extract(from: "not a url"))
        XCTAssertNil(PRLink.extract(from: "https://github.com/sharkdp/bat/issues/3877"))
        XCTAssertNil(PRLink.extract(from: "https://github.com/sharkdp/bat/pull/"))
        XCTAssertNil(PRLink.extract(from: "https://github.com/sharkdp/bat"))
        XCTAssertNil(PRLink.extract(from: "https://notgithub.com/sharkdp/bat/pull/3877"))
    }

    func testContourSchemeForms() throws {
        let encoded = try XCTUnwrap(URL(string: "contour://open?url=https%3A%2F%2Fgithub.com%2Fsharkdp%2Fbat%2Fpull%2F3877"))
        XCTAssertEqual(PRLink.pullRequestURL(from: encoded), canonical)
        let withHost = try XCTUnwrap(URL(string: "contour://github.com/sharkdp/bat/pull/3877"))
        XCTAssertEqual(PRLink.pullRequestURL(from: withHost), canonical)
        let ownerAsHost = try XCTUnwrap(URL(string: "contour://sharkdp/bat/pull/3877"))
        XCTAssertEqual(PRLink.pullRequestURL(from: ownerAsHost), canonical)
        let https = try XCTUnwrap(URL(string: "\(canonical)/files"))
        XCTAssertEqual(PRLink.pullRequestURL(from: https), canonical)
        XCTAssertNil(PRLink.pullRequestURL(from: try XCTUnwrap(URL(string: "contour://open"))))
    }

    func testLabel() {
        XCTAssertEqual(PRLink.label(for: canonical), "sharkdp/bat #3877")
        XCTAssertNil(PRLink.label(for: "not a url"))
    }
}
