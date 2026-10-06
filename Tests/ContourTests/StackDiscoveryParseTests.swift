import Foundation
import Testing

@testable import Contour

struct StackDiscoveryParseTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func theGHHeadFixtureIsTheBottomLayerWithItsSize() throws {
        let layers = try #require(StackDiscovery.parseGH(try fixture("gh-pr-list-head")))
        let layer = try #require(layers.first)
        #expect(layers.count == 1)
        #expect(layer.number == 14450)
        #expect(layer.baseRefName == "trunk")
        #expect(layer.headRefName == "babakks/refresh-token-a-foundation")
        #expect(layer.url == "https://github.com/cli/cli/pull/14450")
        #expect(layer.author == "babakks")
        #expect(layer.headSha.count == 40)
        #expect(layer.baseSha.count == 40)
        #expect((layer.size?.changedFiles ?? 0) > 0)
    }

    @Test func theGHBaseFixtureIsTheLayerAbove() throws {
        let layers = try #require(StackDiscovery.parseGH(try fixture("gh-pr-list-base")))
        #expect(layers.map(\.number) == [14451])
        #expect(layers.first?.baseRefName == "babakks/refresh-token-a-foundation")
    }

    @Test func theRESTFixturesParseWithoutSizes() throws {
        let head = try #require(StackDiscovery.parseREST(try fixture("rest-pulls-head"), repository: "cli/cli"))
        let base = try #require(StackDiscovery.parseREST(try fixture("rest-pulls-base"), repository: "cli/cli"))
        #expect(head.map(\.number) == [14450])
        #expect(base.map(\.number) == [14451])
        #expect(head.first?.size == nil)
        #expect(head.first?.headSha.count == 40)
        #expect(head.first?.author == "babakks")
        #expect(head.first?.url == "https://github.com/cli/cli/pull/14450")
    }

    @Test func aGHRowFromAForkIsIgnored() {
        let json = """
            [{"number":1,"url":"https://github.com/acme/api/pull/1","title":"t","author":{"login":"x"},
              "isDraft":false,"headRefName":"h","baseRefName":"b","headRefOid":"1","baseRefOid":"2",
              "additions":1,"deletions":0,"changedFiles":1,"isCrossRepository":true}]
            """
        #expect(StackDiscovery.parseGH(Data(json.utf8)) == [])
    }

    @Test func aRESTRowFromAnotherRepositoryIsIgnored() {
        let json = """
            [{"number":1,"html_url":"https://github.com/acme/api/pull/1","title":"t","draft":false,
              "user":{"login":"x"},"head":{"ref":"h","sha":"1","repo":{"full_name":"someone/api"}},
              "base":{"ref":"b","sha":"2"},"additions":null,"deletions":null,"changed_files":null}]
            """
        #expect(StackDiscovery.parseREST(Data(json.utf8), repository: "acme/api") == [])
    }

    @Test func rowsMissingRequiredFieldsAreSkippedAndNonArraysAreNil() {
        #expect(StackDiscovery.parseGH(Data("{}".utf8)) == nil)
        #expect(StackDiscovery.parseREST(Data("not json".utf8), repository: "acme/api") == nil)
        #expect(StackDiscovery.parseGH(Data("[{\"number\":3}]".utf8)) == [])
        #expect(StackDiscovery.parseREST(Data("[{\"number\":3}]".utf8), repository: "acme/api") == [])
    }

    @Test func aGHRowWithoutSizeFieldsHasNoSizeAndKeepsDraft() {
        let json = """
            [{"number":1,"url":"https://github.com/acme/api/pull/1","title":"t","author":{"login":"x"},
              "isDraft":true,"headRefName":"h","baseRefName":"b","headRefOid":"1","baseRefOid":"2",
              "isCrossRepository":false}]
            """
        let layers = StackDiscovery.parseGH(Data(json.utf8))
        #expect(layers?.first?.size == nil)
        #expect(layers?.first?.isDraft == true)
    }

    @Test func aRESTRowWithSizesAndNoAuthorFallsBackToUnknown() {
        let json = """
            [{"number":1,"html_url":"https://github.com/acme/api/pull/1","title":"t","draft":true,
              "head":{"ref":"h","sha":"1","repo":{"full_name":"acme/api"}},
              "base":{"ref":"b","sha":"2"},"additions":3,"deletions":1,"changed_files":2}]
            """
        let layer = StackDiscovery.parseREST(Data(json.utf8), repository: "acme/api")?.first
        #expect(layer?.author == "unknown")
        #expect(layer?.isDraft == true)
        #expect(layer?.size == StackLayer.Size(additions: 3, deletions: 1, changedFiles: 2))
    }
}
