import Foundation
import Testing

@testable import Contour

struct WatchedRepositoryTests {
    @Test(arguments: [
        "acme/api",
        "  acme/api  ",
        "acme/api/",
        "https://github.com/acme/api",
        "https://github.com/acme/api/",
        "https://github.com/acme/api.git",
        "http://github.com/acme/api",
        "github.com/acme/api",
        "www.github.com/acme/api",
        "https://www.github.com/acme/api/pull/12/files",
        "https://github.com/acme/api/pull/12",
        "https://github.com/acme/api?tab=readme-ov-file",
        "https://github.com/acme/api#readme",
        "https://GitHub.com/acme/api",
    ])
    func everyAcceptedFormNamesTheSameRepository(input: String) {
        #expect(WatchedRepository.parse(input) == WatchedRepository(owner: "acme", name: "api"))
    }

    @Test(arguments: [
        "",
        "   ",
        "acme",
        "acme/",
        "/api",
        "acme/api/extra",
        "-acme/api",
        "--flag/x",
        "acme/a b",
        "acme/api;rm",
        "acme/..",
        "acme/.",
        "../api",
        "./api",
        "https://github.com/../api",
        "acmé/api",
        "https://gitlab.com/acme/api",
        "https://evilgithub.com/acme/api",
        "https://github.com.evil.example/acme/api",
        "ftp://github.com/acme/api",
        "https://github.com/acme",
    ])
    func inputThatIsNotAGitHubRepositoryIsRejected(input: String) {
        #expect(WatchedRepository.parse(input) == nil)
    }

    @Test func namesMayContainDotsUnderscoresAndHyphens() {
        #expect(
            WatchedRepository.parse("my-org_1/my.repo-name_2")
                == WatchedRepository(owner: "my-org_1", name: "my.repo-name_2"))
    }

    @Test func ownersAndNamesLongerThanGitHubAllowsAreRejected() {
        let owner = String(repeating: "a", count: 40)
        let name = String(repeating: "b", count: 101)
        #expect(WatchedRepository.parse("\(owner)/api") == nil)
        #expect(WatchedRepository.parse("acme/\(name)") == nil)
        #expect(WatchedRepository.parse("\(owner.dropLast())/\(name.dropLast())") != nil)
    }

    @Test func idJoinsOwnerAndNameAndURLPointsAtGitHub() {
        let repository = WatchedRepository(owner: "acme", name: "api")
        #expect(repository.id == "acme/api")
        #expect(repository.url == URL(string: "https://github.com/acme/api"))
    }

    @Test func matchingIgnoresCase() {
        let repository = WatchedRepository(owner: "Acme", name: "API")
        #expect(repository.matches("acme/api"))
        #expect(!repository.matches("acme/web"))
    }
}
