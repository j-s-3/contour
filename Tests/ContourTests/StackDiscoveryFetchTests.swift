import Foundation
import Testing
import os

@testable import Contour

struct StackDiscoveryFetchTests {
    private func context(head: String = "b", base: String = "a") -> RawPRContext {
        RawPRContext(
            url: "https://github.com/acme/api/pull/2", owner: "acme", repo: "api", number: 2,
            title: "Layer 2", body: "", author: "mwright", state: "OPEN", headRefName: head,
            baseRefName: base, headSha: "h2", baseSha: "b2", isCrossRepository: false,
            headCloneURL: "https://github.com/acme/api.git", additions: 5, deletions: 1, changedFiles: 2,
            files: [], commits: [], comments: [], reviews: [], diff: "")
    }

    private func row(_ number: Int, head: String, base: String) -> String {
        """
        {"number":\(number),"url":"https://github.com/acme/api/pull/\(number)","title":"Layer \(number)",
         "author":{"login":"mwright"},"isDraft":false,"headRefName":"\(head)","baseRefName":"\(base)",
         "headRefOid":"h\(number)","baseRefOid":"b\(number)","additions":1,"deletions":0,"changedFiles":1,
         "isCrossRepository":false}
        """
    }

    @Test func ghArgumentsFilterByHeadOrBase() {
        #expect(
            StackDiscovery.arguments(repository: "acme/api", filter: .head("a")) == [
                "pr", "list", "-R", "acme/api", "--state", "open", "--limit", "10", "--head", "a",
                "--json", StackDiscovery.ghFields,
            ])
        let base = StackDiscovery.arguments(repository: "acme/api", filter: .base("b"))
        #expect(base.contains("--base"))
        #expect(!base.contains("--head"))
    }

    @Test func restQueryEncodesTheBranchAndPrefixesTheOwnerOnHead() {
        #expect(
            StackDiscovery.restQuery(owner: "acme", filter: .head("feature/x&y"))
                == "state=open&per_page=10&head=acme:feature/x%26y")
        #expect(StackDiscovery.restQuery(owner: "acme", filter: .base("main")) == "state=open&per_page=10&base=main")
    }

    @Test func theOpenedPullRequestBecomesTheCurrentLayer() {
        let layer = StackDiscovery.layer(from: context())
        #expect(layer.number == 2)
        #expect(layer.headRefName == "b")
        #expect(layer.size == StackLayer.Size(additions: 5, deletions: 1, changedFiles: 2))
    }

    @Test func ghDiscoveryWalksBothWaysAndOrdersBottomUp() async {
        let seen = OSAllocatedUnfairLock<[[String]]>(initialState: [])
        let one = row(1, head: "a", base: "main")
        let three = row(3, head: "c", base: "b")
        let service = StackDiscovery(
            ghAvailable: { true },
            runGH: { arguments in
                seen.withLock { $0.append(arguments) }
                if arguments.contains("--head") {
                    return arguments.contains("a") ? "[\(one)]" : "[]"
                }
                return arguments.contains("b") ? "[\(three)]" : "[]"
            })
        let stack = await service.discover(ctx: context(), access: .gh)
        #expect(stack?.layers.map(\.number) == [1, 2, 3])
        #expect(stack?.currentIndex == 1)
        #expect(seen.withLock { $0.count } == 4)
    }

    @Test func aFailingTransportYieldsNoStack() async {
        struct Boom: Error {}
        let service = StackDiscovery(ghAvailable: { true }, runGH: { _ in throw Boom() })
        #expect(await service.discover(ctx: context(), access: .gh) == nil)
    }

    @Test func ghAccessWithoutGHRunsNothing() async {
        let service = StackDiscovery(
            ghAvailable: { false },
            runGH: { _ in
                Issue.record("gh must not run")
                return "[]"
            })
        #expect(await service.discover(ctx: context(), access: .gh) == nil)
    }

    @Test func unparseableOutputYieldsNoStack() async {
        let service = StackDiscovery(ghAvailable: { true }, runGH: { _ in "nope" })
        #expect(await service.discover(ctx: context(), access: .gh) == nil)
    }
}
